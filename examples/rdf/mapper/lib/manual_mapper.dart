import 'package:locorda_rdf_core/core.dart';
import 'package:locorda_rdf_mapper/mapper.dart';
import 'package:locorda_rdf_terms_schema/schema.dart';

// For full control, implement mappers manually
class Book {
  final String isbn;
  final String title;
  final String author;

  Book({
    required this.isbn,
    required this.title,
    required this.author,
  });
}

// Manual mapper implementation
class BookMapper implements GlobalResourceMapper<Book> {
  @override
  IriTerm get typeIri => SchemaBook.classIri;

  @override
  Book fromRdfResource(IriTerm subject, DeserializationContext context) {
    final reader = context.reader(subject);

    return Book(
      isbn: subject.value.split('/').last,
      title: reader.require<String>(SchemaBook.name),
      author: reader.require<String>(SchemaBook.author),
    );
  }

  @override
  (IriTerm, Iterable<Triple>) toRdfResource(
    Book book,
    SerializationContext context, {
    RdfSubject? parentSubject,
  }) {
    final subject = IriTerm('https://example.org/books/${book.isbn}');

    return context
        .resourceBuilder(subject)
        .addValue(SchemaBook.name, book.title)
        .addValue(SchemaBook.author, book.author)
        .build();
  }
}

void main() {
  // Create mapper and register custom implementation
  final mapper = RdfMapper.withDefaultRegistry()
    ..registerMapper<Book>(BookMapper());

  // Serialize
  final book = Book(
    isbn: '978-0-544-00341-5',
    title: 'The Hobbit',
    author: 'J.R.R. Tolkien',
  );

  final turtle = mapper.encodeObject(book);
  print(turtle);

  // Deserialize
  final deserializedBook = mapper.decodeObject<Book>(turtle);
  print('Title: ${deserializedBook.title}');
}
