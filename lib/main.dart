import 'package:flutter/material.dart';
import 'package:scan_text/camera_service.dart';
import 'package:scan_text/stock_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await CameraService.instance.initialize();

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: StockScreen());
  }
}
