// Booking flows for every Phlio Book vertical, in one bottom sheet:
//
//   slot   — date strip + time slots (courts, appointments); peak pricing
//            after `peak_after` for sports, in-clinic/video for doctors.
//   ride   — pickup → drop, fare estimate (bike taxi, auto, cabs).
//   trip   — travel date, class and passengers (flights, trains, buses).
//   ticket — ticket tier and quantity (concerts, events, festivals).
//   rsvp   — Attend (meetups).
//   external — opens the provider (movies and imported events).
//
// Bookings are Phlio demo bookings: fares and fees are estimates and no
// payment is taken (the sheet says so).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/typography.dart';
import '../../../../shared/content/content_surface.dart';
import '../../domain/entities/book_entities.dart';
import '../controllers/book_controller.dart';
import 'book_ui.dart';

Future<void> showBookingSheet(
    BuildContext context, BookListingEntity listing) async {
  if (listing.kind == 'external' ||
      (listing.sourceUrl != null && listing.kind != 'visit')) {
    final url = Uri.tryParse(listing.sourceUrl ?? '');
    if (url != null) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: PhlioColors.background,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => FractionallySizedBox(
        heightFactor: .92, child: _BookingSheet(listing: listing)),
  );
}

class _BookingSheet extends ConsumerStatefulWidget {
  const _BookingSheet({required this.listing});
  final BookListingEntity listing;

  @override
  ConsumerState<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends ConsumerState<_BookingSheet> {
  late DateTime _day;
  String? _slot; // "18:00"
  int _count = 1;
  int _option = 0; // class / tier / consult type / sport
  final _pickup = TextEditingController(text: 'Current location');
  final _drop = TextEditingController();
  bool _busy = false;

  BookListingEntity get l => widget.listing;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _day = l.startsAt?.toLocal() ?? DateTime(now.year, now.month, now.day);
    _drop.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _pickup.dispose();
    _drop.dispose();
    super.dispose();
  }

  // -- slots -------------------------------------------------------------------
  List<String> _slots() {
    int minutes(String hhmm) {
      final p = hhmm.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    }

    final open = minutes(l.metaString('open', '09:00'));
    final close = minutes(l.metaString('close', '21:00'));
    final step = (l.meta['slot_minutes'] as num?)?.toInt() ?? 60;
    final now = DateTime.now();
    final today = _day.year == now.year &&
        _day.month == now.month &&
        _day.day == now.day;
    final out = <String>[];
    for (var t = open; t + step <= close; t += step) {
      if (today && t <= now.hour * 60 + now.minute + 30) continue;
      out.add(
          '${(t ~/ 60).toString().padLeft(2, '0')}:${(t % 60).toString().padLeft(2, '0')}');
    }
    return out;
  }

  bool _peak(String slot) =>
      l.vertical == 'sports' &&
      slot.compareTo(l.metaString('peak_after', '99:99')) >= 0;

  // A stable pseudo-distance (km) for the ride estimate.
  double get _km {
    final text = '${_pickup.text}→${_drop.text}'.trim();
    return 2 + (text.hashCode.abs() % 180) / 10;
  }

  int get _total {
    switch (l.kind) {
      case 'slot':
        final base = l.priceMinMinorUnits;
        return _slot != null && _peak(_slot!)
            ? l.priceMaxMinorUnits * _count
            : base * _count;
      case 'ride':
        final base = (l.meta['base_fare'] as num?)?.toInt() ?? 30;
        final perKm = (l.meta['per_km'] as num?)?.toInt() ?? 10;
        return ((base + perKm * _km) * 100).round();
      case 'trip':
        final classes = l.metaMaps('classes');
        final fare = classes.isEmpty
            ? l.priceMinMinorUnits / 100
            : (classes[_option]['fare'] as num).toDouble();
        return (fare * 100 * _count).round();
      case 'ticket':
        final tiers = l.metaMaps('tiers');
        final price = tiers.isEmpty
            ? l.priceMinMinorUnits / 100
            : (tiers[_option]['price'] as num).toDouble();
        return (price * 100 * _count).round();
      default:
        return 0;
    }
  }

  bool get _ready => switch (l.kind) {
        'slot' => _slot != null,
        'ride' => _drop.text.trim().isNotEmpty,
        _ => true,
      };

  String get _cta => switch (l.kind) {
        'ride' => 'Book ${l.title.toLowerCase()}',
        'rsvp' => 'Attend',
        'trip' => 'Book ${_count > 1 ? '$_count seats' : 'seat'}',
        'ticket' => _count > 1 ? 'Get $_count tickets' : 'Get ticket',
        _ => l.vertical == 'doctor' ? 'Book appointment' : 'Book slot',
      };

  Future<void> _confirm() async {
    setState(() => _busy = true);
    final details = <String, String>{};
    DateTime? time;
    var participants = _count;
    switch (l.kind) {
      case 'slot':
        final p = _slot!.split(':');
        time = DateTime(2026, 1, 1, int.parse(p[0]), int.parse(p[1]));
        if (l.vertical == 'doctor') {
          details['consult'] =
              _option == 1 ? 'Video consult' : 'In-clinic visit';
          participants = 1;
        } else {
          final sports = l.metaList('sports');
          if (sports.isNotEmpty) details['sport'] = sports[_option];
          details['courts'] = '$_count';
          participants = 1;
        }
      case 'ride':
        final now = DateTime.now();
        time = DateTime(2026, 1, 1, now.hour, now.minute);
        details['pickup'] = _pickup.text.trim();
        details['drop'] = _drop.text.trim();
        details['fare_estimate'] = rupees(_total);
        participants = 1;
      case 'trip':
        final classes = l.metaMaps('classes');
        if (classes.isNotEmpty) details['class'] = '${classes[_option]['name']}';
        details['from'] = l.metaString('from_city');
        details['to'] = l.metaString('to_city');
        details['departs'] = l.metaString('depart');
      case 'ticket':
        final tiers = l.metaMaps('tiers');
        if (tiers.isNotEmpty) details['tier'] = '${tiers[_option]['name']}';
        if (l.startsAt != null) {
          final s = l.startsAt!.toLocal();
          time = DateTime(2026, 1, 1, s.hour, s.minute);
        }
      case 'rsvp':
        participants = 1;
        details['group'] = l.metaString('group');
        if (l.startsAt != null) {
          final s = l.startsAt!.toLocal();
          time = DateTime(2026, 1, 1, s.hour, s.minute);
        }
    }
    final result = await ref.read(bookRepositoryProvider).createBooking(
          listingId: l.id,
          date: DateTime(_day.year, _day.month, _day.day),
          time: time,
          participants: participants,
          details: details,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      success: (booking) {
        ref.invalidate(myBookingsProvider);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(l.kind == 'rsvp'
                ? "You're going to ${l.title} 🎉"
                : l.kind == 'ride'
                    ? 'Ride booked · ${l.title} is ${l.metaString('eta_min', '5')} min away'
                    : 'Booked ${l.title} · ${shortDate(_day)}')));
      },
      failure: (failure) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: ListView(padding: EdgeInsets.zero, children: [
          SizedBox(
            height: l.kind == 'ride' ? 150 : 210,
            child: Stack(fit: StackFit.expand, children: [
              ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                  child: BookImage(url: l.imageUrl, glyph: l.vertical)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, PhlioColors.background],
                    stops: [.45, 1],
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Material(
                  color: Colors.black.withValues(alpha: .5),
                  shape: const CircleBorder(),
                  child: InkResponse(
                    onTap: () => Navigator.pop(context),
                    child: const SizedBox.square(
                        dimension: 36,
                        child: Center(
                            child: BookGlyph('close',
                                size: 18, color: Colors.white))),
                  ),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.title,
                    style: PhlioTypography.headline
                        .copyWith(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Row(children: [
                  const BookGlyph('pin', size: 15),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        [l.venue, l.locationNote]
                            .where((e) => e.isNotEmpty)
                            .join(' · '),
                        style: PhlioTypography.caption),
                  ),
                  if (l.rating != null) RatingBadge(l.rating!),
                ]),
                const SizedBox(height: 12),
                Text(l.description,
                    style: PhlioTypography.body.copyWith(
                        color: PhlioColors.textSecondary, height: 1.4)),
                if (l.metaList('amenities').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final a in l.metaList('amenities')) BookChip(a),
                  ]),
                ],
                const SizedBox(height: 12),
                BookSocialProof(listing: l, ring: PhlioColors.background),
                const SizedBox(height: 8),
                EngagementRow(path: 'book/${l.id}'),
                const SizedBox(height: 8),
                ..._form(),
                if ((l.imageCredit ?? '').isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text('Photo: ${l.imageCredit}',
                      style: PhlioTypography.caption
                          .copyWith(fontSize: 10.5, color: PhlioColors.textMuted)),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
        ]),
      ),
      // Sticky total + CTA.
      Container(
        decoration: const BoxDecoration(
          color: PhlioColors.surface,
          border: Border(top: BorderSide(color: PhlioColors.borderSubtle)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
            child: l.kind == 'visit' ? _visitBar() : Row(children: [
              Expanded(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          l.kind == 'rsvp' || _total == 0
                              ? 'Free'
                              : l.kind == 'ride'
                                  ? '~${rupees(_total)}'
                                  : rupees(_total),
                          style: PhlioTypography.title.copyWith(
                              fontSize: 20, fontWeight: FontWeight.w800)),
                      Text('Demo booking · estimate, no payment taken',
                          style: PhlioTypography.caption.copyWith(fontSize: 10.5)),
                    ]),
              ),
              GradientButton(_cta,
                  height: 48, busy: _busy, onTap: _ready ? _confirm : null),
            ]),
          ),
        ),
      ),
    ]);
  }

  // -- Real places (OpenStreetMap): directions / call, no booking ----------------
  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String get _mapsUrl {
    final lat = l.meta['lat'], lon = l.meta['lon'];
    return lat != null && lon != null
        ? 'https://www.google.com/maps/search/?api=1&query=$lat,$lon'
        : 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent('${l.title} ${l.locationNote}')}';
  }

  Widget _visitBar() {
    final phone = l.metaString('phone');
    return Row(children: [
      Expanded(
        child: Text('Booked directly with the venue.\nData © OpenStreetMap contributors',
            style: PhlioTypography.caption.copyWith(fontSize: 11)),
      ),
      if (phone.isNotEmpty) ...[
        OutlinedButton(
          onPressed: () => _launch('tel:${phone.split(';').first.replaceAll(' ', '')}'),
          style: OutlinedButton.styleFrom(
              foregroundColor: PhlioColors.textPrimary,
              side: const BorderSide(color: PhlioColors.borderSubtle),
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
          child: const Text('Call'),
        ),
        const SizedBox(width: 8),
      ],
      GradientButton('Directions', height: 48, onTap: () => _launch(_mapsUrl)),
    ]);
  }

  List<Widget> _visitInfo() {
    Widget row(String glyph, String text, {VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              BookGlyph(glyph, size: 18, color: PhlioColors.brandPeach),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(text,
                      style: PhlioTypography.body
                          .copyWith(color: PhlioColors.textPrimary))),
            ]),
          ),
        );
    final hours = l.metaString('opening_hours');
    final phone = l.metaString('phone');
    final web = l.metaString('website');
    final km = l.meta['distance_km'];
    return [
      _label('Details'),
      row('pin', '${l.locationNote}${km != null ? ' · $km km away' : ''}',
          onTap: () => _launch(_mapsUrl)),
      if (hours.isNotEmpty) row('clock', hours),
      if (phone.isNotEmpty) row('users', phone),
      if (web.isNotEmpty) row('events', web, onTap: () => _launch(web)),
      if (l.metaString('osm_url').isNotEmpty)
        row('chevron_right', 'View on OpenStreetMap',
            onTap: () => _launch(l.metaString('osm_url'))),
    ];
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Text(text,
            style: PhlioTypography.label
                .copyWith(fontSize: 15, fontWeight: FontWeight.w800)),
      );

  Widget _choice(String label, bool on, VoidCallback tap, {String? sub}) =>
      Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: Material(
          color: on
              ? PhlioColors.brandViolet.withValues(alpha: .22)
              : PhlioColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
                color: on ? PhlioColors.brandViolet : PhlioColors.borderSubtle),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: tap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(label,
                    style: PhlioTypography.label.copyWith(
                        fontWeight: FontWeight.w700,
                        color: on
                            ? PhlioColors.textPrimary
                            : PhlioColors.textSecondary)),
                if (sub != null)
                  Text(sub,
                      style: PhlioTypography.caption.copyWith(fontSize: 11)),
              ]),
            ),
          ),
        ),
      );

  Widget _days(int count) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return SizedBox(
      height: 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final day = start.add(Duration(days: i));
          final on = day.year == _day.year &&
              day.month == _day.month &&
              day.day == _day.day;
          return GestureDetector(
            onTap: () => setState(() {
              _day = day;
              _slot = null;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 56,
              decoration: BoxDecoration(
                gradient: on ? PhlioColors.sunsetGradient : null,
                color: on ? null : PhlioColors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(i == 0 ? 'Today' : shortDate(day).split(',').first,
                    style: PhlioTypography.caption.copyWith(
                        fontSize: 11,
                        color: on
                            ? PhlioColors.textOnBrand
                            : PhlioColors.textMuted)),
                Text('${day.day}',
                    style: PhlioTypography.title.copyWith(
                        fontWeight: FontWeight.w800,
                        color: on
                            ? PhlioColors.textOnBrand
                            : PhlioColors.textPrimary)),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _stepper(String label, int min, int max) => Row(children: [
        Expanded(
            child: Text(label,
                style: PhlioTypography.label
                    .copyWith(fontSize: 15, fontWeight: FontWeight.w800))),
        _round('minus', _count > min ? () => setState(() => _count--) : null),
        SizedBox(
            width: 40,
            child: Center(
                child: Text('$_count',
                    style: PhlioTypography.title
                        .copyWith(fontWeight: FontWeight.w800)))),
        _round('plus', _count < max ? () => setState(() => _count++) : null),
      ]);

  Widget _round(String glyph, VoidCallback? tap) => Material(
        color: PhlioColors.surfaceElevated,
        shape: const CircleBorder(),
        child: InkResponse(
          onTap: tap,
          child: SizedBox.square(
            dimension: 36,
            child: Center(
                child: BookGlyph(glyph,
                    size: 18,
                    color: tap == null
                        ? PhlioColors.textMuted
                        : PhlioColors.textPrimary)),
          ),
        ),
      );

  String _unitLabel() {
    final unit = l.metaString('unit', 'court');
    return '${unit[0].toUpperCase()}${unit.substring(1)}s';
  }

  List<Widget> _form() {
    switch (l.kind) {
      case 'slot':
        final slots = _slots();
        final sports = l.metaList('sports');
        final doctor = l.vertical == 'doctor';
        return [
          if (!doctor && sports.length > 1) ...[
            _label('Sport'),
            Wrap(children: [
              for (final (i, s) in sports.indexed)
                _choice(s, _option == i, () => setState(() => _option = i)),
            ]),
          ],
          if (doctor && l.meta['video_consult'] == true) ...[
            _label('Consultation'),
            Wrap(children: [
              _choice('In-clinic', _option == 0,
                  () => setState(() => _option = 0)),
              _choice('Video consult', _option == 1,
                  () => setState(() => _option = 1)),
            ]),
          ],
          _label('Pick a date'),
          _days(7),
          _label(doctor ? 'Available slots' : 'Pick a slot'),
          if (slots.isEmpty)
            Text('No slots left today. Try another date.',
                style: PhlioTypography.caption)
          else
            Wrap(children: [
              for (final s in slots)
                _choice(clockText(s), _slot == s,
                    () => setState(() => _slot = s),
                    sub: _peak(s) ? 'Peak' : null),
            ]),
          if (!doctor) ...[
            const SizedBox(height: 16),
            _stepper(_unitLabel(), 1, 4),
          ],
        ];
      case 'ride':
        final seats = l.meta['seats'];
        return [
          _label('Where to?'),
          _field(_pickup, 'Pickup', 'pin', PhlioColors.success),
          const SizedBox(height: 8),
          _field(_drop, 'Drop location', 'pin', PhlioColors.danger,
              autofocus: true),
          const SizedBox(height: 14),
          Row(children: [
            BookChip('${l.metaString('eta_min', '5')} min away',
                color: PhlioColors.success),
            const SizedBox(width: 6),
            if (seats != null) BookChip('$seats seats'),
            const SizedBox(width: 6),
            if (_drop.text.trim().isNotEmpty)
              BookChip('~${_km.toStringAsFixed(1)} km'),
          ]),
        ];
      case 'trip':
        final classes = l.metaMaps('classes');
        return [
          _label('Travel date'),
          _days(14),
          if (classes.isNotEmpty) ...[
            _label('Class'),
            Wrap(children: [
              for (final (i, c) in classes.indexed)
                _choice('${c['name']}', _option == i,
                    () => setState(() => _option = i),
                    sub: rupees(((c['fare'] as num) * 100).round())),
            ]),
          ],
          const SizedBox(height: 12),
          _stepper('Passengers', 1, 6),
        ];
      case 'ticket':
        final tiers = l.metaMaps('tiers');
        return [
          if (l.startsAt != null) ...[
            _label('When'),
            Row(children: [
              DateBlock(l.startsAt!),
              const SizedBox(width: 12),
              Text('${shortDate(l.startsAt!)} · ${clock(l.startsAt!)}',
                  style: PhlioTypography.body),
            ]),
          ],
          if (tiers.isNotEmpty) ...[
            _label('Tickets'),
            Wrap(children: [
              for (final (i, t) in tiers.indexed)
                _choice('${t['name']}', _option == i,
                    () => setState(() => _option = i),
                    sub: (t['price'] as num) == 0
                        ? 'Free'
                        : rupees(((t['price'] as num) * 100).round())),
            ]),
          ],
          const SizedBox(height: 12),
          _stepper('Quantity', 1, 8),
        ];
      case 'rsvp':
        final cap = l.meta['capacity'];
        return [
          if (l.startsAt != null) ...[
            _label('When'),
            Row(children: [
              DateBlock(l.startsAt!),
              const SizedBox(width: 12),
              Expanded(
                child: Text('${shortDate(l.startsAt!)} · ${clock(l.startsAt!)}',
                    style: PhlioTypography.body),
              ),
            ]),
          ],
          _label('Hosted by ${l.metaString('group')}'),
          if (cap != null)
            Text('${l.goingCount} of $cap spots taken',
                style: PhlioTypography.body
                    .copyWith(color: PhlioColors.domainRooms)),
        ];
      case 'visit':
        return _visitInfo();
      default:
        return const [];
    }
  }

  Widget _field(TextEditingController controller, String hint, String glyph,
          Color dot,
          {bool autofocus = false}) =>
      Container(
        height: 48,
        decoration: BoxDecoration(
            color: PhlioColors.surface,
            borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const SizedBox(width: 14),
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              style: PhlioTypography.body.copyWith(color: PhlioColors.textPrimary),
              decoration: InputDecoration(
                hintText: hint,
                filled: false,
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
        ]),
      );
}

/// Your bookings, newest first.
Future<void> showMyBookings(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: PhlioColors.background,
      builder: (_) => const FractionallySizedBox(
          heightFactor: .85, child: _MyBookings()),
    );

class _MyBookings extends ConsumerWidget {
  const _MyBookings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(myBookingsProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Text('Your bookings',
            style: PhlioTypography.headline
                .copyWith(fontSize: 24, fontWeight: FontWeight.w800)),
      ),
      Expanded(
        child: bookings.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
              child: TextButton(
                  onPressed: () => ref.invalidate(myBookingsProvider),
                  child: const Text('Could not load bookings. Retry'))),
          data: (items) => items.isEmpty
              ? Center(
                  child: Text('Nothing booked yet.',
                      style: PhlioTypography.body))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final b = items[i];
                    final details = b.details.entries
                        .where((e) => e.key != 'fare_estimate')
                        .map((e) => e.value)
                        .where((v) => v.isNotEmpty)
                        .join(' · ');
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: PhlioColors.surface,
                          borderRadius: BorderRadius.circular(18)),
                      child: Row(children: [
                        SizedBox(
                            width: 60,
                            height: 60,
                            child: BookImage(
                                url: b.imageUrl,
                                glyph: b.vertical ?? 'ticket',
                                radius: 14)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(b.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: PhlioTypography.label.copyWith(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800)),
                                Text(
                                    '${shortDate(b.date)}${b.time != null ? ' · ${clock(b.time!)}' : ''}',
                                    style: PhlioTypography.caption.copyWith(
                                        color: PhlioColors.brandPeach)),
                                if (details.isNotEmpty)
                                  Text(details,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: PhlioTypography.caption),
                              ]),
                        ),
                        const SizedBox(width: 8),
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                  b.estimatedTotalMinMinorUnits == 0
                                      ? 'Free'
                                      : b.displayTotal,
                                  style: PhlioTypography.label
                                      .copyWith(fontWeight: FontWeight.w800)),
                              BookChip(
                                  b.status[0].toUpperCase() +
                                      b.status.substring(1),
                                  color: PhlioColors.success),
                            ]),
                      ]),
                    );
                  }),
        ),
      ),
    ]);
  }
}
