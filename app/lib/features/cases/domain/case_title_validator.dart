class CaseValidationException implements Exception {
  const CaseValidationException(this.message);

  final String message;

  @override
  String toString() => 'CaseValidationException: $message';
}

abstract final class CaseTitleValidator {
  static const int maxLength = 120;

  static String normalize(String input) {
    return input.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String? validationMessage(String input) {
    final String normalized = normalize(input);
    if (normalized.isEmpty) {
      return 'Enter a case title.';
    }
    if (normalized.length > maxLength) {
      return 'Use $maxLength characters or fewer.';
    }
    return null;
  }

  static String normalizeAndValidate(String input) {
    final String? message = validationMessage(input);
    if (message != null) {
      throw CaseValidationException(message);
    }
    return normalize(input);
  }
}
