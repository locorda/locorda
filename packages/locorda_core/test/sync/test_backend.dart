import 'package:locorda_core/locorda_core.dart';

class TestBackend implements Backend {
  @override
  Auth get auth => throw UnimplementedError();

  @override
  RemoteStorage get remoteStorage => throw UnimplementedError();

  @override
  ResourceLocator get resourceLocator => throw UnimplementedError();
}
