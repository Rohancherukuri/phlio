import 'package:flutter/material.dart';

@immutable
class BookListingEntity {
  const BookListingEntity({
    required this.id,
    required this.title,
    required this.category,
    required this.venue,
    required this.locationNote,
    required this.description,
    required this.priceMinMinorUnits,
    required this.priceMaxMinorUnits,
    required this.currency,
    required this.durationLabel,
    required this.rating,
    required this.startsAt,
    required this.isFree,
    required this.tags,
    this.imageUrl,
    this.sourceUrl,
    this.sourceName,
    this.vertical = 'events',
    this.kind = 'ticket',
    this.imageCredit,
    this.meta = const {},
    this.goingCount = 0,
    this.going = const [],
  });

  /// People going / booked (meetups, sports, events, concerts, festivals)
  /// and up to three of their profiles (id, display_name, avatar_url).
  final int goingCount;
  final List<Map<String, dynamic>> going;

  final String id;
  final String title;
  final BookCategory category;
  final String venue;
  final String locationNote;
  final String description;
  final int priceMinMinorUnits;
  final int priceMaxMinorUnits;
  final String currency;
  final String durationLabel;
  final double? rating;
  final DateTime? startsAt;
  final bool isFree;
  final List<String> tags;
  final String? imageUrl, sourceUrl, sourceName;

  /// sports · doctor · flight · train · bus · bike · auto · cab · movies ·
  /// events · concerts · festive · meetups
  final String vertical;

  /// How it books: slot · ride · trip · ticket · rsvp · external.
  final String kind;
  final String? imageCredit;

  /// Vertical-specific facts (sports list, speciality, route, tiers, group…).
  final Map<String, dynamic> meta;

  String metaString(String key, [String fallback = '']) =>
      meta[key]?.toString() ?? fallback;

  List<String> metaList(String key) =>
      (meta[key] as List<dynamic>? ?? const []).map((e) => '$e').toList();

  List<Map<String, dynamic>> metaMaps(String key) =>
      (meta[key] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();

  String get displayPrice {
    if (sourceUrl != null && priceMinMinorUnits == 0 && !isFree)
      return 'Check ticket prices';
    if (isFree) return 'Free';
    final min = priceMinMinorUnits / 100;
    final max = priceMaxMinorUnits / 100;
    if (priceMinMinorUnits == priceMaxMinorUnits)
      return '₹${min.toStringAsFixed(0)}';
    return '₹${min.toStringAsFixed(0)} – ₹${max.toStringAsFixed(0)}';
  }
}

/// Mirrors the backend's `BookCategory` (blueprint section 9 categories).
enum BookCategory {
  entertainment,
  sportsAndActivities,
  mobility,
  services,
  meet,
  travel
}

extension BookCategoryX on BookCategory {
  String get apiValue =>
      this == BookCategory.sportsAndActivities ? 'sports_and_activities' : name;
  static BookCategory fromApiValue(String value) =>
      BookCategory.values.firstWhere(
        (c) => c.apiValue == value,
        orElse: () => BookCategory.entertainment,
      );

  String get label => switch (this) {
        BookCategory.entertainment => 'Entertainment',
        BookCategory.sportsAndActivities => 'Sports',
        BookCategory.mobility => 'Mobility',
        BookCategory.services => 'Services',
        BookCategory.meet => 'Meet',
        BookCategory.travel => 'Travel',
      };

  IconData get icon => switch (this) {
        BookCategory.entertainment => Icons.movie_outlined,
        BookCategory.sportsAndActivities => Icons.sports_tennis_outlined,
        BookCategory.mobility => Icons.directions_car_outlined,
        BookCategory.services => Icons.home_repair_service_outlined,
        BookCategory.meet => Icons.local_cafe_outlined,
        BookCategory.travel => Icons.flight_outlined,
      };
}

@immutable
class BookingEntity {
  const BookingEntity({
    required this.id,
    required this.listingId,
    required this.title,
    required this.venue,
    required this.date,
    required this.time,
    required this.participants,
    required this.estimatedTotalMinMinorUnits,
    required this.estimatedTotalMaxMinorUnits,
    required this.currency,
    required this.status,
    required this.createdAt,
    this.details = const {},
    this.vertical,
    this.imageUrl,
  });

  final Map<String, String> details;
  final String? vertical;
  final String? imageUrl;

  final String id;
  final String listingId;
  final String title;
  final String venue;
  final DateTime date;
  final DateTime? time;
  final int participants;
  final int estimatedTotalMinMinorUnits;
  final int estimatedTotalMaxMinorUnits;
  final String currency;
  final String status;
  final DateTime createdAt;

  String get displayTotal {
    final min = estimatedTotalMinMinorUnits / 100;
    final max = estimatedTotalMaxMinorUnits / 100;
    if (estimatedTotalMinMinorUnits == estimatedTotalMaxMinorUnits) {
      return '₹${min.toStringAsFixed(0)}';
    }
    return '₹${min.toStringAsFixed(0)} – ₹${max.toStringAsFixed(0)}';
  }
}
