import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class CameraService {
  CameraService._();
  static final CameraService instance = CameraService._();

  List<CameraDescription> _cameras = [];

  CameraController? controller;

  bool _isProcessing = false;

  Future<void> initialize() async {
    _cameras = await availableCameras();
  }

  Future<void> startCamera() async {
    if (_cameras.isEmpty) {
      throw Exception('No cameras available');
    }

    controller = CameraController(
      _cameras[0],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    await controller!.initialize();
    await controller!.setFocusMode(FocusMode.auto);
    await controller!.setExposureMode(ExposureMode.auto);
  }

  Future<String?> scanImage({
    TextRecognitionScript script = TextRecognitionScript.latin,
  }) async {
    if (cameraIsInitialized() == false) {
      throw Exception('Camera is not initialized');
    }

    if (_isProcessing) {
      throw Exception('Already processing an image');
    }

    _isProcessing = true;

    final completer = Completer<String?>();
    final recognizer = TextRecognizer(script: script);

    bool processingFrame = false;
    bool textDetected = false;

    await controller!.startImageStream((cameraImage) async {
      if (processingFrame || textDetected) return;

      processingFrame = true;

      try {
        final inputImage = convertCameraImage(cameraImage);
        if (inputImage == null) return;

        final metadata = inputImage.metadata!;
        final rotation = metadata.rotation;
        final rawSize = metadata.size;

        final isSideways =
            rotation == InputImageRotation.rotation90deg ||
            rotation == InputImageRotation.rotation270deg;

        final imageSize = Platform.isAndroid && isSideways
            ? Size(rawSize.height, rawSize.width)
            : rawSize;

        final result = await recognizer.processImage(inputImage);

        final scanArea = Rect.fromCenter(
          center: Offset(imageSize.width / 2, imageSize.height / 2),
          width: imageSize.width * 0.80,
          height: imageSize.height * 0.40,
        );

        final text = result.blocks
            .expand((block) => block.lines)
            .where((line) => scanArea.contains(line.boundingBox.center))
            .map((line) => line.text)
            .join('\n')
            .trim();

        if (text.isNotEmpty) {
          textDetected = true;
          await controller!.stopImageStream();
          completer.complete(text);
        }
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      } finally {
        processingFrame = false;
      }
    });

    try {
      final detectedText = await completer.future;
      return detectedText?.trim();
    } finally {
      if (controller?.value.isStreamingImages ?? false) {
        await controller!.stopImageStream();
      }

      await recognizer.close();
      _isProcessing = false;
    }
  }

  Future<String?> captureImage({
    TextRecognitionScript script = TextRecognitionScript.latin,
  }) async {
    if (cameraIsInitialized() == false) {
      throw Exception('Camera is not initialized');
    }

    final image = await controller!.takePicture();
    final inputImage = InputImage.fromFilePath(image.path);

    final recognizer = TextRecognizer(script: script);
    final result = await recognizer.processImage(inputImage);
    await recognizer.close();

    return result.text.trim();
  }

  Future<void> stopCamera() async {
    await controller?.dispose();
    controller = null;
  }

  bool hasInitialize() {
    return _cameras.isNotEmpty;
  }

  bool cameraIsInitialized() {
    return controller != null && controller!.value.isInitialized;
  }

  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  InputImage? convertCameraImage(CameraImage image) {
    final currentController = controller;

    if (currentController == null || !currentController.value.isInitialized) {
      return null;
    }

    final camera = currentController.description;
    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;

    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation =
          _orientations[currentController.value.deviceOrientation];

      if (rotationCompensation == null) {
        return null;
      }

      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }

      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }

    if (rotation == null) {
      return null;
    }

    final format = InputImageFormatValue.fromRawValue(image.format.raw);

    if (format == null) {
      return null;
    }

    final isSupportedFormat = Platform.isAndroid
        ? format == InputImageFormat.nv21
        : format == InputImageFormat.bgra8888;

    if (!isSupportedFormat || image.planes.length != 1) {
      return null;
    }

    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }
}
