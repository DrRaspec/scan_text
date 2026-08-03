import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:scan_text/scan_screen.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _transportController = TextEditingController();

  final transportPatterns = <String, RegExp>{
    '陆运': RegExp(r'陆\s*运|\b(?:by\s+truck|truck|land)\b', caseSensitive: false),
    '海运': RegExp(r'海\s*运|\b(?:by\s+ship|ship|sea)\b', caseSensitive: false),
    '空运': RegExp(r'空\s*运|\b(?:by\s+air|air|flight)\b', caseSensitive: false),
  };

  void _convertData(String scannedText) {
    var normalizedText = scannedText
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('-', ' ');

    normalizedText = normalizedText.replaceAllMapped(
      RegExp(r'\(([^)]*)\)'),
      (match) => ' ${match.group(1)} ',
    );

    String? detectedTransport;

    for (final entry in transportPatterns.entries) {
      if (entry.value.hasMatch(normalizedText)) {
        detectedTransport = entry.key;

        normalizedText = normalizedText.replaceAll(entry.value, ' ');
        break;
      }
    }

    final parts = normalizedText
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .split(' ')
        .where((part) => part.isNotEmpty)
        .toList();

    String code = '';

    // reg for alphanumeric code with at least one letter and one number
    // final codePattern = RegExp(r'^(?=.*[A-Za-z])(?=.*[0-9])[A-Za-z0-9]+$');

    // reg for alphanumeric code starting with a number and containing at least one letter
    final codePattern = RegExp(r'^[0-9](?=.*[A-Za-z])[A-Za-z0-9]*$');

    for (final part in parts) {
      if (codePattern.hasMatch(part)) {
        code = part;
        break;
      }
    }

    if (code.isEmpty && parts.isNotEmpty) {
      code = parts.first;
    }

    _codeController.text = code;
    // _codeController.text = parts.isEmpty ? '' : parts.first;
    _transportController.text = detectedTransport ?? '';
  }

  @override
  void dispose() {
    _codeController.dispose();
    _transportController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Stock Screen')),
        body: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: _codeController,
                decoration: InputDecoration(
                  labelText: 'Enter code',
                  border: OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.document_scanner_outlined),
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ScanScreen(
                            scriptLanguage: TextRecognitionScript.chinese,
                          ),
                        ),
                      );

                      if (result != null && result is String) {
                        _convertData(result);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16.0),
              TextField(
                controller: _transportController,
                decoration: InputDecoration(
                  labelText: 'Enter transport',
                  border: OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.document_scanner_outlined),
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ScanScreen(
                            scriptLanguage: TextRecognitionScript.chinese,
                          ),
                        ),
                      );

                      if (result != null && result is String) {
                        _convertData(result);
                      }
                    },
                  ),
                ),
              ),

              const SizedBox(height: 32.0),

              ElevatedButton(onPressed: null, child: Text('Submit')),
            ],
          ),
        ),
      ),
    );
  }
}
