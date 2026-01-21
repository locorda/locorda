import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('vocabularies.json is valid and includes required keys', () {
    final file = File('lib/src/vocabularies.json');
    final contents = file.readAsStringSync();
    final jsonMap = jsonDecode(contents) as Map<String, dynamic>;

    expect(jsonMap.containsKey('vocabularies'), isTrue);
    final vocabularies = jsonMap['vocabularies'] as Map<String, dynamic>;

    expect(vocabularies.containsKey('foaf'), isTrue);
  });

  test('build.yaml references generator builder', () {
    final contents = File('build.yaml').readAsStringSync();
    expect(
        contents, contains('locorda_rdf_terms_generator|vocabulary_builder'));
    expect(contents, contains('lib/src/vocabularies.json'));
  });

  test('snippet commands are present', () {
    final install = File('snippets/install.txt').readAsStringSync();
    final commands = File('snippets/commands.txt').readAsStringSync();
    final listOutput = File('snippets/list_output.txt').readAsStringSync();

    expect(install, contains('locorda_rdf_terms_generator'));
    expect(commands, contains('locorda_rdf_terms_generator init'));
    expect(commands, contains('locorda_rdf_terms_generator list'));
    expect(commands, contains('build_runner build'));
    expect(listOutput, contains('Available Vocabularies (80 total)'));
    expect(listOutput, contains('📚 Standard Vocabularies:'));
    expect(listOutput, contains('🔧 Custom Vocabularies:'));
    expect(listOutput, contains('schema'));
    expect(listOutput, contains('foaf'));
    expect(listOutput, contains('myOntology ✓ GENERATING'));
  });
}
