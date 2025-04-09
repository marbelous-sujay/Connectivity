import 'dart:async';
import 'dart:io';
import 'package:connectivity/model/error_model.dart';
import 'package:connectivity/utils/utils.dart';
import 'package:connectivity/view/landing_screen.dart';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

/// SERVICE
const easeServiceID = 'ff01';
const batteryServiceID = '180f';

/// CHARACTERISTIC
// battery status, read
const uuidBatteryStatus = '2a19';
// battery custom data, read
const uuidBatteryCustomData = 'ff00';

// eeg setting, write
const uuidEegSett = 'ff05';
// eeg read, notify
const uuidEegRead = 'ff04';

// tDCS setting, write
const uuidTdcsSett = 'ff03';
// tDCS read, notify
const uuidTdcsRead = 'ff02';

// error, notify, read
const uuidError = 'ff06';

// device status, read, write
const uuidDevSett = 'ff07';

enum EnumErrorProtocol {
  noError,
  invalidError,
  timeout,
  eegNotWorking,
  eegHardwareSysFault,
  tdcsNotWorking,
  tdcsOverCurrentTriggered,
  tdcsOverCurrentSoftTriggered,
  tdcsElectrodeOpen,
  fuelGaugeNotWorking,
  protocolRunningWhileCharging,
  batteryCriticalLow,
  accelerometerNotWorking,
  headbandDisconnected,
  lowBattery,
  tdcsEnded,
  callAssistant,
}

class HomeView extends StatefulWidget {
  const HomeView({
    super.key,
    required this.device,
  });

  final BluetoothDevice device;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  double eegFrequency = 250;
  double tdcsCurrent = 1.5;

  String batteryLevel = '';
  String chargingStatus = '';
  String mode = 'IDLE';
  TextEditingController eegTimeController = TextEditingController();
  TextEditingController tdcsTimeController = TextEditingController();
  String eegButtonText = 'Run EEG';
  String tdcsButtonText = 'Run tDCS';

  int bytesBreakDown = 4;
  double gain = 0.26822;
  int countEegRead = 0;
  int incrementMillisecondBy = 2;
  List<double> listCh1 = [];
  List<double> listEmpty = [0, 0, 0, 0, 0, 0];
  List<double> listCh2 = [];
  List<double> listCh3 = [];
  List<double> listCh4 = [];
  List<String> listOfTimeStamps = [];
  int eegCounts = 0;

  List<List<dynamic>> listTDCSData = [];
  int tdcsCounts = 0;

  late DeviceIdentifier remoteId;

  late BluetoothCharacteristic batteryData;
  late BluetoothCharacteristic eegData;
  late BluetoothCharacteristic tdcsData;
  late BluetoothCharacteristic errorData;

  late final StreamSubscription<List<int>> batteryListener;
  late final StreamSubscription<List<int>> eegListener;
  late final StreamSubscription<List<int>> tdcsListener;
  late final StreamSubscription<List<int>> errorListener;

  int errorInHeadband = 0;
  int errorInEEG = 0;
  int errorInTDCS = 0;
  int errorInFuelGauge = 0;
  int errorInAccelerometer = 0;

  Timer? timer;
  int remainingTime = 0;

  void startTimer(String timeInSec) {
    if (timer != null) {
      timer!.cancel();
    }
    remainingTime = int.tryParse(timeInSec) ?? 0;
    timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remainingTime > 0) {
        setState(() {
          remainingTime--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  BluetoothCharacteristic getBluetoothCharacteristics(
      String serviceId, String characteristicId) {
    return BluetoothCharacteristic(
      remoteId: remoteId,
      serviceUuid: Guid(serviceId),
      characteristicUuid: Guid(characteristicId),
    );
  }

  @override
  void initState() {
    super.initState();
    remoteId = widget.device.remoteId;

    Future.delayed(const Duration(seconds: 5), () {
      discoverServices();

      tdcsData = getBluetoothCharacteristics(easeServiceID, uuidTdcsRead);
      eegData = getBluetoothCharacteristics(easeServiceID, uuidEegRead);
      batteryData =
          getBluetoothCharacteristics(batteryServiceID, uuidBatteryStatus);

      errorData = getBluetoothCharacteristics(easeServiceID, uuidError);

      listenToServices();
      readBatteryData();
    });
  }

  @override
  dispose() {
    // _connectionStateSubscription.cancel();
    batteryListener.cancel();
    eegListener.cancel();
    tdcsListener.cancel();
    errorListener.cancel();
    super.dispose();
  }

  Future<void> listToCsv(String csv, String fileName) async {
    String csvFileDirectory =
        '${(await getApplicationDocumentsDirectory()).path}/ease_data';

    if (!Directory(csvFileDirectory).existsSync()) {
      await Directory(csvFileDirectory).create(recursive: true);
    }

    String path = '$csvFileDirectory/$fileName';

    final File file = File(path);

    try {
      await file.writeAsString(
        csv,
        mode: FileMode.write,
      );
      if (kDebugMode) {
        print("CSV_PATH:   $path");
      }
    } catch (e, stacktrace) {
      if (kDebugMode) {
        print("Error--------------------------------: $e");
        print("Stacktrace: $stacktrace");
      }
    }
  }

  int calculateEegVal(List<int> dat, int index, int chNo) {
    var finalVal = 0;
    try {
      final lsbCount = (chNo * 3) + (index * 12) + 2;

      final lsb = dat[lsbCount];
      final midB = dat[(chNo * 3) + (index * 12) + 1];
      final msb = dat[(chNo * 3) + (index * 12)];
      final bool condition = (msb & 0x80) == 128;

      if (condition) {
        finalVal = (0xffffffffff << 24) | (msb << 16) | (midB << 8) | lsb;
        finalVal = ~(finalVal - 1);
        finalVal = -finalVal;
      } else {
        finalVal = (msb << 16) | (midB << 8) | lsb;
      }
    } catch (error) {
      // errorHandling(error: error, stacktrace: stacktrace);
    }
    return finalVal;
  }

  int convertListToInt(List<int> data) {
    if (data.length == 4) {
      return data[0] | data[1] << 8 | data[2] << 16 | data[3] << 24;
    } else if (data.length == 2) {
      return data[0] | data[1] << 8;
    }
    return 0;
  }

  void handelValueChangeTdcs(List<int> data) {
    final List<int> setCurrentList = data.sublist(0, 2);
    final List<int> actualCurrentList = data.sublist(2, 6);

    DateTime now = DateTime.now();
    String formattedDate = DateFormat('HH:mm:ss:SSSSS').format(now);

    final double setCurrentValue = convertListToInt(setCurrentList).toDouble();

    final double actualCurrentValue =
        convertListToInt(actualCurrentList).toDouble();

    listTDCSData
        .add([formattedDate, tdcsCounts, setCurrentValue, actualCurrentValue]);

    tdcsCounts += 1;
  }

  void handleValueChangeEEG(List<int> data) {
    var ch1Val = 0.0;
    var ch2Val = 0.0;
    var ch3Val = 0.0;
    var ch4Val = 0.0;

    bytesBreakDown = data.length ~/ 12;

    for (int i = 0; i < bytesBreakDown; i++) {
      eegCounts++;

      DateTime now = DateTime.now();
      String formattedDate = DateFormat('HH:mm:ss:SSSSS').format(now);

      ch1Val = gain * calculateEegVal(data, i, 0);
      ch2Val = gain * calculateEegVal(data, i, 1);
      ch3Val = gain * calculateEegVal(data, i, 2);
      ch4Val = gain * calculateEegVal(data, i, 3);

      listCh1.add(ch1Val);
      listCh2.add(ch2Val);
      listCh3.add(ch3Val);
      listCh4.add(ch4Val);
      listOfTimeStamps.add(formattedDate);
    }
  }

  Future<void> listenToServices() async {
    widget.device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const LandingScreen(),
          ),
        );
      } else {
        ///TDCS listener
        tdcsData.setNotifyValue(true);
        tdcsListener = tdcsData.onValueReceived.listen((value) {
          // print("^^^^^^^^^^TDCS Data: $value");
          handelValueChangeTdcs(value);
        });

        ///EEG listener
        eegData.setNotifyValue(true);
        eegListener = eegData.onValueReceived.listen((value) {
          // print("^^^^^^^^^^New EEG Data: $value");
          handleValueChangeEEG(value);
        });

        ///Battery listener
        batteryData.setNotifyValue(true);
        batteryListener = batteryData.onValueReceived.listen((value) {
          // print("^^^^^^^^^^New Battery Data: $value");
          setState(() {
            if (value[1] == 10) {
              chargingStatus = 'Charging';
            } else {
              chargingStatus = 'Discharging';
            }

            batteryLevel = value[0].toString();
          });
        });

        ///Error listener
        errorData.setNotifyValue(true);
        errorListener = errorData.onValueReceived.listen((value) {
          // print("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@$value");
          handleValueChangeError(value);
          if (kDebugMode) {
            print("Error: $value");
          }
        });
      }
    });
  }

  void deviceStatus(int timeInSec, String currentMode) {
    setState(() {
      mode = currentMode;
      if (mode == 'EEG') {
        eegButtonText = 'Stop EEG';
      } else if (mode == 'tDCS') {
        tdcsButtonText = 'Stop tDCS';
      } else {
        eegButtonText = 'Run EEG';
        tdcsButtonText = 'Run tDCS';
      }
    });

    timeInSec = currentMode == 'EEG' ? timeInSec : timeInSec + 60;

    Future.delayed(Duration(seconds: timeInSec), () {
      if (kDebugMode) {
        print(
            "--------------------------------------Future also printed $mode");
      }
      setState(() {
        mode = 'IDLE';
        eegButtonText = 'Run EEG';
        tdcsButtonText = 'Run tDCS';
        if (kDebugMode) {
          print("--------------------------------------$mode");
        }
      });
    });
  }

  readBatteryData() async {
    BluetoothCharacteristic data =
        getBluetoothCharacteristics(batteryServiceID, uuidBatteryCustomData);
    try {
      List<int> batData = await readValue(data);

      if (batData.isNotEmpty) {
        setState(() {
          if (batData[1] == 10) {
            chargingStatus = 'Charging';
          } else {
            chargingStatus = 'Discharging';
          }

          batteryLevel = batData[0].toString();
        });
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print("Error: $e");
        print("Stacktrace: $stackTrace");
      }
    }
  }

  startTdcs() {
    eegCounts = 0;

    startTimer((int.parse(tdcsTimeController.text) + 60).toString());

    deviceStatus(int.parse(tdcsTimeController.text), 'tDCS');

    BluetoothCharacteristic data2 =
        getBluetoothCharacteristics(easeServiceID, uuidTdcsSett);

    int tdcsTime = int.parse(tdcsTimeController.text);
    int tdcsCurrentInt = (tdcsCurrent * 1000).toInt();

    writeValue(data2, [
      4,
      (tdcsCurrentInt & 0xff),
      (tdcsCurrentInt >> 8 & 0xff),
      (30000 & 0xff),
      ((30000 >> 8) & 0xff),
      ((30000 >> 16) & 0xff),
      ((30000 >> 24) & 0xff),
      (0xff & (tdcsTime)),
      (0xff & ((tdcsTime) >> 8)),
      (0xff & ((tdcsTime) >> 16)),
      (0xff & ((tdcsTime) >> 24)),
    ]);
  }

  stopTdcs() {
    remainingTime = 0;

    setState(() {
      mode = 'IDLE';
    });

    BluetoothCharacteristic data =
        getBluetoothCharacteristics(easeServiceID, uuidTdcsSett);

    writeValue(data, [1]);
  }

  stopEeg() {
    remainingTime = 0;

    setState(() {
      mode = 'IDLE';
    });

    BluetoothCharacteristic data =
        getBluetoothCharacteristics(easeServiceID, uuidEegSett);

    writeValue(data, [1]);
  }

  startEeg() {
    eegCounts = 0;

    startTimer(eegTimeController.text);

    deviceStatus(int.parse(eegTimeController.text), 'EEG');
    BluetoothCharacteristic data2 =
        getBluetoothCharacteristics(easeServiceID, uuidEegSett);

    int eegTime = int.parse(eegTimeController.text);
    int opCode = eegFrequency == 250 ? 20 : 18;
    writeValue(
      data2,
      [
        opCode,
        (0xff & eegTime),
        (0xff & eegTime >> 8),
        (0xff & eegTime >> 16),
        (0xff & eegTime >> 24)
      ],
    );
  }

  Future<List<int>> readValue(BluetoothCharacteristic characteristic) async {
    // BluetoothCharacteristic data = characteristic;
    if (kDebugMode) {
      print("🤷‍♂️🤷‍♂️🤷‍♂️🤷‍♂️🤷‍♂️🤷‍♂️🤷‍♂️🤷‍♂️🤷‍♂️");
      print(
          " ${characteristic.uuid}  ${characteristic.serviceUuid}  ${characteristic.remoteId}");
    }

    try {
      List<int> readValue = await characteristic.read(timeout: 60);
      if (kDebugMode) {
        print("************************ The read value is  $readValue");
      }
      return readValue;
    } catch (error, stacktrace) {
      if (kDebugMode) {
        print("Error: $error");
        print("Stacktrace: $stacktrace");
      }
    }

    return [];
  }

  Future<void> writeValue(
      BluetoothCharacteristic characteristic, List<int> writeValue) async {
    BluetoothCharacteristic data = characteristic;

    if (kDebugMode) {
      print("************************ The write value is  $writeValue");
    }
    try {
      await data.write(writeValue);
      if (kDebugMode) {
        print("************************ Write done");
      }
    } catch (error, stacktrace) {
      if (kDebugMode) {
        print("Error: $error");
        print("Stacktrace: $stacktrace");
      }
    }
  }

  Future<void> notifyValue(BluetoothCharacteristic characteristic) async {
    BluetoothCharacteristic data = characteristic;

    try {
      bool notifyValue = await data.setNotifyValue(true);
      if (kDebugMode) {
        print("************************ The read value is  $notifyValue");
      }
    } catch (error, stacktrace) {
      if (kDebugMode) {
        print("Error: $error");
        print("Stacktrace: $stacktrace");
      }
    }
  }

  void notifyCase(BluetoothCharacteristic characteristic) {
    characteristic.onValueReceived.listen((value) {
      if (kDebugMode) {
        print("Value: $value");
      }
    });
  }

  void subscribeToService(BluetoothCharacteristic characteristic) async {
    final subscription = characteristic.onValueReceived.listen((value) {
      // onValueReceived is updated:
      //   - anytime read() is called
      //   - anytime a notification arrives (if subscribed)
    });

    // cleanup: cancel subscription when disconnected
    widget.device.cancelWhenDisconnected(subscription);

    // subscribe
    // Note: If a characteristic supports both **notifications** and **indications**,
    // it will default to **notifications**. This matches how CoreBluetooth works on iOS.
    await characteristic.setNotifyValue(true);
  }

  void discoverServices() async {
    await widget.device.discoverServices();
  }

  ErrorData getErrorDataFromErrorCode(int errorCode) {
    switch (errorCode) {
      case 0:
        return ErrorData(
          error: EnumErrorProtocol.noError.name,
          title: 'NO ERROR',
          message: 'There is no error in headband',
        );

      case 1:
        return ErrorData(
          error: EnumErrorProtocol.timeout.name,
          title: 'TIMEOUT',
          message: 'Timeout error',
        );

      case 100:
        return ErrorData(
          error: EnumErrorProtocol.eegNotWorking.name,
          title: 'EEG NOT WORKING',
          message: 'EEG not working',
        );

      case 101:
        return ErrorData(
          error: EnumErrorProtocol.noError.name,
          title: 'EEG HARDWARE SYS FAULT',
          message: 'EEG Hardware system fault',
        );

      case 110:
        return ErrorData(
          error: EnumErrorProtocol.tdcsNotWorking.name,
          title: 'TDCS NOT WORKING',
          message: 'TDCS not working',
        );

      case 111:
        return ErrorData(
          error: EnumErrorProtocol.tdcsOverCurrentTriggered.name,
          title: 'TDCS OVERCURRNT TRIGGED',
          message: 'TDCS over current triggered',
        );

      case 112:
        return ErrorData(
          error: EnumErrorProtocol.tdcsOverCurrentSoftTriggered.name,
          title: 'TDS OVERCURRENT SOFT TRIGGERD',
          message: 'TDCS over current soft triggered',
        );

      case 113:
        return ErrorData(
          error: EnumErrorProtocol.tdcsElectrodeOpen.name,
          title: 'TDCS_ELECTRODE_OPEN',
          message: 'TDCS electrode open',
        );

      case 120:
        return ErrorData(
          error: EnumErrorProtocol.fuelGaugeNotWorking.name,
          title: 'FUEL_GAUGE_NOT_WORKING',
          message: 'Fuel gauge not working',
        );

      case 121:
        return ErrorData(
          error: EnumErrorProtocol.protocolRunningWhileCharging.name,
          title: 'PROTOCOL_RUNNING_WHILE_CHARGING',
          message: 'Protocol running while charging',
        );

      case 122:
        return ErrorData(
          error: EnumErrorProtocol.batteryCriticalLow.name,
          title: 'BATTERY_CRITICAL_LOW',
          message: 'Batter is critically low',
        );

      case 130:
        return ErrorData(
          error: EnumErrorProtocol.accelerometerNotWorking.name,
          title: 'ACCELEROMETER_NOT_WORKING',
          message: 'Accelerometer not working',
        );

      default:
        return ErrorData(
          error: EnumErrorProtocol.invalidError.name,
          title: 'INVALID ERROR',
          message: 'Invalid error code',
        );
    }
  }

  Future<void> handleValueChangeError(List<int> data) async {
    bool isError = false;

    ErrorData errorData = getErrorDataFromErrorCode(
      errorInEEG,
    );

    if (data.length == 4) {
      String? errorMessage;
      errorInFuelGauge = data[0];
      errorInEEG = data[1];
      errorInTDCS = data[2];
      errorInAccelerometer = data[3];

      if (kDebugMode) {
        print(
          "title: 'errorEeg' content: $errorInEEG",
        );
        print(
          "title: 'errorTDCS' content: $errorInTDCS",
        );
        print(
          "title: 'errorFuelGauge' content: $errorInFuelGauge",
        );
        print(
          "title: 'errorAccelerometer' content: $errorInAccelerometer",
        );
      }

      if (mode != 'IDLE') {
        if (errorInEEG != 0) {
          isError = true;
          errorData = getErrorDataFromErrorCode(
            errorInEEG,
          );

          errorMessage = '[$errorInEEG] ${errorData.error}\n';
        }

        if (errorInTDCS != 0) {
          isError = true;
          errorData = getErrorDataFromErrorCode(
            errorInTDCS,
          );

          errorMessage =
              '${errorMessage?.trim()} [$errorInTDCS] ${errorData.error}\n';
        }

        if (errorInFuelGauge != 0) {
          isError = true;
          errorData = getErrorDataFromErrorCode(
            errorInFuelGauge,
          );

          errorMessage =
              '${errorMessage?.trim()} [$errorInFuelGauge] ${errorData.error}\n';
        }

        if (errorInAccelerometer != 0) {
          isError = true;
          errorData = getErrorDataFromErrorCode(
            errorInAccelerometer,
          );

          errorMessage =
              '${errorMessage?.trim()} [$errorInAccelerometer] ${errorData.error}\n';
        }

        if (isError) {
          // mqttController.sendError(
          //   error: errorMessage,
          //   errorProtocol: stringToEnumErrorProtocol(
          //     errorData.error,
          //   ),
          //   title: errorData.title,
          //   message: errorData.message,
          // );
        }
      }
    } else {
      errorInHeadband = data[0];

      if (kDebugMode) {
        print(
          "title: 'errorInHeadband' content: ${getErrorDataFromErrorCode(errorInHeadband)}",
        );

        print(
          "title: 'errorInHeadband' content: ${getErrorDataFromErrorCode(errorInHeadband)}",
        );
      }

      if (errorInHeadband != 0) {
        final errorData = getErrorDataFromErrorCode(
          errorInHeadband,
        );
        showAlertDialog(
          context,
          errorData.title,
          errorData.message,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    int minutes = remainingTime ~/ 60;
    int seconds = remainingTime % 60;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'BLE Application',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            widget.device.disconnect();
            Navigator.of(context).pop();
          },
        ),
        backgroundColor: Colors.lightGreen,
      ),
      body: Center(
          child: batteryLevel.isEmpty
              ? const CircularProgressIndicator(
                  color: Colors.green,
                )
              : Padding(
                  padding: const EdgeInsets.all(25.0),
                  child: SingleChildScrollView(
                    child: Column(
                      children: <Widget>[
                        ///Device Details
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // const SizedBox(height: 30),
                            Text(
                              'Battery Level : $batteryLevel%',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 30),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Battery Status : $chargingStatus',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold),
                                ),
                                Container(
                                  height: 20,
                                  width: 20,
                                  color: mode == 'Charging'
                                      ? Colors.green
                                      : Colors.orangeAccent,
                                )
                              ],
                            ),
                            const SizedBox(height: 30),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Mode : $mode',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold),
                                ),
                                Container(
                                  height: 20,
                                  width: 20,
                                  color: mode == 'EEG'
                                      ? Colors.purpleAccent
                                      : mode == 'tDCS'
                                          ? Colors.blue
                                          : Colors.green,
                                )
                              ],
                            ),

                            const SizedBox(height: 30),
                            Text(
                              'Time : $minutes:${seconds.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),

                        const SizedBox(height: 30),

                        ///Device connection Buttons
                        Row(
                          children: [
                            Expanded(
                                child: ElevatedButton(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const LandingScreen(),
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                    ),
                                    child: const Text(
                                      'Connect',
                                      style: TextStyle(color: Colors.white),
                                    ))),
                            const SizedBox(width: 10),
                            Expanded(
                                child: ElevatedButton(
                                    onPressed: () {
                                      //cancel immediately
                                      widget.device.disconnect(queue: false);
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orangeAccent,
                                    ),
                                    child: const Text(
                                      'Disconnect',
                                      style: TextStyle(color: Colors.white),
                                    ))),
                          ],
                        ),

                        const SizedBox(height: 30),
                        const Divider(),
                        const SizedBox(height: 20),

                        ///EEG controls
                        Column(
                          children: [
                            Slider(
                                value: eegFrequency.toDouble(),
                                min: 250,
                                max: 500,
                                divisions: 1,
                                activeColor: Colors.green,
                                label: '${eegFrequency.round().toString()} Hz',
                                onChanged: (value) {
                                  setState(() {
                                    eegFrequency = value;
                                  });
                                }),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: <Widget>[
                                  Text(
                                    '250 Hz',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '500 Hz',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: eegTimeController,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly
                                    ],
                                    decoration: const InputDecoration(
                                      hintText: 'Enter time in sec',
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.all(
                                              Radius.circular(10.0)),
                                          borderSide:
                                              BorderSide(color: Colors.green)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              eegButtonText == 'Run EEG'
                                                  ? Colors.purpleAccent
                                                  : Colors.deepOrange,
                                        ),
                                        onPressed: eegButtonText == 'Run EEG'
                                            ? () {
                                                if (eegTimeController
                                                    .text.isNotEmpty) {
                                                  setState(() {
                                                    eegButtonText = 'Stop EEG';
                                                  });
                                                  startEeg();
                                                } else {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                          'Please enter EEG time first'),
                                                    ),
                                                  );
                                                }
                                              }
                                            : () {
                                                stopEeg();

                                                setState(() {
                                                  eegButtonText = 'Run EEG';
                                                });
                                              },
                                        child: Text(
                                          eegButtonText,
                                          style: const TextStyle(
                                              color: Colors.white),
                                        ))),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),
                        const Divider(),
                        const SizedBox(height: 20),

                        ///tDCS controls
                        Column(
                          children: [
                            Slider(
                                value: tdcsCurrent.toDouble(),
                                min: 0.5,
                                max: 3,
                                divisions: 5,
                                activeColor: Colors.blue,
                                label: '${tdcsCurrent.toStringAsFixed(1)} mA',
                                onChanged: (value) {
                                  setState(() {
                                    tdcsCurrent = value;
                                  });
                                }),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: <Widget>[
                                  Text(
                                    '0.5 mA',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '1.0 mA',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '1.5 mA',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '2.0 mA',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '2.5 mA',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '3.0 mA',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: tdcsTimeController,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly
                                    ],
                                    decoration: const InputDecoration(
                                      hintText: 'Enter time in sec',
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.all(
                                              Radius.circular(10.0)),
                                          borderSide:
                                              BorderSide(color: Colors.green)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              tdcsButtonText == 'Run tDCS'
                                                  ? Colors.blue
                                                  : Colors.deepOrange,
                                        ),
                                        onPressed: tdcsButtonText == 'Run tDCS'
                                            ? () {
                                                if (tdcsTimeController
                                                    .text.isNotEmpty) {
                                                  setState(() {
                                                    tdcsButtonText =
                                                        'Stop tDCS';
                                                  });
                                                  startTdcs();
                                                } else {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                          'Please enter tDCS time first'),
                                                    ),
                                                  );
                                                }
                                              }
                                            : () {
                                                stopTdcs();
                                                setState(() {
                                                  tdcsButtonText = 'Run tDCS';
                                                });
                                              },
                                        child: Text(
                                          tdcsButtonText,
                                          style: const TextStyle(
                                              color: Colors.white),
                                        ))),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),
                        const Divider(),
                        const SizedBox(height: 20),

                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                  onPressed: listCh1.isEmpty
                                      ? () {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content:
                                                  Text('Please run EEG first'),
                                            ),
                                          );
                                        }
                                      : () {
                                          String eegCsv =
                                              const ListToCsvConverter()
                                                  .convert(
                                            [
                                              [
                                                'Total EEG data:',
                                                '$eegCounts',
                                                'Date',
                                                (DateFormat('dd-MMMM-yyyy')
                                                    .format(DateTime.now()))
                                              ],
                                              [
                                                'Time',
                                                'Ch1',
                                                'Ch2',
                                                'Ch3',
                                                'Ch4'
                                              ],
                                              ...List.generate(listCh1.length,
                                                  (index) {
                                                return [
                                                  listOfTimeStamps[index],
                                                  listCh1[index],
                                                  listCh2[index],
                                                  listCh3[index],
                                                  listCh4[index],
                                                ];
                                              }),
                                            ],
                                          );
                                          String fileName =
                                              'eeg_data-${eegTimeController.text}-${eegFrequency.toInt()}hz-'
                                              '${DateTime.now().millisecondsSinceEpoch}.csv';

                                          listToCsv(eegCsv, fileName);
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.yellow,
                                  ),
                                  child: const Text(
                                    'Get EEG CSV',
                                    // style: TextStyle(color: Colors.white),
                                  )),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                  onPressed: listTDCSData.isEmpty
                                      ? () {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content:
                                                  Text('Please run tDCS first'),
                                            ),
                                          );
                                        }
                                      : () {
                                          String eegCsv =
                                              const ListToCsvConverter()
                                                  .convert(
                                            [
                                              [
                                                'Total tDCS data:',
                                                '$tdcsCounts',
                                                'Date',
                                                (DateFormat('dd-MMMM-yyyy')
                                                    .format(DateTime.now()))
                                              ],
                                              [
                                                'Index',
                                                'Time',
                                                'Set Current',
                                                'Actual Current'
                                              ],
                                              listTDCSData,
                                            ],
                                          );
                                          String fileName =
                                              'tdcs_data-${tdcsTimeController.text}-${tdcsCurrent.toInt()}mA-'
                                              '${DateTime.now().millisecondsSinceEpoch}.csv';

                                          listToCsv(eegCsv, fileName);
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.yellow,
                                  ),
                                  child: const Text(
                                    'Get tDCS CSV',
                                    // style: TextStyle(color: Colors.white),
                                  )),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )),
    );
  }
}
