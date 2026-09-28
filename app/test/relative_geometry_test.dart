import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/geometry/domain/relative_geometry.dart';

void main() {
  test('relative projection preserves nearer/farther ordering', () {
    final geometry = buildRelativeGeometry(
      evidenceId: 'e', depthSha256: 'a' * 64, depthAnalyzedAt: DateTime.utc(2026),
      depth: Float32List.fromList(<double>[1, 2, 3, 4]), depthWidth: 2, depthHeight: 2,
      originalWidth: 2, originalHeight: 2, maxPoints: 4,
    );
    expect(geometry.points.first.z, greaterThan(geometry.points.last.z));
    expect(geometry.points.last.z, 1);
    expect(geometry.points.every((p) => p.x.isFinite && p.y.isFinite), isTrue);
  });

  test('rejects non-finite and degenerate depth', () {
    expect(() => buildRelativeGeometry(evidenceId: 'e', depthSha256: 'a' * 64, depthAnalyzedAt: DateTime.utc(2026), depth: Float32List.fromList(<double>[double.nan]), depthWidth: 1, depthHeight: 1, originalWidth: 1, originalHeight: 1), throwsFormatException);
    expect(() => buildRelativeGeometry(evidenceId: 'e', depthSha256: 'a' * 64, depthAnalyzedAt: DateTime.utc(2026), depth: Float32List.fromList(<double>[1, 1]), depthWidth: 2, depthHeight: 1, originalWidth: 2, originalHeight: 1), throwsFormatException);
  });

  test('sampling is bounded and deterministic for portrait and landscape', () {
    final values = Float32List.fromList(List<double>.generate(100, (i) => i + 1));
    final a = buildRelativeGeometry(evidenceId: 'e', depthSha256: 'a' * 64, depthAnalyzedAt: DateTime.utc(2026), depth: values, depthWidth: 10, depthHeight: 10, originalWidth: 2, originalHeight: 4, maxPoints: 100);
    final b = buildRelativeGeometry(evidenceId: 'e', depthSha256: 'a' * 64, depthAnalyzedAt: DateTime.utc(2026), depth: values, depthWidth: 10, depthHeight: 10, originalWidth: 4, originalHeight: 2, maxPoints: 100);
    expect(a.points.length, lessThanOrEqualTo(100));
    expect(a.points.map((p) => p.z), buildRelativeGeometry(evidenceId: 'e', depthSha256: 'a' * 64, depthAnalyzedAt: DateTime.utc(2026), depth: values, depthWidth: 10, depthHeight: 10, originalWidth: 2, originalHeight: 4, maxPoints: 100).points.map((p) => p.z));
    expect(a.points, isNotEmpty); expect(b.points, isNotEmpty);
  });
}
