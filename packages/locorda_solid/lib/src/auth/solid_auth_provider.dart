import 'package:locorda_core/locorda_core.dart';

abstract interface class SolidAuthProvider implements Auth {
  Future<({String accessToken, String dPoP})> getDpopToken(
      String url, String method);
}
