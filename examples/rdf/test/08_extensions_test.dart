import 'package:test/test.dart';
import 'package:locorda_rdf_core/core.dart';

void main() {
  test('08_extensions example runs without errors', () {
    // Test SPARQL-style Turtle parsing
    final sparqlStyleTurtle = TurtleCodec(
      decoderOptions: TurtleDecoderOptions(
        parsingFlags: {
          TurtleParsingFlag.allowMissingDotAfterPrefix,
          TurtleParsingFlag.allowPrefixWithoutAtSign,
        },
      ),
    );

    final customRdf = RdfCore.withCodecs(codecs: [
      sparqlStyleTurtle,
      NTriplesCodec(),
    ]);

    final sparqlData = '''
      PREFIX foaf: <http://xmlns.com/foaf/0.1/>
      <http://example.org/alice> foaf:name "Alice" .
    ''';

    final graph = customRdf.decode(sparqlData, contentType: 'text/turtle');
    expect(graph.triples.length, 1);
  });
}
