import 'package:flutter/material.dart';
import 'package:scan_text/capture_text_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CaptureTextScreen(),
              ),
            );
          },
          child: const Text('Capture Text'),
        ),
      ),
    );
  }
}
