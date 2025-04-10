import 'dart:async';

import 'package:connectivity/view/home_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:connectivity/utils/snackbar.dart';
import 'package:permission_handler/permission_handler.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _isScanning = false;
  late StreamSubscription<List<ScanResult>> _scanResultsSubscription;
  late StreamSubscription<bool> _isScanningSubscription;

  bool locationPermissionGranted = false;
  bool nearbyPermissionGranted = false;

  @override
  void initState() {
    super.initState();

    getLocationPermission();
    getNearbyPermission();

    Future.delayed(const Duration(seconds: 2), () {
      _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (int i = 0; i < results.length; i++) {
          if (results[i].device.advName == "EASE") {
            results[i].device.connect();
            FlutterBluePlus.stopScan();

            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => HomeView(
                  // device: results[i],
                  device: results[i].device,
                ),
              ),
            );
          }
        }
      }, onError: (e) {
        Snackbar.show(ABC.b, prettyException("Scan Error:", e), success: false);
      });

      onScanPressed();
      setState(() {
        _isScanning = true;
      });
    });
  }

  @override
  void dispose() {
    _scanResultsSubscription.cancel();
    _isScanningSubscription.cancel();
    super.dispose();
  }

  Future onScanPressed() async {
    try {
      FlutterBluePlus.systemDevices;
    } catch (e) {
      Snackbar.show(ABC.b, prettyException("System Devices Error:", e),
          success: false);
    }
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      Snackbar.show(ABC.b, prettyException("Start Scan Error:", e),
          success: false);
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future getLocationPermission() async {
    if (await Permission.location.request().isGranted) {
      locationPermissionGranted = true;
    } else if (await Permission.location.request().isPermanentlyDenied) {
      throw ('location.request().isPermanentlyDenied');
    } else if (await Permission.location.request().isDenied) {
      throw ('location.request().isDenied');
    }
  }

  Future getNearbyPermission() async {
    if (await Permission.nearbyWifiDevices.request().isGranted) {
      nearbyPermissionGranted = true;
    } else if (await Permission.nearbyWifiDevices
        .request()
        .isPermanentlyDenied) {
      throw ('location.request().isPermanentlyDenied');
    } else if (await Permission.nearbyWifiDevices.request().isDenied) {
      throw ('location.request().isDenied');
    }
  }

  Future onStopPressed() async {
    try {
      FlutterBluePlus.stopScan();
    } catch (e) {
      Snackbar.show(ABC.b, prettyException("Stop Scan Error:", e),
          success: false);
    }
  }

  Future onRefresh() {
    if (_isScanning == false) {
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    }
    if (mounted) {
      setState(() {});
    }
    return Future.delayed(const Duration(milliseconds: 500));
  }

  Widget buildScanButton(BuildContext context) {
    if (FlutterBluePlus.isScanningNow) {
      return FloatingActionButton(
        onPressed: onStopPressed,
        backgroundColor: Colors.red,
        child: const Icon(Icons.stop),
      );
    } else {
      return FloatingActionButton(
          onPressed: onScanPressed, child: const Text("SCAN"));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: Snackbar.snackBarKeyB,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Find Devices'),
        ),
        body: RefreshIndicator(
            onRefresh: onRefresh,
            child: const Center(
              child: Text('EASE not found yet!'),
            )),
        floatingActionButton: buildScanButton(context),
      ),
    );
  }
}
