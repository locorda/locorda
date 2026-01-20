import 'package:locorda_rdf_mapper_annotations/annotations.dart';
import 'package:locorda_rdf_core/core.dart';

/// Custom literal type example with @RdfValue() for simple value extraction
@RdfLiteral()
class ISBN {
  /// The ISBN value that will be serialized as literal
  @RdfValue()
  final String value;

  ISBN(this.value) {
    if (!RegExp(r'^(?:\d{9}[\dX]|\d{13})$').hasMatch(value)) {
      throw ArgumentError('Invalid ISBN format');
    }
  }
}

/// Custom literal with formatted string representation using custom conversion methods
@RdfLiteral.custom(
  toLiteralTermMethod: 'formatCelsius',
  fromLiteralTermMethod: 'parse',
  datatype: IriTerm('http://example.org/temperature'),
)
class Temperature {
  final double celsius;

  Temperature(this.celsius);

  /// Custom formatting method for serialization
  LiteralContent formatCelsius() => LiteralContent('$celsius°C');

  /// Static parsing method for deserialization
  static Temperature parse(LiteralContent term) {
    return Temperature(double.parse(term.value.replaceAll('°C', '')));
  }
}
