import 'dart:io';
import 'package:locorda_core/src/mapping/recursive_rdf_loader.dart';

/// Test fetcher that maps URLs to local test asset files.
///
/// Maps URLs like 'https://example.org/mappings/recipe-v1' to local files
/// in the test assets directory.
class TestFetcher implements Fetcher {
  final Directory testAssetsDir;
  final Map<String, String> urlToPathMap;

  TestFetcher({
    required this.testAssetsDir,
    Map<String, String>? urlToPathMap,
  }) : urlToPathMap = urlToPathMap ?? {};

  @override
  Future<String> fetch(String url) async {
    // Check if we have an explicit mapping for this URL
    if (urlToPathMap.containsKey(url)) {
      final relativePath = urlToPathMap[url]!;
      final file = File('${testAssetsDir.path}/$relativePath');
      if (!file.existsSync()) {
        throw Exception('Mapped file not found: ${file.path} for URL: $url');
      }
      return file.readAsStringSync();
    }

    // If no mapping found, throw an error (tests should be explicit)
    throw Exception(
        'No mapping found for URL: $url. Add it to TestFetcher.urlToPathMap');
  }
}
