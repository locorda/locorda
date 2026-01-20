import 'package:test/test.dart';
import '../lib/local_resource.dart';

void main() {
  test('LocalResource annotation compiles', () {
    final chapter = Chapter(title: 'An Unexpected Party', number: 1);
    expect(chapter.title, 'An Unexpected Party');
  });
}
