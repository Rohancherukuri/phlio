// Shared pieces for Phlio Book: verticals, glyphs, pictures and the cards
// used by the hub, the vertical lists and search.
//
// Card styles follow the apps people already know for each job:
//   * VenueCard   — Playo: photo, rating, area · km, sport chips, ₹/hr.
//   * DoctorCard  — clinic photo, speciality, experience, fee, next slot.
//   * TripCard    — route timeline (07:10 HYD ── 1h 15m ── 08:25 BLR).
//   * MeetupRow   — Meetup: date block, group, "27 going".
//   * EventCard   — poster with date badge and "from ₹".
//   * PosterCard  — movie poster (2:3).

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../app/config/app_config.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../../../shared/content/content_surface.dart';
import '../../domain/entities/book_entities.dart';

/// A Phlio Book vertical: a tile on the hub and a list page.
class BookVertical {
  const BookVertical(this.id, this.label, this.glyph, this.verticals,
      {this.blurb = ''});

  final String id;
  final String label;
  final String glyph;

  /// Listing verticals it shows (rides group bike/auto/cab).
  final Set<String> verticals;
  final String blurb;

  bool has(BookListingEntity l) => verticals.contains(l.vertical);
}

const bookVerticals = <BookVertical>[
  BookVertical('sports', 'Sports', 'sports', {'sports'},
      blurb: 'Courts, turfs and pools near you'),
  BookVertical('doctor', 'Doctors', 'doctor', {'doctor'},
      blurb: 'Appointments, video consults and lab tests'),
  BookVertical('flight', 'Flights', 'flight', {'flight'},
      blurb: 'Fly out of Hyderabad'),
  BookVertical('train', 'Trains', 'train', {'train'},
      blurb: 'Overnight and day trains'),
  BookVertical('bus', 'Buses', 'bus', {'bus'}, blurb: 'Sleepers and seaters'),
  BookVertical('bike', 'Bike taxi', 'bike', {'bike'},
      blurb: 'Quick rides through traffic'),
  BookVertical('cab', 'Cabs & autos', 'cab', {'cab', 'auto'},
      blurb: 'Autos, minis, sedans and SUVs'),
  BookVertical('movies', 'Movies', 'movies', {'movies'},
      blurb: 'Now showing in cinemas'),
  BookVertical('concerts', 'Concerts', 'concerts', {'concerts'},
      blurb: 'Live music this month'),
  BookVertical('events', 'Events', 'events', {'events'},
      blurb: 'Comedy, food, art and expos'),
  BookVertical('festive', 'Festive', 'festive', {'festive'},
      blurb: 'Melas, markets and festivals'),
  BookVertical('meetups', 'Meetups', 'meetups', {'meetups'},
      blurb: 'Meet your communities offline'),
];

BookVertical? verticalById(String id) {
  for (final v in bookVerticals) {
    if (v.id == id) return v;
  }
  return null;
}

/// One of the Book SVG glyphs (assets/images/book_icons), tinted.
class BookGlyph extends StatelessWidget {
  const BookGlyph(this.name,
      {super.key, this.size = 20, this.color = PhlioColors.textSecondary});
  final String name;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/images/book_icons/$name.svg',
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
}

/// A listing picture (or a soft brand wash with the vertical's glyph).
class BookImage extends StatelessWidget {
  const BookImage(
      {super.key, this.url, this.glyph = 'events', this.radius = 0, this.fit});
  final String? url;
  final String glyph;
  final double radius;
  final BoxFit? fit;

  @override
  Widget build(BuildContext context) {
    final fallback = DecoratedBox(
      decoration: const BoxDecoration(gradient: PhlioColors.brandGradientSoft),
      child: Center(
          child: BookGlyph(glyph, size: 30, color: PhlioColors.textSecondary)),
    );
    final child = url == null || url!.isEmpty
        ? fallback
        : CachedNetworkImage(
            imageUrl: AppConfig.mediaUrl(url!),
            fit: fit ?? BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 150),
            placeholder: (_, __) => fallback,
            errorWidget: (_, __, ___) => fallback,
          );
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }
}

String rupees(int minor) {
  final value = (minor / 100).round().toString();
  final out = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final left = value.length - i;
    if (i > 0 && (left == 3 || (left > 3 && (left - 3) % 2 == 0))) {
      out.write(',');
    }
    out.write(value[i]);
  }
  return '₹$out';
}

const _weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
const _months = [
  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
  'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
];

String shortDate(DateTime d) {
  final l = d.toLocal();
  return '${_weekdays[l.weekday - 1][0]}${_weekdays[l.weekday - 1].substring(1).toLowerCase()}, '
      '${l.day} ${_months[l.month - 1][0]}${_months[l.month - 1].substring(1).toLowerCase()}';
}

String clock(DateTime d) {
  final l = d.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  return '$h:${l.minute.toString().padLeft(2, '0')} ${l.hour < 12 ? 'AM' : 'PM'}';
}

String clockText(String hhmm) {
  final parts = hhmm.split(':');
  return clock(DateTime(2026, 1, 1, int.parse(parts[0]), int.parse(parts[1])));
}

/// Verticals that show who's going; the rest show who liked them.
const goingVerticals = {'meetups', 'sports', 'events', 'concerts', 'festive'};

String compactNumber(int n) => n >= 1000
    ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K'
    : '$n';

/// Overlapping circle avatars (up to three) with a ring in the card colour.
class AvatarStack extends StatelessWidget {
  const AvatarStack(
      {super.key,
      required this.people,
      this.size = 22,
      this.ring = PhlioColors.surface});
  final List<Map<String, dynamic>> people;
  final double size;
  final Color ring;

  @override
  Widget build(BuildContext context) {
    final shown = people.take(3).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    final step = size * .62;
    return SizedBox(
      width: size + step * (shown.length - 1) + 4,
      height: size + 4,
      child: Stack(children: [
        for (final (i, p) in shown.indexed)
          Positioned(
            left: i * step,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
              child: PhlioAvatar(
                  profileId: '${p['id'] ?? ''}',
                  name: '${p['display_name'] ?? p['username'] ?? '?'}',
                  imageUrl: p['avatar_url'] as String?,
                  size: size,
                  showMomentRing: false),
            ),
          ),
      ]),
    );
  }
}

/// "👤👤👤 27 going" for meetups, sports, events, concerts and festivals;
/// "👤👤👤 Liked by 1.2K" for bookable services (tickets, rides, doctors…).
class BookSocialProof extends ConsumerWidget {
  const BookSocialProof(
      {super.key, required this.listing, this.ring = PhlioColors.surface});
  final BookListingEntity listing;
  final Color ring;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = PhlioTypography.caption
        .copyWith(fontSize: 12, fontWeight: FontWeight.w700);
    // Real places (OpenStreetMap "visit" listings) never show invented
    // attendees: they show likes like services do.
    if (goingVerticals.contains(listing.vertical) && listing.kind != 'visit') {
      if (listing.goingCount == 0) {
        return Text('Be the first to go',
            style: style.copyWith(color: PhlioColors.textMuted));
      }
      return Row(mainAxisSize: MainAxisSize.min, children: [
        AvatarStack(people: listing.going, ring: ring),
        const SizedBox(width: 6),
        Flexible(
          child: Text('${compactNumber(listing.goingCount)} going',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(color: PhlioColors.domainRooms)),
        ),
      ]);
    }
    final path = 'book/${listing.id}';
    final data = ref.watch(engagementProvider(path)).valueOrNull;
    final count = (data?['count'] as num?)?.toInt() ?? 0;
    if (count == 0) return const SizedBox(height: 26);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      LikersAvatarStack(path: path, ringColor: ring),
      const SizedBox(width: 6),
      Flexible(
        child: Text('Liked by ${compactNumber(count)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(color: PhlioColors.brandPink)),
      ),
    ]);
  }
}

/// For real places from OpenStreetMap: booked directly with the place.
class VisitNote extends StatelessWidget {
  const VisitNote({super.key});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Call or visit to book',
              style: PhlioTypography.caption.copyWith(
                  fontWeight: FontWeight.w800, color: PhlioColors.textPrimary)),
          Text('© OpenStreetMap',
              style: PhlioTypography.caption.copyWith(fontSize: 10.5)),
        ],
      );
}

/// Small rounded label (sport, speciality, tier…).
class BookChip extends StatelessWidget {
  const BookChip(this.label, {super.key, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: (color ?? PhlioColors.textSecondary).withValues(alpha: .12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            maxLines: 1,
            style: PhlioTypography.caption.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color ?? PhlioColors.textSecondary)),
      );
}

class RatingBadge extends StatelessWidget {
  const RatingBadge(this.rating, {super.key});
  final double rating;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .6),
            borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const BookGlyph('star', size: 12, color: Color(0xFFF6B93B)),
          const SizedBox(width: 3),
          Text(rating.toStringAsFixed(1),
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ]),
      );
}

/// Sunset-gradient action pill.
class GradientButton extends StatelessWidget {
  const GradientButton(this.label,
      {super.key, required this.onTap, this.height = 40, this.busy = false});
  final String label;
  final VoidCallback? onTap;
  final double height;
  final bool busy;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: onTap == null ? null : PhlioColors.sunsetGradient,
          color: onTap == null ? PhlioColors.surfaceElevated : null,
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(height / 2),
            onTap: busy ? null : onTap,
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Center(
                  widthFactor: 1,
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: PhlioColors.textOnBrand))
                      : Text(label,
                          style: PhlioTypography.label.copyWith(
                              fontWeight: FontWeight.w800,
                              color: onTap == null
                                  ? PhlioColors.textMuted
                                  : PhlioColors.textOnBrand)),
                ),
              ),
            ),
          ),
        ),
      );
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child, required this.onTap, this.width});
  final Widget child;
  final VoidCallback onTap;
  final double? width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Material(
          color: PhlioColors.surface,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: child),
        ),
      );
}

/// Playo-style sports venue card.
class VenueCard extends StatelessWidget {
  const VenueCard(
      {super.key, required this.listing, required this.onTap, this.width});
  final BookListingEntity listing;
  final VoidCallback onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final sports = listing.metaList('sports');
    final km = listing.meta['distance_km'];
    return _CardShell(
      width: width,
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 140,
          width: double.infinity,
          child: Stack(fit: StackFit.expand, children: [
            BookImage(url: listing.imageUrl, glyph: 'sports'),
            if (listing.rating != null)
              Positioned(top: 10, left: 10, child: RatingBadge(listing.rating!)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(listing.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PhlioTypography.title
                    .copyWith(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Row(children: [
              const BookGlyph('pin', size: 14),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                    '${listing.metaString('area')}${km != null ? ' · $km km' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PhlioTypography.caption),
              ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final sport in sports.take(3))
                BookChip(sport, color: PhlioColors.domainRooms),
            ]),
            const SizedBox(height: 10),
            BookSocialProof(listing: listing),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: listing.kind == 'visit'
                    ? const VisitNote()
                    : Text.rich(TextSpan(children: [
                        TextSpan(
                            text: rupees(listing.priceMinMinorUnits),
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        TextSpan(
                            text: ' /hr onwards',
                            style:
                                PhlioTypography.caption.copyWith(fontSize: 12)),
                      ])),
              ),
              GradientButton(listing.kind == 'visit' ? 'View' : 'Book',
                  onTap: onTap, height: 34),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Doctor / clinic appointment card: clinic photo, then details.
class DoctorCard extends StatelessWidget {
  const DoctorCard(
      {super.key, required this.listing, required this.onTap, this.width});
  final BookListingEntity listing;
  final VoidCallback onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final years = listing.meta['experience_years'] as int? ?? 0;
    final video = listing.meta['video_consult'] == true;
    return _CardShell(
      width: width,
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 130,
          width: double.infinity,
          child: Stack(fit: StackFit.expand, children: [
            BookImage(url: listing.imageUrl, glyph: 'doctor'),
            if (listing.rating != null)
              Positioned(top: 10, left: 10, child: RatingBadge(listing.rating!)),
            if (video)
              const Positioned(
                  top: 10,
                  right: 10,
                  child: BookChip('Video consult', color: Colors.white)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(listing.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PhlioTypography.title
                    .copyWith(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
                [
                  listing.metaString('speciality'),
                  if (years > 0) '$years yrs exp',
                ].join(' · '),
                style: PhlioTypography.caption
                    .copyWith(color: PhlioColors.brandPeach)),
            const SizedBox(height: 2),
            Text('${listing.venue} · ${listing.metaString('area')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PhlioTypography.caption),
            const SizedBox(height: 10),
            BookSocialProof(listing: listing),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: listing.kind == 'visit'
                    ? const VisitNote()
                    : Text('${rupees(listing.priceMinMinorUnits)} fee',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              GradientButton(listing.kind == 'visit' ? 'View' : 'Book',
                  onTap: onTap, height: 34),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Flight / train / bus route with a departure–arrival timeline.
class TripCard extends StatelessWidget {
  const TripCard({super.key, required this.listing, required this.onTap});
  final BookListingEntity listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = listing.meta;
    final classes = listing.metaMaps('classes');
    final seats = m['seats_left'];
    Widget end(String time, String code, CrossAxisAlignment align) => Column(
          crossAxisAlignment: align,
          children: [
            Text(clockText(time),
                style: PhlioTypography.title
                    .copyWith(fontSize: 17, fontWeight: FontWeight.w800)),
            Text(code, style: PhlioTypography.caption),
          ],
        );
    return _CardShell(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 120,
        width: double.infinity,
        child: Stack(fit: StackFit.expand, children: [
          BookImage(url: listing.imageUrl, glyph: listing.vertical),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withValues(alpha: .6)],
              ),
            ),
          ),
          Positioned(
            left: 14,
            bottom: 10,
            child: Text(m['to_city']?.toString() ?? '',
                style: PhlioTypography.title.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            BookGlyph(listing.vertical, size: 18, color: PhlioColors.brandPeach),
            const SizedBox(width: 8),
            Expanded(
              child: Text(listing.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PhlioTypography.label
                      .copyWith(fontWeight: FontWeight.w800)),
            ),
            if (seats != null && (seats as num) < 10)
              BookChip('$seats seats left', color: PhlioColors.danger),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            end(m['depart']?.toString() ?? '00:00',
                m['from_code']?.toString() ?? '', CrossAxisAlignment.start),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(children: [
                  Text(listing.durationLabel, style: PhlioTypography.caption),
                  const SizedBox(height: 4),
                  Row(children: [
                    Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: PhlioColors.textMuted)),
                    const Expanded(
                        child: Divider(
                            color: PhlioColors.textMuted, thickness: 1)),
                    BookGlyph(listing.vertical,
                        size: 14, color: PhlioColors.textMuted),
                  ]),
                  const SizedBox(height: 4),
                  Text(m['stops']?.toString() ?? '',
                      style: PhlioTypography.caption.copyWith(fontSize: 11)),
                ]),
              ),
            ),
            end(m['arrive']?.toString() ?? '00:00',
                m['to_code']?.toString() ?? '', CrossAxisAlignment.end),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final c in classes.take(3)) BookChip('${c['name']}'),
              ]),
            ),
            Text(rupees(listing.priceMinMinorUnits),
                style: PhlioTypography.title
                    .copyWith(fontSize: 17, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 10),
          BookSocialProof(listing: listing),
        ]),
      ),
      ]),
    );
  }
}

/// Date block used by meetups and events: "SAT / 8".
class DateBlock extends StatelessWidget {
  const DateBlock(this.when, {super.key, this.size = 52});
  final DateTime when;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l = when.toLocal();
    return Container(
      width: size,
      height: size + 4,
      decoration: BoxDecoration(
          color: PhlioColors.surfaceElevated,
          borderRadius: BorderRadius.circular(14)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(_weekdays[l.weekday - 1],
            style: PhlioTypography.caption.copyWith(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: PhlioColors.brandPeach)),
        Text('${l.day}',
            style: PhlioTypography.title
                .copyWith(fontSize: 20, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

/// Meetup-style row: date block, title, group, going count, Attend.
class MeetupRow extends StatelessWidget {
  const MeetupRow({super.key, required this.listing, required this.onTap});
  final BookListingEntity listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cap = listing.meta['capacity'] as num?;
    final left = cap == null ? null : (cap - listing.goingCount).clamp(0, 9999);
    return _CardShell(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            height: 120,
            width: double.infinity,
            child: BookImage(url: listing.imageUrl, glyph: 'meetups')),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (listing.startsAt != null) DateBlock(listing.startsAt!),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (listing.startsAt != null)
                      Text(
                          '${shortDate(listing.startsAt!)} · ${clock(listing.startsAt!)}'
                              .toUpperCase(),
                          style: PhlioTypography.caption.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: PhlioColors.brandPeach)),
                    const SizedBox(height: 2),
                    Text(listing.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: PhlioTypography.title.copyWith(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                        'Hosted by ${listing.metaString('group')} · ${listing.venue}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PhlioTypography.caption),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: BookSocialProof(listing: listing)),
                      GradientButton('Attend', onTap: onTap, height: 34),
                    ]),
                    if (left != null) ...[
                      const SizedBox(height: 4),
                      Text('$left spots left',
                          style: PhlioTypography.caption.copyWith(fontSize: 11)),
                    ],
                  ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Event / concert / festival poster card.
class EventCard extends StatelessWidget {
  const EventCard(
      {super.key, required this.listing, required this.onTap, this.width});
  final BookListingEntity listing;
  final VoidCallback onTap;
  final double? width;

  @override
  Widget build(BuildContext context) => _CardShell(
        width: width,
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: 16 / 10,
            child: Stack(fit: StackFit.expand, children: [
              BookImage(url: listing.imageUrl, glyph: listing.vertical),
              if (listing.startsAt != null)
                Positioned(
                    top: 10, left: 10, child: DateBlock(listing.startsAt!, size: 44)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(listing.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: PhlioTypography.label
                      .copyWith(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(listing.venue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PhlioTypography.caption),
              const SizedBox(height: 6),
              Text(
                  listing.sourceUrl != null
                      ? (listing.sourceName != null
                          ? 'Tickets on ${listing.sourceName}'
                          : 'See tickets')
                      : listing.isFree
                          ? 'Free'
                          : '${rupees(listing.priceMinMinorUnits)} onwards',
                  style: PhlioTypography.caption.copyWith(
                      fontWeight: FontWeight.w800,
                      color: PhlioColors.brandPeach)),
              const SizedBox(height: 8),
              BookSocialProof(listing: listing),
            ]),
          ),
        ]),
      );
}

/// Movie poster (2:3) with title below.
class PosterCard extends StatelessWidget {
  const PosterCard(
      {super.key, required this.listing, required this.onTap, this.width = 130});
  final BookListingEntity listing;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: GestureDetector(
          onTap: onTap,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AspectRatio(
                aspectRatio: 2 / 3,
                child: BookImage(
                    url: listing.imageUrl, glyph: 'movies', radius: 16)),
            const SizedBox(height: 8),
            Text(listing.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: PhlioTypography.label
                    .copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            BookSocialProof(listing: listing, ring: PhlioColors.background),
          ]),
        ),
      );
}

/// Bike taxi / auto / cab with a photo, ETA, fare and who liked it.
class RideCard extends StatelessWidget {
  const RideCard(
      {super.key, required this.listing, required this.onTap, this.width});
  final BookListingEntity listing;
  final VoidCallback onTap;
  final double? width;

  @override
  Widget build(BuildContext context) => _CardShell(
        width: width,
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 110,
            width: double.infinity,
            child: Stack(fit: StackFit.expand, children: [
              BookImage(url: listing.imageUrl, glyph: listing.vertical),
              Positioned(
                top: 10,
                left: 10,
                child: BookChip('${listing.metaString('eta_min', '5')} min away',
                    color: Colors.white),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    BookGlyph(listing.vertical,
                        size: 18, color: PhlioColors.brandPeach),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(listing.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PhlioTypography.label.copyWith(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text('From ${rupees(listing.priceMinMinorUnits)}',
                      style: PhlioTypography.caption.copyWith(
                          fontWeight: FontWeight.w800,
                          color: PhlioColors.brandPeach)),
                  const SizedBox(height: 8),
                  BookSocialProof(listing: listing),
                ]),
          ),
        ]),
      );
}

/// Compact row for search results and "other" listings.
class ListingRow extends StatelessWidget {
  const ListingRow({super.key, required this.listing, required this.onTap});
  final BookListingEntity listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    String? vertical;
    for (final v in bookVerticals) {
      if (v.has(listing)) {
        vertical = v.label;
        break;
      }
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          SizedBox(
              width: 64,
              height: 64,
              child: BookImage(
                  url: listing.imageUrl, glyph: listing.vertical, radius: 14)),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(listing.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PhlioTypography.label
                      .copyWith(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                  [if (vertical != null) vertical, listing.venue]
                      .where((e) => e.isNotEmpty)
                      .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PhlioTypography.caption),
              const SizedBox(height: 2),
              Text(listing.displayPrice,
                  style: PhlioTypography.caption.copyWith(
                      fontWeight: FontWeight.w800,
                      color: PhlioColors.brandPeach)),
              const SizedBox(height: 4),
              BookSocialProof(listing: listing, ring: PhlioColors.background),
            ]),
          ),
          const BookGlyph('chevron_right', size: 18),
        ]),
      ),
    );
  }
}

/// Section heading with an optional "See all".
class BookSectionHeader extends StatelessWidget {
  const BookSectionHeader(this.title,
      {super.key, this.subtitle, this.onSeeAll});
  final String title;
  final String? subtitle;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 26, 12, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: PhlioTypography.title
                      .copyWith(fontSize: 20, fontWeight: FontWeight.w800)),
              if (subtitle != null)
                Text(subtitle!, style: PhlioTypography.caption),
            ]),
          ),
          if (onSeeAll != null)
            TextButton(
                onPressed: onSeeAll,
                child: const Text('See all',
                    style: TextStyle(color: PhlioColors.brandPeach))),
        ]),
      );
}
