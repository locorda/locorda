import 'package:rdf_core/rdf_core.dart';
import 'package:locorda_core/src/index/group_key_generator.dart';
import 'package:locorda_core/src/index/index_config_base.dart';
import 'package:locorda_core/src/config/sync_graph_config.dart';
import 'package:test/test.dart';

void main() {
  group('GroupKeyGenerator', () {
    // Test vocabulary for consistent URIs
    final testSubject = const IriTerm('http://example.org/resource/123');
    final categoryPredicate = const IriTerm('http://example.org/category');
    final dateCreatedPredicate =
        const IriTerm('https://schema.org/dateCreated');

    group('basic functionality', () {
      test('generates simple group key from single property', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(
              dateCreatedPredicate,
              transforms: [
                RegexTransform(
                    r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$', r'${1}-${2}'),
              ],
            ),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          Triple(testSubject, dateCreatedPredicate,
              LiteralTerm.string('2024-08-15')),
        ];

        final result = generator.generateGroupKeys(triples);
        expect(result, equals({'2024-08'}));
      });

      test('generates group key without transforms', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(categoryPredicate),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          Triple(testSubject, categoryPredicate, LiteralTerm.string('work')),
        ];

        final result = generator.generateGroupKeys(triples);
        expect(result, equals({'work'}));
      });

      test('returns null when required property is missing', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(dateCreatedPredicate),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          Triple(testSubject, categoryPredicate, LiteralTerm.string('work')),
          // Missing the required dateCreated property
        ];

        final result = generator.generateGroupKeys(triples);
        expect(result, isEmpty);
      });

      test('uses missing value when property is absent', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(
              categoryPredicate,
              missingValue: 'uncategorized',
            ),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          Triple(testSubject, dateCreatedPredicate,
              LiteralTerm.string('2024-08-15')),
          // Missing the category property
        ];

        final result = generator.generateGroupKeys(triples);
        expect(result, equals({'uncategorized'}));
      });
    });

    group('hierarchical grouping', () {
      test('generates hierarchical group key with multiple levels', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(
              dateCreatedPredicate,
              hierarchyLevel: 1,
              transforms: [
                RegexTransform(
                    r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$', r'${1}'), // Year
              ],
            ),
            GroupingProperty(
              dateCreatedPredicate,
              hierarchyLevel: 2,
              transforms: [
                RegexTransform(r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$',
                    r'${1}-${2}'), // Month
              ],
            ),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          Triple(testSubject, dateCreatedPredicate,
              LiteralTerm.string('2024-08-15')),
        ];

        final result = generator.generateGroupKeys(triples);
        expect(result, equals({'2024/2024-08'}));
      });

      test('handles multiple properties at the same hierarchy level', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(
              categoryPredicate, // http://example.org/category
              hierarchyLevel: 1,
            ),
            GroupingProperty(
              dateCreatedPredicate,
              hierarchyLevel: 1,
              transforms: [
                RegexTransform(
                    r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$', r'${1}-${2}'),
              ],
            ),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          Triple(testSubject, categoryPredicate, LiteralTerm.string('work')),
          Triple(testSubject, dateCreatedPredicate,
              LiteralTerm.string('2024-08-15')),
        ];

        final result = generator.generateGroupKeys(triples);
        // Properties are ordered lexicographically by IRI:
        // http://example.org/category < https://schema.org/dateCreated
        expect(result, equals({'work-2024-08'}));
      });

      test('processes hierarchy levels in correct order', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(
              dateCreatedPredicate,
              hierarchyLevel: 3, // Intentionally out of order
              transforms: [
                RegexTransform(
                    r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$', r'${3}'), // Day
              ],
            ),
            GroupingProperty(
              categoryPredicate,
              hierarchyLevel: 1,
            ),
            GroupingProperty(
              dateCreatedPredicate,
              hierarchyLevel: 2,
              transforms: [
                RegexTransform(
                    r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$', r'${2}'), // Month
              ],
            ),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          Triple(testSubject, categoryPredicate, LiteralTerm.string('work')),
          Triple(testSubject, dateCreatedPredicate,
              LiteralTerm.string('2024-08-15')),
        ];

        final result = generator.generateGroupKeys(triples);
        expect(result, equals({'work/08/15'}));
      });
    });

    group('regex transform integration', () {
      test('applies multiple transforms in order - first match wins', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(
              dateCreatedPredicate,
              transforms: [
                RegexTransform(r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$',
                    r'${1}-${2}'), // ISO format
                RegexTransform(r'^([0-9]{4})/([0-9]{2})/([0-9]{2})$',
                    r'${1}-${2}'), // US format
              ],
            ),
          ],
        );

        final generator = GroupKeyGenerator(config);

        // Test ISO format (first transform should match)
        final isoTriples = [
          Triple(testSubject, dateCreatedPredicate,
              LiteralTerm.string('2024-08-15')),
        ];
        expect(generator.generateGroupKeys(isoTriples), equals({'2024-08'}));

        // Test US format (second transform should match)
        final usTriples = [
          Triple(testSubject, dateCreatedPredicate,
              LiteralTerm.string('2024/08/15')),
        ];
        expect(generator.generateGroupKeys(usTriples), equals({'2024-08'}));
      });

      test('handles complex transform patterns from specification', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(
              categoryPredicate,
              transforms: [
                RegexTransform(r'^project[-_]([a-zA-Z0-9]+)$', r'${1}'),
                RegexTransform(r'^proj[-_]([a-zA-Z0-9]+)$', r'${1}'),
                RegexTransform(r'^([a-zA-Z0-9]+)[-_]project$', r'${1}'),
                RegexTransform(r'^([a-zA-Z0-9]+)[-_]proj$', r'${1}'),
              ],
            ),
          ],
        );

        final generator = GroupKeyGenerator(config);

        final testCases = [
          ('project-alpha', 'alpha'),
          ('proj_beta', 'beta'),
          ('gamma-project', 'gamma'),
          ('delta_proj', 'delta'),
        ];

        for (final (input, expected) in testCases) {
          final triples = [
            Triple(testSubject, categoryPredicate, LiteralTerm.string(input)),
          ];
          final result = generator.generateGroupKeys(triples);
          expect(result, equals({expected}), reason: 'Input: $input');
        }
      });

      test('uses original value when no transforms match', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(
              categoryPredicate,
              transforms: [
                RegexTransform(r'^number-(\d+)$', r'${1}'), // Won't match
              ],
            ),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          Triple(
              testSubject, categoryPredicate, LiteralTerm.string('text-value')),
        ];

        final result = generator.generateGroupKeys(triples);
        expect(result, equals({'text-value'}));
      });
    });

    group('RDF term type handling', () {
      test('handles IRI objects', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(
              categoryPredicate,
              transforms: [
                RegexTransform(r'^http://example\.org/category/(.+)$', r'${1}'),
              ],
            ),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          Triple(testSubject, categoryPredicate,
              const IriTerm('http://example.org/category/work')),
        ];

        final result = generator.generateGroupKeys(triples);
        expect(result, equals({'work'}));
      });

      test('handles literal with datatype', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(
              dateCreatedPredicate,
              transforms: [
                RegexTransform(
                    r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$', r'${1}-${2}'),
              ],
            ),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          Triple(testSubject, dateCreatedPredicate,
              LiteralTerm.string('2024-08-15')),
        ];

        final result = generator.generateGroupKeys(triples);
        expect(result, equals({'2024-08'}));
      });

      test('returns null for blank node objects', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(categoryPredicate),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          Triple(testSubject, categoryPredicate, BlankNodeTerm()),
        ];

        final result = generator.generateGroupKeys(triples);
        expect(result, isEmpty);
      });
    });

    group('cartesian product generation', () {
      test(
          'generates cartesian product from multiple properties with multiple values',
          () {
        // Test the core Cartesian product functionality as specified in ARCHITECTURE.md 5.3.3
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(
                categoryPredicate), // Multiple values: work, personal
            GroupingProperty(dateCreatedPredicate, transforms: [
              RegexTransform(
                  r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$', r'${1}-${2}'),
            ]), // Multiple values: 2024-08, 2024-09
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          // Two category values
          Triple(testSubject, categoryPredicate, LiteralTerm.string('work')),
          Triple(
              testSubject, categoryPredicate, LiteralTerm.string('personal')),
          // Two date values
          Triple(testSubject, dateCreatedPredicate,
              LiteralTerm.string('2024-08-15')),
          Triple(testSubject, dateCreatedPredicate,
              LiteralTerm.string('2024-09-20')),
        ];

        final result = generator.generateGroupKeys(triples);
        // Should generate 2x2 = 4 combinations
        // Lexicographic IRI ordering: category < dateCreated
        expect(
            result,
            equals({
              'work-2024-08',
              'work-2024-09',
              'personal-2024-08',
              'personal-2024-09'
            }));
      });

      test('generates cartesian product across hierarchy levels', () {
        final priorityPredicate = const IriTerm('http://example.org/priority');

        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            // Level 1: Two properties, each with multiple values
            GroupingProperty(categoryPredicate, hierarchyLevel: 1),
            GroupingProperty(priorityPredicate, hierarchyLevel: 1),
            // Level 2: One property with multiple values
            GroupingProperty(dateCreatedPredicate,
                hierarchyLevel: 2,
                transforms: [
                  RegexTransform(
                      r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$', r'${1}'),
                ]),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          // Two categories
          Triple(testSubject, categoryPredicate, LiteralTerm.string('work')),
          Triple(
              testSubject, categoryPredicate, LiteralTerm.string('personal')),
          // Two priorities
          Triple(testSubject, priorityPredicate, LiteralTerm.string('high')),
          Triple(testSubject, priorityPredicate, LiteralTerm.string('low')),
          // Two years
          Triple(testSubject, dateCreatedPredicate,
              LiteralTerm.string('2023-08-15')),
          Triple(testSubject, dateCreatedPredicate,
              LiteralTerm.string('2024-08-15')),
        ];

        final result = generator.generateGroupKeys(triples);
        // Should generate 2x2x2 = 8 combinations
        // Level 1: category-priority (lexicographic: category < priority)
        // Level 2: year
        expect(
            result,
            equals({
              'work-high/2023',
              'work-high/2024',
              'work-low/2023',
              'work-low/2024',
              'personal-high/2023',
              'personal-high/2024',
              'personal-low/2023',
              'personal-low/2024',
            }));
      });

      test('handles cartesian product with missing values', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(categoryPredicate, missingValue: 'default'),
            GroupingProperty(dateCreatedPredicate, transforms: [
              RegexTransform(
                  r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$', r'${1}-${2}'),
            ]),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          // No category (will use missing value)
          // Two dates
          Triple(testSubject, dateCreatedPredicate,
              LiteralTerm.string('2024-08-15')),
          Triple(testSubject, dateCreatedPredicate,
              LiteralTerm.string('2024-09-20')),
        ];

        final result = generator.generateGroupKeys(triples);
        // Should generate 1x2 = 2 combinations using missing value
        expect(
            result,
            equals({
              'default-2024-08',
              'default-2024-09',
            }));
      });
    });

    group('deduplication and edge cases', () {
      test('deduplicates identical group keys from different transform paths',
          () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(
              categoryPredicate,
              transforms: [
                RegexTransform(r'^work-(.+)$', r'${1}'), // Transform 1
                RegexTransform(r'^(.+)-project$', r'${1}'), // Transform 2
              ],
            ),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          // These should both transform to 'alpha'
          Triple(
              testSubject, categoryPredicate, LiteralTerm.string('work-alpha')),
          Triple(testSubject, categoryPredicate,
              LiteralTerm.string('alpha-project')),
        ];

        final result = generator.generateGroupKeys(triples);
        // Should deduplicate to single 'alpha' result
        expect(result, equals({'alpha'}));
      });

      test('handles different datatypes with same string representation', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(dateCreatedPredicate),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          // Different RDF datatypes but same string content
          Triple(testSubject, dateCreatedPredicate, LiteralTerm.string('42')),
          Triple(
              testSubject,
              dateCreatedPredicate,
              LiteralTerm('42',
                  datatype: const IriTerm(
                      'http://www.w3.org/2001/XMLSchema#integer'))),
        ];

        final result = generator.generateGroupKeys(triples);
        // Should deduplicate based on string representation
        expect(result, equals({'42'}));
      });

      test('handles literals with language tags', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(categoryPredicate),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          Triple(testSubject, categoryPredicate,
              LiteralTerm('travail', language: 'fr')), // French
          Triple(testSubject, categoryPredicate,
              LiteralTerm('work', language: 'en')), // English
        ];

        final result = generator.generateGroupKeys(triples);
        // Should use string content, ignoring language tags
        expect(result, equals({'travail', 'work'}));
      });
    });

    group('multiple triples handling', () {
      test(
          'generates multiple group keys when multiple property values present',
          () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(categoryPredicate),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          Triple(testSubject, categoryPredicate, LiteralTerm.string('work')),
          Triple(
              testSubject,
              categoryPredicate,
              LiteralTerm.string(
                  'personal')), // Second value creates Cartesian product
          Triple(testSubject, dateCreatedPredicate,
              LiteralTerm.string('2024-08-15')),
        ];

        final result = generator.generateGroupKeys(triples);
        expect(result, equals({'work', 'personal'}));
      });

      test('handles mixed relevant and irrelevant triples', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(
              dateCreatedPredicate,
              transforms: [
                RegexTransform(
                    r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$', r'${1}-${2}'),
              ],
            ),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          Triple(testSubject, const IriTerm('http://example.org/title'),
              LiteralTerm.string('Some Title')),
          Triple(testSubject, dateCreatedPredicate,
              LiteralTerm.string('2024-08-15')),
          Triple(testSubject, const IriTerm('http://example.org/content'),
              LiteralTerm.string('Content here')),
        ];

        final result = generator.generateGroupKeys(triples);
        expect(result, equals({'2024-08'}));
      });
    });

    group('edge cases and error handling', () {
      test('handles empty triples list', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(categoryPredicate),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final result = generator.generateGroupKeys([]);

        expect(result, isEmpty);
      });

      test('handles empty triples list with missing values', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(
              categoryPredicate,
              missingValue: 'default',
            ),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final result = generator.generateGroupKeys([]);

        expect(result, equals({'default'}));
      });

      test('handles configuration with no grouping properties', () {
        // This should not happen in practice due to assertion in GroupIndex constructor
        // The constructor should throw an assertion error for empty grouping properties
        expect(
            () => GroupIndexGraphConfig(
                  localName: 'test-index',
                  groupingProperties: [], // This will fail assertion
                ),
            throwsA(isA<AssertionError>()));
      });

      test('handles mixed missing and present properties', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(
              categoryPredicate,
              hierarchyLevel: 1,
              missingValue: 'uncategorized',
            ),
            GroupingProperty(
              dateCreatedPredicate,
              hierarchyLevel: 2,
              transforms: [
                RegexTransform(
                    r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$', r'${1}-${2}'),
              ],
            ),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          Triple(testSubject, dateCreatedPredicate,
              LiteralTerm.string('2024-08-15')),
          // Missing category property
        ];

        final result = generator.generateGroupKeys(triples);
        expect(result, equals({'uncategorized/2024-08'}));
      });
    });

    group('performance and efficiency', () {
      test('efficiently organizes extractors by level', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(categoryPredicate, hierarchyLevel: 2),
            GroupingProperty(dateCreatedPredicate, hierarchyLevel: 1),
            GroupingProperty(const IriTerm('http://example.org/priority'),
                hierarchyLevel: 2),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          Triple(testSubject, categoryPredicate, LiteralTerm.string('work')),
          Triple(testSubject, dateCreatedPredicate,
              LiteralTerm.string('2024-08-15')),
          Triple(testSubject, const IriTerm('http://example.org/priority'),
              LiteralTerm.string('high')),
        ];

        final result = generator.generateGroupKeys(triples);
        // Level 1: dateCreated, Level 2: category-priority (lexicographic IRI order)
        // http://example.org/category < http://example.org/priority
        expect(result, equals({'2024-08-15/work-high'}));
      });

      test('enforces lexicographic IRI ordering within same level', () {
        // Create predicates with clear lexicographic ordering
        final aProperty = const IriTerm('http://example.org/a');
        final zProperty = const IriTerm('http://example.org/z');

        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            // Intentionally declare in reverse alphabetical order
            GroupingProperty(zProperty, hierarchyLevel: 1),
            GroupingProperty(aProperty, hierarchyLevel: 1),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          Triple(testSubject, aProperty, LiteralTerm.string('first')),
          Triple(testSubject, zProperty, LiteralTerm.string('last')),
        ];

        final result = generator.generateGroupKeys(triples);
        // Despite declaration order (z, a), lexicographic IRI ordering gives us (a, z)
        expect(result, equals({'first-last'}));
      });

      test('reuses compiled regex patterns', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(
              dateCreatedPredicate,
              transforms: [
                RegexTransform(
                    r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$', r'${1}-${2}'),
              ],
            ),
          ],
        );

        final generator = GroupKeyGenerator(config);

        // Multiple calls should reuse the compiled patterns efficiently
        final triples1 = [
          Triple(testSubject, dateCreatedPredicate,
              LiteralTerm.string('2024-08-15')),
        ];
        final triples2 = [
          Triple(testSubject, dateCreatedPredicate,
              LiteralTerm.string('2024-09-20')),
        ];

        expect(generator.generateGroupKeys(triples1), equals({'2024-08'}));
        expect(generator.generateGroupKeys(triples2), equals({'2024-09'}));
      });
    });

    group('filesystem safety integration', () {
      test('preserves safe group keys unchanged', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(categoryPredicate),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          Triple(testSubject, categoryPredicate, LiteralTerm.string('work')),
        ];

        final result = generator.generateGroupKeys(triples);
        // Safe keys should be preserved exactly
        expect(result, equals({'work'}));
      });

      test('makes unsafe single-level group keys filesystem-safe', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(categoryPredicate),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          Triple(testSubject, categoryPredicate,
              LiteralTerm.string('contains/slash')),
        ];

        final result = generator.generateGroupKeys(triples);
        final groupKey = result.first;

        // Should be hashed due to unsafe characters
        expect(groupKey, equals('14_a483ee140ab4c8dd7a20be801e2982d7'));
      });

      test('makes unsafe hierarchical group keys filesystem-safe', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(
              categoryPredicate,
              hierarchyLevel: 1,
            ),
            GroupingProperty(
              dateCreatedPredicate,
              hierarchyLevel: 2,
              transforms: [
                RegexTransform(
                    r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$', r'${1}-${2}'),
              ],
            ),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          Triple(testSubject, categoryPredicate,
              LiteralTerm.string('unsafe:category')),
          Triple(testSubject, dateCreatedPredicate,
              LiteralTerm.string('2024-08-15')),
        ];

        final result = generator.generateGroupKeys(triples);
        final groupKey = result.first;

        // Should have safe date component and hashed category component
        expect(groupKey, equals('15_2e6ebbea1fa1fa110a66dc847c0e9b36/2024-08'));
      });

      test('handles mixed safe and unsafe components in hierarchical paths',
          () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(
              categoryPredicate,
              hierarchyLevel: 1,
            ),
            GroupingProperty(
              dateCreatedPredicate,
              hierarchyLevel: 2,
              transforms: [
                RegexTransform(r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$', r'${1}'),
              ],
            ),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          Triple(testSubject, categoryPredicate,
              LiteralTerm.string('work')), // Safe
          Triple(testSubject, dateCreatedPredicate,
              LiteralTerm.string('2024-08-15')), // Safe after transform
        ];

        final result = generator.generateGroupKeys(triples);
        // Both components are safe, should be preserved
        expect(result, equals({'work/2024'}));
      });

      test('handles IRI values with filesystem safety', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(categoryPredicate),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          Triple(testSubject, categoryPredicate,
              const IriTerm('http://example.org/category/work')),
        ];

        final result = generator.generateGroupKeys(triples);
        final groupKey = result.first;

        // IRI contains unsafe characters, should be hashed
        expect(groupKey, equals('32_5b2b9616e0134f026cc73e3bf8115ab6'));
      });

      test('ensures deterministic filesystem-safe results', () {
        final config = GroupIndexGraphConfig(
          localName: 'test-index',
          groupingProperties: [
            GroupingProperty(categoryPredicate),
          ],
        );

        final generator = GroupKeyGenerator(config);
        final triples = [
          Triple(testSubject, categoryPredicate,
              LiteralTerm.string('unicode-café')),
        ];

        final result1 = generator.generateGroupKeys(triples);
        final result2 = generator.generateGroupKeys(triples);

        // Should produce identical results
        expect(result1, equals(result2));

        // Should be hashed due to unicode characters
        final groupKey = result1.first;
        expect(groupKey, equals('12_cdc649a181b63cd672da583bf751418c'));
      });
    });
  });
}
