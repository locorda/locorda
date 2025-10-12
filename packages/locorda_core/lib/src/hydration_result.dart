/// Result object for hydration streams containing batched updates.
library;

abstract interface class HydrationSubscription {
  /// Cancel the subscription and stop receiving updates.
  Future<void> cancel();

  /// Whether the subscription is currently active.
  bool get isActive;
}
