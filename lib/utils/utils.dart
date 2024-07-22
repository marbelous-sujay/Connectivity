import 'package:flutter/material.dart';

showAlertDialog(BuildContext context, String title, String description) {
  AlertDialog alert = AlertDialog(
    title: Text(title),
    content: Text(description),
    actions: [
      TextButton(
        child: const Text("OK"),
        onPressed: () {
          Navigator.pop(context);
        },
      ),
    ],
  );

  // show the dialog
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return alert;
    },
  );
}