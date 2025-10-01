import 'package:locorda_core/locorda_core.dart';

class TestBackend implements Backend {
  @override
  // TODO: implement auth
  Auth get auth => throw UnimplementedError();

  @override
  // TODO: implement remoteStorage
  RemoteStorage get remoteStorage => throw UnimplementedError();

  @override
  // TODO: implement resourceLocator
  ResourceLocator get resourceLocator => throw UnimplementedError();
}
