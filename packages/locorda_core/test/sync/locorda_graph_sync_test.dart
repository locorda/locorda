import 'dart:convert';
import 'dart:io';

import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/mapping/iri_translator.dart';
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
            case 'save_error':
              await _executeSaveErrorTest(testJson, testAssetsDir, urlToPathMap,
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
      final resourceIri = loc.toIri(ResourceIdentifier(
          IriTerm('https://schema.org/Recipe'), 'recipe123', "it"));
      expect(
          resourceIri.value,
          equals(
              "tag:locorda.org,2025:l:aHR0cHM6Ly9zY2hlbWEub3JnL1JlY2lwZQ==:cmVjaXBlMTIz#it"));
    });
  });
}

RdfGraph? _readGraphFromPath(Directory testAssetsDir, String? path) {
  if (path == null) return null;
  final content = File('${testAssetsDir.path}/$path').readAsStringSync();
  return turtle.decode(content);
}

typedef TestData = ({
  IriTerm externalDocumentIri,
  Map<String, dynamic> expectedJson,
  IriTerm typeIri,
  RdfGraph? storedGraphBefore,
  RdfGraph inputResource,
  Map<String, dynamic>? actionTs,
  SyncGraphConfig config
});
Future<TestData> _prepare(
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

  // Load action timestamps if provided
  final actionTs = testJson['action_ts'] as Map<String, dynamic>?;

  // Extract document IRI - use stored_graph_before if available (which has internal IRIs),
  // otherwise use input_resource (which has external IRIs that will be translated)
  final documentIri = inputResource.subjects
      .whereType<IriTerm>()
      .map((s) => s.getDocumentIri())
      .toSet()
      .single;

  return (
    externalDocumentIri: documentIri,
    expectedJson: expectedJson,
    typeIri: typeIri,
    storedGraphBefore: storedGraphBefore,
    inputResource: inputResource,
    actionTs: actionTs,
    config: config
  );
}

Future<void> _executeSave(
    TestData testData,
    TestStorage storage,
    Directory testAssetsDir,
    Map<String, String> urlToPathMap,
    DateTime baseTimestamp,
    String? baseInstallationId,
    IriTranslator iriTranslator) async {
  final timestampFactory =
      TestPhysicalTimestampFactory(baseTimestamp: baseTimestamp);
  final (
    externalDocumentIri: documentIri,
    expectedJson: _,
    typeIri: typeIri,
    storedGraphBefore: storedGraphBefore,
    inputResource: inputResource,
    actionTs: actionTs,
    config: config
  ) = testData;
  if (storedGraphBefore != null) {
    // Set timestamp for prepare.save if specified
    setTime(actionTs?['prepare']?['save'], timestampFactory);
    final now = timestampFactory();

    storage.saveDocument(
        iriTranslator.externalToInternal(documentIri),
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
}

Future<void> _executeSaveTest(
    Map<String, dynamic> testJson,
    Directory testAssetsDir,
    Map<String, String> urlToPathMap,
    DateTime baseTimestamp,
    String? baseInstallationId) async {
  final testData = await _prepare(
      testJson, testAssetsDir, urlToPathMap, baseTimestamp, baseInstallationId);
  final storage = TestStorage();
  final iriTranslator = _createIriTranslator(testData);
  await _executeSave(testData, storage, testAssetsDir, urlToPathMap,
      baseTimestamp, baseInstallationId, iriTranslator);

  final expectedJson = testData.expectedJson;
  final documentIri =
      iriTranslator.externalToInternal(testData.externalDocumentIri);
  final expectedStoredGraph = _readGraphFromPath(
      testAssetsDir, expectedJson['stored_graph'] as String)!;
  final expectedInstallation = _readGraphFromPath(
      testAssetsDir, expectedJson['installation'] as String?);
  final expectedPropertyChanges = _parseExpectedPropertyChanges(expectedJson);

  final stored = await storage.getDocument(documentIri);

  if (stored == null) {
    fail('No document stored for $documentIri');
  }
  _expectEqualGraphs(stored.document, expectedStoredGraph);

  // Verify property changes if expected
  if (expectedPropertyChanges != null) {
    final actualPropertyChanges = await storage.getPropertyChanges(documentIri);
    _expectEqualPropertyChanges(actualPropertyChanges, expectedPropertyChanges);
  }

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

IriTranslator _createIriTranslator(TestData testData) {
  return IriTranslator(
      resourceLocator: LocalResourceLocator(iriTermFactory: IriTerm.validated),
      resourceConfigs: testData.config.resources);
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

/// Parse expected property changes from test JSON.
/// Returns null if property_changes is not specified (meaning: don't test).
/// Returns empty list if property_changes is specified as empty array.
List<PropertyChange>? _parseExpectedPropertyChanges(
    Map<String, dynamic> expectedJson) {
  if (!expectedJson.containsKey('property_changes')) {
    return null; // Not specified - don't test property changes
  }

  final propertyChangesJson = expectedJson['property_changes'] as List<dynamic>;
  return propertyChangesJson.map((json) {
    final map = json as Map<String, dynamic>;
    return PropertyChange(
      resourceIri: IriTerm(map['resource_iri'] as String),
      propertyIri: IriTerm(map['property_iri'] as String),
      changedAtMs:
          DateTime.parse(map['changed_at'] as String).millisecondsSinceEpoch,
      changeLogicalClock: map['logical_clock'] as int,
    );
  }).toList();
}

/// Compare actual and expected property changes (order-independent).
void _expectEqualPropertyChanges(
    List<PropertyChange> actual, List<PropertyChange> expected) {
  // Sort both lists by a consistent key for comparison
  String key(PropertyChange pc) =>
      '${pc.resourceIri.value}|${(pc.propertyIri as IriTerm).value}|${pc.changeLogicalClock}';

  final actualSorted = actual.toList()
    ..sort((a, b) => key(a).compareTo(key(b)));
  final expectedSorted = expected.toList()
    ..sort((a, b) => key(a).compareTo(key(b)));

  if (actualSorted.length != expectedSorted.length) {
    fail('Expected ${expectedSorted.length} property changes, '
        'but got ${actualSorted.length}.\n'
        '\nExpected: \n\t${expectedSorted.map(formatChangedProperty).join('\n\t')}\n'
        '\nActual: \n\t${actualSorted.map(formatChangedProperty).join('\n\t')}');
  }

  for (var i = 0; i < expectedSorted.length; i++) {
    final exp = expectedSorted[i];
    final act = actualSorted[i];

    // Build a detailed context message for this property change comparison
    String context() => '\n'
        '\nExpected:\n\t${formatChangedProperty(exp)}\n'
        '\nActual:\n\t${formatChangedProperty(act)}';

    if (act.resourceIri != exp.resourceIri) {
      fail('Property change #$i: resource IRI mismatch${context()}');
    }
    if (act.propertyIri != exp.propertyIri) {
      fail('Property change #$i: property IRI mismatch${context()}');
    }
    if (act.changeLogicalClock != exp.changeLogicalClock) {
      fail('Property change #$i: logical clock mismatch${context()}');
    }
    if (act.changedAtMs != exp.changedAtMs) {
      fail('Property change #$i: timestamp mismatch${context()}');
    }
  }
}

String formatChangedProperty(PropertyChange exp) =>
    'resource=${exp.resourceIri.value}, property=${(exp.propertyIri as IriTerm).value}, clock=${exp.changeLogicalClock}, timestamp=${exp.changedAtMs}';

/// Execute a save error test - expects an exception to be thrown
Future<void> _executeSaveErrorTest(
    Map<String, dynamic> testJson,
    Directory testAssetsDir,
    Map<String, String> urlToPathMap,
    DateTime baseTimestamp,
    String? baseInstallationId) async {
  final testData = await _prepare(
      testJson, testAssetsDir, urlToPathMap, baseTimestamp, baseInstallationId);
  final expectedJson = testData.expectedJson;
  final expectedErrorType = expectedJson['error_type'] as String;
  final expectedErrorMessagePattern =
      expectedJson['error_message_pattern'] as String?;
  final storage = TestStorage();
  final iriTranslator = _createIriTranslator(testData);
  try {
    await _executeSave(testData, storage, testAssetsDir, urlToPathMap,
        baseTimestamp, baseInstallationId, iriTranslator);
    fail('Expected $expectedErrorType to be thrown, but save succeeded');
  } catch (e) {
    // Verify error type
    final actualErrorType = e.runtimeType.toString();
    expect(actualErrorType, equals(expectedErrorType),
        reason:
            'Expected error type $expectedErrorType but got $actualErrorType');

    // Verify error message pattern if specified
    if (expectedErrorMessagePattern != null) {
      final errorMessage = e.toString();
      expect(errorMessage, contains(expectedErrorMessagePattern),
          reason:
              'Error message "$errorMessage" does not contain expected pattern "$expectedErrorMessagePattern"');
    }
  }
}
