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
  });

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

  String get displayPrice {
    if (isFree) return 'Free';
    final min = priceMinMinorUnits / 100;
    final max = priceMaxMinorUnits / 100;
    if (priceMinMinorUnits == priceMaxMinorUnits) return '₹${min.toStringAsFixed(0)}';
    return '₹${min.toStringAsFixed(0)} – ₹${max.toStringAsFixed(0)}';
  }
}

/// Mirrors the backend's `BookCategory` (blueprint section 9 categories).
enum BookCategory { entertainment, sportsAndActivities, mobility, services, meet, travel }

extension BookCategoryX on BookCategory {
  static BookCategory fromApiValue(String value) => BookCategory.values.firstWhere(
        (c) => c.name == value,
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
  });

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
