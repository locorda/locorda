/// Default implementations for [SolidStatusWidget] customization.
///
/// These functions provide the standard behavior for [SolidStatusWidget]
/// and can be reused or mixed with custom implementations.
library;

import 'package:flutter/material.dart';
import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_solid_auth/locorda_solid_auth.dart';
import 'package:solid_auth/solid_auth.dart';

/// Default implementations for [SolidStatusWidget] customization.
///
/// This class provides the standard implementations used by [SolidStatusWidget]
/// when no custom builders are provided. You can reference these when building
/// custom implementations.
///
/// ## Example: Custom icon
///
/// ```dart
/// SolidStatusWidget(
///   solidAuth: solidAuth,
///   syncManager: syncManager,
///   iconBuilder: (context, state) {
///     if (state.isSyncing) {
///       return Icon(Icons.sync, color: Colors.blue);
///     }
///     return SolidStatusDefaults.materialIcon(context, state);
///   },
/// )
/// ```
class SolidStatusDefaults {
  SolidStatusDefaults._(); // Private constructor - utility class

  /// Default icon builder using Material Design icons.
  ///
  /// Shows:
  /// - `cloud_off` (grey) when not authenticated
  /// - `cloud_off` (red) when error
  /// - `CircularProgressIndicator` when syncing
  /// - `cloud_done` (green) when up to date
  static Widget materialIcon(BuildContext context, SolidStatusState state) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!state.isAuthenticated) {
      return Icon(Icons.cloud_off, color: colorScheme.onSurfaceVariant);
    } else if (state.hasError) {
      return Icon(Icons.cloud_off, color: colorScheme.error);
    } else if (state.isSyncing) {
      // Show explicit progress indicator for user-initiated syncs
      final isUserInitiated = state.lastTrigger == SyncTrigger.manual ||
          state.lastTrigger == SyncTrigger.pullToRefresh;

      if (isUserInitiated) {
        // Explicit progress for manual syncs - user expects feedback
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
          ),
        );
      } else {
        // Subtle feedback for automatic syncs - don't make user think app is slow
        return Icon(Icons.cloud_sync, color: colorScheme.primary);
      }
    } else {
      return Icon(Icons.cloud_done, color: Colors.green);
    }
  }

  /// Default login flow showing [SolidLoginScreen] as modal dialog.
  ///
  /// This is a factory function that returns a login callback configured
  /// with the provided parameters.
  static Future<bool> Function(BuildContext) modalLogin({
    required SolidAuth solidAuth,
    SolidProviderService providerService = const DefaultSolidProviderService(),
    List<String> extraOidcScopes = const [],
  }) {
    return (BuildContext context) async {
      final user = await Navigator.of(context).push<UserAndWebId>(
        MaterialPageRoute(
          builder: (context) => SolidLoginScreen(
            solidAuth: solidAuth,
            providerService: providerService,
            extraOidcScopes: extraOidcScopes,
            onLoginSuccess: (userInfo) {
              Navigator.of(context).pop(userInfo);
            },
            onLoginError: (error) {
              // Error is already shown in the login screen
            },
          ),
        ),
      );
      return user != null;
    };
  }

  /// Full-screen login flow showing [SolidLoginScreen] as fullscreen dialog.
  ///
  /// Similar to [modalLogin] but uses fullscreenDialog presentation.
  /// Useful for onboarding flows where login is a primary action.
  static Future<bool> Function(BuildContext) fullscreenLogin({
    required SolidAuth solidAuth,
    SolidProviderService providerService = const DefaultSolidProviderService(),
    List<String> extraOidcScopes = const [],
  }) {
    return (BuildContext context) async {
      final user = await Navigator.of(context).push<UserAndWebId>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => SolidLoginScreen(
            solidAuth: solidAuth,
            providerService: providerService,
            extraOidcScopes: extraOidcScopes,
            onLoginSuccess: (userInfo) {
              Navigator.of(context).pop(userInfo);
            },
            onLoginError: (error) {
              // Error is already shown in the login screen
            },
          ),
        ),
      );
      return user != null;
    };
  }

  /// Default status menu showing modal bottom sheet with standard items.
  ///
  /// Shows connection status, sync actions, and sign out option.
  static StatusMenuCallback bottomSheetStatusMenu({
    required SolidAuth solidAuth,
  }) {
    return (
      BuildContext context, {
      required SolidStatusState state,
      required VoidCallback onTriggerSync,
      required VoidCallback onTriggerDisconnect,
    }) {
      final l10n = SolidAuthLocalizations.of(context)!;

      // Build menu items
      final menuItems = <Widget>[
        // Status header
        ListTile(
          leading: Icon(
            state.isAuthenticated ? Icons.cloud_done : Icons.cloud_off,
            color: state.isAuthenticated ? Colors.green : Colors.grey,
          ),
          title:
              Text(state.isAuthenticated ? l10n.connected : l10n.notConnected),
          subtitle: solidAuth.currentWebId != null
              ? Text(solidAuth.currentWebId!)
              : null,
        ),
        const Divider(),

        // Error display if present
        if (state.hasError) ...[
          ListTile(
            leading: const Icon(Icons.error_outline, color: Colors.red),
            title: Text(l10n.syncError),
            subtitle: Text(
              state.errorMessage ?? l10n.syncError,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const Divider(),
        ],

        // Sync action (Retry or Sync Now depending on state)
        if (state.hasError)
          ListTile(
            leading: const Icon(Icons.refresh),
            title: Text(l10n.retrySync),
            enabled: !state.isSyncing,
            onTap: state.isSyncing
                ? null
                : () {
                    Navigator.pop(context);
                    onTriggerSync();
                  },
          )
        else
          ListTile(
            leading: const Icon(Icons.sync),
            title: Text(l10n.syncNow),
            enabled: !state.isSyncing,
            onTap: state.isSyncing
                ? null
                : () {
                    Navigator.pop(context);
                    onTriggerSync();
                  },
          ),

        const Divider(),

        // Sign out
        ListTile(
          leading: const Icon(Icons.logout),
          title: Text(l10n.signOut),
          onTap: () {
            Navigator.pop(context);
            onTriggerDisconnect();
          },
        ),
      ];

      showModalBottomSheet(
        context: context,
        builder: (context) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: menuItems,
          ),
        ),
      );
    };
  }
}
