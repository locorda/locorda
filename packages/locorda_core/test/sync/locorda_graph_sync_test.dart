import 'dart:convert';
import 'dart:io';

import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/index/index_rdf_generator.dart';
import 'package:locorda_core/src/index/shard_manager.dart';
import 'package:locorda_core/src/mapping/iri_translator.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:rdf_core/rdf_core.dart';
import 'package:test/test.dart';

import '../util/rdf_test_utils.dart';
import 'in_memory_backend.dart';
import 'test_fetcher.dart';
import 'test_physical_timestamp_factory.dart';
import 'in_memory_storage.dart';

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
        final shouldSkip = testJson['skip'] as bool? ?? false;

        test('$testId: $testTitle', () async {
          // Get test-specific baseTimestamp or use default
          final testBaseTimestampStr = testJson['baseTimestamp'] as String?;
          final testBaseTimestamp = testBaseTimestampStr != null
              ? DateTime.parse(testBaseTimestampStr)
              : baseTimestamp;

          // Execute test based on suite type
          switch (suiteName) {
            case 'save':
            case 'group_index':
              await _executeSaveTestWithSteps(testJson, testAssetsDir,
                  urlToPathMap, testBaseTimestamp, baseInstallationId);
              break;
            case 'save_error':
              await _executeSaveErrorTest(testJson, testAssetsDir, urlToPathMap,
                  testBaseTimestamp, baseInstallationId);
              break;
            default:
              fail('Unknown test suite: $suiteName');
          }
        }, skip: shouldSkip);
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
  return readGraphFromFile(testAssetsDir, path);
}

/// Executes a save test with support for multiple sequential steps.
/// Each step can have its own input, action timestamps, and expectations.
Future<void> _executeSaveTestWithSteps(
    Map<String, dynamic> testJson,
    Directory testAssetsDir,
    Map<String, String> urlToPathMap,
    DateTime baseTimestamp,
    String? baseInstallationId) async {
  final testId = testJson['id'] as String;

  // Test-specific installation ID overrides base installation ID
  final testInstallationId =
      testJson['installation_id'] as String? ?? baseInstallationId;

  final config = _loadConfig(testAssetsDir, testJson['config'] as String);
  final storage = InMemoryStorage();
  final iriTranslator = IriTranslator(
      resourceLocator: LocalResourceLocator(iriTermFactory: IriTerm.validated),
      resourceConfigs: config.resources);

  final steps = testJson['steps'] as List<dynamic>;

  for (var stepIndex = 0; stepIndex < steps.length; stepIndex++) {
    final stepJson = steps[stepIndex] as Map<String, dynamic>;

    await _executeStep(
      testId: testId,
      stepIndex: stepIndex,
      stepJson: stepJson,
      testAssetsDir: testAssetsDir,
      urlToPathMap: urlToPathMap,
      baseTimestamp: baseTimestamp,
      baseInstallationId: testInstallationId,
      config: config,
      storage: storage,
      iriTranslator: iriTranslator,
    );
  }
}

/// Executes a single step within a multi-step test.
Future<void> _executeStep({
  required String testId,
  required int stepIndex,
  required Map<String, dynamic> stepJson,
  required Directory testAssetsDir,
  required Map<String, String> urlToPathMap,
  required DateTime baseTimestamp,
  required String? baseInstallationId,
  required SyncGraphConfig config,
  required InMemoryStorage storage,
  required IriTranslator iriTranslator,
}) async {
  // make sure to reset property changes for next step
  storage.resetPropertyChanges();

  final action = stepJson['action'] as String;

  // Load action timestamps if provided
  final actionTs = stepJson['action_ts'] as Map<String, dynamic>?;
  final timestampFactory =
      TestPhysicalTimestampFactory(baseTimestamp: baseTimestamp);

  if (action == 'prepare') {
    // Prepare action: Load multiple documents into storage
    final documents = stepJson['documents'] as List<dynamic>;

    // Set timestamp for prepare.save if specified
    setTime(actionTs?['save'], timestampFactory);
    final now = timestampFactory();

    for (final docJson in documents) {
      final docMap = docJson as Map<String, dynamic>;
      final typeIri = IriTerm(docMap['typeIri'] as String);
      final graphPath = docMap['graph'] as String;
      final graph = _readGraphFromPath(testAssetsDir, graphPath)!;

      // Extract document IRI from the graph
      final documentIri = graph.subjects
          .whereType<IriTerm>()
          .map((s) => s.getDocumentIri())
          .toSet()
          .single;

      storage.saveDocument(
        documentIri,
        typeIri,
        graph,
        DocumentMetadata(
          ourPhysicalClock: now.millisecondsSinceEpoch,
          updatedAt: now.millisecondsSinceEpoch,
        ),
        [],
      );
    }
    return; // Prepare action has no expectations
  }

  if (action == 'sync') {
    // Sync action: Trigger sync for all shards that need updates

    // Set timestamp for sync action if specified
    setTime(actionTs?['sync'], timestampFactory);

    final fetcher = TestFetcher(
      testAssetsDir: testAssetsDir,
      urlToPathMap: urlToPathMap,
    );

    // Create installation ID factory if base installation ID provided
    final installationIdFactory =
        baseInstallationId != null ? () => baseInstallationId : null;

    final sync = await LocordaGraphSync.setup(
        backends: [InMemoryBackend()],
        storage: storage,
        config: config,
        fetcher: fetcher,
        physicalTimestampFactory: timestampFactory,
        installationIdFactory: installationIdFactory);

    // Trigger sync - finds all shards with changes and syncs them
    await sync.syncManager.sync();

    // Verify expectations if provided
    final expectedJson = stepJson['expected'] as Map<String, dynamic>?;
    if (expectedJson != null) {
      // For sync action, we verify shard documents and group index documents
      await _verifyExpectations(
        testId: testId,
        stepIndex: stepIndex,
        expectedJson: expectedJson,
        testAssetsDir: testAssetsDir,
        storage: storage,
        config: config,
        iriTranslator: iriTranslator,
      );
    }
    return;
  }

  if (action != 'save') {
    fail('Unknown action: $action');
  }

  // Get type IRI from step
  final typeIri = IriTerm(stepJson['typeIri'] as String);

  // Load input resource
  final inputResource =
      _readGraphFromPath(testAssetsDir, stepJson['input_resource'] as String)!;

  // Load stored_graph_before if specified (legacy support)
  final storedGraphBefore = _readGraphFromPath(
      testAssetsDir, stepJson['stored_graph_before'] as String?);

  // Extract document IRI from input
  final externalDocumentIri = inputResource.subjects
      .whereType<IriTerm>()
      .map((s) => s.getDocumentIri())
      .toSet()
      .single;

  if (storedGraphBefore != null) {
    // Legacy support: Set timestamp for prepare.save if specified
    setTime(actionTs?['prepare']?['save'], timestampFactory);
    final now = timestampFactory();

    storage.saveDocument(
        iriTranslator.externalToInternal(externalDocumentIri),
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
      backends: [InMemoryBackend()],
      storage: storage,
      config: config,
      fetcher: fetcher,
      physicalTimestampFactory: timestampFactory,
      installationIdFactory: installationIdFactory);

  // Set timestamp for save action if specified
  setTime(actionTs?['save'], timestampFactory);

  await sync.save(typeIri, inputResource);

  // Verify expectations if provided
  final expectedJson = stepJson['expected'] as Map<String, dynamic>?;
  if (expectedJson != null) {
    await _verifyExpectations(
      testId: testId,
      stepIndex: stepIndex,
      expectedJson: expectedJson,
      testAssetsDir: testAssetsDir,
      storage: storage,
      config: config,
      iriTranslator: iriTranslator,
      externalDocumentIri: externalDocumentIri,
      typeIri: typeIri,
    );
  }
}

/// Verifies all expectations for a step.
Future<void> _verifyExpectations({
  required String testId,
  required int stepIndex,
  required Map<String, dynamic> expectedJson,
  required Directory testAssetsDir,
  required InMemoryStorage storage,
  required SyncGraphConfig config,
  required IriTranslator iriTranslator,
  IriTerm? externalDocumentIri,
  IriTerm? typeIri,
}) async {
  final documentIri = externalDocumentIri == null
      ? null
      : iriTranslator.externalToInternal(externalDocumentIri);

  // Verify stored graph if expected
  final expectedStoredGraphPath = expectedJson['stored_graph'] as String?;
  if (expectedStoredGraphPath != null) {
    if (documentIri == null || typeIri == null) {
      fail('documentIri and typeIri must be provided to verify stored_graph');
    }
    final expectedStoredGraph =
        _readGraphFromPath(testAssetsDir, expectedStoredGraphPath)!;
    final storedDataDocument = await storage.getDocument(documentIri);
    if (storedDataDocument == null) {
      fail(await _failMissing(storage, typeIri, documentIri));
    }
    _expectEqualGraphs("$testId [step $stepIndex] - expected_stored_graph",
        storedDataDocument.document, expectedStoredGraph);
  }

  // Verify property changes if expected
  final expectedPropertyChanges = _parseExpectedPropertyChanges(expectedJson);
  if (expectedPropertyChanges != null) {
    if (documentIri == null) {
      fail('documentIri must be provided to verify property_changes');
    }
    final actualPropertyChanges = await storage.getPropertyChanges(documentIri);
    _expectEqualPropertyChanges(actualPropertyChanges, expectedPropertyChanges);
  }

  // Verify installation document if expected
  final expectedInstallationPath = expectedJson['installation'] as String?;
  if (expectedInstallationPath != null) {
    final expectedInstallation =
        _readGraphFromPath(testAssetsDir, expectedInstallationPath)!;
    final settings = await storage.getSettings(['installation_iri']);
    final installationIriStr = settings['installation_iri'];
    if (installationIriStr == null) {
      fail('No installation IRI found in settings');
    }
    final installationIri = IriTerm(installationIriStr).getDocumentIri();
    final storedInstallation = await storage.getDocument(installationIri);

    if (storedInstallation == null) {
      fail(await _failMissing(
          storage, CrdtClientInstallation.classIri, installationIri));
    }
    _expectEqualGraphs("$testId [step $stepIndex] - expected_installation",
        storedInstallation.document, expectedInstallation);
  }

  // Verify index documents if expected
  final expectedIndexDocs = expectedJson['index_documents'] as List<dynamic>?;
  if (expectedIndexDocs != null) {
    await _verifyIndexDocuments(
        testId, expectedIndexDocs, testAssetsDir, storage, config);
  }

  // Verify group index documents if expected
  final expectedGroupIndexDocs =
      expectedJson['group_index_documents'] as List<dynamic>?;
  if (expectedGroupIndexDocs != null) {
    await _verifyGroupIndexDocuments(
        testId, expectedGroupIndexDocs, testAssetsDir, storage, config);
  }

  // Verify shard documents if expected
  final expectedShardDocs = expectedJson['shard_documents'] as List<dynamic>?;
  if (expectedShardDocs != null) {
    await _verifyShardDocuments(
        testId, expectedShardDocs, testAssetsDir, storage, config);
  }

  // Export documents if requested (for test data generation)
  final exportValue = expectedJson['export_documents'];
  if (exportValue != null) {
    if (exportValue is String) {
      // Auto-export all documents to directory
      await _exportAllDocuments(
          testId, stepIndex, exportValue, testAssetsDir, storage, config);
    } else if (exportValue is List) {
      // Export specific documents with custom paths
      await _exportDocuments(
          testId, stepIndex, exportValue, testAssetsDir, storage, config);
    }
  }
}

void _expectEqualGraphs(String name, RdfGraph actual, RdfGraph expected) {
  expectEqualGraphs(name, actual, expected);
}

void setTime(String? ts, TestPhysicalTimestampFactory timestampFactory) {
  if (ts != null) {
    final dateTime = DateTime.parse(ts);
    timestampFactory.setTimestamp(dateTime);
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
/// Filters out framework properties from actual changes, as tests only verify app data changes.
void _expectEqualPropertyChanges(
    List<PropertyChange> actual, List<PropertyChange> expected) {
  // Filter to app data changes only (exclude framework metadata)
  final actualAppChanges =
      actual.where((pc) => !pc.isFrameworkProperty).toList();

  // Sort both lists by a consistent key for comparison
  String key(PropertyChange pc) =>
      '${pc.resourceIri.value}|${(pc.propertyIri as IriTerm).value}|${pc.changeLogicalClock}';

  final actualSorted = actualAppChanges.toList()
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
    'resource=${exp.resourceIri.debug}, property=${(exp.propertyIri as IriTerm).value}, clock=${exp.changeLogicalClock}, timestamp=${exp.changedAtMs}';

/// Verify index documents match expected graphs
Future<void> _verifyIndexDocuments(
  String testId,
  List<dynamic> expectedIndexDocs,
  Directory testAssetsDir,
  InMemoryStorage storage,
  SyncGraphConfig config,
) async {
  for (final indexDocJson in expectedIndexDocs) {
    final indexMap = indexDocJson as Map<String, dynamic>;
    final localName = indexMap['localName'] as String;
    final expectedGraphPath = indexMap['expected_graph'] as String;

    // Generate index IRI based on type and localName
    final indexRdfGenerator = _createIndexRdfGenerator();
    final (idx, resourceTypeIri) =
        _findIndexConfigByLocalName(config, localName)!;
    final indexResourceIri =
        indexRdfGenerator.generateIndexOrTemplateIri(idx, resourceTypeIri);
    final indexDocumentIri = indexResourceIri.getDocumentIri();

    // Get actual stored document
    final storedIndex = await storage.getDocument(indexDocumentIri);
    if (storedIndex == null) {
      fail(await _failMissing(
          storage,
          switch (idx) {
            FullIndexGraphConfig _ => IdxFullIndex.classIri,
            GroupIndexGraphConfig _ => IdxGroupIndex.classIri
          },
          indexDocumentIri));
    }

    // Load expected graph
    final expectedGraph = _readGraphFromPath(testAssetsDir, expectedGraphPath)!;

    _expectEqualGraphs("${testId} - expected_graph $expectedGraphPath",
        storedIndex.document, expectedGraph);
  }
}

/// Verify GroupIndex documents match expected graphs
Future<void> _verifyGroupIndexDocuments(
  String testId,
  List<dynamic> expectedGroupIndexDocs,
  Directory testAssetsDir,
  InMemoryStorage storage,
  SyncGraphConfig config,
) async {
  for (final groupIndexDocJson in expectedGroupIndexDocs) {
    final groupIndexMap = groupIndexDocJson as Map<String, dynamic>;
    final templateLocalName = groupIndexMap['template_localName'] as String;
    final groupPath = groupIndexMap['group_path'] as String;
    final expectedGraphPath = groupIndexMap['expected_graph'] as String;

    // Generate GroupIndex IRI from template and group path
    final indexRdfGenerator = _createIndexRdfGenerator();
    final (idx, resourceTypeIri) =
        _findIndexConfigByLocalName(config, templateLocalName)!;

    if (idx is! GroupIndexGraphConfig) {
      fail(
          'Expected GroupIndexGraphConfig for template $templateLocalName, got ${idx.runtimeType}');
    }

    // Generate template IRI first
    final templateIri =
        indexRdfGenerator.generateGroupIndexTemplateIri(idx, resourceTypeIri);

    // Then generate GroupIndex IRI for this specific group
    final groupIndexIri =
        indexRdfGenerator.generateGroupIndexIri(templateIri, groupPath);
    final groupIndexDocumentIri = groupIndexIri.getDocumentIri();

    // Get actual stored document
    final storedGroupIndex = await storage.getDocument(groupIndexDocumentIri);
    if (storedGroupIndex == null) {
      fail(await _failMissing(
          storage, IdxGroupIndex.classIri, groupIndexDocumentIri));
    }

    // Load expected graph
    final expectedGraph = _readGraphFromPath(testAssetsDir, expectedGraphPath)!;

    _expectEqualGraphs(
        "${testId} - expected group index graph $expectedGraphPath",
        storedGroupIndex.document,
        expectedGraph);
  }
}

(CrdtIndexGraphConfig, IriTerm resourceTypeIri)? _findIndexConfigByLocalName(
    SyncGraphConfig config, String localName) {
  for (var resource in config.resources) {
    for (var index in resource.indices) {
      if (index.localName == localName) {
        return (index, resource.typeIri);
      }
    }
  }
  return null;
}

IndexRdfGenerator _createIndexRdfGenerator(
    [ShardManager shardManager = const ShardManager()]) {
  final resourceLocator =
      LocalResourceLocator(iriTermFactory: IriTerm.validated);
  final indexRdfGenerator = IndexRdfGenerator(
    resourceLocator: resourceLocator,
    shardManager: shardManager,
  );
  return indexRdfGenerator;
}

/// Verify shard documents match expected graphs
Future<void> _verifyShardDocuments(
  String testId,
  List<dynamic> expectedShardDocs,
  Directory testAssetsDir,
  InMemoryStorage storage,
  SyncGraphConfig config,
) async {
  for (final shardDocJson in expectedShardDocs) {
    final shardMap = shardDocJson as Map<String, dynamic>;
    final indexLocalName = shardMap['index_localName'] as String?;
    final shardTotal = shardMap['shard_total'] as int;
    final shardNumber = shardMap['shard_number'] as int;
    final shardVersion = shardMap['shard_version'] as String;
    final expectedGraphPath = shardMap['expected_graph'] as String;
    final groupPath =
        shardMap['group_path'] as String?; // For GroupIndex shards

    // Allow direct specification of index IRIs (for foreign/external indices)
    final indexResourceIriString = shardMap['index_resource_iri'] as String?;
    final indexClassIriString = shardMap['index_class_iri'] as String?;

    final indexRdfGenerator = _createIndexRdfGenerator();
    final IriTerm indexResourceIri;
    final IriTerm indexClassIri;

    if (indexResourceIriString != null && indexClassIriString != null) {
      // Direct IRI specification - use these directly
      indexResourceIri = IriTerm(indexResourceIriString);
      indexClassIri = IriTerm(indexClassIriString);
    } else if (indexLocalName != null) {
      // Generate shard IRI from config
      final (idx, resourceTypeIri) =
          _findIndexConfigByLocalName(config, indexLocalName)!;

      if (idx is FullIndexGraphConfig) {
        indexResourceIri =
            indexRdfGenerator.generateFullIndexIri(idx, resourceTypeIri);
        indexClassIri = IdxFullIndex.classIri;
      } else if (idx is GroupIndexGraphConfig) {
        if (groupPath == null) {
          fail('group_path is required for GroupIndex shards');
        }
        // First generate template IRI, then group index IRI
        final templateIri = indexRdfGenerator.generateGroupIndexTemplateIri(
            idx, resourceTypeIri);
        indexResourceIri =
            indexRdfGenerator.generateGroupIndexIri(templateIri, groupPath);
        indexClassIri = IdxGroupIndex.classIri;
      } else {
        fail('Unsupported index config type: ${idx.runtimeType}');
      }
    } else {
      fail(
          'Either index_localName or both index_resource_iri and index_class_iri must be provided');
    }

    final shardResourceIri = indexRdfGenerator.generateShardIri(
        shardTotal, shardNumber, shardVersion, indexResourceIri, indexClassIri);

    // Calculate index hash

    final shardDocumentIri = shardResourceIri.getDocumentIri();

    // Get actual stored shard document
    final storedShard = await storage.getDocument(shardDocumentIri);
    if (storedShard == null) {
      fail(await _failMissing(storage, IdxShard.classIri, shardDocumentIri));
    }

    // Load expected graph
    final expectedGraph = _readGraphFromPath(testAssetsDir, expectedGraphPath)!;

    _expectEqualGraphs("${testId} - expected_graph $expectedGraphPath",
        storedShard.document, expectedGraph);
  }
}

Future<String> _failMissing(
    InMemoryStorage storage, IriTerm typeIri, IriTerm shardDocumentIri) async {
  final all = await storage.watchDocumentsModifiedSince(typeIri, null).first;
  final existing = all.documents
      .map((d) => '${d.documentIri.debug} - ${d.documentIri.value}')
      .join('\n');
  final failMsg =
      'No ${typeIri.localName} document stored for  ${shardDocumentIri.debug} - $shardDocumentIri\nExisting documents:\n$existing';
  return failMsg;
}

/// Execute a save error test - expects an exception to be thrown
Future<void> _executeSaveErrorTest(
    Map<String, dynamic> testJson,
    Directory testAssetsDir,
    Map<String, String> urlToPathMap,
    DateTime baseTimestamp,
    String? baseInstallationId) async {
  // Load configuration
  final config = _loadConfig(testAssetsDir, testJson['config'] as String);

  // Get type IRI
  final typeIri = IriTerm(testJson['typeIri'] as String);

  // Load input resource
  final inputResource =
      _readGraphFromPath(testAssetsDir, testJson['input_resource'] as String)!;

  // Get expected error details
  final expectedJson = testJson['expected'] as Map<String, dynamic>;
  final expectedErrorType = expectedJson['error_type'] as String;
  final expectedErrorMessagePattern =
      expectedJson['error_message_pattern'] as String?;

  // Load action timestamps if provided
  final actionTs = testJson['action_ts'] as Map<String, dynamic>?;

  final storage = InMemoryStorage();

  try {
    // Execute save (should throw)
    final timestampFactory =
        TestPhysicalTimestampFactory(baseTimestamp: baseTimestamp);

    final fetcher = TestFetcher(
      testAssetsDir: testAssetsDir,
      urlToPathMap: urlToPathMap,
    );

    final installationIdFactory =
        baseInstallationId != null ? () => baseInstallationId : null;

    final sync = await LocordaGraphSync.setup(
        backends: [InMemoryBackend()],
        storage: storage,
        config: config,
        fetcher: fetcher,
        physicalTimestampFactory: timestampFactory,
        installationIdFactory: installationIdFactory);

    // Set timestamp for save action if specified
    setTime(actionTs?['save'], timestampFactory);

    await sync.save(typeIri, inputResource);

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

/// Export documents from storage to files for test data generation.
///
/// Exports all documents from storage to a directory with auto-generated names.
/// This is used for generating test data from a "foreign application" simulation.
Future<void> _exportAllDocuments(
  String testId,
  int stepIndex,
  String outputDir,
  Directory testAssetsDir,
  InMemoryStorage storage,
  SyncGraphConfig config,
) async {
  // Get all document types from config plus infrastructure types
  final typeIris = <IriTerm>[
    IdxFullIndex.classIri,
    IdxGroupIndexTemplate.classIri,
    IdxGroupIndex.classIri,
    IdxShard.classIri,
    CrdtClientInstallation.classIri,
    // Add all resource types from config
    for (final resourceConfig in config.resources) resourceConfig.typeIri,
  ];

  final exportedFiles = <String>[];

  // Export documents of each type
  for (final typeIri in typeIris) {
    final docs = await storage.watchDocumentsModifiedSince(typeIri, null).first;

    for (final doc in docs.documents) {
      // Generate filename from type and document IRI
      final typeName = typeIri.localName.toLowerCase();
      final docHash =
          doc.documentIri.value.hashCode.toUnsigned(32).toRadixString(16);
      final filename = 'prepare_${typeName}_$docHash.ttl';

      // Serialize to Turtle
      final turtleContent = turtle.encode(doc.document);

      // Write to file
      final outputFile = File('${testAssetsDir.path}/$outputDir/$filename');
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsString(turtleContent);

      exportedFiles.add(filename);
      print('Exported ${doc.documentIri.debug} to $outputDir/$filename');
    }
  }

  print('Exported ${exportedFiles.length} documents to $outputDir/');
}

/// This is used to capture the state of documents created by one test configuration
/// (e.g., a "foreign application") so they can be used as prepare data in another test.
Future<void> _exportDocuments(
  String testId,
  int stepIndex,
  List<dynamic> exportDocs,
  Directory testAssetsDir,
  InMemoryStorage storage,
  SyncGraphConfig config,
) async {
  for (final exportJson in exportDocs) {
    final exportMap = exportJson as Map<String, dynamic>;
    final documentIriStr = exportMap['documentIri'] as String;
    final outputPath = exportMap['output_path'] as String;

    final documentIri = IriTerm(documentIriStr);
    final storedDoc = await storage.getDocument(documentIri);

    if (storedDoc == null) {
      print(
          'WARNING: Document $documentIri not found in storage, skipping export');
      continue;
    }

    // Serialize to Turtle
    final turtleContent = turtle.encode(storedDoc.document);

    // Write to file
    final outputFile = File('${testAssetsDir.path}/$outputPath');
    await outputFile.parent.create(recursive: true);
    await outputFile.writeAsString(turtleContent);

    print('Exported $documentIri to $outputPath');
  }
}
