import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'solid_auth_localizations_de.dart';
import 'solid_auth_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of SolidAuthLocalizations
/// returned by `SolidAuthLocalizations.of(context)`.
///
/// Applications need to include `SolidAuthLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/solid_auth_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: SolidAuthLocalizations.localizationsDelegates,
///   supportedLocales: SolidAuthLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the SolidAuthLocalizations.supportedLocales
/// property.
abstract class SolidAuthLocalizations {
  SolidAuthLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static SolidAuthLocalizations? of(BuildContext context) {
    return Localizations.of<SolidAuthLocalizations>(
        context, SolidAuthLocalizations);
  }

  static const LocalizationsDelegate<SolidAuthLocalizations> delegate =
      _SolidAuthLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en')
  ];

  /// Title for the Solid login screen
  ///
  /// In en, this message translates to:
  /// **'Connect to Solid'**
  String get connectToSolid;

  /// Subtitle explaining the purpose of connecting to Solid
  ///
  /// In en, this message translates to:
  /// **'Sync Across Devices'**
  String get syncAcrossDevices;

  /// Label for the provider selection section
  ///
  /// In en, this message translates to:
  /// **'Choose a provider:'**
  String get chooseProvider;

  /// Label for manual WebID input section
  ///
  /// In en, this message translates to:
  /// **'Or enter your WebID manually:'**
  String get orEnterManually;

  /// Placeholder text for WebID input field
  ///
  /// In en, this message translates to:
  /// **'https://username.provider.com/profile/card#me'**
  String get webIdHint;

  /// Button text to initiate connection
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// Text asking if user doesn't have a Pod
  ///
  /// In en, this message translates to:
  /// **'Don\'t have a Pod yet?'**
  String get noPod;

  /// Button text to get a new Pod
  ///
  /// In en, this message translates to:
  /// **'Get a Pod'**
  String get getPod;

  /// Error message when connection fails
  ///
  /// In en, this message translates to:
  /// **'Error connecting to Solid: {error}'**
  String errorConnectingSolid(String error);

  /// Status message when connecting
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get connecting;

  /// Status message when connected
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// Status message when syncing
  ///
  /// In en, this message translates to:
  /// **'Syncing...'**
  String get syncing;

  /// Status message when sync is complete
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get upToDate;

  /// Status message when not connected
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get notConnected;

  /// Button text to sign out
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get signOut;

  /// Validation message when WebID field is empty
  ///
  /// In en, this message translates to:
  /// **'Please enter a WebID or select a provider'**
  String get pleaseEnterWebId;

  /// Button text to trigger manual sync
  ///
  /// In en, this message translates to:
  /// **'Sync Now'**
  String get syncNow;

  /// Generic sync error message
  ///
  /// In en, this message translates to:
  /// **'Sync error'**
  String get syncError;
}

class _SolidAuthLocalizationsDelegate
    extends LocalizationsDelegate<SolidAuthLocalizations> {
  const _SolidAuthLocalizationsDelegate();

  @override
  Future<SolidAuthLocalizations> load(Locale locale) {
    return SynchronousFuture<SolidAuthLocalizations>(
        lookupSolidAuthLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_SolidAuthLocalizationsDelegate old) => false;
}

SolidAuthLocalizations lookupSolidAuthLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return SolidAuthLocalizationsDe();
    case 'en':
      return SolidAuthLocalizationsEn();
  }

  throw FlutterError(
      'SolidAuthLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
