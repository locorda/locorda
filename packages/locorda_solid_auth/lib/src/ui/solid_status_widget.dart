import 'package:flutter/material.dart';
import 'package:locorda_core/locorda_core.dart';
import 'package:logging/logging.dart';
import 'package:solid_auth/solid_auth.dart';

import '../../l10n/solid_auth_localizations.dart';
import 'solid_status_defaults.dart';

final _log = Logger('SolidStatusWidget');

/// Callback signature for showing the status menu.
///
/// Receives the current [state] and callbacks to trigger sync or disconnect actions.
typedef StatusMenuCallback = void Function(
  BuildContext context, {
  required SolidStatusState state,
  required VoidCallback onTriggerSync,
  required VoidCallback onTriggerDisconnect,
});

/// Immutable state representing current Solid authentication and sync status.
///
/// Used by [SolidStatusWidget] builders to render appropriate UI.
class SolidStatusState {
  final bool isAuthenticated;
  final bool isSyncing;
  final bool hasError;
  final String? errorMessage;
  final String? webId;
  final SyncTrigger? lastTrigger;

  const SolidStatusState({
    required this.isAuthenticated,
    this.isSyncing = false,
    this.hasError = false,
    this.errorMessage,
    this.webId,
    this.lastTrigger,
  });
}

/// A combined authentication and sync status widget for the app bar.
///
/// This widget shows the current Solid authentication status and reactive
/// sync state from [SyncManager] in a compact format suitable for app bars.
/// It handles the complete user journey from "not connected" → "connecting"
/// → "syncing" → "up to date".
///
/// ## Requirements
///
/// - [solidAuth]: SolidAuth instance for authentication state
/// - [syncManager]: SyncManager for reactive sync status (required)
///
/// ## Customization
///
/// The widget can be customized via:
///
/// - [iconBuilder]: Custom status icon rendering based on state
/// - [onShowLogin]: Custom login flow presentation
///
/// Both have sensible defaults - only override what you need.
class SolidStatusWidget extends StatefulWidget {
  /// The SolidAuth instance to monitor for authentication state.
  final SolidAuth solidAuth;

  /// Sync manager for reactive sync status updates and sync operations.
  final SyncManager syncManager;

  /// Custom icon builder. Receives current [SolidStatusState] and returns widget.
  ///
  /// Default: Material Design icons (cloud_off, cloud_done, spinner, etc.)
  final Widget Function(BuildContext context, SolidStatusState state)
      iconBuilder;

  /// Custom login flow. Called when user taps icon while not authenticated.
  ///
  /// Default: Shows [SolidLoginScreen] as modal dialog
  final Future<bool> Function(BuildContext context) onShowLogin;

  /// Custom status menu. Called when authenticated user taps the icon.
  ///
  /// Receives current state and callbacks for sync/disconnect actions.
  /// Default: Shows modal bottom sheet with standard menu items
  final StatusMenuCallback onShowStatusMenu;

  SolidStatusWidget({
    super.key,
    required this.solidAuth,
    required this.syncManager,
    Future<bool> Function(BuildContext)? onShowLogin,
    Widget Function(BuildContext, SolidStatusState)? iconBuilder,
    StatusMenuCallback? onShowStatusMenu,
  })  : iconBuilder = iconBuilder ?? SolidStatusDefaults.materialIcon,
        onShowLogin =
            onShowLogin ?? SolidStatusDefaults.modalLogin(solidAuth: solidAuth),
        onShowStatusMenu = onShowStatusMenu ??
            SolidStatusDefaults.bottomSheetStatusMenu(solidAuth: solidAuth);

  @override
  State<SolidStatusWidget> createState() => _SolidStatusWidgetState();
}

class _SolidStatusWidgetState extends State<SolidStatusWidget> {
  bool _isAuthenticated = false;
  SyncState? _syncState;

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();

    // Listen to authentication changes
    widget.solidAuth.isAuthenticatedNotifier.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    widget.solidAuth.isAuthenticatedNotifier.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    try {
      _log.info('Authentication state changed');
      _checkAuthStatus();
    } catch (e, stackTrace) {
      _log.severe(
          'Error in authentication state change handler', e, stackTrace);
    }
  }

  Future<void> _checkAuthStatus() async {
    try {
      final isAuth = await widget.solidAuth.isAuthenticated;
      _log.fine('Authentication status checked: $isAuth');
      if (mounted) {
        setState(() {
          _isAuthenticated = isAuth;
        });
      }
    } catch (e, stackTrace) {
      _log.severe('Error checking authentication status', e, stackTrace);
      // Avoid setState if there's an error to prevent potential recursion
    }
  }

  Future<void> _showLoginScreen() async {
    // Use custom login flow
    final success = await widget.onShowLogin(context);

    if (success) {
      // Refresh auth status after successful login
      _checkAuthStatus();
    }
  }

  Future<void> _disconnect() async {
    try {
      await widget.solidAuth.logout();
      _checkAuthStatus();
    } catch (e, stackTrace) {
      _log.severe('Error during logout', e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              SolidAuthLocalizations.of(context)!
                  .errorConnectingSolid(e.toString()),
            ),
          ),
        );
      }
    }
  }

  /// Show status menu with authentication and sync options.
  void _showStatusMenu() {
    if (!_isAuthenticated) return;
    // Build state for icon builder
    final state = _buildSolidStatusState();
    widget.onShowStatusMenu(
      context,
      state: state,
      onTriggerSync: _triggerSync,
      onTriggerDisconnect: _disconnect,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncState>(
      stream: widget.syncManager.statusStream,
      initialData: widget.syncManager.currentState,
      builder: (context, snapshot) {
        _syncState = snapshot.data ?? const SyncState.idle();
        return _buildIcon(context);
      },
    );
  }

  Widget _buildIcon(BuildContext context) {
    final l10n = SolidAuthLocalizations.of(context)!;

    // Build state for icon builder
    final state = _buildSolidStatusState();

    // Use custom icon builder
    final icon = widget.iconBuilder(context, state);

    // Determine tooltip and action
    String tooltip;
    VoidCallback? onPressed;

    if (!_isAuthenticated) {
      // Not connected - open login screen
      tooltip = l10n.notConnected;
      onPressed = _showLoginScreen;
    } else if (state.hasError) {
      // Connected but has error - open menu (includes retry option)
      tooltip = state.errorMessage ?? l10n.syncError;
      onPressed = _showStatusMenu;
    } else if (state.isSyncing) {
      // Connected and syncing - open menu (options disabled during sync)
      tooltip = l10n.syncing;
      onPressed = _showStatusMenu;
    } else {
      // Connected and up to date - open menu
      tooltip = l10n.upToDate;
      onPressed = _showStatusMenu;
    }

    return IconButton(
      onPressed: onPressed,
      icon: icon,
      tooltip: tooltip,
    );
  }

  SolidStatusState _buildSolidStatusState() {
    // Get sync status from syncManager stream
    final bool isSyncing = _syncState?.status == SyncStatus.syncing;
    final bool hasError = _syncState?.status == SyncStatus.error;
    final String? errorMessage = _syncState?.errorMessage;
    final SyncTrigger? lastTrigger = _syncState?.lastTrigger;

    // Build state for icon builder
    return SolidStatusState(
      isAuthenticated: _isAuthenticated,
      isSyncing: isSyncing,
      hasError: hasError,
      errorMessage: errorMessage,
      webId: widget.solidAuth.currentWebId,
      lastTrigger: lastTrigger,
    );
  }

  Future<void> _triggerSync() async {
    await widget.syncManager.sync(trigger: SyncTrigger.manual);
  }
}
