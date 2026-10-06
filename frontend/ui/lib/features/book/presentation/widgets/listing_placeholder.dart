// Branded placeholder imagery for Book listings (see
// scripts/media/build_placeholder_assets.py). Real listing photos arrive
// with provider integrations; until then each listing gets a deterministic
// on-brand shot based on its id/category.

import '../../domain/entities/book_entities.dart';

const _base = 'assets/images/placeholders/book';

/// Picks the best placeholder for a listing: id keywords first (they match
/// the seeded listings), then the category fallback.
String listingPlaceholderImage(BookListingEntity listing) {
  final id = listing.id.toLowerCase();
  final title = listing.title.toLowerCase();

  String? fromKeywords(List<String> keys, String image) {
    for (final key in keys) {
      if (id.contains(key) || title.contains(key)) return image;
    }
    return null;
  }

  return fromKeywords(['movie', 'cinema'], '$_base/listing_movie.png') ??
      fromKeywords(['dinner'], '$_base/listing_dinner.png') ??
      fromKeywords(['cafe', 'hangout', 'brew'], '$_base/listing_cafe.png') ??
      fromKeywords(['badminton', 'court'], '$_base/listing_badminton.png') ??
      fromKeywords(['walk', 'sunrise'], '$_base/listing_walk.png') ??
      fromKeywords(['travel', 'getaway'], '$_base/listing_travel.png') ??
      switch (listing.category) {
        BookCategory.entertainment => '$_base/listing_movie.png',
        BookCategory.meet => '$_base/listing_dinner.png',
        BookCategory.sportsAndActivities => '$_base/listing_badminton.png',
        BookCategory.travel => '$_base/listing_travel.png',
        BookCategory.mobility || BookCategory.services => '$_base/listing_cafe.png',
      };
}
