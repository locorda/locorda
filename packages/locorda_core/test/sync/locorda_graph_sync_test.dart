import 'dart:convert';
import 'dart:io';

import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:rdf_canonicalization/rdf_canonicalization.dart';
import 'package:rdf_core/rdf_core.dart';
import 'package:test/test.dart';

import 'test_backend.dart';
import 'test_fetcher.dart';
import 'test_physical_timestamp_factory.dart';
import 'test_storage.dart';

void main() {
  // Load and parse all_tests.json
  final testAssetsDir = Directory('test/assets/graph');
  final allTestsFile = File('${testAssetsDir.path}/all_tests.json');
  final allTestsJson =
      jsonDecode(allTestsFile.readAsStringSync()) as Map<String, dynamic>;

  final urlToPathMapJson = allTestsJson['urlToPathMap'] as Map<String, dynamic>;
  final urlToPathMap = urlToPathMapJson.map((k, v) => MapEntry(k, v as String));

  // Parse base configuration
  final baseJson = allTestsJson['base'] as Map<String, dynamic>;
  final baseTimestamp = DateTime.parse(baseJson['timestamp'] as String);
  final baseInstallationId = baseJson['installation_id'] as String?;

  final testSuites = allTestsJson['test_suites'] as List<dynamic>;

  // Group tests by suite
  for (final suiteJson in testSuites) {
    final suiteName = suiteJson['suite'] as String;
    final suiteDescription = suiteJson['description'] as String;
    final tests = suiteJson['tests'] as List<dynamic>;

    group('$suiteName - $suiteDescription', () {
      for (final testJson in tests) {
        final testId = testJson['id'] as String;
        final testTitle = testJson['title'] as String;
        //final testDescription = testJson['description'] as String;

        test('$testId: $testTitle', () async {
          // Get test-specific baseTimestamp or use default
          final testBaseTimestampStr = testJson['baseTimestamp'] as String?;
          final testBaseTimestamp = testBaseTimestampStr != null
              ? DateTime.parse(testBaseTimestampStr)
              : baseTimestamp;

          // Execute test based on suite type
          switch (suiteName) {
            case 'save':
              await _executeSaveTest(testJson, testAssetsDir, urlToPathMap,
                  testBaseTimestamp, baseInstallationId);
              break;
            default:
              fail('Unknown test suite: $suiteName');
          }
        });
      }
    });
  }
  group('Generate Iri', () {
    test('Recipe Iri Generation', () {
      final loc = LocalResourceLocator(iriTermFactory: IriTerm.validated);
      final result =
          loc.toIri(IriTerm('https://schema.org/Recipe'), 'recipe123', null);
      print(result.resourceIri);
    });
  });
}

RdfGraph? _readGraphFromPath(Directory testAssetsDir, String? path) {
  if (path == null) return null;
  final content = File('${testAssetsDir.path}/$path').readAsStringSync();
  return turtle.decode(content);
}

Future<void> _executeSaveTest(
    Map<String, dynamic> testJson,
    Directory testAssetsDir,
    Map<String, String> urlToPathMap,
    DateTime baseTimestamp,
    String? baseInstallationId) async {
  // Load configuration
  final config = _loadConfig(testAssetsDir, testJson['config'] as String);

  // Get type IRI from test JSON
  final typeIri = IriTerm(testJson['typeIri'] as String);

  // Load TTL files
  final storedGraphBefore = _readGraphFromPath(
      testAssetsDir, testJson['stored_graph_before'] as String?);
  final inputResource =
      _readGraphFromPath(testAssetsDir, testJson['input_resource'] as String)!;

  final expectedJson = testJson['expected'] as Map<String, dynamic>;
  final expectedStoredGraph = _readGraphFromPath(
      testAssetsDir, expectedJson['stored_graph'] as String)!;
  final expectedInstallation = _readGraphFromPath(
      testAssetsDir, expectedJson['installation'] as String?);
  final timestampFactory =
      TestPhysicalTimestampFactory(baseTimestamp: baseTimestamp);

  // Load action timestamps if provided
  final actionTs = testJson['action_ts'] as Map<String, dynamic>?;

  // Extract document IRI from input resource
  final documentIri = inputResource.subjects
      .whereType<IriTerm>()
      .map((s) => s.getDocumentIri())
      .toSet()
      .single;
  final storage = TestStorage();
  if (storedGraphBefore != null) {
    // Set timestamp for prepare.save if specified
    setTime(actionTs?['prepare']?['save'], timestampFactory);
    final now = timestampFactory();
    storage.saveDocument(
        documentIri,
        typeIri,
        storedGraphBefore,
        DocumentMetadata(
          ourPhysicalClock: now.millisecondsSinceEpoch,
          updatedAt: now.millisecondsSinceEpoch,
        ),
        []);
  }

  final fetcher = TestFetcher(
    testAssetsDir: testAssetsDir,
    urlToPathMap: urlToPathMap,
  );

  // Create installation ID factory if base installation ID provided
  final installationIdFactory =
      baseInstallationId != null ? () => baseInstallationId : null;

  final sync = await LocordaGraphSync.setup(
      backend: TestBackend(),
      storage: storage,
      config: config,
      fetcher: fetcher,
      physicalTimestampFactory: timestampFactory,
      installationIdFactory: installationIdFactory);

  // Set timestamp for save action if specified
  setTime(actionTs?['save'], timestampFactory);

  await sync.save(typeIri, inputResource);

  final stored = await storage.getDocument(documentIri);

  if (stored == null) {
    fail('No document stored for $documentIri');
  }
  _expectEqualGraphs(stored.document, expectedStoredGraph);

  // Verify installation document if expected
  if (expectedInstallation != null) {
    final settings = await storage.getSettings(['installation_iri']);
    final installationIriStr = settings['installation_iri'];
    if (installationIriStr == null) {
      fail('No installation IRI found in settings');
    }
    final installationIri = IriTerm(installationIriStr).getDocumentIri();
    final storedInstallation = await storage.getDocument(installationIri);

    if (storedInstallation == null) {
      fail('No installation document stored for $installationIri');
    }
    _expectEqualGraphs(storedInstallation.document, expectedInstallation);
  }
}

void _expectEqualGraphs(RdfGraph actual, RdfGraph expected) {
  var actualCanonical = canonicalizeGraph(actual);
  var expectedCanonical = canonicalizeGraph(expected);
  if (actualCanonical != expectedCanonical) {
    // For easier debugging, print the actual and expected graphs in Turtle
    var actualTurtle = turtle.encode(actual);
    var expectedTurtle = turtle.encode(expected);
    print('-' * 80);
    print(actualTurtle);
    print('-' * 80);
    expect(actualTurtle, equals(expectedTurtle));
    // This should have failed by now, but just in case:
    expect(actualCanonical, equals(expectedCanonical));
  }
}

void setTime(String? ts, TestPhysicalTimestampFactory timestampFactory) {
  if (ts != null) {
    timestampFactory.setTimestamp(DateTime.parse(ts));
  }
}

SyncGraphConfig _loadConfig(Directory testAssetsDir, String configPath) {
  final configFile = File('${testAssetsDir.path}/$configPath');
  final configJson =
      jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;

  return SyncGraphConfig.fromJson(configJson);
}
