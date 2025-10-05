/// Service for managing installation identity and lifecycle.
library;

import 'package:rdf_core/rdf_core.dart';
import 'package:uuid/uuid.dart';
import 'package:locorda_core/src/storage/storage_interface.dart';
import 'package:locorda_core/src/mapping/resource_locator.dart';
import 'package:locorda_core/src/generated/crdt/classes/clientinstallation.dart';

/// Factory function for generating installation IDs.
///
/// Returns a simple string identifier (not a full IRI).
/// Default implementation generates a UUID v4.
typedef InstallationIdFactory = String Function();

/// Settings keys for installation management
class InstallationSettings {
  static const installationIri = 'installation_iri';
  static const installationLocalId = 'installation_local_id';
  static const installationDocumentSaved = 'installation_document_saved';
}

/// Service for managing installation identity and document lifecycle.
///
/// Responsibilities:
/// - Generate and persist unique installation IRI on first run
/// - Track whether installation document has been saved
/// - Provide installation IRI for HLC operations
class InstallationService {
  final Storage _storage;
  final IriTerm installationIri;
  final String installationLocalId;
  final bool installationDocumentSaved;

  InstallationService._({
    required Storage storage,
    required this.installationIri,
    required this.installationLocalId,
    required this.installationDocumentSaved,
  }) : _storage = storage;

  /// Initialize installation service by loading or creating installation identity.
  ///
  /// On first run:
  /// - Generates installation ID via factory (default: UUID v4)
  /// - Creates local IRI using LocalResourceLocator
  /// - Stores installation IRI in settings
  ///
  /// On subsequent runs:
  /// - Loads existing installation IRI from settings
  /// - Loads installation document saved flag
  static Future<InstallationService> initialize({
    required Storage storage,
    required LocalResourceLocator resourceLocator,
    InstallationIdFactory? installationIdFactory,
    IriTermFactory iriTermFactory = IriTerm.validated,
  }) async {
    installationIdFactory ??= () => const Uuid().v4();
    // Load settings in single request
    final settings = await storage.getSettings([
      InstallationSettings.installationIri,
      InstallationSettings.installationLocalId,
      InstallationSettings.installationDocumentSaved,
    ]);

    final IriTerm installationIri;
    final String installationLocalId;

    if (settings.containsKey(InstallationSettings.installationIri)) {
      // Load existing installation IRI and localId
      installationIri =
          iriTermFactory(settings[InstallationSettings.installationIri]!);
      installationLocalId = settings[InstallationSettings.installationLocalId]!;
    } else {
      // Generate new installation ID and IRI with 'installation' fragment
      installationLocalId = installationIdFactory();
      installationIri = resourceLocator.toIri(ResourceIdentifier(
        CrdtClientInstallation.classIri,
        installationLocalId,
        'installation',
      ));

      // Persist both installation IRI and localId
      await storage.setSetting(
        InstallationSettings.installationLocalId,
        installationLocalId,
      );
      await storage.setSetting(
        InstallationSettings.installationIri,
        installationIri.value,
      );
    }

    final installationDocumentSaved =
        settings[InstallationSettings.installationDocumentSaved] == 'true';

    return InstallationService._(
      storage: storage,
      installationIri: installationIri,
      installationLocalId: installationLocalId,
      installationDocumentSaved: installationDocumentSaved,
    );
  }

  /// Mark installation document as saved.
  ///
  /// Should be called after successfully saving the installation document
  /// through the normal saveDocument flow.
  Future<void> markInstallationDocumentSaved() async {
    await _storage.setSetting(
      InstallationSettings.installationDocumentSaved,
      'true',
    );
  }
}
