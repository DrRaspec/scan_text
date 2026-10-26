import 'dart:async';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  final _previewKey = GlobalKey();
  ui.Image? _frozenPreview;
  MemoryImage? _capturedImage;
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
      // Show the preview as soon as the camera is initialized. Focus and
      // exposure configuration can finish while the user frames the text.
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
    ui.Image? frozenPreview;
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary =
          _previewKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      frozenPreview = await boundary.toImage();
      if (!mounted) return;
      setState(() => _frozenPreview = frozenPreview);
      // Cover the native texture before pausing can detach its surface.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await CameraService.instance.controller?.pausePreview();
      if (!mounted) return;
      final detectedText = await CameraService.instance.captureImage(
        script: widget.scriptLanguage,
        onImageCaptured: (bytes) async {
          if (!mounted) return;
          final photo = MemoryImage(bytes);
          await precacheImage(photo, context);
          if (!mounted) return;
          setState(() => _capturedImage = photo);
          // Paint the captured photo before starting text recognition.
          if (mounted) await WidgetsBinding.instance.endOfFrame;
        },
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
      if (mounted) {
        try {
          await CameraService.instance.controller?.resumePreview();
          // Keep the still image covering the texture while preview reattaches.
          if (mounted) await WidgetsBinding.instance.endOfFrame;
        } catch (error) {
          debugPrint('Could not resume camera preview: $error');
          if (mounted) {
            setState(
              () => _cameraError =
                  'Could not resume the camera. Please reopen this screen.',
            );
          }
        } finally {
          if (mounted) {
            setState(() {
              _capturedImage = null;
              _frozenPreview = null;
              _isCapturing = false;
            });
          }
        }
      }
      if (mounted) await WidgetsBinding.instance.endOfFrame;
      frozenPreview?.dispose();
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
                        RepaintBoundary(
                          key: _previewKey,
                          child: ColoredBox(
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
                        ),
                        if (_frozenPreview != null)
                          Positioned.fill(
                            child: RawImage(
                              image: _frozenPreview,
                              fit: BoxFit.contain,
                            ),
                          ),
                        if (_capturedImage != null)
                          Positioned.fill(
                            child: ColoredBox(
                              color: Colors.black,
                              child: Image(
                                image: _capturedImage!,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
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
