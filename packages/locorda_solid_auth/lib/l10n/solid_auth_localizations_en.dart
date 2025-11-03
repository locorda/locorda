// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'solid_auth_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class SolidAuthLocalizationsEn extends SolidAuthLocalizations {
  SolidAuthLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String errorConnectingSolid(String error) {
    return 'Error connecting to Solid: $error';
  }

  @override
  String get syncAcrossDevices => 'Sync Across Devices';

  @override
  String get chooseProvider => 'Choose a provider:';

  @override
  String get orEnterManually => 'Or enter your WebID manually:';

  @override
  String get webIdHint => 'https://username.provider.com/profile/card#me';

  @override
  String get connect => 'Connect';

  @override
  String get pleaseEnterWebId => 'Please enter a WebID or select a provider';

  @override
  String get connectToSolid => 'Connect to Solid';

  @override
  String get noPod => 'Don\'t have a Pod yet?';

  @override
  String get getPod => 'Get a Pod';
}
