import 'package:camera/camera.dart';

abstract interface class CameraDiscoveryGateway {
  Future<List<CameraDescription>> available();
}

class PlatformCameraDiscoveryGateway implements CameraDiscoveryGateway {
  const PlatformCameraDiscoveryGateway();

  @override
  Future<List<CameraDescription>> available() => availableCameras();
}
