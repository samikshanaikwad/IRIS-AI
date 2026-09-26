import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/iris_spacing.dart';
import '../../../core/widgets/iris_app_bar.dart';
import '../../../core/widgets/iris_async_states.dart';
import '../../../core/widgets/iris_button.dart';
import '../application/evidence_acquisition_service.dart';
import '../data/camera_gateway.dart';
import '../domain/evidence_image.dart';

class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({this.cameraGateway, super.key});

  final CameraDiscoveryGateway? cameraGateway;

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  CameraDescription? _camera;
  bool _initializing = true;
  bool _capturing = false;
  String? _error;
  late final CameraDiscoveryGateway _cameraGateway;

  @override
  void initState() {
    super.initState();
    _cameraGateway =
        widget.cameraGateway ?? const PlatformCameraDiscoveryGateway();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      unawaited(controller.dispose());
      _controller = null;
    } else if (state == AppLifecycleState.resumed && _camera != null) {
      unawaited(_initializeController(_camera!));
    }
  }

  Future<void> _initialize() async {
    try {
      final List<CameraDescription> cameras = await _cameraGateway.available();
      if (cameras.isEmpty) {
        throw CameraException('NoCamera', 'No camera is available.');
      }
      _camera = cameras.first;
      await _initializeController(cameras.first);
    } on CameraException catch (error) {
      _setError(cameraFailureMessage(error.code));
    } on Object {
      _setError('The camera could not be initialized on this device.');
    }
  }

  Future<void> _initializeController(CameraDescription camera) async {
    final CameraController previous =
        _controller ??
        CameraController(
          camera,
          ResolutionPreset.max,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );
    _controller = previous;
    try {
      await previous.initialize();
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = null;
        });
      }
    } on CameraException catch (error) {
      _setError(cameraFailureMessage(error.code));
    }
  }

  void _setError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _initializing = false;
      _error = message;
    });
  }

  Future<void> _capture() async {
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final XFile file = await controller.takePicture();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(
        EvidenceImportCandidate(
          path: file.path,
          source: EvidenceSource.camera,
          originalDisplayName: file.name,
          capturedAt: DateTime.now().toUtc(),
          mimeType: file.mimeType ?? 'image/jpeg',
        ),
      );
    } on CameraException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The image could not be captured. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _capturing = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CameraController? controller = _controller;
    return Scaffold(
      appBar: const IrisAppBar(title: 'Capture Evidence'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(IrisSpacing.md),
          child: _error != null
              ? IrisErrorState(
                  title: 'Camera unavailable',
                  message: _error!,
                  onRetry: () {
                    setState(() => _initializing = true);
                    unawaited(_initialize());
                  },
                )
              : _initializing ||
                    controller == null ||
                    !controller.value.isInitialized
              ? const IrisLoadingState(label: 'Opening camera')
              : Column(
                  children: <Widget>[
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Center(child: CameraPreview(controller)),
                      ),
                    ),
                    const SizedBox(height: IrisSpacing.md),
                    IrisPrimaryButton(
                      key: const ValueKey<String>('take-evidence-photo-button'),
                      label: _capturing ? 'Saving image…' : 'Capture Evidence',
                      icon: Icons.camera_alt_outlined,
                      onPressed: _capturing ? null : _capture,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

String cameraFailureMessage(String code) {
  return switch (code) {
    'CameraAccessDenied' || 'CameraAccessDeniedWithoutPrompt' =>
      'Camera permission is required to capture evidence. You can enable it in Android settings.',
    'CameraAccessRestricted' => 'Camera access is restricted on this device.',
    _ => 'The camera is unavailable. Try again or import evidence instead.',
  };
}
