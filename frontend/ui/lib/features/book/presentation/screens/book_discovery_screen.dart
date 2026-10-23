import 'package:phlio/shared/widgets/notifications_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/config/app_config.dart';
import '../../../../shared/content/content_surface.dart';
import '../../domain/entities/book_entities.dart';
import '../controllers/book_controller.dart';

class BookDiscoveryScreen extends ConsumerStatefulWidget {
  const BookDiscoveryScreen({this.explore = false, super.key});
  final bool explore;
  @override
  ConsumerState<BookDiscoveryScreen> createState() =>
      _BookDiscoveryScreenState();
}

class _BookDiscoveryScreenState extends ConsumerState<BookDiscoveryScreen> {
  String section = 'All', query = '';
  final banners = PageController(viewportFraction: .92);
  @override
  void dispose() {
    banners.dispose();
    super.dispose();
  }

  /// Category → two-tone line illustration in
  /// `assets/images/book_categories/<slug>.svg` (light line + coral accent).
  static const icons = {
    'Movies': 'movies',
    'Navratri': 'navratri',
    'Music': 'music',
    'Plays': 'plays',
    'Comedy': 'comedy',
    'Workshops': 'workshops',
    'Sports': 'sports',
    'Experiences': 'experiences',
  };

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(listingsControllerProvider);
    return Scaffold(
        appBar: AppBar(
            actions: const [PhlioNotificationsButton()],
            title: Text(widget.explore ? 'Explore Phlio Book' : 'Phlio Book')),
        body: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(listingsControllerProvider);
              await ref.read(listingsControllerProvider.future);
            },
            child:
                ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('It all starts here.',
                            style: TextStyle(
                                fontSize: 27, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        const Row(children: [
                          Icon(Icons.location_on_outlined,
                              size: 18, color: Color(0xFFFFB58F)),
                          SizedBox(width: 6),
                          Expanded(
                              child: Text('Hyderabad',
                                  style: TextStyle(
                                      color: Color(0xFFFFB58F), fontSize: 15)))
                        ]),
                        if (widget.explore)
                          Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: TextField(
                                  onChanged: (value) => setState(
                                      () => query = value.toLowerCase().trim()),
                                  decoration: const InputDecoration(
                                      prefixIcon: Icon(Icons.search),
                                      hintText: 'Movies, events, venues…'))),
                      ])),
              _CategoryStrip(
                  categories: const {'All': 'all', ...icons},
                  selected: section,
                  onSelected: (value) => setState(() => section = value)),
              data.when(
                  loading: () => const Padding(
                      padding: EdgeInsets.all(50),
                      child: Center(child: CircularProgressIndicator())),
                  error: (_, __) => Center(
                      child: TextButton(
                          onPressed: () =>
                              ref.invalidate(listingsControllerProvider),
                          child:
                              const Text('Could not load experiences. Retry'))),
                  data: (all) {
                    final items = all
                        .where((l) =>
                            l.imageUrl != null &&
                            (section == 'All' || l.tags.contains(section)) &&
                            ('${l.title} ${l.venue} ${l.tags.join(' ')}'
                                .toLowerCase()
                                .contains(query)))
                        .toList();
                    if (items.isEmpty)
                      return const Padding(
                          padding: EdgeInsets.all(40),
                          child: Text(
                              'No listings match this selection. Try another category.'));
                    final featured = items
                        .where((l) => !l.tags.contains('Movies'))
                        .take(5)
                        .toList();
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!widget.explore &&
                              section == 'All' &&
                              featured.isNotEmpty)
                            SizedBox(
                                height: 220,
                                child: PageView.builder(
                                    controller: banners,
                                    itemCount: featured.length,
                                    itemBuilder: (_, i) => Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            4, 8, 8, 16),
                                        child: _banner(featured[i])))),
                          for (final tag
                              in section == 'All' ? icons.keys : [section])
                            if (items.any((l) => l.tags.contains(tag))) ...[
                              Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 16, 20, 12),
                                  child: Row(children: [
                                    Expanded(
                                        child: Text(
                                            tag == 'Movies'
                                                ? 'Movies to discover'
                                                : tag == 'Navratri'
                                                    ? 'Navratri celebrations'
                                                    : tag,
                                            style: const TextStyle(
                                                fontSize: 21,
                                                fontWeight: FontWeight.w700))),
                                    if (section == 'All')
                                      TextButton(
                                          onPressed: () =>
                                              setState(() => section = tag),
                                          child: const Text('See all')),
                                  ])),
                              SizedBox(
                                  height: 354 +
                                      MediaQuery.textScalerOf(context)
                                          .scale(80),
                                  child: ListView.separated(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 20),
                                      scrollDirection: Axis.horizontal,
                                      itemCount: items
                                          .where((l) => l.tags.contains(tag))
                                          .length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(width: 14),
                                      itemBuilder: (_, i) => SizedBox(
                                          width: 180,
                                          child: _poster(items
                                              .where(
                                                  (l) => l.tags.contains(tag))
                                              .elementAt(i))))),
                            ],
                        ]);
                  }),
            ])));
  }

  Widget image(BookListingEntity listing, {BoxFit fit = BoxFit.cover}) =>
      Image.network(AppConfig.mediaUrl(listing.imageUrl!),
          fit: fit,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => const ColoredBox(
              color: Color(0xFF182231),
              child: Center(child: Text('Image unavailable'))));

  Widget _banner(BookListingEntity listing) => InkWell(
      onTap: () => openBookDetails(context, listing),
      child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(fit: StackFit.expand, children: [
            image(listing),
            const DecoratedBox(
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87]))),
            Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Text(listing.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white))),
          ])));

  Widget _poster(BookListingEntity listing) => ContentSurface(
      platform: 'book',
      contentId: listing.id,
      child: InkWell(
          onTap: () => openBookDetails(context, listing),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(height: 230, child: image(listing))),
            const SizedBox(height: 8),
            if (listing.startsAt != null)
              Text(_date(listing.startsAt!),
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFFFFB58F))),
            Text(listing.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            Text(listing.venue,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xFF858D9E))),
            Text(listing.displayPrice,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
          ])));
}

String _date(DateTime date) {
  final local = date.toLocal();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

Future<void> openBookDetails(
    BuildContext context, BookListingEntity listing) async {
  trackContentView(context, 'book/${listing.id}');
  await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
          heightFactor: .85,
          child: SafeArea(
              top: false,
              child: ListView(padding: const EdgeInsets.all(20), children: [
                if (listing.imageUrl != null)
                  ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.network(
                          AppConfig.mediaUrl(listing.imageUrl!),
                          height: 300,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox(
                              height: 80,
                              child:
                                  Center(child: Text('Image unavailable'))))),
                const SizedBox(height: 12),
                EngagementRow(path: 'book/${listing.id}'),
                const SizedBox(height: 12),
                Text(listing.title,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('${listing.venue} · ${listing.locationNote}'),
                if (listing.startsAt != null) Text(_date(listing.startsAt!)),
                const SizedBox(height: 12),
                Text(listing.description),
                const SizedBox(height: 12),
                Text(listing.displayPrice),
                const SizedBox(height: 20),
                if (listing.sourceUrl != null)
                  FilledButton.icon(
                      icon: const Icon(Icons.open_in_new),
                      label: Text(
                          'Check tickets on ${listing.sourceName ?? 'provider'}'),
                      onPressed: () async {
                        final opened = await launchUrl(
                            Uri.parse(listing.sourceUrl!),
                            mode: LaunchMode.externalApplication);
                        if (!opened && context.mounted)
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text(
                                  'Could not open the provider. Please try again.')));
                      }),
              ]))));
}

/// Category strip: borderless two-tone illustrations over a label, the
/// selected one marked by a bold label and a short coral underline.
class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip(
      {required this.categories,
      required this.selected,
      required this.onSelected});
  final Map<String, String> categories;
  final String selected;
  final ValueChanged<String> onSelected;

  static const _accent = Color(0xFFFF6F7D);

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
    return Container(
      height: 96 + 16 * scale,
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x14FFFFFF)))),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (final entry in categories.entries)
            _CategoryItem(
              label: entry.key,
              asset: 'assets/images/book_categories/${entry.value}.svg',
              active: entry.key == selected,
              onTap: () => onSelected(entry.key),
            ),
        ],
      ),
    );
  }
}

class _CategoryItem extends StatelessWidget {
  const _CategoryItem(
      {required this.label,
      required this.asset,
      required this.active,
      required this.onTap});
  final String label, asset;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: active,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 84,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AnimatedScale(
                  scale: active ? 1.08 : 1,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: AnimatedOpacity(
                    opacity: active ? 1 : .82,
                    duration: const Duration(milliseconds: 180),
                    child: SvgPicture.asset(asset,
                        width: 40, height: 40, excludeFromSemantics: true),
                  ),
                ),
                const SizedBox(height: 10),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        letterSpacing: .1,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active
                            ? const Color(0xFFF7F7FA)
                            : const Color(0xFFA9B0BE))),
                const SizedBox(height: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  width: active ? 22 : 0,
                  height: 3,
                  decoration: BoxDecoration(
                      color: _CategoryStrip._accent,
                      borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),
      );
}
