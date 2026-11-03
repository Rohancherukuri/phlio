import '../../domain/entities/book_entities.dart';

/// Older API builds don't send `vertical`: work it out from tags/category.
String _inferVertical(Map<String, dynamic> json) {
  final tags = (json['tags'] as List<dynamic>? ?? const []).map((e) => '$e');
  final id = json['id'] as String? ?? '';
  if (tags.contains('Movies')) return 'movies';
  if (tags.contains('Doctors')) return 'doctor';
  if (tags.contains('Meetups')) return 'meetups';
  if (tags.contains('Festive')) return 'festive';
  if (tags.contains('Music')) return 'concerts';
  if (tags.contains('Flight')) return 'flight';
  if (tags.contains('Train')) return 'train';
  if (tags.contains('Bus')) return 'bus';
  if (id.contains('ride_bike')) return 'bike';
  if (id.contains('ride_auto')) return 'auto';
  if (tags.contains('Rides')) return 'cab';
  if (tags.contains('Sports') || json['category'] == 'sports_and_activities') {
    return 'sports';
  }
  return 'events';
}

class BookListingModel {
  const BookListingModel({
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

  factory BookListingModel.fromJson(Map<String, dynamic> json) {
    return BookListingModel(
      id: json['id'] as String,
      title: json['title'] as String,
      category: BookCategoryX.fromApiValue(json['category'] as String),
      venue: json['venue'] as String? ?? '',
      locationNote: json['location_note'] as String? ?? '',
      description: json['description'] as String? ?? '',
      priceMinMinorUnits: json['price_min_minor_units'] as int? ?? 0,
      priceMaxMinorUnits: json['price_max_minor_units'] as int? ?? 0,
      currency: json['currency'] as String? ?? 'INR',
      durationLabel: json['duration_label'] as String? ?? '',
      rating: (json['rating'] as num?)?.toDouble(),
      startsAt: json['starts_at'] != null ? DateTime.parse(json['starts_at'] as String) : null,
      isFree: json['is_free'] as bool? ?? false,
      tags: (json['tags'] as List<dynamic>? ?? []).cast<String>(),
      imageUrl: json['image_url'] as String?,
      sourceUrl: json['source_url'] as String?,
      sourceName: json['source_name'] as String?,
      vertical: json['vertical'] as String? ?? _inferVertical(json),
      kind: json['kind'] as String? ?? 'ticket',
      imageCredit: json['image_credit'] as String?,
      meta: (json['meta'] as Map?)?.cast<String, dynamic>() ?? const {},
      goingCount: json['going_count'] as int? ?? 0,
      going: (json['going'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(),
    );
  }

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
  final String vertical;
  final String kind;
  final String? imageCredit;
  final Map<String, dynamic> meta;
  final int goingCount;
  final List<Map<String, dynamic>> going;

  BookListingEntity toEntity() => BookListingEntity(
        id: id,
        title: title,
        category: category,
        venue: venue,
        locationNote: locationNote,
        description: description,
        priceMinMinorUnits: priceMinMinorUnits,
        priceMaxMinorUnits: priceMaxMinorUnits,
        currency: currency,
        durationLabel: durationLabel,
        rating: rating,
        startsAt: startsAt,
        isFree: isFree,
        tags: tags,
        imageUrl: imageUrl,
        sourceUrl: sourceUrl,
        sourceName: sourceName,
        vertical: vertical,
        kind: kind,
        imageCredit: imageCredit,
        meta: meta,
        goingCount: goingCount,
        going: going,
      );
}

class BookingModel {
  const BookingModel({
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

  factory BookingModel.fromJson(Map<String, dynamic> json) {
    return BookingModel(
      id: json['id'] as String,
      listingId: json['listing_id'] as String,
      title: json['title'] as String,
      venue: json['venue'] as String? ?? '',
      date: DateTime.parse(json['date'] as String),
      time: json['time'] != null
          ? DateTime.parse('2026-01-01T${(json['time'] as String)}:00')
          : null,
      participants: json['participants'] as int? ?? 1,
      estimatedTotalMinMinorUnits: json['estimated_total_min_minor_units'] as int? ?? 0,
      estimatedTotalMaxMinorUnits: json['estimated_total_max_minor_units'] as int? ?? 0,
      currency: json['currency'] as String? ?? 'INR',
      status: json['status'] as String? ?? 'confirmed',
      createdAt: DateTime.parse(json['created_at'] as String),
      details: (json['details'] as Map?)
              ?.map((k, v) => MapEntry('$k', '$v')) ??
          const {},
      vertical: json['vertical'] as String?,
      imageUrl: json['image_url'] as String?,
    );
  }

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

  BookingEntity toEntity() => BookingEntity(
        id: id,
        listingId: listingId,
        title: title,
        venue: venue,
        date: date,
        time: time,
        participants: participants,
        estimatedTotalMinMinorUnits: estimatedTotalMinMinorUnits,
        estimatedTotalMaxMinorUnits: estimatedTotalMaxMinorUnits,
        currency: currency,
        status: status,
        createdAt: createdAt,
        details: details,
        vertical: vertical,
        imageUrl: imageUrl,
      );
}
