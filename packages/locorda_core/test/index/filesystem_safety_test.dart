import 'package:locorda_core/src/index/filesystem_safety.dart';
import 'package:test/test.dart';

void main() {
  group('FilesystemSafety', () {
    group('safe key preservation', () {
      test('preserves safe alphanumeric keys', () {
        final safeKeys = [
          'work',
          '2024-08',
          'project_alpha',
          'v1.2.3',
          'ABC123',
          'test-file',
          'my_project',
          '123',
          'a',
          'Z',
          'item.backup',
          'file-2024-08-15',
        ];

        for (final key in safeKeys) {
          final result = FilesystemSafety.makeSafe(key);
          expect(result, equals(key),
              reason: 'Safe key should be preserved: $key');
        }
      });

      test('preserves keys at maximum safe length', () {
        // Exactly 50 characters - should be preserved
        final maxLengthKey = 'a' * 50;
        final result = FilesystemSafety.makeSafe(maxLengthKey);
        expect(result, equals(maxLengthKey));
        expect(result.length, equals(50));
      });
    });

    group('hash-based fallback', () {
      test('hashes keys with unsafe characters', () {
        final unsafeKeys = [
          'contains/slash',
          'contains\\backslash',
          'contains:colon',
          'contains*asterisk',
          'contains?question',
          'contains"quote',
          'contains<less>than',
          'contains|pipe',
          'contains\ttab',
          'contains\nnewline',
          'unicode-café-résumé',
          'control\x00\x01chars',
        ];

        for (final key in unsafeKeys) {
          final result = FilesystemSafety.makeSafe(key);

          // Should be hashed with format: {length}_{16-char-hex}
          expect(result, matches(r'^\d+_[0-9a-f]{32}$'),
              reason: 'Unsafe key should be hashed: $key → $result');

          // Should start with character count
          final expectedPrefix = '${key.length}_';
          expect(result, startsWith(expectedPrefix),
              reason:
                  'Hash should include character count prefix: $key → $result');
        }
      });

      test('hashes keys exceeding length limit', () {
        // 51 characters - exceeds limit, should be hashed
        final longKey = 'a' * 51;
        final result = FilesystemSafety.makeSafe(longKey);

        expect(result, matches(r'^51_[0-9a-f]{32}$'));
        expect(result, isNot(equals(longKey)));
      });

      test('hashes reserved names', () {
        final reservedNames = [
          '.',
          '..',
          '.hidden',
          '.bashrc',
        ];

        for (final name in reservedNames) {
          final result = FilesystemSafety.makeSafe(name);
          expect(result, matches(r'^\d+_[0-9a-f]{32}$'),
              reason: 'Reserved name should be hashed: $name → $result');
        }
      });

      test('hashes empty strings', () {
        final result = FilesystemSafety.makeSafe('');
        expect(
            result,
            equals(
                '0_d41d8cd98f00b204e9800998ecf8427e')); // Exact deterministic result (MD5 empty string)
      });
    });

    group('hash consistency and properties', () {
      test('produces deterministic results', () {
        final testCases = [
          'contains/slash',
          'http://example.org/resource',
          'very-long-category-name-exceeding-the-fifty-character-limit-significantly',
          'unicode-café-naïve-résumé',
        ];

        for (final testCase in testCases) {
          final result1 = FilesystemSafety.makeSafe(testCase);
          final result2 = FilesystemSafety.makeSafe(testCase);
          expect(result1, equals(result2),
              reason: 'Hash should be deterministic for: $testCase');
        }
      });

      test('produces different hashes for different inputs', () {
        final inputs = [
          'input1',
          'input2',
          'slightly different input',
          'completely different content here',
        ];

        final results = inputs.map(FilesystemSafety.makeSafe).toSet();
        expect(results.length, equals(inputs.length),
            reason: 'Different inputs should produce different hashes');
      });

      test('hash format is consistent', () {
        final testInputs = [
          'a',
          'short',
          'medium-length-string',
          'very-long-string-that-exceeds-the-fifty-character-limit-and-will-definitely-be-hashed',
          'contains/unsafe/characters',
          'unicode-content-漢字',
        ];

        for (final input in testInputs) {
          final result = FilesystemSafety.makeSafe(input);

          if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(input) ||
              input.length > 50 ||
              input.startsWith('.') ||
              input == '.' ||
              input == '..') {
            // Should be hashed
            expect(result, matches(r'^\d+_[0-9a-f]{32}$'),
                reason:
                    'Expected hash format for unsafe input: $input → $result');

            // Verify character count prefix
            final parts = result.split('_');
            final expectedLength = int.parse(parts[0]);
            expect(expectedLength, equals(input.length),
                reason: 'Character count prefix should match input length');

            // Verify hash part length
            expect(parts[1].length, equals(32),
                reason: 'Hash part should be exactly 32 characters');
          }
        }
      });
    });

    group('exact hash verification', () {
      test('produces exact expected hash values', () {
        final exactCases = {
          'contains/slash': '14_a483ee140ab4c8dd7a20be801e2982d7',
          'http://example.org/category/work':
              '32_5b2b9616e0134f026cc73e3bf8115ab6',
          'unicode-café': '12_cdc649a181b63cd672da583bf751418c',
          'unsafe:category': '15_2e6ebbea1fa1fa110a66dc847c0e9b36',
          '': '0_d41d8cd98f00b204e9800998ecf8427e',
          '.': '1_5058f1af8388633f609cadb75a75dc9d',
          '.hidden': '7_6b96ab441bab2f8d5022c57ffb17136e',
        };

        for (final entry in exactCases.entries) {
          final input = entry.key;
          final expected = entry.value;
          final result = FilesystemSafety.makeSafe(input);
          expect(result, equals(expected),
              reason: 'Exact hash mismatch for input: $input');
        }
      });

      test('verifies hash implementation consistency', () {
        // This test ensures our MD5 implementation produces consistent results
        // If this test fails, it indicates a change in the hash algorithm
        const input = 'test/hash/consistency';
        const expectedHash = '21_157b5e7ca4f67a725df2b59eaf37503c'; // MD5 hash

        final result = FilesystemSafety.makeSafe(input);
        expect(result, equals(expectedHash),
            reason:
                'Hash algorithm consistency check failed - did the MD5 implementation change?');
      });
    });

    group('real-world examples from specification', () {
      test('matches specification examples exactly', () {
        final examples = {
          // Safe keys (preserved)
          'work': 'work',
          '2024-08': '2024-08',
          'project_alpha': 'project_alpha',
          'v1.2.3': 'v1.2.3',

          // Unsafe keys (hashed) - Note: actual hashes may differ, testing format
          'contains/slash': '14_', // Prefix should be 14_
          'http://example.org/resource': '27_', // Prefix should be 27_
        };

        for (final entry in examples.entries) {
          final input = entry.key;
          final expected = entry.value;
          final result = FilesystemSafety.makeSafe(input);

          if (expected.endsWith('_')) {
            // Testing hash prefix format
            expect(result, startsWith(expected),
                reason:
                    'Hash should start with correct character count: $input');
            expect(result, matches(r'^\d+_[0-9a-f]{32}$'),
                reason: 'Hash should match expected format: $input → $result');
          } else {
            // Testing exact preservation
            expect(result, equals(expected),
                reason: 'Safe key should be preserved exactly: $input');
          }
        }
      });

      test('handles IRI strings correctly', () {
        final iris = [
          'http://example.org/category/work',
          'https://schema.org/dateCreated',
          'http://www.w3.org/2001/XMLSchema#integer',
          'urn:uuid:12345678-1234-5678-9abc-123456789abc',
        ];

        for (final iri in iris) {
          final result = FilesystemSafety.makeSafe(iri);

          // IRIs contain unsafe characters, should be hashed
          expect(result, matches(r'^\d+_[0-9a-f]{32}$'),
              reason: 'IRI should be hashed for filesystem safety: $iri');

          // Character count should match IRI length
          final prefix = result.split('_')[0];
          expect(int.parse(prefix), equals(iri.length),
              reason: 'Character count should match IRI length');
        }
      });
    });

    group('edge cases and boundary conditions', () {
      test('handles single characters correctly', () {
        final singleChars = ['a', 'Z', '1', '_', '-', '.'];

        for (final char in singleChars) {
          final result = FilesystemSafety.makeSafe(char);

          if (char == '.') {
            // Special case: '.' is reserved
            expect(result, matches(r'^1_[0-9a-f]{32}$'));
          } else {
            // Should be preserved
            expect(result, equals(char));
          }
        }
      });

      test('handles boundary lengths correctly', () {
        final cases = {
          49: true, // Under limit - should be preserved (if safe)
          50: true, // At limit - should be preserved (if safe)
          51: false, // Over limit - should be hashed
          100: false, // Well over limit - should be hashed
        };

        for (final entry in cases.entries) {
          final length = entry.key;
          final shouldPreserve = entry.value;

          // Create safe string of specified length
          final testString = 'a' * length;
          final result = FilesystemSafety.makeSafe(testString);

          if (shouldPreserve) {
            expect(result, equals(testString),
                reason: 'Safe string of length $length should be preserved');
          } else {
            expect(result, matches(r'^\d+_[0-9a-f]{32}$'),
                reason: 'String of length $length should be hashed');
            expect(result, startsWith('${length}_'),
                reason: 'Hash should include correct character count');
          }
        }
      });

      test('handles unicode characters correctly', () {
        final unicodeStrings = [
          'café', // Contains non-ASCII but safe characters should be hashed
          '漢字', // CJK characters
          '🚀🌟', // Emoji
          'naïve', // Accented characters
          'résumé', // Multiple accents
        ];

        for (final str in unicodeStrings) {
          final result = FilesystemSafety.makeSafe(str);

          // Unicode characters are not in the safe whitelist, should be hashed
          expect(result, matches(r'^\d+_[0-9a-f]{32}$'),
              reason: 'Unicode string should be hashed: $str');

          final expectedLength = str.length;
          expect(result, startsWith('${expectedLength}_'),
              reason: 'Character count should match Unicode string length');
        }
      });
    });
  });
}
