import 'dart:async';

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
    this.requiredStableMatches = 2,
  });

  final TextRecognitionScript scriptLanguage;
  final ScanCandidateExtractor? candidateExtractor;
  final int requiredStableMatches;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  static const _cameraWarmUpDuration = Duration(milliseconds: 750);

  bool hasCameraPermission = false;
  bool isInitializingCamera = false;
  bool _isScanning = false;
  bool _isCapturing = false;
  Timer? _scanTimer;

  @override
  void initState() {
    super.initState();
    startCamera();
  }

  void setInitializingCamera(bool isInitializing) {
    if (!mounted) return;
    setState(() {
      isInitializingCamera = isInitializing;
    });
  }

  void startCamera() async {
    if (isInitializingCamera) return;

    final status = await Permission.camera.request();

    hasCameraPermission = status == PermissionStatus.granted;

    if (!mounted || !hasCameraPermission) {
      if (mounted) setState(() {});
      return;
    }

    setInitializingCamera(true);
    if (!CameraService.instance.hasInitialize()) {
      await CameraService.instance.initialize();
    }
    setInitializingCamera(false);

    try {
      await CameraService.instance.startCamera();
      await CameraService.instance.waitForCameraConfiguration();

      if (!mounted) return;
      _scheduleScanning(_cameraWarmUpDuration);

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
    if (!mounted || _isScanning) return;
    _isScanning = true;

    try {
      final scannedText = await CameraService.instance.scanImage(
        script: widget.scriptLanguage,
        candidateExtractor: widget.candidateExtractor,
        requiredStableMatches: widget.requiredStableMatches,
      );

      if (!mounted || scannedText == null || _isCapturing) return;

      debugPrint('Scanned text: $scannedText');
      await _presentResult(scannedText);
    } catch (e) {
      debugPrint('Error scanning image: $e');
    } finally {
      _isScanning = false;
    }
  }

  Future<void> captureImage() async {
    if (!mounted || _isCapturing) return;

    _scanTimer?.cancel();
    setState(() => _isCapturing = true);

    try {
      final scannedText = await CameraService.instance.captureImage(
        script: widget.scriptLanguage,
        candidateExtractor: widget.candidateExtractor,
      );

      if (!mounted) return;
      if (scannedText == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No text detected. Try again.')),
        );
        _scheduleScanning(_cameraWarmUpDuration);
        return;
      }

      debugPrint('Captured text: $scannedText');
      await _presentResult(scannedText);
    } catch (e) {
      debugPrint('Error capturing image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not capture the image.')),
        );
        _scheduleScanning(_cameraWarmUpDuration);
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _presentResult(String scannedText) async {
    await CameraService.instance.controller?.pausePreview();
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

    if (!mounted) return;
    if (confirmed == true) {
      Navigator.of(context).pop<String>(scannedText);
    } else {
      await CameraService.instance.controller?.resumePreview();
      _scheduleScanning(_cameraWarmUpDuration);
    }
  }

  void _scheduleScanning(Duration delay) {
    _scanTimer?.cancel();
    _scanTimer = Timer(delay, () {
      if (mounted) unawaited(startScanning());
    });
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    unawaited(stopCamera());
    super.dispose();
  }

  Future<void> stopCamera() async {
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
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CameraPreview(CameraService.instance.controller!),
                          Center(
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
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 32,
                            child: Center(
                              child: FloatingActionButton.large(
                                heroTag: 'captureText',
                                onPressed: _isCapturing ? null : captureImage,
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
                      ),
                    )
                  : const Center(child: CircularProgressIndicator())
            : const Center(child: Text('Camera permission denied')),
      ),
    );
  }
}
