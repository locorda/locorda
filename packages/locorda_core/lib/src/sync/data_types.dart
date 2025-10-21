import 'package:locorda_core/src/crdt/crdt_types.dart';
import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/hlc_service.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:logging/logging.dart';
import 'package:rdf_core/rdf_core.dart';

final _log = Logger('RemoteDocumentMerger');

/// Organized statement data structures for efficient lookup during merge.
///
/// Note that identified blank nodes are already resolved from canonical IRIs
/// in graph statements to actual blank nodes in the graph,
/// so that you can directly  use blank nodes from the graph when querying statements.
class OrganizedStatements {
  final Map<MetadataStatementKey, MetadataStatement> _statementsByKey;
  final Iterable<RdfSubject> statementIdentifiers;

  MetadataStatement? getStatementForTriple(Triple triple) =>
      _statementsByKey[MetadataStatementKey.fromTriple(triple)];

  MetadataStatement? getStatementForSubjectPredicate(
          RdfSubject subject, RdfPredicate predicate) =>
      _statementsByKey[
          MetadataStatementKey.fromSubjectPredicate(subject, predicate)];

  MetadataStatement? getStatementForSubject(RdfSubject subject) =>
      _statementsByKey[MetadataStatementKey.fromSubject(subject)];

  OrganizedStatements._(
      Iterable<MetadataStatement> statements, this.statementIdentifiers)
      : _statementsByKey = {for (final stmt in statements) stmt.key: stmt} {
    if (_statementsByKey.length != statements.length) {
      throw StateError(
          'Duplicate statements found during OrganizedStatements creation. '
          'This may indicate an issue with statement identification.');
    }
  }

  factory OrganizedStatements.fromGraph(
    IriTerm documentIri,
    RdfGraph document,
    OrganizedBlankNodeMappings blankNodeMappings,
  ) {
    final statementIdentifiers = document.getMultiValueObjects<RdfSubject>(
        documentIri, SyncManagedDocument.hasStatement);
    final statementGraphs = {
      for (final subject in statementIdentifiers)
        subject: document.matching(subject: subject)
    };
    final statementsByKey = <MetadataStatementKey, Set<Node>>{};

    for (final entry in statementGraphs.entries) {
      final subject = entry.key;
      final graph = entry.value;
      final rdfSubject =
          graph.findSingleObject<RdfSubject>(subject, RdfStatement.subject);
      if (rdfSubject is BlankNodeTerm) {
        throw StateError(
            'Statement subject cannot be a blank node in document $documentIri: $rdfSubject');
      }
      final rdfPredicate =
          graph.findSingleObject<IriTerm>(subject, RdfStatement.predicate);
      final rdfObject =
          graph.findSingleObject<RdfObject>(subject, RdfStatement.object);
      if (rdfObject is BlankNodeTerm) {
        throw StateError(
            'Statement object cannot be a blank node in document $documentIri: $rdfObject');
      }
      final realSubject = rdfSubject is IriTerm
          ? blankNodeMappings.getBlankNode(rdfSubject) ?? rdfSubject
          : rdfSubject;
      final realObject = rdfObject is IriTerm
          ? blankNodeMappings.getBlankNode(rdfObject) ?? rdfObject
          : rdfObject;
      final MetadataStatementKey key;
      if (realSubject != null && rdfPredicate != null && realObject != null) {
        key = MetadataStatementKey.fromSubjectPredicateObject(
            subject, rdfPredicate, realObject);
      } else if (realSubject != null && rdfPredicate != null) {
        key = MetadataStatementKey.fromSubjectPredicate(subject, rdfPredicate);
      } else if (realSubject != null) {
        key = MetadataStatementKey.fromSubject(subject);
      } else {
        throw StateError(
            'Invalid statement node in document $documentIri: $subject  - \n${'-' * 40}\n${turtle.encode(graph)}\n${'-' * 40}\n');
      }
      statementsByKey.putIfAbsent(key, () => <Node>{}).add((subject, graph));
    }
    final statements = statementsByKey.entries.map((entry) {
      final key = entry.key;
      final nodes = entry.value;
      final predicateObjectMap =
          nodes.fold(<RdfPredicate, Set<RdfObject>>{}, (map, node) {
        final (subject, graph) = node;
        for (final triple in graph.findTriples(subject: subject)) {
          final objects =
              map.putIfAbsent(triple.predicate, () => <RdfObject>{});
          final realTripleObject = triple.object is IriTerm
              ? blankNodeMappings.getBlankNode(triple.object as IriTerm) ??
                  triple.object
              : triple.object;
          objects.add(realTripleObject);
        }
        return map;
      });
      return MetadataStatement(key, predicateObjectMap);
    });
    return OrganizedStatements._(statements, statementIdentifiers);
  }
}

enum MergeSubjectType {
  statement,
  blankNodeIdentifier,
  identifiedBlankNode,
  unidentifiedBlankNode,
  iri,
}

class MergeSubject {
  final RdfSubject? localSubject;
  final RdfSubject? remoteSubject;
  final RdfSubjectKey key;
  final MergeSubjectType type;
  late final RdfSubject subject;

  MergeSubject._({
    required this.localSubject,
    required this.remoteSubject,
    required this.key,
    required this.type,
  }) {
    if (localSubject == null && remoteSubject == null) {
      throw ArgumentError(
          'Both localSubject and remoteSubject are null for MergeSubject with key: $key');
    }
    subject = localSubject ?? remoteSubject!;
  }

  static MergeSubjectType _determineType(RdfSubjectKey key,
      Set<RdfSubject> statementIdentifiers, Set<IriTerm> blankNodeIdentifiers) {
    if (statementIdentifiers.contains(key.subject)) {
      return MergeSubjectType.statement;
    }
    if (blankNodeIdentifiers.contains(key.subject)) {
      return MergeSubjectType.blankNodeIdentifier;
    }
    return switch (key) {
      IriSubjectKey() => MergeSubjectType.iri,
      IdentifiedBlankNodeKey() => MergeSubjectType.identifiedBlankNode,
      UnIdentifiedBlankNodeKey() => MergeSubjectType.unidentifiedBlankNode,
    };
  }

  static Iterable<MergeSubject> createMergeSubjects(
      OrganizedGraph local, OrganizedGraph remote) {
    final allKeys = {...local.allSubjectKeys, ...remote.allSubjectKeys};
    final allStatementIdentifiers = {
      ...local.statements.statementIdentifiers,
      ...remote.statements.statementIdentifiers
    };
    final allBlankNodeIdentifiers = {
      ...local.blankNodeMappings.blankNodeIdentifiers,
      ...remote.blankNodeMappings.blankNodeIdentifiers
    };
    return allKeys.map((key) => MergeSubject._(
        localSubject: local.getSubjectForKey(key),
        remoteSubject: remote.getSubjectForKey(key),
        key: key,
        type: _determineType(
            key, allStatementIdentifiers, allBlankNodeIdentifiers)));
  }
}

class OrganizedBlankNodeMappings {
  /// Maps blank node identifier to its mapping subject
  final Map<BlankNodeTerm, Iterable<IriTerm>> _identifiedBlankNodes;

  late final Set<IriTerm> blankNodeIdentifiers =
      _identifiedBlankNodes.values.expand((v) => v).toSet();
  late final Map<IriTerm, BlankNodeTerm> _canonicalToBlankNodeMap = {
    for (final entry in _identifiedBlankNodes.entries) ...{
      for (final iri in entry.value) iri: entry.key
    }
  };
  Iterable<BlankNodeTerm> get identifiedBlankNodes =>
      _identifiedBlankNodes.keys;

  OrganizedBlankNodeMappings._(this._identifiedBlankNodes);

  Iterable<IriTerm>? getCanonicalIrisForBlankNode(BlankNodeTerm blankNode) {
    return _identifiedBlankNodes[blankNode];
  }

  factory OrganizedBlankNodeMappings.fromGraph(
    IriTerm documentIri,
    RdfGraph document,
  ) {
    final blankNodeIdentifiers = document.getMultiValueObjects<RdfSubject>(
      documentIri,
      SyncManagedDocument.hasBlankNodeMapping,
    );
    final identifiedBlankNodes =
        _buildBlankNodeToCanonicalMap(document, blankNodeIdentifiers);

    return OrganizedBlankNodeMappings._(
      identifiedBlankNodes,
    );
  }

  static Map<BlankNodeTerm, Set<IriTerm>> _buildBlankNodeToCanonicalMap(
      RdfGraph localGraph, Set<RdfSubject> localSubjects) {
    return localGraph
        .findTriples(
            subjectIn: localSubjects, predicate: SyncBlankNodeMapping.blankNode)
        .fold(<BlankNodeTerm, Set<IriTerm>>{}, (map, triple) {
      if (triple.predicate == SyncBlankNodeMapping.blankNode &&
          triple.object is BlankNodeTerm &&
          triple.subject is IriTerm) {
        final subject = triple.subject as IriTerm;
        final object = triple.object as BlankNodeTerm;
        map.putIfAbsent(object, () => <IriTerm>{}).add(subject);
      } else {
        _log.warning('Unexpected triple in blank node mapping: $triple');
      }
      return map;
    });
  }

  BlankNodeTerm? byIdentifiers(List<IriTerm> identifiers) => identifiers
      .map((id) => _canonicalToBlankNodeMap[id])
      .firstWhere((bnode) => bnode != null, orElse: () => null);

  BlankNodeTerm? getBlankNode(RdfSubject rdfSubject) {
    return _canonicalToBlankNodeMap[rdfSubject];
  }
}

sealed class RdfSubjectKey {
  RdfSubject get subject;

  static RdfSubjectKey fromSubject(
      RdfSubject subject, OrganizedBlankNodeMappings mappings) {
    switch (subject) {
      case IriTerm iri:
        return IriSubjectKey(iri);
      case BlankNodeTerm bnode:
        final identifiers = mappings.getCanonicalIrisForBlankNode(bnode);
        if (identifiers == null || identifiers.isEmpty) {
          return UnIdentifiedBlankNodeKey(bnode);
        }
        return IdentifiedBlankNodeKey(bnode, identifiers.toList());
    }
  }
}

class IriSubjectKey extends RdfSubjectKey {
  final IriTerm iri;

  IriSubjectKey(this.iri);

  @override
  RdfSubject get subject => iri;

  @override
  int get hashCode => iri.hashCode;

  @override
  bool operator ==(Object other) => other is IriSubjectKey && other.iri == iri;
}

class IdentifiedBlankNodeKey extends RdfSubjectKey {
  final BlankNodeTerm blankNode;
  final List<IriTerm> identifiers;

  IdentifiedBlankNodeKey(this.blankNode, this.identifiers);

  @override
  RdfSubject get subject => blankNode;

  // Two identified blank nodes are considered equal if they share at least one identifier,
  // so we cannot implement hashCode properly since we cannot know here which
  // of the identifiers will match. So the only way to get a consistent behaviour
  // is to return a constant hashCode and do a full comparison in operator==.
  @override
  int get hashCode => 0;

  @override
  bool operator ==(Object other) {
    if (other is! IdentifiedBlankNodeKey) {
      return false;
    }
    // Two identified blank nodes are considered equal if they share at least one identifier

    if (identifiers.any((id) => other.identifiers.contains(id))) {
      return true;
    }

    return false;
  }
}

class UnIdentifiedBlankNodeKey extends RdfSubjectKey {
  final BlankNodeTerm blankNode;

  UnIdentifiedBlankNodeKey(this.blankNode);

  @override
  RdfSubject get subject => blankNode;

  @override
  int get hashCode => blankNode.hashCode;

  @override
  bool operator ==(Object other) {
    if (other is! UnIdentifiedBlankNodeKey) {
      return false;
    }

    return blankNode == other.blankNode;
  }
}

final class OrganizedGraph {
  final OrganizedStatements statements;
  final OrganizedBlankNodeMappings blankNodeMappings;
  final RdfGraph fullGraph;
  final CurrentCrdtClock clock;
  final Set<RdfSubject> _allSubjects;

  OrganizedGraph._({
    required this.statements,
    required this.blankNodeMappings,
    required this.fullGraph,
    required this.clock,
  }) : _allSubjects =
            // Relying on RdfGraph being immutable, so we do not need to copy the subjects set
            fullGraph.subjects;

  Iterable<RdfSubjectKey> get allSubjectKeys {
    return _allSubjects.map(
        (subject) => RdfSubjectKey.fromSubject(subject, blankNodeMappings));
  }

  /// While an RdfSubject might be specific to a given graph (due to blank nodes),
  /// a RdfSubjectKey can be used to identify the same subject across different graphs
  /// if it is an identifiable blank node or an IRI.
  ///
  /// Use this method to resolve a RdfSubjectKey back to the actual RdfSubject in this graph.
  ///
  /// Return null if the subject cannot be found in this graph.
  RdfSubject? getSubjectForKey(RdfSubjectKey key) => switch (key) {
        IriSubjectKey() => _allSubjects.contains(key.iri) ? key.iri : null,
        IdentifiedBlankNodeKey() =>
          blankNodeMappings.byIdentifiers(key.identifiers),
        UnIdentifiedBlankNodeKey() =>
          _allSubjects.contains(key.blankNode) ? key.blankNode : null,
      };

  factory OrganizedGraph.fromGraph(
      IriTerm documentIri, RdfGraph document, HlcService hlcService) {
    final clock = hlcService.getCurrentClock(document, documentIri);
    final blankNodeMappings =
        OrganizedBlankNodeMappings.fromGraph(documentIri, document);
    final statements =
        OrganizedStatements.fromGraph(documentIri, document, blankNodeMappings);
    return OrganizedGraph._(
        statements: statements,
        blankNodeMappings: blankNodeMappings,
        fullGraph: document,
        clock: clock);
  }
}
