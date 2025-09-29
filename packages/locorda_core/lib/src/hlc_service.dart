/// Main facade for the CRDT sync system.
library;

import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:rdf_core/rdf_core.dart';

/// Factory function for generating physical timestamps (wall-clock time)
typedef PhysicalTimestampFactory = int Function();

/// Factory function for generating logical clock values
typedef LogicalClockFactory = int Function();

/// Factory function for getting the current installation ID
typedef InstallationIdFactory = IriTerm Function();

// Default factory functions for time and clock generation
int defaultPhysicalTimestampFactory() => DateTime.now().millisecondsSinceEpoch;

int _logicalClockCounter = 0;
int _defaultLogicalClockFactory() => ++_logicalClockCounter;

// TODO: Get actual installation ID from config or storage - for now using placeholder
IriTerm _defaultInstallationIdFactory() =>
    const IriTerm('https://example.org/installations/default-installation');

typedef CrdtClock = List<Node>;
typedef CurrentCrdtClock = ({
  IriTerm installationId,
  int logicalTime,
  int physicalTime,
  CrdtClock fullClock,
  String hash
});

class HlcService {
  final InstallationIdFactory _installationIdFactory;
  final PhysicalTimestampFactory _physicalTimestampFactory;
  final LogicalClockFactory _logicalClockFactory;

  HlcService(
      {InstallationIdFactory installationIdFactory =
          _defaultInstallationIdFactory,
      PhysicalTimestampFactory physicalTimestampFactory =
          defaultPhysicalTimestampFactory,
      LogicalClockFactory logicalClockFactory = _defaultLogicalClockFactory})
      : _installationIdFactory = installationIdFactory,
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
      LiteralTerm(logicalTime.toString()),
    ));

    triples.add(Triple(
      clockEntryNode,
      CrdtClockEntry.physicalTime,
      LiteralTerm(physicalTime.toString()),
    ));
    return (clockEntryNode, RdfGraph.fromTriples(triples));
  }

  CurrentCrdtClock newClock() {
    final installationId = _installationIdFactory();
    final physicalTime = _physicalTimestampFactory();
    final logicalTime = _logicalClockFactory();

    var fullClock = [
      _buildClockEntryNode(installationId, physicalTime, logicalTime)
    ];
    return (
      installationId: installationId,
      logicalTime: logicalTime,
      physicalTime: physicalTime,
      fullClock: fullClock,
      hash: _hashClock(fullClock)
    );
  }

  CurrentCrdtClock incrementClock(CrdtClock clock) {
    final installationId = _installationIdFactory();
    final physicalTime = _physicalTimestampFactory();
    final (ours: ours, theirs: theirs) =
        clock.fold((ours: <Node>[], theirs: <Node>[]), (acc, entry) {
      final (node, triples) = entry;
      final idTriple =
          triples.findTriples(predicate: CrdtClockEntry.installationId).single;
      final id = idTriple.object;
      if (id == installationId) {
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
    final ourNewEntry =
        _buildClockEntryNode(installationId, physicalTime, logicalTime);

    var fullClock = [ourNewEntry, ...theirs];

    return (
      installationId: installationId,
      logicalTime: logicalTime,
      physicalTime: physicalTime,
      fullClock: fullClock,
      hash: _hashClock(fullClock)
    );
  }

  String _hashClock(CrdtClock clock) {
    // TODO: Implement proper clock hash generation - for now using simple hash

    return "FIXME";
  }
}
