/// Validation utilities for SyncConfig and related configuration classes.
library;

/// Result of a validation operation containing errors and warnings.
class ValidationResult {
  final List<ValidationError> errors = [];
  final List<ValidationWarning> warnings = [];
  final List<String> _contextMessage;
  final Map<String, Object>? _contextDetails;

  ValidationResult(
      [String? contextMessage, Map<String, Object>? contextDetails])
      : _contextDetails = contextDetails,
        _contextMessage = contextMessage == null ? const [] : [contextMessage];

  /// True if validation passed (no errors, warnings are allowed).
  bool get isValid => errors.isEmpty;

  /// True if there are any issues (errors or warnings).
  bool get hasIssues => errors.isNotEmpty || warnings.isNotEmpty;

  /// Add a validation error (blocks operation).
  void addError(String message, {Object? details, List<String>? context}) {
    errors.add(ValidationError(
        context == null ? _contextMessage : [..._contextMessage, ...context],
        message,
        details: _withContextDetails(details, _contextDetails)));
  }

  /// Add a validation warning (informational).
  void addWarning(String message, {Object? details, List<String>? context}) {
    warnings.add(ValidationWarning(
        context == null ? _contextMessage : [..._contextMessage, ...context],
        message,
        details: _withContextDetails(details, _contextDetails)));
  }

  void addSubvalidationResult(ValidationResult result,
      {String? context, Map<String, Object>? details}) {
    // Add transform validation errors to the overall result
    for (final error in result.errors) {
      errors.add(ValidationError(
          _buildContext(context, error.context), error.message,
          details: _withContextDetails(error.details, details)));
    }

    // Add transform validation warnings
    for (final warning in result.warnings) {
      warnings.add(ValidationWarning(
          _buildContext(context, warning.context), warning.message,
          details: _withContextDetails(warning.details, details)));
    }
  }

  List<String> _buildContext(String? context, List<String> errorContext) {
    return context == null && _contextMessage.isEmpty
        ? errorContext
        : <String>[
            ..._contextMessage,
            if (context != null) context,
            ...errorContext
          ];
  }

  Object? _withContextDetails(Object? details, Map<String, Object>? context) {
    return context == null
        ? details
        : {...context, 'subvalidation_error': details};
  }

  static ValidationResult merge(List<ValidationResult> results) {
    final combinedValidationResult = ValidationResult();
    for (final result in results) {
      combinedValidationResult.errors.addAll(result.errors);
      combinedValidationResult.warnings.addAll(result.warnings);
    }
    return combinedValidationResult;
  }

  /// Throw SyncConfigValidationException if validation failed.
  void throwIfInvalid() {
    if (!isValid) {
      throw SyncConfigValidationException(this);
    }
  }

  /// Get a formatted summary of all issues.
  String getSummary() {
    final buffer = StringBuffer();
    buffer.writeln();
    if (errors.isNotEmpty) {
      buffer.writeln('-' * 40);
      buffer.writeln('Validation Errors (${errors.length}):');
      buffer.writeln('-' * 40);
      for (int i = 0; i < errors.length; i++) {
        buffer.writeln();
        buffer.writeln('  ${i + 1}. ${errors[i].fullMessage}');
      }
    }

    if (warnings.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln('-' * 40);
      buffer.writeln('Validation Warnings (${warnings.length}):');
      buffer.writeln('-' * 40);
      for (int i = 0; i < warnings.length; i++) {
        buffer.writeln();
        buffer.writeln('  ${i + 1}. ${warnings[i].fullMessage}');
      }
    }
    buffer.writeln();
    return buffer.toString();
  }
}

/// Base class for validation issues.
abstract class ValidationIssue {
  final List<String> context;
  final String message;
  final Object? details;

  const ValidationIssue(this.context, this.message, {this.details});

  @override
  String toString() => message;

  String get fullMessage =>
      context.isEmpty ? message : '[${context.join(' > ')}]:\n\n$message';
}

/// A validation error that prevents the configuration from being used.
class ValidationError extends ValidationIssue {
  const ValidationError(List<String> context, String message, {Object? details})
      : super(context, message, details: details);
}

/// A validation warning about potential issues.
class ValidationWarning extends ValidationIssue {
  const ValidationWarning(List<String> context, String message,
      {Object? details})
      : super(context, message, details: details);
}

/// Exception thrown when SyncConfig validation fails.
class SyncConfigValidationException implements Exception {
  final ValidationResult result;

  const SyncConfigValidationException(this.result);

  @override
  String toString() {
    return 'SyncConfig validation failed:\n${result.getSummary()}';
  }
}
