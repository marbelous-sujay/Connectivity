import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:connectivity/utils/snackbar.dart';

class BluetoothOffScreen extends StatelessWidget {
  const BluetoothOffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: Snackbar.snackBarKeyA,
      child: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(
                Icons.bluetooth_disabled,
                size: 200.0,
                color: Colors.blue,
              ),
              const Text(
                'Bluetooth Adapter is Off',
                style: TextStyle(fontSize: 24),
              ),
              if (Platform.isAndroid)
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: ElevatedButton(
                    child: const Text('TURN ON'),
                    onPressed: () async {
                      try {
                        if (Platform.isAndroid) {
                          await FlutterBluePlus.turnOn();
                        }
                      } catch (e) {
                        Snackbar.show(ABC.a, prettyException
                          ("Error Turning On:", e), success: false);
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
