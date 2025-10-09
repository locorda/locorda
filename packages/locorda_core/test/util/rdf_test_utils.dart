import 'dart:io';

import 'package:rdf_canonicalization/rdf_canonicalization.dart';
import 'package:rdf_core/rdf_core.dart';
import 'package:test/test.dart';

/// Reads an RDF graph from a Turtle file.
///
/// Throws if the file does not exist.
RdfGraph readGraphFromFile(Directory testAssetsDir, String relativePath) {
  final file = File('${testAssetsDir.path}/$relativePath');
  if (!file.existsSync()) {
    throw TestFailure(
      'Expected RDF file not found: ${file.path}\n'
      'This test requires the file to exist. If this is a generate test, '
      'ensure the expected output file has been created.',
    );
  }
  final content = file.readAsStringSync();
  return turtle.decode(content);
}

/// Compares two RDF graphs using RDF canonicalization.
///
/// If the graphs differ, prints both in Turtle format for easier debugging.
void expectEqualGraphs(String name, RdfGraph actual, RdfGraph expected) {
  final actualCanonical = canonicalizeGraph(actual);
  final expectedCanonical = canonicalizeGraph(expected);

  if (actualCanonical != expectedCanonical) {
    // To make "fixing" the test by copying actual to
    // the expected file easier, print the actual graph in Turtle
    final actualTurtle = turtle.encode(actual);
    final expectedTurtle = turtle.encode(expected);
    print('-' * 4 + name + ' - Graphs differ ' + '-' * 4);
    print(actualTurtle);
    print('-' * 40);

    // First try string comparison for better diff output
    expect(actualTurtle, equals(expectedTurtle),
        reason: 'RDF graphs differ (Turtle comparison)');

    // This should have failed by now, but just in case:
    expect(actualCanonical, equals(expectedCanonical),
        reason: 'RDF graphs differ (canonical comparison)');
  }
}
