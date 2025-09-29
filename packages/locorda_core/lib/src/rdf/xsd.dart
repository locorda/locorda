import 'package:rdf_core/rdf_core.dart';

class Xsd {
  static const String namespace = 'http://www.w3.org/2001/XMLSchema#';
  static const IriTerm string = IriTerm('${namespace}string');
  static const IriTerm int = IriTerm('${namespace}int');
  static const IriTerm integer = IriTerm('${namespace}integer');
  static const IriTerm double = IriTerm('${namespace}double');
  static const IriTerm float = IriTerm('${namespace}float');
  static const IriTerm boolean = IriTerm('${namespace}boolean');
  static const IriTerm dateTime = IriTerm('${namespace}dateTime');
  static const IriTerm date = IriTerm('${namespace}date');
}
