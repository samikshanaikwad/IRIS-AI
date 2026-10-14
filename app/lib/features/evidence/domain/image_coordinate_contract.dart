import 'dart:math' as math;

/// Versioned pixel-edge coordinate contract shared by detector, depth and any
/// future segmentation derivative. Existing analyses without metadata retain
/// their legacy semantics and are never silently reinterpreted as this version.
abstract final class IrisImageCoordinateContract {
  static const version = 'iris-image-coordinate-v2';
}

enum IrisExifOrientation {
  normal(1),
  mirrorHorizontal(2),
  rotate180(3),
  mirrorVertical(4),
  transpose(5),
  rotate90Clockwise(6),
  transverse(7),
  rotate270Clockwise(8);

  const IrisExifOrientation(this.exifValue);
  final int exifValue;

  bool get swapsAxes => exifValue >= 5;

  static IrisExifOrientation fromExifValue(int value) => values.firstWhere(
    (orientation) => orientation.exifValue == value,
    orElse: () => normal,
  );
}

enum RasterResizeMode { containLetterbox, coverCrop }

enum RasterRounding { floor, nearest }

class ImageExtent {
  const ImageExtent(this.width, this.height)
    : assert(width > 0),
      assert(height > 0);

  final int width, height;
}

class ImageCoordinate {
  const ImageCoordinate(this.x, this.y);
  final double x, y;

  bool get isFinite => x.isFinite && y.isFinite;
}

class ImageCoordinateRect {
  const ImageCoordinateRect(this.left, this.top, this.right, this.bottom);
  final double left, top, right, bottom;

  bool contains(ImageCoordinate point, {double epsilon = 1e-9}) =>
      point.isFinite &&
      point.x >= left - epsilon &&
      point.y >= top - epsilon &&
      point.x <= right + epsilon &&
      point.y <= bottom + epsilon;
}

class ImageAffineTransform {
  const ImageAffineTransform({
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.tx,
    required this.ty,
  });

  final double a, b, c, d, tx, ty;

  ImageCoordinate map(ImageCoordinate point) => ImageCoordinate(
    a * point.x + c * point.y + tx,
    b * point.x + d * point.y + ty,
  );

  ImageAffineTransform then(ImageAffineTransform next) => ImageAffineTransform(
    a: next.a * a + next.c * b,
    b: next.b * a + next.d * b,
    c: next.a * c + next.c * d,
    d: next.b * c + next.d * d,
    tx: next.a * tx + next.c * ty + next.tx,
    ty: next.b * tx + next.d * ty + next.ty,
  );

  ImageAffineTransform inverse() {
    final determinant = a * d - b * c;
    if (!determinant.isFinite || determinant.abs() < 1e-12) {
      throw const FormatException('Image transform is not invertible.');
    }
    final inverseA = d / determinant;
    final inverseB = -b / determinant;
    final inverseC = -c / determinant;
    final inverseD = a / determinant;
    return ImageAffineTransform(
      a: inverseA,
      b: inverseB,
      c: inverseC,
      d: inverseD,
      tx: -(inverseA * tx + inverseC * ty),
      ty: -(inverseB * tx + inverseD * ty),
    );
  }
}

class RasterPlacement {
  const RasterPlacement({
    required this.mode,
    required this.canvas,
    required this.resizedWidth,
    required this.resizedHeight,
    required this.offsetX,
    required this.offsetY,
  }) : assert(resizedWidth > 0),
       assert(resizedHeight > 0);

  factory RasterPlacement.forImage({
    required ImageExtent oriented,
    required ImageExtent canvas,
    required RasterResizeMode mode,
    required RasterRounding rounding,
  }) {
    final widthScale = canvas.width / oriented.width;
    final heightScale = canvas.height / oriented.height;
    final scale = mode == RasterResizeMode.containLetterbox
        ? math.min(widthScale, heightScale)
        : math.max(widthScale, heightScale);
    int round(double value) => switch (rounding) {
      RasterRounding.floor => value.floor(),
      RasterRounding.nearest => value.round(),
    };
    final resizedWidth = math.max(1, round(oriented.width * scale));
    final resizedHeight = math.max(1, round(oriented.height * scale));
    return RasterPlacement(
      mode: mode,
      canvas: canvas,
      resizedWidth: resizedWidth,
      resizedHeight: resizedHeight,
      offsetX: (canvas.width - resizedWidth) ~/ 2,
      offsetY: (canvas.height - resizedHeight) ~/ 2,
    );
  }

  final RasterResizeMode mode;
  final ImageExtent canvas;
  final int resizedWidth, resizedHeight, offsetX, offsetY;

  ImageCoordinateRect get imageContent => ImageCoordinateRect(
    offsetX.toDouble(),
    offsetY.toDouble(),
    (offsetX + resizedWidth).toDouble(),
    (offsetY + resizedHeight).toDouble(),
  );
}

class ImageCoordinateMetadata {
  const ImageCoordinateMetadata({
    required this.contractVersion,
    required this.raw,
    required this.orientation,
    required this.oriented,
    required this.placement,
  });

  factory ImageCoordinateMetadata.create({
    required ImageExtent raw,
    required IrisExifOrientation orientation,
    required ImageExtent canvas,
    required RasterResizeMode mode,
    required RasterRounding rounding,
  }) {
    final oriented = orientation.swapsAxes
        ? ImageExtent(raw.height, raw.width)
        : raw;
    return ImageCoordinateMetadata(
      contractVersion: IrisImageCoordinateContract.version,
      raw: raw,
      orientation: orientation,
      oriented: oriented,
      placement: RasterPlacement.forImage(
        oriented: oriented,
        canvas: canvas,
        mode: mode,
        rounding: rounding,
      ),
    );
  }

  factory ImageCoordinateMetadata.fromJson(Map<String, Object?> json) {
    int integer(String key) {
      final value = json[key];
      if (value is! num || value.toInt() != value) {
        throw FormatException('Invalid image-coordinate field: $key.');
      }
      return value.toInt();
    }

    final version = json['contractVersion'];
    if (version != IrisImageCoordinateContract.version) {
      throw const FormatException('Unsupported image-coordinate contract.');
    }
    final modeName = json['resizeMode'];
    final mode = RasterResizeMode.values.firstWhere(
      (candidate) => candidate.name == modeName,
      orElse: () => throw const FormatException('Invalid resize mode.'),
    );
    final raw = ImageExtent(integer('rawWidth'), integer('rawHeight'));
    final orientationValue = integer('exifOrientation');
    final orientation = IrisExifOrientation.values.firstWhere(
      (candidate) => candidate.exifValue == orientationValue,
      orElse: () => throw const FormatException('Invalid EXIF orientation.'),
    );
    final oriented = ImageExtent(
      integer('orientedWidth'),
      integer('orientedHeight'),
    );
    final expectedOriented = orientation.swapsAxes
        ? ImageExtent(raw.height, raw.width)
        : raw;
    if (oriented.width != expectedOriented.width ||
        oriented.height != expectedOriented.height) {
      throw const FormatException(
        'Oriented image dimensions are inconsistent.',
      );
    }
    final placement = RasterPlacement(
      mode: mode,
      canvas: ImageExtent(integer('canvasWidth'), integer('canvasHeight')),
      resizedWidth: integer('resizedWidth'),
      resizedHeight: integer('resizedHeight'),
      offsetX: integer('offsetX'),
      offsetY: integer('offsetY'),
    );
    final content = placement.imageContent;
    if (mode == RasterResizeMode.containLetterbox &&
        (content.left < 0 ||
            content.top < 0 ||
            content.right > placement.canvas.width ||
            content.bottom > placement.canvas.height)) {
      throw const FormatException('Letterbox content exceeds its canvas.');
    }
    return ImageCoordinateMetadata(
      contractVersion: version! as String,
      raw: raw,
      orientation: orientation,
      oriented: oriented,
      placement: placement,
    );
  }

  final String contractVersion;
  final ImageExtent raw, oriented;
  final IrisExifOrientation orientation;
  final RasterPlacement placement;

  ImageAffineTransform get rawToOriented {
    final width = raw.width.toDouble(), height = raw.height.toDouble();
    return switch (orientation) {
      IrisExifOrientation.normal => const ImageAffineTransform(
        a: 1,
        b: 0,
        c: 0,
        d: 1,
        tx: 0,
        ty: 0,
      ),
      IrisExifOrientation.mirrorHorizontal => ImageAffineTransform(
        a: -1,
        b: 0,
        c: 0,
        d: 1,
        tx: width,
        ty: 0,
      ),
      IrisExifOrientation.rotate180 => ImageAffineTransform(
        a: -1,
        b: 0,
        c: 0,
        d: -1,
        tx: width,
        ty: height,
      ),
      IrisExifOrientation.mirrorVertical => ImageAffineTransform(
        a: 1,
        b: 0,
        c: 0,
        d: -1,
        tx: 0,
        ty: height,
      ),
      IrisExifOrientation.transpose => const ImageAffineTransform(
        a: 0,
        b: 1,
        c: 1,
        d: 0,
        tx: 0,
        ty: 0,
      ),
      IrisExifOrientation.rotate90Clockwise => ImageAffineTransform(
        a: 0,
        b: 1,
        c: -1,
        d: 0,
        tx: height,
        ty: 0,
      ),
      IrisExifOrientation.transverse => ImageAffineTransform(
        a: 0,
        b: -1,
        c: -1,
        d: 0,
        tx: height,
        ty: width,
      ),
      IrisExifOrientation.rotate270Clockwise => ImageAffineTransform(
        a: 0,
        b: -1,
        c: 1,
        d: 0,
        tx: 0,
        ty: width,
      ),
    };
  }

  ImageAffineTransform get orientedToCanvas => ImageAffineTransform(
    a: placement.resizedWidth / oriented.width,
    b: 0,
    c: 0,
    d: placement.resizedHeight / oriented.height,
    tx: placement.offsetX.toDouble(),
    ty: placement.offsetY.toDouble(),
  );

  ImageAffineTransform get rawToCanvas => rawToOriented.then(orientedToCanvas);

  ImageCoordinate rawPointToCanvas(ImageCoordinate point) {
    if (!rawBounds.contains(point)) {
      throw const FormatException('Raw point lies outside the image.');
    }
    return rawToCanvas.map(point);
  }

  ImageCoordinate canvasPointToRaw(ImageCoordinate point) {
    if (!placement.imageContent.contains(point)) {
      throw const FormatException('Canvas point lies outside image content.');
    }
    final mapped = rawToCanvas.inverse().map(point);
    if (!rawBounds.contains(mapped, epsilon: 1e-7)) {
      throw const FormatException('Mapped point lies outside the raw image.');
    }
    return mapped;
  }

  ImageCoordinate normalizedCanvasToRaw(ImageCoordinate point) =>
      canvasPointToRaw(
        ImageCoordinate(
          point.x * placement.canvas.width,
          point.y * placement.canvas.height,
        ),
      );

  ImageCoordinate rawToNormalizedCanvas(ImageCoordinate point) {
    final canvas = rawPointToCanvas(point);
    return ImageCoordinate(
      canvas.x / placement.canvas.width,
      canvas.y / placement.canvas.height,
    );
  }

  ImageCoordinate normalizedCanvasTo({
    required ImageCoordinate point,
    required ImageCoordinateMetadata target,
  }) => target.rawToNormalizedCanvas(normalizedCanvasToRaw(point));

  ImageCoordinateRect get rawBounds =>
      ImageCoordinateRect(0, 0, raw.width.toDouble(), raw.height.toDouble());

  Map<String, Object> toJson() => {
    'contractVersion': contractVersion,
    'rawWidth': raw.width,
    'rawHeight': raw.height,
    'exifOrientation': orientation.exifValue,
    'orientedWidth': oriented.width,
    'orientedHeight': oriented.height,
    'canvasWidth': placement.canvas.width,
    'canvasHeight': placement.canvas.height,
    'resizeMode': placement.mode.name,
    'resizedWidth': placement.resizedWidth,
    'resizedHeight': placement.resizedHeight,
    'offsetX': placement.offsetX,
    'offsetY': placement.offsetY,
  };
}
