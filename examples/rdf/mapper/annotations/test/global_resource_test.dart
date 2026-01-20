import 'package:test/test.dart';
import '../lib/global_resource.dart';

void main() {
  test('GlobalResource annotation compiles', () {
    final book = Book(isbn: '978-0-544-00341-5', title: 'The Hobbit');
    expect(book.title, 'The Hobbit');
  });
}
