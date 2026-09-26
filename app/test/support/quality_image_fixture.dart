import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as path;

enum TestImagePattern { solid, checker, verticalSplit }

class TestRgb {
  const TestRgb(this.red, this.green, this.blue);

  final int red;
  final int green;
  final int blue;
}

Future<File> writeTestPng({
  required Directory directory,
  required String name,
  required int width,
  required int height,
  required TestImagePattern pattern,
  TestRgb first = const TestRgb(128, 128, 128),
  TestRgb second = const TestRgb(128, 128, 128),
  int checkerSize = 32,
  int blurRadius = 0,
}) async {
  final Uint8List rgba = Uint8List(width * height * 4);
  Uint8List? grayscale = blurRadius > 0 ? Uint8List(width * height) : null;
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final bool useSecond = switch (pattern) {
        TestImagePattern.solid => false,
        TestImagePattern.checker =>
          ((x ~/ checkerSize) + (y ~/ checkerSize)).isOdd,
        TestImagePattern.verticalSplit => x >= width ~/ 2,
      };
      final TestRgb color = useSecond ? second : first;
      final int pixel = (y * width) + x;
      final int offset = pixel * 4;
      rgba[offset] = color.red;
      rgba[offset + 1] = color.green;
      rgba[offset + 2] = color.blue;
      rgba[offset + 3] = 255;
      grayscale?[pixel] =
          ((0.2126 * color.red) +
                  (0.7152 * color.green) +
                  (0.0722 * color.blue))
              .round();
    }
  }
  if (blurRadius > 0) {
    grayscale = _boxBlur(
      grayscale!,
      width: width,
      height: height,
      radius: blurRadius,
    );
    for (
      int pixel = 0, offset = 0;
      pixel < grayscale.length;
      pixel++, offset += 4
    ) {
      final int value = grayscale[pixel];
      rgba[offset] = value;
      rgba[offset + 1] = value;
      rgba[offset + 2] = value;
    }
  }

  final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
    rgba,
  );
  final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final ui.Codec codec = await descriptor.instantiateCodec();
  final ui.FrameInfo frame = await codec.getNextFrame();
  final ByteData? encoded = await frame.image.toByteData(
    format: ui.ImageByteFormat.png,
  );
  try {
    if (encoded == null) {
      throw StateError('Test PNG encoding failed.');
    }
    return File(path.join(directory.path, name)).writeAsBytes(
      encoded.buffer.asUint8List(encoded.offsetInBytes, encoded.lengthInBytes),
      flush: true,
    );
  } finally {
    frame.image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
  }
}

Future<File> writeTestJpeg(Directory directory, String name) {
  const String encoded =
      '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQE'
      'BQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/'
      '2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQU'
      'FBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAADAAQDASIAAhEBAxEB/'
      '8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAw'
      'UFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2Jygg'
      'kKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3'
      'R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxM'
      'XGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQ'
      'EBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AA'
      'ECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGR'
      'omJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6go'
      'OEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0t'
      'PU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD6B+CPgT'
      'w//wAK80//AIlVv37H0HvRRRQB/9k=';
  return File(
    path.join(directory.path, name),
  ).writeAsBytes(base64Decode(encoded), flush: true);
}

Uint8List _boxBlur(
  Uint8List source, {
  required int width,
  required int height,
  required int radius,
}) {
  final Uint8List horizontal = Uint8List(source.length);
  for (int y = 0; y < height; y++) {
    int sum = 0;
    for (int x = -radius; x <= radius; x++) {
      final int clamped = x.clamp(0, width - 1);
      sum += source[(y * width) + clamped];
    }
    for (int x = 0; x < width; x++) {
      horizontal[(y * width) + x] = sum ~/ ((radius * 2) + 1);
      final int removeX = (x - radius).clamp(0, width - 1);
      final int addX = (x + radius + 1).clamp(0, width - 1);
      sum -= source[(y * width) + removeX];
      sum += source[(y * width) + addX];
    }
  }

  final Uint8List output = Uint8List(source.length);
  for (int x = 0; x < width; x++) {
    int sum = 0;
    for (int y = -radius; y <= radius; y++) {
      final int clamped = y.clamp(0, height - 1);
      sum += horizontal[(clamped * width) + x];
    }
    for (int y = 0; y < height; y++) {
      output[(y * width) + x] = sum ~/ ((radius * 2) + 1);
      final int removeY = (y - radius).clamp(0, height - 1);
      final int addY = (y + radius + 1).clamp(0, height - 1);
      sum -= horizontal[(removeY * width) + x];
      sum += horizontal[(addY * width) + x];
    }
  }
  return output;
}
