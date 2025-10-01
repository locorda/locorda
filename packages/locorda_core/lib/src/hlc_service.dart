/// Main facade for the CRDT sync system.
library;

import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:rdf_core/rdf_core.dart';

/// Factory function for generating physical timestamps (wall-clock time)
typedef PhysicalTimestampFactory = DateTime Function();

/// Factory function for generating logical clock values
typedef LogicalClockFactory = int Function();

// Default factory functions for time and clock generation
DateTime defaultPhysicalTimestampFactory() => DateTime.now();

int _logicalClockCounter = 0;
int _defaultLogicalClockFactory() => ++_logicalClockCounter;

typedef CrdtClock = List<Node>;
typedef CurrentCrdtClock = ({
  IriTerm installationId,
  int logicalTime,
  int physicalTime,
  CrdtClock fullClock,
  String hash
});

class HlcService {
  final IriTerm _installationId;
  final PhysicalTimestampFactory _physicalTimestampFactory;
  final LogicalClockFactory _logicalClockFactory;

  HlcService({
    required IriTerm installationId,
    PhysicalTimestampFactory physicalTimestampFactory =
        defaultPhysicalTimestampFactory,
    LogicalClockFactory logicalClockFactory = _defaultLogicalClockFactory,
  })  : _installationId = installationId,
        _physicalTimestampFactory = physicalTimestampFactory,
        _logicalClockFactory = logicalClockFactory;

  Node _buildClockEntryNode(
      IriTerm installationId, int physicalTime, int logicalTime) {
    // Create a blank node for the clock entry
    final clockEntryNode = BlankNodeTerm();
    final triples = <Triple>[];

    triples.add(Triple(
      clockEntryNode,
      CrdtClockEntry.installationId,
      installationId,
    ));

    triples.add(Triple(
      clockEntryNode,
      CrdtClockEntry.logicalTime,
      LiteralTerm.integer(logicalTime),
    ));

    triples.add(Triple(
      clockEntryNode,
      CrdtClockEntry.physicalTime,
      LiteralTerm.integer(physicalTime),
    ));
    return (clockEntryNode, RdfGraph.fromTriples(triples));
  }

  CurrentCrdtClock newClock() {
    final physicalTime = _physicalTimestampFactory();
    final logicalTime = _logicalClockFactory();

    var fullClock = [
      _buildClockEntryNode(
          _installationId, physicalTime.millisecondsSinceEpoch, logicalTime)
    ];
    return (
      installationId: _installationId,
      logicalTime: logicalTime,
      physicalTime: physicalTime.millisecondsSinceEpoch,
      fullClock: fullClock,
      hash: _hashClock(fullClock)
    );
  }

  CurrentCrdtClock incrementClock(CrdtClock clock) {
    final physicalTime = _physicalTimestampFactory();
    final (ours: ours, theirs: theirs) =
        clock.fold((ours: <Node>[], theirs: <Node>[]), (acc, entry) {
      final (node, triples) = entry;
      final idTriple =
          triples.findTriples(predicate: CrdtClockEntry.installationId).single;
      final id = idTriple.object;
      if (id == _installationId) {
        acc.ours.add(entry);
      } else {
        acc.theirs.add(entry);
      }
      return acc;
    });

    final ourClockEntry = ours.single;
    final oldLogicalTimeTriple = ourClockEntry.$2
        .findTriples(predicate: CrdtClockEntry.logicalTime)
        .single;
    final oldLogicalTimeTerm = oldLogicalTimeTriple.object as LiteralTerm;
    final oldLogicalTime = int.parse(oldLogicalTimeTerm.value);
    final logicalTime = oldLogicalTime + 1;
    final ourNewEntry = _buildClockEntryNode(
        _installationId, physicalTime.millisecondsSinceEpoch, logicalTime);

    var fullClock = [ourNewEntry, ...theirs];

    return (
      installationId: _installationId,
      logicalTime: logicalTime,
      physicalTime: physicalTime.millisecondsSinceEpoch,
      fullClock: fullClock,
      hash: _hashClock(fullClock)
    );
  }

  String _hashClock(CrdtClock clock) {
    // TODO: Implement proper clock hash generation - for now using simple hash

    return "FIXME";
  }
}
