import 'package:test/test.dart';
import '../lib/iri_strategy.dart';

void main() {
  test('IriStrategy annotations compile', () {
    final user = User(username: 'alice', fullName: 'Alice Smith');
    expect(user.username, 'alice');

    final product = Product(id: 'p123', name: 'Widget');
    expect(product.id, 'p123');
  });
}
