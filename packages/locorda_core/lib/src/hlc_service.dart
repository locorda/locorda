/// Main facade for the CRDT sync system.
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:rdf_core/rdf_core.dart';

/// Factory function for generating physical timestamps (wall-clock time)
typedef PhysicalTimestampFactory = DateTime Function();

// Default factory functions for time and clock generation
DateTime defaultPhysicalTimestampFactory() => DateTime.now();

typedef CrdtClock = List<Node>;
typedef CurrentCrdtClock = ({
  int logicalTime,
  int physicalTime,
  CrdtClock fullClock,
  String hash
});

class HlcService {
  final String _installationLocalId;
  final PhysicalTimestampFactory _physicalTimestampFactory;

  HlcService({
    required String installationLocalId,
    PhysicalTimestampFactory physicalTimestampFactory =
        defaultPhysicalTimestampFactory,
  })  : _installationLocalId = installationLocalId,
        _physicalTimestampFactory = physicalTimestampFactory;

  /// Generates a stable clock entry IRI based on installation localId
  /// Fragment format: #lcrd-clk-md5-{hash-of-installation-localId}
  IriTerm _generateClockEntryIri(IriTerm documentIri) {
    final hash = md5.convert(utf8.encode(_installationLocalId)).toString();
    return documentIri.withFragment('lcrd-clk-md5-$hash');
  }

  /// Builds a clock entry node as an IRI resource (not blank node)
  /// Note: installationIri property is NOT added here - it's added during sync
  Node _buildClockEntryNode(
      IriTerm documentIri, int physicalTime, int logicalTime) {
    final clockEntryIri = _generateClockEntryIri(documentIri);
    final triples = <Triple>[
      Triple(
        clockEntryIri,
        CrdtClockEntry.logicalTime,
        LiteralTerm.integer(logicalTime),
      ),
      Triple(
        clockEntryIri,
        CrdtClockEntry.physicalTime,
        LiteralTerm.integer(physicalTime),
      ),
    ];
    return (clockEntryIri, RdfGraph.fromTriples(triples));
  }

  CurrentCrdtClock newClock(IriTerm documentIri) {
    final physicalTime = _physicalTimestampFactory();
    final logicalTime = 1;

    var fullClock = [
      _buildClockEntryNode(
          documentIri, physicalTime.millisecondsSinceEpoch, logicalTime)
    ];
    return (
      logicalTime: logicalTime,
      physicalTime: physicalTime.millisecondsSinceEpoch,
      fullClock: fullClock,
      hash: _hashClock(fullClock)
    );
  }

  CurrentCrdtClock incrementClock(IriTerm documentIri, CrdtClock clock) {
    final physicalTime = _physicalTimestampFactory();
    final ourClockEntryIri = _generateClockEntryIri(documentIri);

    final (ours: ours, theirs: theirs) =
        clock.fold((ours: <Node>[], theirs: <Node>[]), (acc, entry) {
      final (node, triples) = entry;
      if (node == ourClockEntryIri) {
        acc.ours.add(entry);
      } else {
        acc.theirs.add(entry);
      }
      return acc;
    });
    final Node entry;
    final int logicalTime;
    if (ours.length > 0) {
      final ourClockEntry = ours.single;
      final oldLogicalTime = ourClockEntry.$2.findSingleObject<LiteralTerm>(
          ourClockEntry.$1, CrdtClockEntry.logicalTime)!;
      logicalTime = oldLogicalTime.integerValue + 1;
      entry = _buildClockEntryNode(
          documentIri, physicalTime.millisecondsSinceEpoch, logicalTime);
    } else {
      logicalTime = 1;
      entry = _buildClockEntryNode(
          documentIri, physicalTime.millisecondsSinceEpoch, logicalTime);
    }

    var fullClock = [entry, ...theirs];

    return (
      logicalTime: logicalTime,
      physicalTime: physicalTime.millisecondsSinceEpoch,
      fullClock: fullClock,
      hash: _hashClock(fullClock)
    );
  }

  /// Computes clock hash from logical and physical time only
  /// Per spec: includes only logicalTime and physicalTime triples, excludes installationIri
  String _hashClock(CrdtClock clock) {
    final triples = <Triple>[];

    // Extract only logicalTime and physicalTime triples from all clock entries
    for (final (_, graph) in clock) {
      triples.addAll(graph.findTriples(predicate: CrdtClockEntry.logicalTime));
      triples.addAll(graph.findTriples(predicate: CrdtClockEntry.physicalTime));
    }

    // Serialize to canonical N-Quads
    final dataset = RdfDataset.fromDefaultGraph(RdfGraph.fromTriples(triples));
    final nquadsEncoder = NQuadsEncoder(
      options: const NQuadsEncoderOptions(canonical: true),
    );
    final nquads =
        nquadsEncoder.encode(dataset, generateNewBlankNodeLabels: false);

    // Compute MD5 hash
    return md5.convert(utf8.encode(nquads)).toString();
  }
}
