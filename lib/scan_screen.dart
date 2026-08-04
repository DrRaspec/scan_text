import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:scan_text/camera_service.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({
    super.key,
    this.scriptLanguage = TextRecognitionScript.latin,
    this.candidateExtractor,
  });

  final TextRecognitionScript scriptLanguage;
  final ScanCandidateExtractor? candidateExtractor;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool hasCameraPermission = false;
  bool isInitializingCamera = false;

  @override
  void initState() {
    super.initState();
    startCamera();
  }

  void setInitializingCamera(bool isInitializing) {
    setState(() {
      isInitializingCamera = isInitializing;
    });
  }

  void startCamera() async {
    if (isInitializingCamera) return;

    final status = await Permission.camera.request();

    hasCameraPermission = status == PermissionStatus.granted;

    setInitializingCamera(true);
    if (!CameraService.instance.hasInitialize()) {
      await CameraService.instance.initialize();
    }
    setInitializingCamera(false);

    try {
      if (hasCameraPermission && CameraService.instance.controller == null) {
        await CameraService.instance.startCamera();
        Future.delayed(const Duration(seconds: 3), () async {
          if (!mounted) return;

          await CameraService.instance.waitForCameraConfiguration();

          if (!mounted) return;
          await startScanning();
        });
      }

      if (!mounted) return;
      setState(() {});
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() {
        // Store and display error.description
      });

      debugPrint('Camera error: ${error.description}');
    }
  }

  Future<void> startScanning() async {
    try {
      final scannedText = await CameraService.instance.scanImage(
        script: widget.scriptLanguage,
        candidateExtractor: widget.candidateExtractor,
      );

      debugPrint('Scanned text: $scannedText');
      if (scannedText != null) {
        if (!mounted) return;

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Scanned Text'),
              content: Text(scannedText),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('OK'),
                ),

                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );

        if (confirmed == true && mounted) {
          Navigator.of(context).pop<String>(scannedText);
        } else {
          Future.delayed(const Duration(seconds: 3), () async {
            await startScanning();
          });
        }
      }
    } catch (e) {
      debugPrint('Error scanning image: $e');
    }
  }

  @override
  void dispose() {
    stopCamera();
    super.dispose();
  }

  void stopCamera() async {
    await CameraService.instance.stopCamera();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: hasCameraPermission
            ? CameraService.instance.controller != null &&
                      CameraService.instance.controller!.value.isInitialized
                  ? ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: CameraPreview(
                          CameraService.instance.controller!,
                          child: Center(
                            child: FractionallySizedBox(
                              widthFactor: 0.80,
                              heightFactor: 0.40,
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.green,
                                    width: 3,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : const Center(child: CircularProgressIndicator())
            : const Center(child: Text('Camera permission denied')),
      ),
    );
  }
}
