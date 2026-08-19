import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

typedef ScanCandidateExtractor = String? Function(String recognizedText);

class CameraService {
  CameraService._();
  static final CameraService instance = CameraService._();

  List<CameraDescription> _cameras = [];

  CameraController? controller;

  bool _isProcessing = false;
  _ScanSession? _activeScan;
  Future<void>? _stopOperation;

  static final RegExp _whitespacePattern = RegExp(r'\s+');

  final Map<TextRecognitionScript, TextRecognizer> _recognizers = {};

  TextRecognizer _getRecognizer(TextRecognitionScript script) {
    return _recognizers.putIfAbsent(
      script,
      () => TextRecognizer(script: script),
    );
  }

  Future<void> initialize() async {
    _cameras = await availableCameras();
  }

  Future<void>? _cameraConfiguration;

  Future<void> _configureCamera(CameraController cameraController) async {
    try {
      await cameraController.setFocusMode(FocusMode.auto);
      await cameraController.setExposureMode(ExposureMode.auto);
      await cameraController.setFocusPoint(const Offset(0.5, 0.5));
      await cameraController.setExposurePoint(const Offset(0.5, 0.5));
    } on CameraException catch (error) {
      debugPrint('Camera configuration error: ${error.description}');
    }
  }

  Future<void> waitForCameraConfiguration() async {
    final configuration = _cameraConfiguration;

    if (configuration != null) {
      await configuration;
    }
  }

  Future<void> startCamera() async {
    await _stopOperation;

    if (cameraIsInitialized()) return;

    if (_cameras.isEmpty) {
      throw Exception('No cameras available');
    }

    final selectedCamera = _cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );

    controller = CameraController(
      selectedCamera,
      ResolutionPreset.high,
      enableAudio: false,
      // ML Kit takes longer than one camera frame to process an image. A high
      // frame rate only creates frames that are dropped by [processingFrame].
      fps: 15,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    await controller!.initialize();

    _cameraConfiguration = _configureCamera(controller!);
  }

  Future<String?> scanImage({
    TextRecognitionScript script = TextRecognitionScript.latin,
    ScanCandidateExtractor? candidateExtractor,
    int requiredStableMatches = 2,
  }) async {
    if (cameraIsInitialized() == false) {
      throw Exception('Camera is not initialized');
    }

    if (_isProcessing) {
      throw Exception('Already processing an image');
    }

    _isProcessing = true;

    final session = _ScanSession();
    _activeScan = session;
    final recognizer = _getRecognizer(script);

    String? previousCandidate;
    int stableMatches = 0;

    try {
      await controller!.startImageStream((cameraImage) async {
        if (session.processingFrame ||
            session.textDetected ||
            session.cancelled) {
          return;
        }

        session.processingFrame = true;
        final frameFinished = Completer<void>();
        session.frameFinished = frameFinished;

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

          if (session.cancelled) return;

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

          final candidate = _extractCandidate(text, candidateExtractor);
          if (candidate == null) return;

          final candidateKey = candidate.toUpperCase();

          if (candidateKey == previousCandidate) {
            stableMatches++;
          } else {
            previousCandidate = candidateKey;
            stableMatches = 1;
          }

          if (stableMatches < requiredStableMatches) return;

          session.textDetected = true;
          await controller!.stopImageStream();

          if (!session.completer.isCompleted) {
            session.completer.complete(candidate);
          }
        } catch (error, stackTrace) {
          if (!session.cancelled && !session.completer.isCompleted) {
            session.completer.completeError(error, stackTrace);
          }
        } finally {
          session.processingFrame = false;
          frameFinished.complete();
        }
      });

      final detectedText = await session.completer.future;
      return detectedText?.trim();
    } finally {
      try {
        final frameFinished = session.frameFinished;
        if (frameFinished != null && !frameFinished.isCompleted) {
          await frameFinished.future;
        }

        if (controller?.value.isStreamingImages ?? false) {
          await controller!.stopImageStream();
        }
      } finally {
        if (identical(_activeScan, session)) {
          _activeScan = null;
        }
        _isProcessing = false;

        if (!session.finished.isCompleted) {
          session.finished.complete();
        }
      }
    }
  }

  Future<void> cancelScanning() async {
    final session = _activeScan;
    if (session == null) return;

    session.cancelled = true;
    if (!session.completer.isCompleted) {
      session.completer.complete(null);
    }
    await session.finished.future;
  }

  Future<String?> captureImage({
    TextRecognitionScript script = TextRecognitionScript.latin,
    ScanCandidateExtractor? candidateExtractor,
  }) async {
    await cancelScanning();

    if (cameraIsInitialized() == false) {
      throw Exception('Camera is not initialized');
    }

    final image = await controller!.takePicture();
    final inputImage = InputImage.fromFilePath(image.path);

    final recognizer = TextRecognizer(script: script);
    try {
      final result = await recognizer.processImage(inputImage);
      return _extractCandidate(result.text, candidateExtractor);
    } finally {
      await recognizer.close();
      try {
        await File(image.path).delete();
      } on FileSystemException catch (error) {
        debugPrint('Could not delete temporary capture: $error');
      }
    }
  }

  String? _extractCandidate(
    String recognizedText,
    ScanCandidateExtractor? candidateExtractor,
  ) {
    final extracted = candidateExtractor == null
        ? recognizedText
        : candidateExtractor(recognizedText);

    if (extracted == null) return null;

    final candidate = extracted.replaceAll(_whitespacePattern, ' ').trim();
    return candidate.isEmpty ? null : candidate;
  }

  Future<void> stopCamera() {
    final existingOperation = _stopOperation;
    if (existingOperation != null) return existingOperation;

    late final Future<void> operation;
    operation = _stopCamera().whenComplete(() {
      if (identical(_stopOperation, operation)) {
        _stopOperation = null;
      }
    });
    _stopOperation = operation;
    return operation;
  }

  Future<void> _stopCamera() async {
    await cancelScanning();
    await waitForCameraConfiguration();
    _cameraConfiguration = null;

    if (controller?.value.isStreamingImages ?? false) {
      await controller!.stopImageStream();
    }

    await controller?.dispose();
    controller = null;

    for (final recognizer in _recognizers.values) {
      await recognizer.close();
    }
    _recognizers.clear();
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

class _ScanSession {
  final Completer<String?> completer = Completer<String?>();
  final Completer<void> finished = Completer<void>();

  Completer<void>? frameFinished;
  bool processingFrame = false;
  bool textDetected = false;
  bool cancelled = false;
}
