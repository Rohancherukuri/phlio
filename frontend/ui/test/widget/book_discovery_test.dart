import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/book/data/models/book_models.dart';
import 'package:phlio/features/book/domain/entities/book_entities.dart';
import 'package:phlio/features/book/presentation/controllers/book_controller.dart';
import 'package:phlio/features/book/presentation/screens/book_discovery_screen.dart';
import 'package:phlio/shared/content/content_surface.dart';

class Catalog extends ListingsController {
  @override
  Future<List<BookListingEntity>> build() async => [
    for (final section in ['Movies','Navratri','Sports']) BookListingModel.fromJson({
      'id': section, 'title': '$section listing', 'category': 'entertainment',
      'venue': 'Hyderabad venue', 'image_url': 'https://example.com/poster.jpg',
      'source_url': 'https://example.com/tickets', 'source_name': 'Provider', 'tags': [section],
    }).toEntity(),
  ];
}
void main() {
  test('Sports category and sourced image survive API parsing', () {
    final listing = BookListingModel.fromJson({'id':'sports','title':'Sport','category':'sports_and_activities',
      'image_url':'https://example.com/photo.jpg','source_url':'https://example.com/tickets'}).toEntity();
    expect(listing.category, BookCategory.sportsAndActivities);
    expect(listing.category.apiValue, 'sports_and_activities');
    expect(listing.displayPrice, 'Check ticket prices');
    expect(listing.imageUrl, 'https://example.com/photo.jpg');
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('Book categories and poster rows fit at scale $scale', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(overrides: [
        listingsControllerProvider.overrideWith(Catalog.new),
        engagementProvider.overrideWith((ref, id) async => {'count':0, 'avatars':[], 'people':[], 'liked_by_me':false}),
      ], child: MaterialApp(builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: const BookDiscoveryScreen())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Movies').first); await tester.pumpAndSettle();
      expect(find.text('Movies listing'), findsOneWidget);
      expect(find.text('Navratri listing'), findsNothing);
      await tester.drag(find.byType(ListView).first, const Offset(0, -350));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
