import 'package:test/test.dart';
import 'package:locorda_rdf_core/core.dart';
import '../lib/class_specific_approach.dart' as class_specific;
import '../lib/direct_vocabulary_approach.dart' as direct;
import '../lib/cross_vocabulary_properties.dart' as cross_vocab;
import '../lib/core_usage.dart' as core_usage;
import '../lib/common_usage.dart' as common_usage;

void main() {
  group('Class-Specific Approach', () {
    test('creates person with type-safe properties', () {
      class_specific.main();
      // If it runs without error, the example is valid
    });
  });

  group('Direct Vocabulary Approach', () {
    test('uses vocabulary classes directly', () {
      direct.main();
      // If it runs without error, the example is valid
    });
  });

  group('Cross-Vocabulary Properties', () {
    test('demonstrates cross-vocabulary property access', () {
      cross_vocab.main();
      // If it runs without error, the example is valid
    });
  });

  group('Core Vocabularies Usage', () {
    test('demonstrates core RDF vocabularies', () {
      core_usage.main();
      // If it runs without error, the example is valid
    });
  });

  group('Common Vocabularies Usage', () {
    test('demonstrates common semantic web vocabularies', () {
      common_usage.main();
      // If it runs without error, the example is valid
    });
  });
}
