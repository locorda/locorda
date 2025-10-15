import 'package:locorda_core/locorda_core.dart';

import 'auth/solid_auth_provider.dart';

class SolidBackend implements Backend {
  String get name => 'solid';

  // ignore: unused_field
  final SolidAuthProvider _authProvider;

  SolidBackend({
    required SolidAuthProvider auth,
  }) : _authProvider = auth;

  @override
  List<RemoteStorage> get remotes =>
      // FIXME: Implement actual Pod RemoteStorage instances
      [];
}
