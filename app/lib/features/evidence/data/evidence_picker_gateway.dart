import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import '../application/evidence_acquisition_service.dart';
import '../domain/evidence_image.dart';

abstract interface class EvidencePickerGateway {
  Future<List<EvidenceImportCandidate>> pickOne();

  Future<List<EvidenceImportCandidate>> pickMultiple();
}

class PlatformEvidencePickerGateway implements EvidencePickerGateway {
  PlatformEvidencePickerGateway({ImagePicker? picker})
    : _picker = picker ?? ImagePicker() {
    final ImagePickerPlatform implementation = ImagePickerPlatform.instance;
    if (implementation is ImagePickerAndroid) {
      implementation.useAndroidPhotoPicker = true;
    }
  }

  final ImagePicker _picker;

  @override
  Future<List<EvidenceImportCandidate>> pickOne() async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
    return file == null
        ? const <EvidenceImportCandidate>[]
        : <EvidenceImportCandidate>[_candidate(file)];
  }

  @override
  Future<List<EvidenceImportCandidate>> pickMultiple() async {
    final List<XFile> files = await _picker.pickMultiImage(
      requestFullMetadata: false,
    );
    return files.map(_candidate).toList(growable: false);
  }

  EvidenceImportCandidate _candidate(XFile file) => EvidenceImportCandidate(
    path: file.path,
    source: EvidenceSource.gallery,
    originalDisplayName: file.name,
    mimeType: file.mimeType,
  );
}
