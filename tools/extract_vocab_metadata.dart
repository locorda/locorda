#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';
import 'package:locorda_rdf_core/core.dart';
import 'package:locorda_rdf_terms_core/owl.dart';
import 'package:locorda_rdf_terms_core/rdf.dart';
import 'package:locorda_rdf_terms_core/rdfs.dart';
import 'package:path/path.dart' as p;

/// Extracts metadata from RDF vocabulary and mapping files.
///
/// Uses locorda_rdf_core to parse TTL files and extract titles, descriptions,
/// and other metadata, generating JSON files for Astro pages.
///
/// Usage: dart tools/extract_vocab_metadata.dart
void main() async {
  print('Extracting vocabulary and mapping metadata...\n');

  await extractMetadata(
    sourceDir: 'public/vocab',
    outputFile: 'src/data/vocabularies.json',
    type: 'vocabulary',
  );

  await extractMetadata(
    sourceDir: 'public/mappings',
    outputFile: 'src/data/mappings.json',
    type: 'mapping',
  );

  print('\n✓ Metadata extraction complete!');
}

/// Extracts metadata from TTL files in a directory using RDF parsing.
Future<void> extractMetadata({
  required String sourceDir,
  required String outputFile,
  required String type,
}) async {
  final dir = Directory(sourceDir);

  if (!await dir.exists()) {
    print('⚠ Directory not found: $sourceDir');
    print('  Run ./copy-sync-engine-content.sh first\n');

    await _writeJson(outputFile, {'files': []});
    return;
  }

  final files = await dir
      .list()
      .where((entity) => entity is File && entity.path.endsWith('.ttl'))
      .cast<File>()
      .toList();

  if (files.isEmpty) {
    print('⚠ No TTL files found in: $sourceDir\n');
    await _writeJson(outputFile, {'files': []});
    return;
  }

  print('Processing $type files in: $sourceDir');

  final fileMetadata = <Map<String, dynamic>>[];

  for (final file in files) {
    final filename = p.basename(file.path);
    print('  - $filename');

    try {
      final content = await file.readAsString();
      final graph = turtle.decode(content);
      final metadata = _extractMetadataFromGraph(filename, graph);

      fileMetadata.add({
        'filename': filename,
        'title': metadata['title'],
        'description': metadata['description'],
        'version': metadata['version'],
        'namespace': metadata['namespace'],
      });
    } catch (e) {
      print('    ⚠ Error parsing $filename: $e');
      // Add fallback metadata
      fileMetadata.add({
        'filename': filename,
        'title': _generateTitleFromFilename(filename),
        'description': null,
        'version': null,
        'namespace': null,
      });
    }
  }

  // Sort by filename
  fileMetadata.sort(
      (a, b) => (a['filename'] as String).compareTo(b['filename'] as String));

  await _writeJson(outputFile, {
    'files': fileMetadata,
    'generatedAt': DateTime.now().toIso8601String(),
  });

  print('  → Generated: $outputFile');
  print('  → Found ${fileMetadata.length} ${type}(s)\n');
}

/// Extracts metadata from an RDF graph using standard vocabularies.
Map<String, String?> _extractMetadataFromGraph(
  String filename,
  RdfGraph graph,
) {
  // Try to find the ontology/vocabulary subject (owl:Ontology or similar)
  final ontologySubject = graph
      .getSubjects(Rdf.type, OwlOntology.classIri)
      .whereType<IriTerm>()
      .firstOrNull;
  if (ontologySubject == null) {
    // No ontology found, return minimal metadata
    return {
      'title': _generateTitleFromFilename(filename),
      'description': null,
      'version': null,
      'namespace': null,
    };
  }
  final title = graph
      .getObjects(ontologySubject, Rdfs.label)
      .whereType<LiteralTerm>()
      .firstOrNull;
  final description = graph
      .getObjects(ontologySubject, Rdfs.comment)
      .whereType<LiteralTerm>()
      .firstOrNull;

  final version = graph
      .getObjects(ontologySubject, Owl.versionInfo)
      .whereType<LiteralTerm>()
      .firstOrNull;

  return {
    if (title != null) 'title': title.value,
    if (description != null) 'description': description.value,
    if (version != null) 'version': version.value,
    'namespace': ontologySubject.value,
  };
}

/// Generates a human-readable title from a filename.
String _generateTitleFromFilename(String filename) {
  // Remove .ttl extension
  var name = filename.replaceAll('.ttl', '');

  // Replace hyphens with spaces
  name = name.replaceAll('-', ' ');

  // Capitalize each word
  final words = name.split(' ');
  final capitalized = words.map((word) {
    if (word.isEmpty) return word;
    if (word.toLowerCase() == 'crdt' || word.toLowerCase() == 'rdf') {
      return word.toUpperCase();
    }
    return word[0].toUpperCase() + word.substring(1);
  }).join(' ');

  return capitalized;
}

/// Writes JSON to a file, creating parent directories if needed.
Future<void> _writeJson(String path, Map<String, dynamic> data) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(data),
  );
}
