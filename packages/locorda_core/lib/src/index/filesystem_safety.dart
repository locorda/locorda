/// Filesystem safety utilities for group keys according to GROUP-INDEXING.md specification.
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Ensures group keys are safe for use as filesystem path components across all platforms.
///
/// This utility implements the filesystem safety specification from GROUP-INDEXING.md,
/// providing automatic conversion of unsafe group keys to deterministic, collision-resistant
/// hash-based alternatives while preserving human-readable keys when possible.
class FilesystemSafety {
  // Conservative whitelist pattern - only lowercase after normalization
  static final RegExp _safePattern = RegExp(r'^[a-z0-9._-]+$');

  // Maximum length for preserved human-readable keys
  static const int _maxSafeLength = 50;

  /// Makes a group key safe for filesystem use according to the specification.
  ///
  /// **Case Normalization:** All keys are converted to lowercase first to ensure
  /// consistent grouping and avoid case-sensitivity issues across filesystems.
  ///
  /// **Safe Key Preservation:** Keys meeting all criteria are preserved unchanged:
  /// - Contains only safe characters: lowercase letters, digits, periods, underscores, hyphens
  /// - Length ≤ 50 characters
  /// - Does not start with period (hidden file prevention)
  /// - Not a reserved name (CON, PRN, AUX, NUL, COM1-9, LPT1-9)
  ///
  /// **Hash Generation:** Unsafe keys are converted to format:
  /// `{originalLength}_{32-char-hex-hash}` using MD5
  ///
  /// This ensures deterministic, collision-resistant transformation while maintaining
  /// compact file paths suitable for all platforms.
  static String makeSafe(String groupKey) {
    // Step 1: Convert to lowercase for case normalization
    final lowercaseKey = groupKey.toLowerCase();

    // Step 2: Check if lowercase key is safe
    if (_isSafe(lowercaseKey)) {
      return lowercaseKey;
    }

    // Step 3: Generate hash with character count prefix (using original case for hash input)
    final bytes = utf8.encode(lowercaseKey);
    final digest = md5.convert(bytes);
    final hexHash = digest.toString();
    return '${lowercaseKey.length}_$hexHash';
  }

  /// Checks if a group key meets all safety criteria.
  ///
  /// NOTE: This method expects the key to already be lowercase normalized.
  ///
  /// Returns true only if the key:
  /// - Contains only safe characters (lowercase letters, digits, period, underscore, hyphen)
  /// - Is within the maximum safe length
  /// - Does not start with a period (to avoid hidden files)
  /// - Is not a reserved Windows filename
  static bool _isSafe(String groupKey) {
    // Must contain only safe characters (lowercase only after normalization)
    if (!_safePattern.hasMatch(groupKey)) {
      return false;
    }

    // Must be within safe length limits
    if (groupKey.length > _maxSafeLength) {
      return false;
    }

    // Must not start with period (hidden file prevention)
    if (groupKey.startsWith('.')) {
      return false;
    }

    // Must not be a reserved Windows filename
    if (_isReservedWindowsName(groupKey)) {
      return false;
    }

    return true;
  }

  /// Checks if a name is a reserved Windows filename.
  static bool _isReservedWindowsName(String name) {
    final upperName = name.toUpperCase();
    final reservedNames = [
      'CON',
      'PRN',
      'AUX',
      'NUL',
      'COM1',
      'COM2',
      'COM3',
      'COM4',
      'COM5',
      'COM6',
      'COM7',
      'COM8',
      'COM9',
      'LPT1',
      'LPT2',
      'LPT3',
      'LPT4',
      'LPT5',
      'LPT6',
      'LPT7',
      'LPT8',
      'LPT9'
    ];

    return reservedNames.contains(upperName);
  }
}
