import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:locorda_core/src/mapping/recursive_rdf_loader.dart';
import 'package:test/test.dart';

void main() {
  group('HttpFetcher content negotiation', () {
    test('uses original URL when server supports content negotiation',
        () async {
      var headCalled = false;
      var getCalled = false;
      var getUrl = '';

      final mockClient = MockClient((request) async {
        if (request.method == 'HEAD') {
          headCalled = true;
          // Server supports content negotiation - returns turtle
          return http.Response('', 200, headers: {
            'content-type': 'text/turtle; charset=utf-8',
          });
        } else if (request.method == 'GET') {
          getCalled = true;
          getUrl = request.url.toString();
          return http.Response('@prefix : <http://example.com/> .', 200,
              headers: {'content-type': 'text/turtle'});
        }
        return http.Response('Not Found', 404);
      });

      final fetcher = HttpFetcher(httpClient: mockClient);
      final url = 'https://example.com/mappings/core-v1';

      final result = await fetcher.fetch(url, contentType: 'text/turtle');

      expect(headCalled, isTrue, reason: 'HEAD request should be made');
      expect(getCalled, isTrue, reason: 'GET request should be made');
      expect(getUrl, equals(url),
          reason: 'Should use original URL without .ttl extension');
      expect(result, contains('@prefix'));
    });

    test(
        'appends .ttl extension when server does not support content negotiation',
        () async {
      var headCalled = false;
      var getCalled = false;
      var getUrl = '';

      final mockClient = MockClient((request) async {
        if (request.method == 'HEAD') {
          headCalled = true;
          // Server does NOT support content negotiation - returns HTML
          return http.Response('', 200, headers: {
            'content-type': 'text/html',
          });
        } else if (request.method == 'GET') {
          getCalled = true;
          getUrl = request.url.toString();
          return http.Response('@prefix : <http://example.com/> .', 200,
              headers: {'content-type': 'text/turtle'});
        }
        return http.Response('Not Found', 404);
      });

      final fetcher = HttpFetcher(httpClient: mockClient);
      final url = 'https://example.com/mappings/core-v1';

      final result = await fetcher.fetch(url, contentType: 'text/turtle');

      expect(headCalled, isTrue, reason: 'HEAD request should be made');
      expect(getCalled, isTrue, reason: 'GET request should be made');
      expect(getUrl, equals('$url.ttl'),
          reason:
              'Should append .ttl extension when content negotiation not supported');
      expect(result, contains('@prefix'));
    });

    test('does not append .ttl if URL already ends with .ttl', () async {
      var getCalled = false;
      var getUrl = '';

      final mockClient = MockClient((request) async {
        if (request.method == 'HEAD') {
          // Server does NOT support content negotiation
          return http.Response('', 200, headers: {
            'content-type': 'text/html',
          });
        } else if (request.method == 'GET') {
          getCalled = true;
          getUrl = request.url.toString();
          return http.Response('@prefix : <http://example.com/> .', 200,
              headers: {'content-type': 'text/turtle'});
        }
        return http.Response('Not Found', 404);
      });

      final fetcher = HttpFetcher(httpClient: mockClient);
      final url = 'https://example.com/mappings/core-v1.ttl';

      final result = await fetcher.fetch(url, contentType: 'text/turtle');

      expect(getCalled, isTrue, reason: 'GET request should be made');
      expect(getUrl, equals(url),
          reason: 'Should not append .ttl if URL already ends with .ttl');
      expect(result, contains('@prefix'));
    });

    test('handles HEAD request failure gracefully', () async {
      var headFailed = false;
      var getUrl = '';

      final mockClient = MockClient((request) async {
        if (request.method == 'HEAD') {
          headFailed = true;
          throw Exception('HEAD request failed');
        } else if (request.method == 'GET') {
          getUrl = request.url.toString();
          return http.Response('@prefix : <http://example.com/> .', 200,
              headers: {'content-type': 'text/turtle'});
        }
        return http.Response('Not Found', 404);
      });

      final fetcher = HttpFetcher(httpClient: mockClient);
      final url = 'https://example.com/mappings/core-v1';

      final result = await fetcher.fetch(url, contentType: 'text/turtle');

      expect(headFailed, isTrue, reason: 'HEAD request should fail');
      expect(getUrl, equals('$url.ttl'),
          reason: 'Should append .ttl when HEAD fails');
      expect(result, contains('@prefix'));
    });

    test('handles HEAD returning 404', () async {
      var getUrl = '';

      final mockClient = MockClient((request) async {
        if (request.method == 'HEAD') {
          return http.Response('', 404);
        } else if (request.method == 'GET') {
          getUrl = request.url.toString();
          return http.Response('@prefix : <http://example.com/> .', 200,
              headers: {'content-type': 'text/turtle'});
        }
        return http.Response('Not Found', 404);
      });

      final fetcher = HttpFetcher(httpClient: mockClient);
      final url = 'https://example.com/mappings/core-v1';

      final result = await fetcher.fetch(url, contentType: 'text/turtle');

      expect(getUrl, equals('$url.ttl'),
          reason: 'Should append .ttl when HEAD returns 404');
      expect(result, contains('@prefix'));
    });

    test('accepts various RDF content types', () async {
      final contentTypes = [
        'text/turtle',
        'application/rdf+xml',
        'application/n-triples',
        'text/turtle; charset=utf-8',
      ];

      for (final contentType in contentTypes) {
        var getUrl = '';

        final mockClient = MockClient((request) async {
          if (request.method == 'HEAD') {
            return http.Response('', 200, headers: {
              'content-type': contentType,
            });
          } else if (request.method == 'GET') {
            getUrl = request.url.toString();
            return http.Response('@prefix : <http://example.com/> .', 200,
                headers: {'content-type': contentType});
          }
          return http.Response('Not Found', 404);
        });

        final fetcher = HttpFetcher(httpClient: mockClient);
        final url = 'https://example.com/mappings/core-v1';

        final result = await fetcher.fetch(url, contentType: contentType);

        expect(getUrl, equals(url),
            reason: 'Should use original URL for content type: $contentType');
        expect(result, contains('@prefix'));
      }
    });

    test('works without content type parameter', () async {
      var getCalled = false;

      final mockClient = MockClient((request) async {
        if (request.method == 'GET') {
          getCalled = true;
          return http.Response('content', 200);
        }
        return http.Response('Not Found', 404);
      });

      final fetcher = HttpFetcher(httpClient: mockClient);
      final url = 'https://example.com/data';

      final result = await fetcher.fetch(url);

      expect(getCalled, isTrue);
      expect(result, equals('content'));
    });
  });
}
