import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:iris/features/classification/application/evidence_classification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled V0 classifier asset matches the accepted frozen model hash',
    () async {
      final ByteData bytes = await rootBundle.load(
        'assets/models/iris_v0_experimental_mobilenet_v3_small.tflite',
      );
      final String actual = sha256
          .convert(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          )
          .toString();

      expect(actual, EvidenceClassificationService.modelSha256);
    },
  );
}
