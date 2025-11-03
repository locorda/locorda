/// Abstract authentication interface for Solid Pod access.
///
/// This interface defines the contract that authentication implementations
/// must provide to enable Pod synchronization. Concrete implementations
/// will integrate with specific auth libraries like solid-auth.
abstract interface class Auth {
  Future<bool> isAuthenticated();
  String? get userDisplayName;
  AuthValueListenable get isAuthenticatedNotifier;
  Future<void> logout();
}

abstract interface class AuthValueListenable {
  bool get isAuthenticated;

  /// Register a closure to be called when the object notifies its listeners.
  void addListener(void Function() listener);

  /// Remove a previously registered closure from the list of closures that the
  /// object notifies.
  void removeListener(void Function() listener);
}
