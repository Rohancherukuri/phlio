// Phlio Book: one place to book everything — courts and turfs (Playo-style),
// doctor appointments, flights, trains, buses, bike taxis, autos and cabs,
// movies, concerts, events, festivals and community meetups (Meetup-style).
//
// Home (`BookDiscoveryScreen()`):
//   Book · 📍 Hyderabad ⌄                          🎟  🔔
//   [ Search courts, doctors, flights, events… ]
//   ┌ service grid: photo tiles for every vertical ┐
//   Where to? ride card · Travel search (Flights | Trains | Buses)
//   Play nearby · Doctors near you · Meetups this week · Concerts ·
//   Festive season · Events · Movies in cinemas
// Explore (`BookDiscoveryScreen(explore: true)`): search everything with
// vertical chips.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phlio/shared/widgets/notifications_button.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/typography.dart';
import '../../../../shared/content/content_surface.dart';
import '../../domain/entities/book_entities.dart';
import '../controllers/book_controller.dart';
import '../widgets/book_sheets.dart';
import '../widgets/book_ui.dart';

// Kept stateful (the old screen was) so a hot reload swaps it cleanly.
class BookDiscoveryScreen extends ConsumerStatefulWidget {
  const BookDiscoveryScreen({this.explore = false, super.key});
  final bool explore;

  @override
  ConsumerState<BookDiscoveryScreen> createState() =>
      _BookDiscoveryScreenState();
}

class _BookDiscoveryScreenState extends ConsumerState<BookDiscoveryScreen> {
  @override
  Widget build(BuildContext context) =>
      widget.explore ? const _BookExplore() : const _BookHub();
}

void _open(BuildContext context, BookListingEntity listing) =>
    showBookingSheet(context, listing);

void _openVertical(BuildContext context, BookVertical vertical) =>
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BookVerticalScreen(vertical: vertical)));

// -- Hub ---------------------------------------------------------------------

class _BookHub extends ConsumerWidget {
  const _BookHub();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(listingsControllerProvider);
    return Scaffold(
      backgroundColor: PhlioColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(listingsControllerProvider);
            await ref.read(listingsControllerProvider.future);
          },
          child: data.when(
            loading: () => ListView(children: const [
              _Header(),
              Padding(
                  padding: EdgeInsets.all(60),
                  child: Center(child: CircularProgressIndicator())),
            ]),
            error: (_, __) => ListView(children: [
              const _Header(),
              Center(
                  child: TextButton(
                      onPressed: () =>
                          ref.invalidate(listingsControllerProvider),
                      child: const Text('Could not load Phlio Book. Retry'))),
            ]),
            data: (all) => _hub(context, all),
          ),
        ),
      ),
    );
  }

  Widget _hub(BuildContext context, List<BookListingEntity> all) {
    List<BookListingEntity> of(String vertical) {
      final items = all.where((l) => l.vertical == vertical).toList();
      items.sort((a, b) {
        final x = a.startsAt, y = b.startsAt;
        if (x != null && y != null) return x.compareTo(y);
        return (b.rating ?? 0).compareTo(a.rating ?? 0);
      });
      return items;
    }

    final venues = of('sports');
    final doctors = of('doctor');
    final meetups = of('meetups');
    final concerts = of('concerts');
    final festive = of('festive');
    final events = of('events');
    final movies = of('movies');
    final rides = all.where((l) => l.kind == 'ride').toList()
      ..sort((a, b) => a.priceMinMinorUnits.compareTo(b.priceMinMinorUnits));
    final trips = all.where((l) => l.kind == 'trip').toList();

    Widget shelf(List<BookListingEntity> items, double height,
            Widget Function(BookListingEntity) card) =>
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            // No ContentSurface here: its stretched Column gets an unbounded
            // width in a horizontal list, so the cards never laid out (the
            // blank shelves). Long-press still opens the share sheet.
            itemBuilder: (context, i) => GestureDetector(
                onLongPress: () =>
                    showContentShare(context, 'book/${items[i].id}'),
                child: Align(
                    alignment: Alignment.topLeft, child: card(items[i]))),
          ),
        );

    // One standout per category for the hero banners.
    final featured = <BookListingEntity>[
      for (final group in [venues, concerts, meetups, of('flight'), festive,
        doctors, events])
        if (group.any((l) => (l.imageUrl ?? '').isNotEmpty))
          group.firstWhere((l) => (l.imageUrl ?? '').isNotEmpty),
    ];

    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      const _Header(),
      if (featured.isNotEmpty) ...[
        const SizedBox(height: 14),
        BookHeroCarousel(items: featured),
      ],
      _ServiceGrid(all: all),
      if (rides.isNotEmpty) ...[
        _RideCard(rides: rides),
        const SizedBox(height: 12),
        shelf(rides, 236, (l) => RideCard(
            listing: l, width: 210, onTap: () => _open(context, l))),
      ],
      if (trips.isNotEmpty) ...[
        _TravelCard(trips: trips),
        BookSectionHeader('Popular routes',
            subtitle: 'Flights, trains and buses from Hyderabad',
            onSeeAll: () => _openVertical(context, verticalById('flight')!)),
        shelf(trips, 340, (l) => SizedBox(
            width: 300,
            child: TripCard(listing: l, onTap: () => _open(context, l)))),
      ],
      if (festive.isNotEmpty) _FestiveBanner(items: festive),
      if (venues.isNotEmpty) ...[
        BookSectionHeader('Play nearby',
            subtitle: 'Book courts and turfs by the hour',
            onSeeAll: () => _openVertical(context, verticalById('sports')!)),
        shelf(venues, 372, (l) => VenueCard(
            listing: l, width: 260, onTap: () => _open(context, l))),
      ],
      if (doctors.isNotEmpty) ...[
        BookSectionHeader('Doctors near you',
            subtitle: 'Appointments today and video consults',
            onSeeAll: () => _openVertical(context, verticalById('doctor')!)),
        shelf(doctors, 330, (l) => DoctorCard(
            listing: l, width: 270, onTap: () => _open(context, l))),
      ],
      if (meetups.isNotEmpty) ...[
        BookSectionHeader('Meetups this week',
            subtitle: 'Hosted by Phlio communities',
            onSeeAll: () => _openVertical(context, verticalById('meetups')!)),
        shelf(meetups, 340, (l) => SizedBox(
            width: 300,
            child: MeetupRow(listing: l, onTap: () => _open(context, l)))),
      ],
      if (concerts.isNotEmpty) ...[
        BookSectionHeader('Concerts & live music',
            onSeeAll: () => _openVertical(context, verticalById('concerts')!)),
        shelf(concerts, 282, (l) => EventCard(
            listing: l, width: 220, onTap: () => _open(context, l))),
      ],
      if (events.isNotEmpty) ...[
        BookSectionHeader('Events this week',
            onSeeAll: () => _openVertical(context, verticalById('events')!)),
        shelf(events, 282, (l) => EventCard(
            listing: l, width: 220, onTap: () => _open(context, l))),
      ],
      if (movies.isNotEmpty) ...[
        BookSectionHeader('Movies in cinemas',
            subtitle: 'Showtimes and tickets on the provider',
            onSeeAll: () => _openVertical(context, verticalById('movies')!)),
        shelf(movies, 282, (l) => PosterCard(
            listing: l, onTap: () => _open(context, l))),
      ],
    ]);
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Book',
                        style: PhlioTypography.headline.copyWith(
                            fontSize: 30, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Row(children: [
                      const BookGlyph('pin',
                          size: 15, color: PhlioColors.brandPeach),
                      const SizedBox(width: 4),
                      Text('Hyderabad',
                          style: PhlioTypography.label.copyWith(
                              color: PhlioColors.brandPeach,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(width: 2),
                      const BookGlyph('chevron_down',
                          size: 14, color: PhlioColors.brandPeach),
                    ]),
                  ]),
            ),
            IconButton(
                tooltip: 'Your bookings',
                onPressed: () => showMyBookings(context),
                icon: const BookGlyph('ticket',
                    size: 24, color: PhlioColors.textPrimary)),
            const PhlioNotificationsButton(),
          ]),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Material(
              color: PhlioColors.surface,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const _BookExplore(standalone: true))),
                child: SizedBox(
                  height: 48,
                  child: Row(children: [
                    const SizedBox(width: 14),
                    const BookGlyph('search', size: 20),
                    const SizedBox(width: 10),
                    Text('Search courts, doctors, flights, events…',
                        style: PhlioTypography.body
                            .copyWith(color: PhlioColors.textMuted)),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      );
}

/// Photo tiles for every vertical (the first listing's picture, so the grid
/// shows real places and events rather than stock icons). Two rows until
/// "See all" reveals the rest.
class _ServiceGrid extends StatefulWidget {
  const _ServiceGrid({required this.all});
  final List<BookListingEntity> all;

  @override
  State<_ServiceGrid> createState() => _ServiceGridState();
}

class _ServiceGridState extends State<_ServiceGrid> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    String? picture(BookVertical v) {
      for (final l in widget.all) {
        if (v.has(l) && (l.imageUrl ?? '').isNotEmpty) return l.imageUrl;
      }
      return null;
    }

    return LayoutBuilder(builder: (context, box) {
      final columns = box.maxWidth > 560 ? 6 : 4;
      final width = (box.maxWidth - 24) / columns;
      final collapsed = columns * 2;
      final tiles = _expanded || bookVerticals.length <= collapsed
          ? bookVerticals
          : bookVerticals.take(collapsed).toList();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
          child: Row(children: [
            Expanded(
              child: Text('Book anything',
                  style: PhlioTypography.title
                      .copyWith(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            if (bookVerticals.length > collapsed)
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'Show less' : 'See all',
                    style: const TextStyle(color: PhlioColors.brandPeach)),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Wrap(children: [
              for (final v in tiles)
                SizedBox(
                  width: width,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _openVertical(context, v),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(children: [
                        SizedBox(
                          width: 62,
                          height: 62,
                          child: Stack(fit: StackFit.expand, children: [
                            BookImage(
                                url: picture(v), glyph: v.glyph, radius: 18),
                            if (picture(v) != null)
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: .55)
                                    ],
                                  ),
                                ),
                                child: Align(
                                  alignment: Alignment.bottomRight,
                                  child: Padding(
                                    padding: const EdgeInsets.all(5),
                                    child: BookGlyph(v.glyph,
                                        size: 16, color: Colors.white),
                                  ),
                                ),
                              ),
                          ]),
                        ),
                        const SizedBox(height: 6),
                        Text(v.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PhlioTypography.caption.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: PhlioColors.textPrimary)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ]);
    });
  }
}

/// Swipeable hero banners (photo, category, title, social proof, Book).
class BookHeroCarousel extends StatefulWidget {
  const BookHeroCarousel({super.key, required this.items, this.height = 210});
  final List<BookListingEntity> items;
  final double height;

  @override
  State<BookHeroCarousel> createState() => _BookHeroCarouselState();
}

class _BookHeroCarouselState extends State<BookHeroCarousel> {
  final _pages = PageController(viewportFraction: .9);
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        SizedBox(
          height: widget.height,
          child: PageView.builder(
            controller: _pages,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: widget.items.length,
            itemBuilder: (context, i) {
              final l = widget.items[i];
              String? label;
              for (final v in bookVerticals) {
                if (v.has(l)) {
                  label = v.label;
                  break;
                }
              }
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () => _open(context, l),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(fit: StackFit.expand, children: [
                      BookImage(url: l.imageUrl, glyph: l.vertical),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: .05),
                              Colors.black.withValues(alpha: .8)
                            ],
                          ),
                        ),
                      ),
                      if (label != null)
                        Positioned(
                            top: 12,
                            left: 12,
                            child: BookChip(label.toUpperCase(),
                                color: Colors.white)),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 14,
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(l.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: PhlioTypography.title.copyWith(
                                              fontSize: 21,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white)),
                                      const SizedBox(height: 6),
                                      BookSocialProof(
                                          listing: l,
                                          ring: const Color(0xFF1B1B22)),
                                    ]),
                              ),
                              const SizedBox(width: 10),
                              GradientButton(
                                  l.kind == 'rsvp' ? 'Attend' : 'Book',
                                  height: 38,
                                  onTap: () => _open(context, l)),
                            ]),
                      ),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.items.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < widget.items.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page
                        ? PhlioColors.brandPeach
                        : PhlioColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ]),
          ),
      ]);
}

/// "Where to?" — pick a vehicle, then pickup/drop in the sheet.
class _RideCard extends StatelessWidget {
  const _RideCard({required this.rides});
  final List<BookListingEntity> rides;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: PhlioColors.surface,
              borderRadius: BorderRadius.circular(22)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Ride now',
                style: PhlioTypography.title
                    .copyWith(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Material(
              color: PhlioColors.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _open(context, rides.first),
                child: SizedBox(
                  height: 46,
                  child: Row(children: [
                    const SizedBox(width: 14),
                    Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                            color: PhlioColors.danger,
                            shape: BoxShape.circle)),
                    const SizedBox(width: 12),
                    Text('Where to?',
                        style: PhlioTypography.body.copyWith(
                            fontWeight: FontWeight.w700,
                            color: PhlioColors.textSecondary)),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: rides.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final r = rides[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _open(context, r),
                    child: Container(
                      width: 104,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: PhlioColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(16)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            BookGlyph(r.vertical,
                                size: 22, color: PhlioColors.brandPeach),
                            const Spacer(),
                            Text(r.title.replaceFirst('Cab · ', ''),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PhlioTypography.label
                                    .copyWith(fontWeight: FontWeight.w800)),
                            Text('${r.metaString('eta_min', '5')} min',
                                style: PhlioTypography.caption
                                    .copyWith(fontSize: 11)),
                          ]),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      );
}

/// Flights | Trains | Buses search: pick a destination, see routes.
class _TravelCard extends StatefulWidget {
  const _TravelCard({required this.trips});
  final List<BookListingEntity> trips;

  @override
  State<_TravelCard> createState() => _TravelCardState();
}

class _TravelCardState extends State<_TravelCard> {
  String _mode = 'flight';
  String? _to;

  @override
  Widget build(BuildContext context) {
    final routes = widget.trips.where((t) => t.vertical == _mode).toList();
    final destinations = {for (final r in routes) r.metaString('to_city')}
        .where((d) => d.isNotEmpty)
        .toList()
      ..sort();
    final to = destinations.contains(_to) ? _to! : destinations.firstOrNullX;
    Widget tab(String id, String label) => Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _mode = id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 38,
              decoration: BoxDecoration(
                gradient: _mode == id ? PhlioColors.sunsetGradient : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                BookGlyph(id,
                    size: 16,
                    color: _mode == id
                        ? PhlioColors.textOnBrand
                        : PhlioColors.textSecondary),
                const SizedBox(width: 6),
                Text(label,
                    style: PhlioTypography.label.copyWith(
                        fontWeight: FontWeight.w800,
                        color: _mode == id
                            ? PhlioColors.textOnBrand
                            : PhlioColors.textSecondary)),
              ]),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: PhlioColors.surface,
            borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
                color: PhlioColors.surfaceElevated,
                borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              tab('flight', 'Flights'),
              tab('train', 'Trains'),
              tab('bus', 'Buses'),
            ]),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _place('From', 'Hyderabad')),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: BookGlyph('swap', size: 20),
            ),
            Expanded(
              child: PopupMenuButton<String>(
                color: PhlioColors.surfaceElevated,
                onSelected: (value) => setState(() => _to = value),
                itemBuilder: (_) => [
                  for (final d in destinations)
                    PopupMenuItem(value: d, child: Text(d)),
                ],
                child: _place('To', to ?? 'Choose'),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: GradientButton(
                'Search ${_mode == 'bus' ? 'buses' : '${_mode}s'}',
                height: 46,
                onTap: to == null
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => BookVerticalScreen(
                            vertical: verticalById(_mode)!,
                            initialFilter: to)))),
          ),
        ]),
      ),
    );
  }

  Widget _place(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
            color: PhlioColors.surfaceElevated,
            borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: PhlioTypography.caption.copyWith(fontSize: 11)),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PhlioTypography.label
                  .copyWith(fontSize: 15, fontWeight: FontWeight.w800)),
        ]),
      );
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNullX => isEmpty ? null : first;
}

/// Swipeable festive banners.
class _FestiveBanner extends StatefulWidget {
  const _FestiveBanner({required this.items});
  final List<BookListingEntity> items;

  @override
  State<_FestiveBanner> createState() => _FestiveBannerState();
}

class _FestiveBannerState extends State<_FestiveBanner> {
  final _pages = PageController(viewportFraction: .9);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BookSectionHeader('Festive season',
              subtitle: 'Melas, markets and festivals',
              onSeeAll: () =>
                  _openVertical(context, verticalById('festive')!)),
          SizedBox(
            height: 190,
            child: PageView.builder(
              controller: _pages,
              itemCount: widget.items.length,
              itemBuilder: (context, i) {
                final l = widget.items[i];
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () => _open(context, l),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Stack(fit: StackFit.expand, children: [
                        BookImage(url: l.imageUrl, glyph: 'festive'),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: .75)
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 14,
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (l.startsAt != null)
                                          Text(
                                              shortDate(l.startsAt!)
                                                  .toUpperCase(),
                                              style: PhlioTypography.caption
                                                  .copyWith(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: PhlioColors
                                                          .brandPeach)),
                                        Text(l.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: PhlioTypography.title
                                                .copyWith(
                                                    fontSize: 20,
                                                    fontWeight:
                                                        FontWeight.w800,
                                                    color: Colors.white)),
                                        Text(l.venue,
                                            maxLines: 1,
                                            style: PhlioTypography.caption
                                                .copyWith(
                                                    color: Colors.white70)),
                                      ]),
                                ),
                                GradientButton('Book',
                                    height: 36, onTap: () => _open(context, l)),
                              ]),
                        ),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
}

// -- One vertical --------------------------------------------------------------

/// Every listing in one vertical, with the filters that vertical needs:
/// sports for venues, speciality for doctors, destination for trips.
class BookVerticalScreen extends ConsumerStatefulWidget {
  const BookVerticalScreen(
      {super.key, required this.vertical, this.initialFilter});
  final BookVertical vertical;
  final String? initialFilter;

  @override
  ConsumerState<BookVerticalScreen> createState() =>
      _BookVerticalScreenState();
}

class _BookVerticalScreenState extends ConsumerState<BookVerticalScreen> {
  String? _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
  }

  List<String> _facet(BookListingEntity l) => switch (l.vertical) {
        'sports' => l.metaList('sports'),
        'doctor' => [l.metaString('speciality')],
        'flight' || 'train' || 'bus' => [l.metaString('to_city')],
        'cab' || 'auto' => [l.vertical == 'auto' ? 'Auto' : 'Cabs'],
        _ => const [],
      };

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(listingsControllerProvider);
    final v = widget.vertical;
    return Scaffold(
      backgroundColor: PhlioColors.background,
      appBar: AppBar(
        backgroundColor: PhlioColors.background,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v.label,
              style: PhlioTypography.title.copyWith(fontWeight: FontWeight.w800)),
          Text(v.blurb, style: PhlioTypography.caption),
        ]),
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
            child: TextButton(
                onPressed: () => ref.invalidate(listingsControllerProvider),
                child: const Text('Could not load. Retry'))),
        data: (all) {
          final items = all.where(v.has).toList()
            ..sort((a, b) {
              final x = a.startsAt, y = b.startsAt;
              if (x != null && y != null) return x.compareTo(y);
              return (b.rating ?? 0).compareTo(a.rating ?? 0);
            });
          final facets = <String>{
            for (final l in items) ..._facet(l).where((f) => f.isNotEmpty)
          }.toList()
            ..sort();
          final shown = _filter == null
              ? items
              : items.where((l) => _facet(l).contains(_filter)).toList();
          final banners = shown
              .where((l) => (l.imageUrl ?? '').isNotEmpty)
              .take(5)
              .toList();
          // Banners run edge to edge; everything else is inset by 16.
          return ListView(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 32),
            children: [
              if (banners.length > 1 && v.id != 'movies') ...[
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: BookHeroCarousel(items: banners, height: 190),
                ),
                const SizedBox(height: 16),
              ],
              if (facets.length > 1)
                SizedBox(
                  height: 40,
                  child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                    _chip('All', _filter == null,
                        () => setState(() => _filter = null)),
                    for (final f in facets)
                      _chip(f, _filter == f, () => setState(() => _filter = f)),
                  ]),
                ),
              const SizedBox(height: 12),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Text('Nothing here yet.',
                      textAlign: TextAlign.center, style: PhlioTypography.body),
                ),
              if (v.id == 'movies')
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(spacing: 12, runSpacing: 16, children: [
                    for (final l in shown)
                      PosterCard(
                          listing: l,
                          width: (MediaQuery.sizeOf(context).width - 44) / 2,
                          onTap: () => _open(context, l)),
                  ]),
                )
              else
                for (final l in shown)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: ContentSurface(
                      platform: 'book',
                      contentId: l.id,
                      showEngagement: false,
                      child: _card(context, l),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  Widget _card(BuildContext context, BookListingEntity l) => switch (l.kind) {
        'slot' || 'visit' when l.vertical == 'doctor' =>
          DoctorCard(listing: l, onTap: () => _open(context, l)),
        'slot' || 'visit' => VenueCard(listing: l, onTap: () => _open(context, l)),
        'trip' => TripCard(listing: l, onTap: () => _open(context, l)),
        'rsvp' => MeetupRow(listing: l, onTap: () => _open(context, l)),
        'ride' => RideCard(listing: l, onTap: () => _open(context, l)),
        _ => EventCard(listing: l, onTap: () => _open(context, l)),
      };

  Widget _chip(String label, bool on, VoidCallback tap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: on ? PhlioColors.textPrimary : PhlioColors.surface,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: tap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Text(label,
                    style: PhlioTypography.label.copyWith(
                        fontWeight: FontWeight.w700,
                        color: on
                            ? PhlioColors.background
                            : PhlioColors.textSecondary)),
              ),
            ),
          ),
        ),
      );
}

// -- Explore / search -------------------------------------------------------------

class _BookExplore extends ConsumerStatefulWidget {
  const _BookExplore({this.standalone = false});
  final bool standalone;

  @override
  ConsumerState<_BookExplore> createState() => _BookExploreState();
}

class _BookExploreState extends ConsumerState<_BookExplore> {
  String _query = '';
  BookVertical? _vertical;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(listingsControllerProvider);
    return Scaffold(
      backgroundColor: PhlioColors.background,
      appBar: widget.standalone
          ? AppBar(backgroundColor: PhlioColors.background)
          : null,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!widget.standalone)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
              child: Row(children: [
                Expanded(
                  child: Text('Explore Book',
                      style: PhlioTypography.headline
                          .copyWith(fontSize: 28, fontWeight: FontWeight.w800)),
                ),
                IconButton(
                    tooltip: 'Your bookings',
                    onPressed: () => showMyBookings(context),
                    icon: const BookGlyph('ticket',
                        size: 24, color: PhlioColors.textPrimary)),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                  color: PhlioColors.surface,
                  borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                const SizedBox(width: 14),
                const BookGlyph('search', size: 20),
                Expanded(
                  child: TextField(
                    autofocus: widget.standalone,
                    onChanged: (value) =>
                        setState(() => _query = value.toLowerCase().trim()),
                    style: PhlioTypography.body
                        .copyWith(color: PhlioColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Badminton, dentist, Bengaluru, concert…',
                      hintStyle: PhlioTypography.body
                          .copyWith(color: PhlioColors.textMuted),
                      filled: false,
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _chip('All', _vertical == null,
                    () => setState(() => _vertical = null)),
                for (final v in bookVerticals)
                  _chip(v.label, _vertical == v,
                      () => setState(() => _vertical = v)),
              ],
            ),
          ),
          Expanded(
            child: data.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                  child: TextButton(
                      onPressed: () =>
                          ref.invalidate(listingsControllerProvider),
                      child: const Text('Could not load. Retry'))),
              data: (all) {
                final words = _query.split(' ').where((w) => w.isNotEmpty);
                final shown = all.where((l) {
                  if (_vertical != null && !_vertical!.has(l)) return false;
                  final hay = [
                    l.title,
                    l.venue,
                    l.locationNote,
                    l.description,
                    ...l.tags,
                    ...l.meta.values.map((e) => '$e'),
                  ].join(' ').toLowerCase();
                  return words.every(hay.contains);
                }).toList();
                if (shown.isEmpty) {
                  return Center(
                      child: Text('No matches yet.',
                          style: PhlioTypography.body));
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: shown.length,
                  itemBuilder: (_, i) => ListingRow(
                      listing: shown[i], onTap: () => _open(context, shown[i])),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _chip(String label, bool on, VoidCallback tap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: on ? PhlioColors.textPrimary : PhlioColors.surface,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: tap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Text(label,
                    style: PhlioTypography.label.copyWith(
                        fontWeight: FontWeight.w700,
                        color: on
                            ? PhlioColors.background
                            : PhlioColors.textSecondary)),
              ),
            ),
          ),
        ),
      );
}
