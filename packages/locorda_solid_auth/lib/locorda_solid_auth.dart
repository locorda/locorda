/// Solid authentication implementation for locorda.
///
/// This library provides the bridge between locorda_core's
/// authentication interfaces and the solid-auth library, plus ready-to-use
/// UI components for Solid authentication.
library locorda_solid_auth;

export 'src/solid_auth_bridge.dart';
export 'src/ui/login_page.dart';
export 'src/ui/solid_status_widget.dart';
export 'src/providers/solid_provider_service.dart';
export 'l10n/solid_auth_localizations.dart';
