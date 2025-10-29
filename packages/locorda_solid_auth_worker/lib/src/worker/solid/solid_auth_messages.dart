/// Solid-specific authentication messages for worker communication.
///
/// Defines message types for transmitting authentication state and credentials
/// from main thread to worker isolate via [WorkerChannel].
library;

import 'package:solid_auth/solid_auth.dart';

/// Message to update authentication credentials in worker.
///
/// Sent from main thread's [SolidAuthConnector] to worker's
/// [WorkerSolidAuthProvider] when authentication state changes.
///
/// - When user logs in: Contains [credentials] and [webId]
/// - When user logs out: Contains `null` credentials to clear worker state
class UpdateAuthMessage {
  /// DPoP credentials for authenticated requests.
  ///
  /// `null` means user is logged out and worker should clear auth state.
  final DpopCredentials? credentials;

  /// Authenticated user's WebID.
  ///
  /// Stored separately from DPoP credentials for backend initialization.
  final String? webId;

  /// Creates update message with optional [credentials] and [webId].
  UpdateAuthMessage({required this.credentials, this.webId});

  /// Serializes to JSON for transmission over channel.
  Map<String, dynamic> toJson() => {
        'type': 'UpdateAuthMessage',
        if (credentials != null) 'credentials': credentials!.toJson(),
        if (webId != null) 'webId': webId,
      };

  /// Deserializes from JSON received on channel.
  factory UpdateAuthMessage.fromJson(Map<String, dynamic> json) {
    final credentialsJson = json['credentials'] as Map<String, dynamic>?;
    return UpdateAuthMessage(
      credentials: credentialsJson != null
          ? DpopCredentials.fromJson(credentialsJson)
          : null,
      webId: json['webId'] as String?,
    );
  }
}
