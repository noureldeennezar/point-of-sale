import 'package:flutter/material.dart';
import 'login.dart';

class settings extends StatelessWidget {
  const settings({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
          appBar: AppBar(title: const Text("Settings")),
          body: TextButton(
              onPressed: () {
                //Navigate to sign up
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const LoginScreen()));
              },
              child:
                  const Text("Log out", style: TextStyle(color: Colors.red)))),
    );
  }
}
