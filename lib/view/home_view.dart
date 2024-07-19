import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

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

// device status, read, write
const uuidDevSett = 'ff07';

class HomeView extends StatefulWidget {
  const HomeView({
    super.key,
    // required this.device,
    required this.device,
  });

  // final ScanResult device;
  final BluetoothDevice device;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  double eegFrequency = 250;
  double tdcsCurrent = 1.5;

  String batteryLevel = '--';
  String chargingStatus = '------';
  String mode = 'IDLE';
  TextEditingController eegTimeController = TextEditingController();
  TextEditingController tdcsTimeController = TextEditingController();
  String eegButtonText = 'Run EEG';
  String tdcsButtonText = 'Run tDCS';

  late DeviceIdentifier remoteId;

  // late BluetoothDevice selectedDevice;
  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;
  late StreamSubscription<BluetoothConnectionState>
      _connectionStateSubscription;

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
      // getDeviceMode();

      discoverServices();
      getBatteryInfo();
    });
  }

  readBatteryData() async{
    BluetoothCharacteristic data =
    getBluetoothCharacteristics(batteryServiceID, uuidBatteryCustomData);
    try {
      List<int> batData = await readValue(data);

      print("^^^^^^^^^^Init Battery Data: $batData");

      if(batData.isNotEmpty) {
        setState(() {
        if (batData[0] == 10) {
          chargingStatus = 'Charging';
        } else {
          chargingStatus = 'Discharging';
        }

        batteryLevel = batData[1].toString();
      });
      }
    } catch(e, stackTrace){
      print("Error: $e");
      print("Stacktrace: $stackTrace");
    }
  }

  startTdcs() {
    print("😊😊😊😊😊😊😊 Started running TDCS");

    _connectionStateSubscription =
        widget.device.connectionState.listen((state) {
      _connectionState = state;
      // discoverServices();

      //TODO::::::: to read the data
      BluetoothCharacteristic data =
          getBluetoothCharacteristics(easeServiceID, uuidTdcsRead);

      readValue(data);
      //TODO:::::: reading till here

      data.setNotifyValue(true);
      final subscription = data.onValueReceived.listen((value) {
        print("^^^^^^^^^^TDCS Data: $value");

        // onValueReceived is updated:
        //   - anytime read() is called
        //   - anytime a notification arrives (if subscribed)
      });

      // int tdcsTimeElapsed = 0;

      //TODO::::::: to write the data
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
        (0xff & (tdcsTime - 60)),
        (0xff & ((tdcsTime - 60) >> 8)),
        (0xff & ((tdcsTime - 60) >> 16)),
        (0xff & ((tdcsTime - 60) >> 24)),
      ]);

      //TODO::::::: to write the data till here

      // cleanup: cancel subscription when disconnected
      //           device.cancelWhenDisconnected(subscription);
      if (mounted) {
        setState(() {});
      }
    });
  }

  stopTdcs() {
    print("😊😊😊😊😊😊😊 Stopped running TDCS");
  }

  stopEeg() {
    print("😊😊😊😊😊😊😊 Stopped running EEG");
  }

  startEeg() {
    _connectionStateSubscription =
        widget.device.connectionState.listen((state) {
      _connectionState = state;
      discoverServices();

      //TODO:::::::::: TO read the EEG data
      BluetoothCharacteristic data =
          getBluetoothCharacteristics(easeServiceID, uuidEegRead);

      readValue(data);

      //TODO:::::::::: TO read the EEG data till here

      data.setNotifyValue(true);
      final subscription = data.onValueReceived.listen((value) {
        print("^^^^^^^^^^New EEG Data: $value");

        // onValueReceived is updated:
        //   - anytime read() is called
        //   - anytime a notification arrives (if subscribed)
      });

      //TODO:::::::::: TO write the EEG data
      BluetoothCharacteristic data2 =
          getBluetoothCharacteristics(easeServiceID, uuidEegSett);

      int eegTime = int.parse(eegTimeController.text);
      writeValue(
        data2,
        [
          18,
          (0xff & eegTime),
          (0xff & eegTime >> 8),
          (0xff & eegTime >> 16),
          (0xff & eegTime >> 24)
        ],
      );

      //TODO:::::::::: TO write the EEG data

// cleanup: cancel subscription when disconnected
//           device.cancelWhenDisconnected(subscription);
      if (mounted) {
        setState(() {});
      }
    });
  }

  void getBatteryInfo()  {
    _connectionStateSubscription =
        widget.device.connectionState.listen((state) async {
      _connectionState = state;
      // discoverServices();

      BluetoothCharacteristic data =
          getBluetoothCharacteristics(batteryServiceID, uuidBatteryStatus);


      data.setNotifyValue(true);
      final subscription = data.onValueReceived.listen((value) {
        print("^^^^^^^^^^New Battery Data: $value");
        setState(() {

          if(value[0] == 10) {
            chargingStatus = 'Charging';
          } else{
            chargingStatus = 'Discharging';
          }

          batteryLevel = value[1].toString();
        });
        // onValueReceived is updated:
        //   - anytime read() is called
        //   - anytime a notification arrives (if subscribed)
      });
    });
  }

  getDeviceMode(){
    _connectionStateSubscription =
        widget.device.connectionState.listen((state){
          _connectionState = state;
        });

    BluetoothCharacteristic data = getBluetoothCharacteristics(easeServiceID, uuidDevSett);

    // readValue(data);

    data.setNotifyValue(true);
    final subscription = data.onValueReceived.listen((value){
      print("^^^^^^^^^^New Device Mode Data: $value");
      setState(() {
        // if(value[0] == 0){
        //   mode = 'IDLE';
        // } else if(value[0] == 1){
        //   mode = 'EEG';
        // } else if(value[0] == 2){
        //   mode = 'tDCS';
        // }
      });
    });
  }

  Future<List<int>> readValue(BluetoothCharacteristic characteristic) async {
    // BluetoothCharacteristic data = characteristic;
    print("🤷‍♂️🤷‍♂️🤷‍♂️🤷‍♂️🤷‍♂️🤷‍♂️🤷‍♂️🤷‍♂️🤷‍♂️");
    print(" ${characteristic.uuid}  ${characteristic.serviceUuid}  ${characteristic.remoteId}");

    try {

      List<int> readValue = await characteristic.read(timeout: 60);
      print("************************ The read value is  $readValue");
      return readValue;
    } catch (error, stacktrace) {
      print("Error: $error");
      print("Stacktrace: $stacktrace");
    }

    return [];
  }

  Future<void> writeValue(
      BluetoothCharacteristic characteristic, List<int> writeValue) async {
    BluetoothCharacteristic data = characteristic;

    print("************************ The write value is  $writeValue");
    try {
      await data.write(writeValue);
      print("************************ Write done");
    } catch (error, stacktrace) {
      print("Error: $error");
      print("Stacktrace: $stacktrace");
    }
  }

  Future<void> notifyValue(BluetoothCharacteristic characteristic) async {
    BluetoothCharacteristic data = characteristic;

    try {
      bool notifyValue = await data.setNotifyValue(true);
      print("************************ The read value is  $notifyValue");
    } catch (error, stacktrace) {
      print("Error: $error");
      print("Stacktrace: $stacktrace");
    }
  }

  void notifyCase(BluetoothCharacteristic characteristic) {
    characteristic.onValueReceived.listen((value) {
      print("Value: $value");
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
    List<BluetoothService> services =
    await widget.device.discoverServices();
    // for (var service in services) {
    //   // service.serviceUuid
    //
    //   print("Service: ${service.serviceUuid} :: UUID :${service.uuid}");
    //   print("${service.characteristics.length} characteristics");
    //
    //   for (int i = 0; i < service.characteristics.length; i++) {
    //     print("Characteristic ${i + 1}: ${service.characteristics[i].uuid}  "
    //         "${service.characteristics[i].properties}");
    //
    //     for (int j = 0;
    //         j < service.characteristics[i].descriptors.length;
    //         j++) {
    //       print(
    //           "Descriptor ${j + 1}: ${service.characteristics[i].descriptors[j].uuid}");
    //     }
    //   }
    // }
  }

  // Future onDiscoverServicesPressed() async {
  //   if (mounted) {
  //     setState(() {
  //       _isDiscoveringServices = true;
  //     });
  //   }
  //   try {
  //     _services = await widget.device.discoverServices();
  //     Snackbar.show(ABC.c, "Discover Services: Success", success: true);
  //   } catch (e) {
  //     Snackbar.show(ABC.c, prettyException("Discover Services Error:", e), success: false);
  //   }
  //   if (mounted) {
  //     setState(() {
  //       _isDiscoveringServices = false;
  //     });
  //   }
  // }
  //
  // // void discoverServices() async {
  // //   List<BluetoothService> services = widget.bDevice.servicesList;
  // //   setState(() {
  // //     this.services = services;
  // //   });
  // // }
  //
  // // void readCharacteristic(BluetoothCharacteristic characteristic) async {
  // //   var value = await characteristic.read();
  // //   print('Characteristic ${characteristic.uuid}: $value');
  // // }
  // //
  // // void writeCharacteristic(
  // //     BluetoothCharacteristic characteristic, List<int> value) async {
  // //   await characteristic.write(value);
  // //   print('Wrote $value to ${characteristic.uuid}');
  // // }
  //
  // @override
  // void dispose() {
  //   deviceStateSubscription?.cancel();
  //   super.dispose();
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'BLE Application',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        backgroundColor: Colors.lightGreen,
      ),
      body: Center(
          child: Padding(
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
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),

                  ElevatedButton(onPressed: (){
                    readBatteryData();
                  },
                      child: const Text('Get Battery Data')),

                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Battery Status : $chargingStatus',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Container(
                        height: 20,
                        width: 20,
                        color:
                            mode == 'Charging' ? Colors.green : Colors.yellow,
                      )
                    ],
                  ),
                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Mode : EEG/tDCS/IDLE',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Container(
                        height: 20,
                        width: 20,
                        color: mode == 'IDLE'
                            ? Colors.green
                            : mode == 'EEG'
                                ? Colors.yellow
                                : Colors.red,
                      )
                    ],
                  ),

                  const SizedBox(height: 30),
                  const Text(
                    'Time : 00:00:00',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),

              const SizedBox(height: 30),
              const Divider(),
              const SizedBox(height: 20),

              ///Device connection Buttons
              Row(
                children: [
                  Expanded(
                      child: ElevatedButton(
                          onPressed: () {
                            widget.device.connect();
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          '250 Hz',
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '500 Hz',
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.bold),
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
                                borderRadius:
                                    BorderRadius.all(Radius.circular(10.0)),
                                borderSide: BorderSide(color: Colors.green)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                          child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: eegButtonText == 'Run EEG'
                                    ? Colors.purpleAccent
                                    : Colors.deepOrange,
                              ),
                              onPressed: eegButtonText == 'Run EEG'
                                  ? () {
                                      if (eegTimeController.text.isNotEmpty) {
                                        setState(() {
                                          eegButtonText = 'Stop EEG';
                                        });
                                        startEeg();
                                      } else{
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Please enter EEG time first'),
                                          ),
                                        );
                                      }
                                    }
                                  : () {
                                      // stopEEG();

                                      setState(() {
                                        eegButtonText = 'Run EEG';
                                      });
                                    },
                              child: Text(
                                eegButtonText,
                                style: const TextStyle(color: Colors.white),
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          '0.5 mA',
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '1.0 mA',
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '1.5 mA',
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '2.0 mA',
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '2.5 mA',
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '3.0 mA',
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.bold),
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
                                borderRadius:
                                    BorderRadius.all(Radius.circular(10.0)),
                                borderSide: BorderSide(color: Colors.green)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                          child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: tdcsButtonText == 'Run tDCS'
                                    ? Colors.blue
                                    : Colors.deepOrange,
                              ),
                              onPressed: tdcsButtonText == 'Run tDCS'
                                  ? () {
                                      if (tdcsTimeController.text.isNotEmpty) {
                                        setState(() {
                                          tdcsButtonText = 'Stop tDCS';
                                        });
                                        startTdcs();
                                      } else{
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Please enter tDCS time first'),
                                          ),
                                        );
                                      }
                                    }
                                  : () {
                                      // stopTDCS();
                                      setState(() {
                                        tdcsButtonText = 'Run tDCS';
                                      });
                                    },
                              child: const Text(
                                'Run tDCS',
                                style: TextStyle(color: Colors.white),
                              ))),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 20),

              ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.yellow,
                  ),
                  child: const Text(
                    'Generate CSV',
                    // style: TextStyle(color: Colors.white),
                  ))
            ],
          ),
        ),
      )),
    );
  }
}
