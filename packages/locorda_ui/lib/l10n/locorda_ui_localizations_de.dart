// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'locorda_ui_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class LocordaUILocalizationsDe extends LocordaUILocalizations {
  LocordaUILocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String errorConnecting(String error) {
    return 'Fehler beim Verbinden: $error';
  }

  @override
  String get connected => 'Verbunden';

  @override
  String get notConnected => 'Nicht verbunden';

  @override
  String get syncError => 'Synchronisierungsfehler';

  @override
  String get syncing => 'Synchronisiere...';

  @override
  String get upToDate => 'Auf dem neuesten Stand';

  @override
  String get signOut => 'Abmelden';

  @override
  String get syncNow => 'Jetzt synchronisieren';

  @override
  String get retrySync => 'Synchronisierung erneut versuchen';
}
