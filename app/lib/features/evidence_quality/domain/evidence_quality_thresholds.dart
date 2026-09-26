abstract final class EvidenceQualityThresholds {
  /// Longest edge of the deterministic pixel representation used for metrics.
  static const int maxAnalysisDimensionPx = 1024;

  /// Minimum original-image short edge used by IRIS analysis readiness v1.
  static const int minimumShortEdgePx = 720;

  /// Minimum original-image area used by IRIS analysis readiness v1.
  static const int minimumPixelCount = 921600;

  /// Minimum variance of the 4-neighbor Laplacian on 0–255 luma values.
  static const double minimumSharpnessVariance = 100.0;

  /// Mean 0–255 BT.709 luma values below this trigger a dark limitation.
  static const double darkMeanLuminanceBelow = 50.0;

  /// Mean 0–255 BT.709 luma values above this trigger a bright limitation.
  static const double brightMeanLuminanceAbove = 205.0;

  /// Pixels at or below this 0–255 luma value count as near black.
  static const double darkClippingBoundary = 10.0;

  /// Pixels at or above this 0–255 luma value count as near white.
  static const double brightClippingBoundary = 245.0;

  /// Clipped fractions at or above this value trigger a limitation.
  static const double maximumClippedFraction = 0.20;

  static bool isLowResolution({required int width, required int height}) {
    final int shortEdge = width < height ? width : height;
    return shortEdge < minimumShortEdgePx || width * height < minimumPixelCount;
  }

  static bool isPossiblyBlurred(double sharpnessVariance) =>
      sharpnessVariance < minimumSharpnessVariance;

  static bool isVeryDark(double meanLuminance) =>
      meanLuminance < darkMeanLuminanceBelow;

  static bool isVeryBright(double meanLuminance) =>
      meanLuminance > brightMeanLuminanceAbove;

  static bool hasSignificantClipping(double fraction) =>
      fraction >= maximumClippedFraction;
}
