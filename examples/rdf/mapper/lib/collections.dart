import 'package:locorda_rdf_mapper_annotations/annotations.dart';
import 'package:locorda_rdf_terms_schema/schema.dart';

// Import the generated init file (created by build_runner) - needed by main() below
import 'init_rdf_mapper.g.dart';

// Collections are automatically handled
@RdfGlobalResource(
  SchemaBook.classIri,
  IriStrategy('{+baseUri}/books/{isbn}'),
)
class Book {
  @RdfIriPart()
  final String isbn;

  @RdfProperty(SchemaBook.name)
  final String title;

  // List - preserves order with RDF List structure
  @RdfProperty(SchemaBook.hasPart, collection: rdfList)
  final List<Chapter> chapters;

  // Set - unordered collection (multiple triples)
  @RdfProperty(SchemaBook.keywords)
  final Set<String> keywords;

  // Map - with custom entry class
  @RdfProperty(SchemaBook.review)
  @RdfMapEntry(ReviewEntry)
  final Map<String, Review> reviews;

  Book({
    required this.isbn,
    required this.title,
    required this.chapters,
    required this.keywords,
    required this.reviews,
  });
}

@RdfLocalResource(SchemaChapter.classIri)
class Chapter {
  @RdfProperty(SchemaChapter.name)
  final String title;

  @RdfProperty(SchemaChapter.position)
  final int number;

  Chapter({required this.title, required this.number});
}

@RdfLocalResource(SchemaReview.classIri)
class ReviewEntry {
  @RdfProperty(SchemaReview.author)
  @RdfMapKey()
  final String reviewer;

  @RdfProperty(SchemaReview.reviewRating)
  @RdfMapValue()
  final Review rating;

  ReviewEntry({required this.reviewer, required this.rating});
}

@RdfLocalResource(SchemaRating.classIri)
class Review {
  @RdfProperty(SchemaRating.ratingValue)
  final int stars;

  Review({required this.stars});
}

void main() {
  final book = Book(
    isbn: '978-0-544-00341-5',
    title: 'The Hobbit',
    chapters: [
      Chapter(title: 'An Unexpected Party', number: 1),
      Chapter(title: 'Roast Mutton', number: 2),
    ],
    keywords: {'fantasy', 'adventure', 'dragons'},
    reviews: {
      'Alice': Review(stars: 5),
      'Bob': Review(stars: 4),
    },
  );

  // After generation - initialize generated mapper:
  final mapper = initRdfMapper(
    baseUriProvider: () => 'https://example.org',
  );
  final turtle = mapper.encodeObject(book);
  print(turtle);
}
