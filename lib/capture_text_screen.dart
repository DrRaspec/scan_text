import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:scan_text/camera_service.dart';

class CaptureTextScreen extends StatefulWidget {
  const CaptureTextScreen({
    super.key,
    this.scriptLanguage = TextRecognitionScript.latin,
  });

  final TextRecognitionScript scriptLanguage;

  @override
  State<CaptureTextScreen> createState() => _CaptureTextScreenState();
}

class _CaptureTextScreenState extends State<CaptureTextScreen> {
  bool hasCameraPermission = false;
  bool isInitializingCamera = true;
  bool _isCapturing = false;
  String? _cameraError;
  late final Future<void> _initialization;
  Future<void>? _captureOperation;

  @override
  void initState() {
    super.initState();
    _initialization = startCamera();
  }

  Future<void> startCamera() async {
    try {
      final status = await Permission.camera.request();
      if (!mounted) return;
      hasCameraPermission = status == PermissionStatus.granted;
      if (!hasCameraPermission) return;

      if (!CameraService.instance.hasInitialize()) {
        await CameraService.instance.initialize();
      }
      if (!mounted) return;
      await CameraService.instance.startCamera();
      await CameraService.instance.waitForCameraConfiguration();
    } catch (error) {
      if (mounted) {
        _cameraError = 'Could not start the camera. Please reopen this screen.';
      }
      debugPrint('Camera error: $error');
    } finally {
      if (mounted) {
        setState(() => isInitializingCamera = false);
      }
    }
  }

  Future<void> captureImage() async {
    if (!mounted || _isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      final detectedText = await CameraService.instance.captureImage(
        script: widget.scriptLanguage,
      );
      if (!mounted) return;
      final hasText = detectedText != null && detectedText.isNotEmpty;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(hasText ? 'Detected Text' : 'No Text Detected'),
          content: SingleChildScrollView(
            child: Text(
              hasText ? detectedText : 'No text was detected in the image.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (error) {
      debugPrint('Capture error: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not capture the image. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  void dispose() {
    unawaited(stopCamera());
    super.dispose();
  }

  Future<void> stopCamera() async {
    // Let initialization and any capture finish before disposing their camera.
    await _initialization;
    await _captureOperation;
    await CameraService.instance.stopCamera();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: isInitializingCamera
            ? const Center(child: CircularProgressIndicator())
            : _cameraError != null
            ? Center(child: Text(_cameraError!))
            : hasCameraPermission
            ? CameraService.instance.controller != null &&
                      CameraService.instance.controller!.value.isInitialized
                  ? Stack(
                      children: [
                        ColoredBox(
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
                        ),

                        Positioned(
                          bottom: 20,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: FloatingActionButton.large(
                              onPressed: _isCapturing
                                  ? null
                                  : () {
                                      _captureOperation = captureImage();
                                    },
                              tooltip: 'Capture image and scan text',
                              child: _isCapturing
                                  ? const SizedBox.square(
                                      dimension: 28,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                      ),
                                    )
                                  : const Icon(Icons.camera_alt_outlined),
                            ),
                          ),
                        ),
                      ],
                    )
                  : const Center(child: CircularProgressIndicator())
            : const Center(child: Text('Camera permission denied')),
      ),
    );
  }
}
