// Social Explore → Posts.
//
// A categorised discovery surface modelled on a news-style "Explore" page:
//
//   [For you] [Trending] [News] [Sports] [Entertainment] …   ← category tabs
//
//   Today on Phlio
//   <headline from the topic's top post>
//   (●●●) 18h ago · Entertainment · 504 posts               ← author stack
//   ───────────────────────────────────────────────
//   #topic                                          ⋯
//   86 posts · Trending in Music
//
// Topics come from post hashtags; categories are derived from tags and
// text with a small keyword map, so the page works with today's API and
// needs no backend change. Tapping a headline or trend opens every post in
// that topic.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../design_system/colors.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../shared/content/social_comments_sheet.dart';
import '../../../profile/presentation/controllers/avatar_controller.dart';
import '../../../profile/presentation/widgets/profile_posts.dart'
    show publicProfileProvider;
import '../../domain/entities/post_entity.dart';
import '../controllers/feed_controller.dart';
import 'post_card.dart';

/// Topics the viewer dismissed with "Not interested" (session-scoped).
final _hiddenTopicsProvider = StateProvider<Set<String>>((ref) => {});

const _forYou = 'For you';
const _trending = 'Trending';
const _fallbackCategory = 'Lifestyle';

/// Keyword → category map used to file posts under a tab.
const Map<String, List<String>> _categoryKeywords = {
  'News': ['news', 'politics', 'world', 'breaking', 'election', 'economy'],
  'Sports': [
    'sport',
    'sports',
    'cricket',
    'football',
    'soccer',
    'nba',
    'ipl',
    'tennis',
    'f1',
    'fitness',
    'gym',
    'running'
  ],
  'Entertainment': [
    'entertainment',
    'movie',
    'movies',
    'film',
    'tv',
    'series',
    'netflix',
    'celebrity',
    'bollywood',
    'hollywood',
    'anime',
    'meme',
    'memes',
    'comedy'
  ],
  'Music': ['music', 'song', 'songs', 'album', 'concert', 'spotify', 'band'],
  'Tech': [
    'tech',
    'ai',
    'coding',
    'code',
    'startup',
    'gadgets',
    'flutter',
    'programming',
    'science',
    'design'
  ],
  'Gaming': ['gaming', 'game', 'games', 'esports', 'playstation', 'xbox'],
  'Food': ['food', 'recipe', 'cooking', 'coffee', 'restaurant', 'foodie'],
  'Travel': ['travel', 'trip', 'beach', 'mountains', 'wanderlust', 'nature'],
  'Fashion': ['fashion', 'style', 'ootd', 'beauty', 'makeup'],
  'Art': ['art', 'photography', 'drawing', 'painting', 'illustration'],
};

String _categoryOf(PostEntity post) {
  final words = {
    for (final tag in post.tags) tag.toLowerCase().replaceAll('#', ''),
    ...post.text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length > 1),
  };
  for (final entry in _categoryKeywords.entries) {
    if (entry.value.any(words.contains)) return entry.key;
  }
  return _fallbackCategory;
}

class _Topic {
  _Topic(this.tag);
  final String tag;
  final posts = <PostEntity>[];

  String get category {
    final counts = <String, int>{};
    for (final post in posts) {
      final c = _categoryOf(post);
      counts[c] = (counts[c] ?? 0) + 1;
    }
    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked.isEmpty ? _fallbackCategory : ranked.first.key;
  }

  DateTime get latest =>
      posts.map((p) => p.createdAt).reduce((a, b) => a.isAfter(b) ? a : b);

  PostEntity get lead =>
      ([...posts]..sort((a, b) => (b.likeCount + b.commentCount)
              .compareTo(a.likeCount + a.commentCount)))
          .first;

  List<String> get authors => [
        for (final id in posts.map((p) => p.authorId).toSet()) id
      ].take(3).toList();

  /// Volume and engagement, decayed by age in hours.
  double get score {
    final engagement =
        posts.fold<int>(0, (sum, p) => sum + p.likeCount + p.commentCount * 2);
    final hours = DateTime.now().difference(latest).inMinutes / 60;
    return (posts.length * 3 + engagement) / (1 + hours / 24);
  }
}

List<_Topic> _topics(List<PostEntity> posts, Set<String> hidden) {
  final byTag = <String, _Topic>{};
  for (final post in posts) {
    for (final raw in post.tags.toSet()) {
      final tag = raw.toLowerCase().replaceAll('#', '').trim();
      if (tag.isEmpty || hidden.contains(tag)) continue;
      byTag.putIfAbsent(tag, () => _Topic(tag)).posts.add(post);
    }
  }
  return byTag.values.toList()..sort((a, b) => b.score.compareTo(a.score));
}

String _postsLabel(int n) => n == 1 ? '1 post' : '$n posts';

class SocialExplorePostsView extends ConsumerStatefulWidget {
  const SocialExplorePostsView(
      {required this.posts,
      required this.query,
      required this.onRefresh,
      super.key});
  final List<PostEntity> posts;
  final String query;
  final Future<void> Function() onRefresh;

  @override
  ConsumerState<SocialExplorePostsView> createState() =>
      _SocialExplorePostsViewState();
}

class _SocialExplorePostsViewState
    extends ConsumerState<SocialExplorePostsView> {
  String tab = _forYou;

  @override
  Widget build(BuildContext context) {
    final hidden = ref.watch(_hiddenTopicsProvider);
    final topics = _topics(widget.posts, hidden);

    // Category tabs, busiest first, only when they have posts.
    final counts = <String, int>{};
    for (final post in widget.posts) {
      final c = _categoryOf(post);
      counts[c] = (counts[c] ?? 0) + 1;
    }
    final categories = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final tabs = [_forYou, _trending, ...categories];
    if (!tabs.contains(tab)) tab = _forYou;

    if (widget.query.isNotEmpty) {
      final matches = widget.posts
          .where((p) => '${p.text} ${p.tags.join(' ')}'
              .toLowerCase()
              .contains(widget.query))
          .toList();
      return RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(PhlioSpacing.lg),
              children: [
                if (matches.isEmpty)
                  const _EmptyNote('No posts match your search.')
                else
                  for (final post in matches) _ExplorePostCard(post: post),
              ]));
    }

    return Column(children: [
      _CategoryTabs(
          tabs: tabs,
          selected: tab,
          onSelected: (value) => setState(() => tab = value)),
      Expanded(
          child: RefreshIndicator(
              onRefresh: widget.onRefresh,
              child: ListView(
                  key: PageStorageKey('explore-posts-$tab'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: PhlioSpacing.xxxl),
                  children: _sections(topics)))),
    ]);
  }

  List<Widget> _sections(List<_Topic> topics) {
    if (widget.posts.isEmpty) {
      return const [_EmptyNote('No posts to explore yet.')];
    }
    switch (tab) {
      case _forYou:
        final headlines = topics.take(3).toList();
        final trends = topics.skip(3).take(6).toList();
        final latest = [...widget.posts]
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return [
          if (headlines.isNotEmpty) ...[
            const _SectionTitle("Today on Phlio"),
            ..._divided([for (final t in headlines) _TopicHeadline(topic: t)]),
          ],
          if (trends.isNotEmpty) ...[
            const _Divider(),
            ..._divided([for (final t in trends) _TrendRow(topic: t)]),
          ],
          const _SectionTitle('Latest posts'),
          for (final post in latest.take(20)) _ExplorePostCard(post: post),
        ];
      case _trending:
        if (topics.isEmpty) {
          return const [_EmptyNote('Nothing is trending yet.')];
        }
        return _divided([
          for (final (i, t) in topics.take(30).indexed)
            _TrendRow(topic: t, rank: i + 1),
        ]);
      default:
        final inCategory = topics.where((t) => t.category == tab).toList();
        final posts = widget.posts.where((p) => _categoryOf(p) == tab).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return [
          if (inCategory.isNotEmpty) ...[
            _SectionTitle('Today in $tab'),
            ..._divided(
                [for (final t in inCategory.take(5)) _TopicHeadline(topic: t)]),
            const _Divider(),
          ],
          _SectionTitle('$tab posts'),
          if (posts.isEmpty) const _EmptyNote('No posts here yet.'),
          for (final post in posts) _ExplorePostCard(post: post),
        ];
    }
  }

  List<Widget> _divided(List<Widget> rows) => [
        for (final (i, row) in rows.indexed) ...[
          if (i > 0) const _Divider(),
          row,
        ]
      ];
}

/// Underlined text tabs, scrollable, like a news app's section bar.
class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs(
      {required this.tabs, required this.selected, required this.onSelected});
  final List<String> tabs;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Container(
        height: 46,
        decoration: const BoxDecoration(
            border:
                Border(bottom: BorderSide(color: PhlioColors.borderSubtle))),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.sm),
          itemCount: tabs.length,
          separatorBuilder: (_, __) => const SizedBox(width: 4),
          itemBuilder: (_, i) {
            final active = tabs[i] == selected;
            return InkWell(
              onTap: () => onSelected(tabs[i]),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                // Horizontal lists leave width unbounded. Measure the label
                // before stretching the underline to the same finite width.
                child: IntrinsicWidth(
                    child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(tabs[i],
                        textAlign: TextAlign.center,
                        style: PhlioTypography.bodyStrong.copyWith(
                            fontSize: 15,
                            color: active
                                ? PhlioColors.textPrimary
                                : PhlioColors.textMuted)),
                    const SizedBox(height: 10),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 3,
                      decoration: BoxDecoration(
                          color: active
                              ? PhlioColors.brandOrange
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ],
                )),
              ),
            );
          },
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(
          PhlioSpacing.lg, PhlioSpacing.xl, PhlioSpacing.lg, PhlioSpacing.xs),
      child: Text(text, style: PhlioTypography.headline));
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => const Divider(
      height: 1,
      thickness: 1,
      indent: PhlioSpacing.lg,
      endIndent: PhlioSpacing.lg,
      color: PhlioColors.borderSubtle);
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(PhlioSpacing.xxl),
      child:
          Text(text, textAlign: TextAlign.center, style: PhlioTypography.body));
}

/// Headline row: lead post as the title, then a stack of up to three
/// authors and "18h ago · Category · N posts".
class _TopicHeadline extends StatelessWidget {
  const _TopicHeadline({required this.topic});
  final _Topic topic;

  @override
  Widget build(BuildContext context) {
    final lead = topic.lead.text.trim().split('\n').first;
    return InkWell(
      onTap: () => _openTopic(context, topic),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: PhlioSpacing.lg, vertical: PhlioSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(lead.isEmpty ? '#${topic.tag}' : lead,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: PhlioTypography.title.copyWith(height: 1.3)),
            const SizedBox(height: PhlioSpacing.sm),
            Row(children: [
              _AuthorStack(authorIds: topic.authors),
              const SizedBox(width: PhlioSpacing.sm),
              Expanded(
                child: Text(
                    '${timeago.format(topic.latest)} · ${topic.category} · ${_postsLabel(topic.posts.length)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PhlioTypography.caption
                        .copyWith(color: PhlioColors.textMuted, fontSize: 13)),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Trend row: "#tag", post count and "Trending in Category", with a ⋯ menu.
class _TrendRow extends ConsumerWidget {
  const _TrendRow({required this.topic, this.rank});
  final _Topic topic;
  final int? rank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = PhlioTypography.caption
        .copyWith(color: PhlioColors.textMuted, fontSize: 13);
    return InkWell(
      onTap: () => _openTopic(context, topic),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            PhlioSpacing.lg, PhlioSpacing.md, PhlioSpacing.xs, PhlioSpacing.md),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${rank == null ? '' : '$rank · '}Trending in ${topic.category}',
                    style: muted),
                const SizedBox(height: 2),
                Text('#${topic.tag}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PhlioTypography.title),
                const SizedBox(height: 2),
                Text(_postsLabel(topic.posts.length), style: muted),
              ],
            ),
          ),
          IconButton(
            tooltip: 'More',
            icon: const Icon(Icons.more_horiz_rounded,
                color: PhlioColors.textMuted),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              useRootNavigator: true,
              builder: (sheet) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ListTile(
                    leading: const Icon(Icons.sentiment_dissatisfied_outlined),
                    title: const Text('Not interested in this'),
                    onTap: () {
                      Navigator.pop(sheet);
                      ref.read(_hiddenTopicsProvider.notifier).state = {
                        ...ref.read(_hiddenTopicsProvider),
                        topic.tag
                      };
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.tag_rounded),
                    title: Text('See posts in #${topic.tag}'),
                    onTap: () {
                      Navigator.pop(sheet);
                      _openTopic(context, topic);
                    },
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Up to three overlapping author avatars, ringed against the background.
class _AuthorStack extends StatelessWidget {
  const _AuthorStack({required this.authorIds});
  final List<String> authorIds;
  static const double size = 26;

  @override
  Widget build(BuildContext context) {
    if (authorIds.isEmpty) return const SizedBox.shrink();
    const step = size * .62;
    final ring = Theme.of(context).scaffoldBackgroundColor;
    return SizedBox(
      width: size + step * (authorIds.length - 1),
      height: size,
      child: Stack(children: [
        for (var i = authorIds.length - 1; i >= 0; i--)
          Positioned(
            left: i * step,
            child: Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
              child: IgnorePointer(
                  child: _ProfileAvatar(id: authorIds[i], size: size - 3)),
            ),
          ),
      ]),
    );
  }
}

class _ProfileAvatar extends ConsumerWidget {
  const _ProfileAvatar({required this.id, required this.size});
  final String id;
  final double size;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(publicProfileProvider(id)).valueOrNull;
    return ContentAuthorAvatar(
        author: id,
        name: profile?['full_name'] as String? ?? id,
        imageUrl: profile?['avatar_url'] as String?,
        size: size);
  }
}

class _ExplorePostCard extends ConsumerWidget {
  const _ExplorePostCard({required this.post});
  final PostEntity post;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.fromLTRB(
            PhlioSpacing.lg, PhlioSpacing.sm, PhlioSpacing.lg, PhlioSpacing.sm),
        child: PostCard(
          post: post,
          authorName: post.authorId,
          onToggleLike: () =>
              ref.read(socialRepositoryProvider).toggleLike(post.id),
          onOpenComments: () => showSocialComments(context, post.id),
        ),
      );
}

void _openTopic(BuildContext context, _Topic topic) {
  final posts = [...topic.posts]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('#${topic.tag}', style: PhlioTypography.title),
          Text('${topic.category} · ${_postsLabel(posts.length)}',
              style: PhlioTypography.caption),
        ]),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: PhlioSpacing.sm),
        children: [for (final post in posts) _ExplorePostCard(post: post)],
      ),
    ),
  ));
}
