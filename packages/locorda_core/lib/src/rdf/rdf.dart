import 'package:rdf_core/rdf_core.dart';

typedef Node = (RdfSubject node, RdfGraph triples);

class Rdf {
  static const String namespace = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';
  static const IriTerm type = IriTerm('$namespace#type');
  static const IriTerm subject = IriTerm('$namespace#subject');
  static const IriTerm predicate = IriTerm('$namespace#predicate');
  static const IriTerm object = IriTerm('$namespace#object');
  static const IriTerm first = IriTerm('$namespace#first');
  static const IriTerm nil = IriTerm('$namespace#nil');
  static const IriTerm rest = IriTerm('$namespace#rest');
}

extension RdfGraphExtensions on RdfGraph {
  IriTerm getIdentifier(IriTerm type) {
    final localIdTriple = findTriples(predicate: Rdf.type, object: type).single;
    return localIdTriple.subject as IriTerm;
  }

  T? findSingleObject<T extends RdfObject>(
      RdfSubject subject, IriTerm predicate) {
    final triple =
        findTriples(subject: subject, predicate: predicate).singleOrNull;
    final obj = triple?.object;
    if (obj is T) {
      return obj;
    }
    return null;
  }

  /**
   * Gets a list of RdfObjects from a rdf:List structure (e.g. rdf:first, rdf:rest, rdf:nil)
   */
  List<T> getListObjects<T extends RdfObject>(
      RdfSubject subject, IriTerm predicate) {
    final obj = findSingleObject(subject, predicate);
    if (!(obj is RdfSubject)) {
      return [];
    }
    return traverseListObjects<T>(obj);
  }

/*
* Gets a list of RdfObjects from a multi-valued property (i.e. multiple triples with the same predicate)
*/
  List<T> getMultiValueObjects<T extends RdfObject>(
      RdfSubject subject, IriTerm predicate) {
    final obj = findTriples(subject: subject, predicate: predicate);
    if (obj.isEmpty) {
      return [];
    }
    return obj.map((t) => t.object).whereType<T>().toList();
  }

  List<T> traverseListObjects<T extends RdfObject>(RdfSubject listRoot) {
    if (listRoot == Rdf.nil) return [];
    return subgraph(listRoot, filter: (t, depth) {
      if (t.predicate == Rdf.rest) {
        if (t.object == Rdf.nil) {
          return TraversalDecision.skip;
        }
        return TraversalDecision.skipButDescend;
      }
      if (t.predicate == Rdf.first) {
        // the actual file
        return TraversalDecision.includeButDontDescend;
      }
      return TraversalDecision.skip;
    }).triples.map((t) => t.object).whereType<T>().toList();
  }
}

extension IriTermExtensions on IriTerm {
  String get localName {
    final hashIndex = value.lastIndexOf('#');
    if (hashIndex != -1 && hashIndex < value.length - 1) {
      return value.substring(hashIndex + 1);
    }
    final slashIndex = value.lastIndexOf('/');
    if (slashIndex != -1 && slashIndex < value.length - 1) {
      return value.substring(slashIndex + 1);
    }
    return value; // Fallback to full IRI if no separator found
  }

  IriTerm getDocumentIri([IriTermFactory iriFactory = IriTerm.validated]) {
    final hashIndex = value.lastIndexOf('#');
    if (hashIndex != -1) {
      return iriFactory(value.substring(0, hashIndex));
    }
    final slashIndex = value.lastIndexOf('/');
    if (slashIndex != -1) {
      return iriFactory(value.substring(0, slashIndex));
    }
    return this; // Fallback to self if no separator found
  }
}

extension LiteralTermExtensions on LiteralTerm {
  bool get isBoolean {
    return datatype == IriTerm('http://www.w3.org/2001/XMLSchema#boolean');
  }

  bool get booleanValue {
    if (!isBoolean) {
      throw StateError('Literal is not a boolean');
    }
    return value == 'true' || value == '1';
  }

  bool get isInteger {
    return datatype == IriTerm('http://www.w3.org/2001/XMLSchema#integer') ||
        datatype == IriTerm('http://www.w3.org/2001/XMLSchema#int');
  }

  int get integerValue {
    if (!isInteger) {
      throw StateError('Literal is not an integer');
    }
    return int.parse(value);
  }

  bool get isString {
    return datatype == IriTerm('http://www.w3.org/2001/XMLSchema#string') ||
        datatype ==
            IriTerm('http://www.w3.org/1999/02/22-rdf-syntax-ns#langString');
  }

  String get stringValue {
    if (!isString) {
      throw StateError('Literal is not a string');
    }
    return value;
  }

  double get doubleValue {
    if (!isDouble) {
      throw StateError('Literal is not a double or float');
    }
    return double.parse(value);
  }

  bool get isDouble {
    return datatype == IriTerm('http://www.w3.org/2001/XMLSchema#double') ||
        datatype == IriTerm('http://www.w3.org/2001/XMLSchema#float');
  }

  bool get isDateTime {
    return datatype == IriTerm('http://www.w3.org/2001/XMLSchema#dateTime');
  }

  DateTime get dateTimeValue {
    if (!isDateTime) {
      throw StateError('Literal is not a dateTime');
    }
    return DateTime.parse(value);
  }

  bool get isDate {
    return datatype == IriTerm('http://www.w3.org/2001/XMLSchema#date');
  }

  DateTime get dateValue {
    if (!isDate) {
      throw StateError('Literal is not a date');
    }
    return DateTime.parse(value);
  }
}

extension TripleListExtensions on List<Triple> {
  void addRdfList(
      RdfSubject subject, RdfPredicate predicate, List<RdfObject> items) {
    if (items.isEmpty) {
      add(Triple(subject, predicate, Rdf.nil));
      return;
    }

    // Create blank nodes for each list item
    final blankNodes = List.generate(items.length, (index) => BlankNodeTerm());

    for (var i = 0; i < items.length; i++) {
      final currentNode = blankNodes[i];
      final nextNode = (i < items.length - 1) ? blankNodes[i + 1] : Rdf.nil;

      // Add rdf:first triple
      add(Triple(currentNode, Rdf.first, items[i]));

      // Add rdf:rest triple
      add(Triple(currentNode, Rdf.rest, nextNode));
    }

    // Link the head of the list to the subject via the predicate
    add(Triple(subject, predicate, blankNodes.first));
  }

  void addNodes(RdfSubject subject, RdfPredicate predicate, List<Node> nodes) {
    for (final node in nodes) {
      {
        final (objectTerm, graph) = node;
        add(Triple(
          subject,
          predicate,
          objectTerm,
        ));
        addAll(graph.triples);
      }
    }
  }

  RdfGraph toRdfGraph() {
    return RdfGraph.fromTriples(this);
  }
}
