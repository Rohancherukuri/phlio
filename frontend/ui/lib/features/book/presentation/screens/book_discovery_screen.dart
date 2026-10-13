import 'package:flutter/material.dart';
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

  static const icons = {
    'Movies': Icons.movie_outlined,
    'Navratri': Icons.celebration_outlined,
    'Music': Icons.music_note_outlined,
    'Plays': Icons.theater_comedy_outlined,
    'Comedy': Icons.mic_none,
    'Workshops': Icons.palette_outlined,
    'Sports': Icons.sports_basketball_outlined,
    'Experiences': Icons.explore_outlined
  };

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(listingsControllerProvider);
    return Scaffold(
        appBar: AppBar(
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
                          Text('Hyderabad',
                              style: TextStyle(
                                  color: Color(0xFFFFB58F), fontSize: 15))
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
              SizedBox(
                  height: 100,
                  child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final entry
                            in {'All': Icons.apps_rounded, ...icons}.entries)
                          SizedBox(
                              width: 88,
                              child: InkWell(
                                  onTap: () =>
                                      setState(() => section = entry.key),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                                color: section == entry.key
                                                    ? const Color(0xFF8D78FF)
                                                    : const Color(0xFF182231),
                                                borderRadius:
                                                    BorderRadius.circular(16)),
                                            child: Icon(entry.value, size: 25)),
                                        const SizedBox(height: 6),
                                        Text(entry.key,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style:
                                                const TextStyle(fontSize: 12)),
                                      ]))),
                      ])),
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
                                  height: 330 +
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

Future<void> openBookDetails(BuildContext context, BookListingEntity listing) =>
    showModalBottomSheet<void>(
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
                  const SizedBox(height: 16),
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
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Could not open the provider. Please try again.')));
                        }),
                ]))));
