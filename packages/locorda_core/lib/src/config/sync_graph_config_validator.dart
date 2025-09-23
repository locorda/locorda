/// Resource-focused configuration for CRDT sync setup.
///
/// This provides a resource-centric API where all configuration flows from
/// "what resources am I working with?" rather than separate configuration
/// of indices, mappings, and paths.
library;

import 'package:locorda_core/locorda_core.dart';
import 'package:rdf_core/rdf_core.dart';

/// Configuration for the entire sync system organized by resources.
class SyncGraphConfigValidator {
  final SyncConfigBaseValidator _baseValidator =
      SyncConfigBaseValidator((c) => (c as ResourceGraphConfig).typeIri.value);

  SyncGraphConfigValidator();

  /// Validate this configuration for consistency and correctness.
  ValidationResult validate(SyncGraphConfig config) {
    final result = _baseValidator.validate(config);
    _validateResourceUniqueness(config, result);

    return result;
  }

  void _validateResourceUniqueness(
      SyncGraphConfig config, ValidationResult result) {
    // Check for duplicate Dart types
    final typeIris = <IriTerm>{};

    for (final resource in config.resources) {
      // Check for duplicate Dart types
      if (typeIris.contains(resource.typeIri)) {
        result.addError(
            'Duplicate resource type: ${resource.typeIri}. Each  type can only be configured once.',
            context: {'type': resource.typeIri});
        continue; // Skip further processing for this resource
      }
      typeIris.add(resource.typeIri);
    }
  }
}
