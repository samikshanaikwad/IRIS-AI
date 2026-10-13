import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

/// Canonical TASK012 case-local world coordinate.
///
/// X points east, Y points up, Z points north. The confirmed TASK011 incident
/// location is (0, 0, 0). Map coordinates use the accepted TASK011 local
/// conversion and are expressed in metres. Evidence coordinates enter this
/// frame only through an explicit user-supplied TASK012B transform; that does
/// not make the source geometry or its scale measured/metric evidence.
class CaseLocalWorldPoint {
  const CaseLocalWorldPoint({
    required this.xEast,
    required this.yUp,
    required this.zNorth,
  });

  const CaseLocalWorldPoint.origin() : xEast = 0, yUp = 0, zNorth = 0;

  final double xEast, yUp, zNorth;

  factory CaseLocalWorldPoint.fromMapXZ(List<double> value, {double yUp = 0}) {
    if (value.length < 2 ||
        !value[0].isFinite ||
        !value[1].isFinite ||
        !yUp.isFinite) {
      throw const FormatException('Invalid TASK011 local map coordinate');
    }
    return CaseLocalWorldPoint(xEast: value[0], yUp: yUp, zNorth: value[1]);
  }

  List<double> get mapXZ => [xEast, zNorth];
}

/// Single conversion boundary shared by TASK011 map data and TASK012 scenes.
abstract final class CaseLocalWorldFrame {
  static const String version = 'task012-case-local-world-v1';
  static const String contract =
      'origin=confirmed incident location; X=east; Y=up; Z=north';

  // Preserve the accepted TASK011 persisted conversion exactly. Changing this
  // would reinterpret existing roads and user alignments and therefore needs a
  // separately designed migration, not a display repair.
  static const double metresPerDegree = 111320.0;
  static const double acceptedEastScale = .999;

  static List<double> geographicToMapXZ({
    required double latitude,
    required double longitude,
    required double originLatitude,
    required double originLongitude,
  }) => [
    (longitude - originLongitude) * metresPerDegree * acceptedEastScale,
    (latitude - originLatitude) * metresPerDegree,
  ];

  /// Stable identity for a case's confirmed-location world frame. Mutable road
  /// or environment content is deliberately excluded.
  static String fingerprint({
    required String caseId,
    required double originLatitude,
    required double originLongitude,
  }) {
    if (caseId.isEmpty ||
        !originLatitude.isFinite ||
        !originLongitude.isFinite ||
        originLatitude.abs() > 90 ||
        originLongitude.abs() > 180) {
      throw const FormatException('Invalid canonical world-frame identity');
    }
    return sha256
        .convert(
          utf8.encode(
            '$version|$caseId|'
            '${originLatitude.toStringAsPrecision(17)}|'
            '${originLongitude.toStringAsPrecision(17)}',
          ),
        )
        .toString();
  }

  /// Applies the persisted TASK012B convention exactly once:
  /// uniform scale, positive yaw about +Y, then X/Y/Z translation.
  static CaseLocalWorldPoint alignRelative({
    required double relativeX,
    required double relativeY,
    required double relativeZ,
    required double translationX,
    required double translationY,
    required double translationZ,
    required double yaw,
    required double uniformScale,
  }) {
    final x = relativeX * uniformScale;
    final y = relativeY * uniformScale;
    final z = relativeZ * uniformScale;
    final c = math.cos(yaw), s = math.sin(yaw);
    return CaseLocalWorldPoint(
      xEast: x * c - z * s + translationX,
      yUp: y + translationY,
      zNorth: x * s + z * c + translationZ,
    );
  }
}

double nearestMapPolylineDistance(
  CaseLocalWorldPoint point,
  Iterable<List<List<double>>> polylines,
) {
  var nearest = double.infinity;
  for (final line in polylines) {
    for (var i = 1; i < line.length; i++) {
      final a = CaseLocalWorldPoint.fromMapXZ(line[i - 1]);
      final b = CaseLocalWorldPoint.fromMapXZ(line[i]);
      final dx = b.xEast - a.xEast, dz = b.zNorth - a.zNorth;
      final length2 = dx * dx + dz * dz;
      final t = length2 == 0
          ? 0.0
          : (((point.xEast - a.xEast) * dx + (point.zNorth - a.zNorth) * dz) /
                    length2)
                .clamp(0.0, 1.0);
      final x = a.xEast + dx * t, z = a.zNorth + dz * t;
      nearest = math.min(
        nearest,
        math.sqrt(math.pow(point.xEast - x, 2) + math.pow(point.zNorth - z, 2)),
      );
    }
  }
  return nearest;
}

String mapDistanceBucket(double distance) {
  if (!distance.isFinite) return 'noRoadSegments';
  if (distance <= 5) return 'within5';
  if (distance <= 10) return 'within10';
  if (distance <= 20) return 'within20';
  if (distance <= 40) return 'within40';
  return 'over40';
}
