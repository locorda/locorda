/// Implementation of SolidAuthProvider using solid-auth library.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:locorda_solid/locorda_solid.dart';
import 'package:solid_auth/solid_auth.dart';

class AuthValueListenableImpl implements AuthValueListenable {
  final ValueListenable<bool> _notifier;

  AuthValueListenableImpl(this._notifier);

  @override
  bool get isAuthenticated => _notifier.value;

  @override
  void addListener(void Function() listener) {
    _notifier.addListener(listener);
  }

  @override
  void removeListener(void Function() listener) {
    _notifier.removeListener(listener);
  }
}

/// Concrete implementation of SolidAuthProvider using solid-auth library.
///
/// This class bridges the abstract authentication interface from the core
/// library with the solid-auth implementation.
class SolidAuthBridge implements SolidAuthProvider {
  final SolidAuth _solidAuth;
  final AuthValueListenableImpl _isAuthenticatedNotifier;

  SolidAuthBridge(this._solidAuth)
      : _isAuthenticatedNotifier =
            AuthValueListenableImpl(_solidAuth.isAuthenticatedNotifier);

  @override
  Future<bool> isAuthenticated() async => _solidAuth.isAuthenticated;

  @override
  AuthValueListenable get isAuthenticatedNotifier => _isAuthenticatedNotifier;

  @override
  String? get currentWebId => _solidAuth.currentWebId;

  @override
  Future<({String accessToken, String dPoP})> getDpopToken(
      String url, String method) async {
    final dpop = await _solidAuth.genDpopToken(url, method);
    return (accessToken: dpop.accessToken, dPoP: dpop.dpopToken);
  }

  /// Clean up resources.
  void dispose() {
    // Solid Auth instance was provided externally; do not dispose it here.
  }
}
