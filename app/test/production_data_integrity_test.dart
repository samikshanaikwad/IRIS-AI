import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'production source contains no fabricated incident records or results',
    () {
      final List<RegExp> prohibitedPatterns = <RegExp>[
        RegExp(r'\bmock\b', caseSensitive: false),
        RegExp(r'\bfake\b', caseSensitive: false),
        RegExp(r'\bdummy\b', caseSensitive: false),
        RegExp(r'sample case', caseSensitive: false),
        RegExp(r'demo case', caseSensitive: false),
        RegExp(r'sample incident', caseSensitive: false),
        RegExp(r'demo incident', caseSensitive: false),
        RegExp(r'case\s*#001', caseSensitive: false),
        RegExp(r'seedDatabase', caseSensitive: false),
        RegExp(r'seedCases', caseSensitive: false),
        RegExp(r'insertDemoData', caseSensitive: false),
        RegExp(r'\b87%', caseSensitive: false),
        RegExp(r'accident detected', caseSensitive: false),
        RegExp(r'reconstruction complete', caseSensitive: false),
      ];
      final List<String> violations = <String>[];

      for (final FileSystemEntity entity in Directory(
        'lib',
      ).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }

        final String source = entity.readAsStringSync();
        for (final RegExp pattern in prohibitedPatterns) {
          if (pattern.hasMatch(source)) {
            violations.add('${entity.path}: ${pattern.pattern}');
          }
        }
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );
}
