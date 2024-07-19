import 'package:connectivity/view/home_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {


  FlutterBluePlus flutterBluePlus = FlutterBluePlus();
  List<BluetoothDevice> deviceList = [];
  late BluetoothDevice selectedDevice;
  BluetoothConnectionState deviceState = BluetoothConnectionState.disconnected;
  List<BluetoothService> services = [];
  // StreamSubscription<BluetoothConnectionState>? deviceStateSubscription;


  @override
  void initState() {
    initFlutterBluePlus();
    Future.delayed(const Duration(seconds: 3), () {
      // Navigator.of(context).push(MaterialPageRoute(
      //   builder: (context) => const HomeView(device: null, bDevice: BluetoothDevice(),),
      // ));
    });
    super.initState();
  }

  void initFlutterBluePlus() {
    FlutterBluePlus.setLogLevel(LogLevel.verbose, color: true);

    FlutterBluePlus.isSupported.then((isAvailable) {
      if (!isAvailable) {
        print('Bluetooth is not available on this device');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bluetooth is not available on this device')),
        );
      } else{
        print('Bluetooth is available on this device');

        startScan();
      }
    });
  }

  void startScan(){
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 60));

    FlutterBluePlus.scanResults.listen((results){
      for(ScanResult r in results){

        //add all the scanned devices to the deviceList
        if(!deviceList.contains(r.device)){
          deviceList.add(r.device);
        }

        //If the device found is EASE, then set addDevice to the current device
        if(r.device.advName == 'EASE'){
          selectedDevice = r.device;
          FlutterBluePlus.stopScan();
          // connectToDevice();
        }
      }

      //Stop the scan after 60 seconds
      FlutterBluePlus.stopScan();
    });
  }


  // void connectToDevice() async {
  //   await selectedDevice.connect();
  //   deviceStateSubscription = selectedDevice.connectionState.listen((state) {
  //     setState(() {
  //       deviceState = state;
  //     });
  //   });
  //
  // }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Icon(Icons.bluetooth,size: 150,color: Colors.lightGreen,),
      ),
    );
  }
}
