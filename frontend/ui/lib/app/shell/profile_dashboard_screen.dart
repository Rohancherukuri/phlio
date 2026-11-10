// Profile dashboard — "Your dashboard": insights about your content and
// followers, opened from the profile page.
//
// Every number is real: GET /profile/insights computes views, interactions,
// new followers and content shared from the graph for the chosen range
// (7 / 30 / 90 days), with the period before for the trend arrows.
//
// Interactive: tap a metric to open its chart (drag to scrub any day), the
// interactions row breaks down into likes/saves/shares/reposts/comments,
// followers show when your audience is active. Foxy introduces the page,
// cheers when things go up, and hosts the Monthly recap and tips.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../design_system/colors.dart';
import '../../design_system/typography.dart';
import '../../design_system/widgets/foxy_puppet.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';
import '../config/app_config.dart';
import '../platform/phlio_platform.dart';
import 'platform_home_screen.dart' show switchPlatform;

// -- Data ---------------------------------------------------------------------------------

final _insightsProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, days) async {
  final response = await getIt<ApiClient>()
      .dio
      .get('/profile/insights', queryParameters: {'days': days});
  return (response.data as Map).cast<String, dynamic>();
});

/// Per-user dashboard preferences (intro seen, insights off, banner closed),
/// kept in a small file like the tour's seen-flag.
class _Prefs {
  _Prefs(this.userId);
  final String userId;
  bool introSeen = false, off = false, bannerClosed = false;

  Future<File?> _file() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final safe = userId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      return File('${dir.path}${Platform.pathSeparator}insights_$safe.json');
    } catch (_) {
      return null;
    }
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (f == null || !f.existsSync()) return;
      final m = jsonDecode(await f.readAsString()) as Map;
      introSeen = m['intro_seen'] == true;
      off = m['off'] == true;
      bannerClosed = m['banner_closed'] == true;
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      final f = await _file();
      await f?.writeAsString(jsonEncode(
          {'intro_seen': introSeen, 'off': off, 'banner_closed': bannerClosed}));
    } catch (_) {}
  }
}

enum _Metric {
  views('Views', 'views', Icons.visibility_outlined),
  interactions('Interactions', 'interactions', Icons.favorite_border_rounded),
  followers('New followers', 'followers', Icons.person_add_alt_outlined),
  content('Content you shared', null, Icons.grid_view_rounded);

  const _Metric(this.label, this.seriesKey, this.icon);
  final String label;
  final String? seriesKey;
  final IconData icon;
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

String _shortDate(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : '${_months[d.month - 1]} ${d.day}';
}

String _compact(num n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 10000) return '${(n / 1000).toStringAsFixed(0)}K';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

String _hour(int h) =>
    h == 0 ? '12 am' : h < 12 ? '$h am' : h == 12 ? '12 pm' : '${h - 12} pm';

// -- Screen ------------------------------------------------------------------------------

class ProfileDashboardScreen extends ConsumerStatefulWidget {
  const ProfileDashboardScreen({required this.postCount, super.key});

  final int postCount;

  @override
  ConsumerState<ProfileDashboardScreen> createState() =>
      _ProfileDashboardScreenState();
}

class _ProfileDashboardScreenState
    extends ConsumerState<ProfileDashboardScreen> {
  int _days = 30;
  _Metric? _open;
  _Prefs? _prefs;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authControllerProvider).valueOrNull;
    final prefs = _Prefs(user?.id ?? 'me');
    prefs.load().then((_) {
      if (!mounted) return;
      setState(() => _prefs = prefs);
      if (!prefs.introSeen) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _intro());
      }
    });
  }

  Future<void> _intro() async {
    final prefs = _prefs!;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PhlioColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => const _IntroSheet(),
    );
    prefs.introSeen = true;
    if (result == false) prefs.off = true;
    await prefs.save();
    if (mounted) setState(() {});
  }

  Future<void> _setOff(bool off) async {
    final prefs = _prefs;
    if (prefs == null) return;
    HapticFeedback.selectionClick();
    setState(() => prefs.off = off);
    await prefs.save();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = _prefs;
    return Scaffold(
      backgroundColor: PhlioColors.background,
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Your dashboard'),
        actions: [
          IconButton(
            tooltip: 'Insights settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: prefs == null
                ? null
                : () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      builder: (sheet) => SafeArea(
                        child: SwitchListTile(
                          value: !prefs.off,
                          title: const Text('Insights'),
                          subtitle: const Text(
                              'Views, interactions and follower stats on your dashboard'),
                          onChanged: (on) {
                            Navigator.pop(sheet);
                            _setOff(!on);
                          },
                        ),
                      ),
                    ),
          ),
        ],
      ),
      body: prefs == null
          ? const Center(child: CircularProgressIndicator())
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 380),
              switchInCurve: Curves.easeOutCubic,
              child: prefs.off
                  ? _InsightsOff(
                      key: const ValueKey('off'),
                      onTurnOn: () => _setOff(false))
                  : _body(prefs),
            ),
    );
  }

  Widget _body(_Prefs prefs) {
    final async = ref.watch(_insightsProvider(_days));
    final data = async.valueOrNull;
    return RefreshIndicator(
      key: const ValueKey('on'),
      onRefresh: () => ref.refresh(_insightsProvider(_days).future),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 12, 4),
            child: Row(children: [
              Text('Insights', style: PhlioTypography.headline),
              const Spacer(),
              _RangePicker(
                days: _days,
                label: data == null
                    ? '…'
                    : '${_shortDate(data['start'] as String)} - ${_shortDate(data['end'] as String)}',
                onChanged: (d) => setState(() {
                  _days = d;
                  _open = null;
                }),
              ),
            ]),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            child: prefs.bannerClosed
                ? const SizedBox(width: double.infinity)
                : _Banner(
                    onClose: () async {
                      setState(() => prefs.bannerClosed = true);
                      await prefs.save();
                    },
                    onTurnOff: () => _setOff(true),
                  ),
          ),
          if (async.hasError && data == null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: TextButton(
                  onPressed: () => ref.invalidate(_insightsProvider(_days)),
                  child: const Text('Could not load insights. Retry'),
                ),
              ),
            )
          else if (data == null)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _FoxyCoach(data: data),
            for (final (i, metric) in _Metric.values.indexed)
              _Staggered(
                index: i,
                child: _MetricRow(
                  metric: metric,
                  data: data,
                  open: _open == metric,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _open = _open == metric ? null : metric);
                  },
                ),
              ),
            if ((data['top_content'] as List).isNotEmpty) ...[
              const _Divider(),
              _section('Top content'),
              _TopContent(items: (data['top_content'] as List).cast()),
            ],
          ],
          const _Divider(),
          _section('Your tools'),
          _ToolRow(
            icon: Icons.history_rounded,
            title: 'Monthly recap',
            subtitle: 'See what you made happen last month.',
            isNew: true,
            onTap: data == null ? null : () => _showRecap(context, data),
          ),
          _ToolRow(
            icon: Icons.school_outlined,
            title: 'Best practices',
            isNew: true,
            onTap: () => _showTips(context, data),
          ),
          _ToolRow(
            icon: Icons.lightbulb_outline_rounded,
            title: 'Inspiration',
            isNew: true,
            onTap: data == null ? null : () => _showInspiration(context, data),
          ),
          _ToolRow(
            icon: Icons.north_east_rounded,
            title: 'Trending audio',
            isNew: true,
            onTap: () {
              switchPlatform(context, PhlioPlatform.stream);
              context.go('/home');
            },
          ),
          const _Divider(),
          _section('Professional tools'),
          _ToolRow(
            icon: Icons.payments_outlined,
            title: 'Monetization',
            onTap: () => _showMonetization(context),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
        child: Text(title, style: PhlioTypography.headline),
      );
}

// -- Pieces --------------------------------------------------------------------------------

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Divider(height: 1, color: PhlioColors.borderSubtle),
      );
}

/// Rows slide in one after another the first time they appear.
class _Staggered extends StatelessWidget {
  const _Staggered({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + index * 90),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}

class _RangePicker extends StatelessWidget {
  const _RangePicker(
      {required this.days, required this.label, required this.onChanged});
  final int days;
  final String label;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Date range',
      initialValue: days,
      onSelected: onChanged,
      color: PhlioColors.surfaceElevated,
      itemBuilder: (_) => [
        for (final d in const [7, 30, 90])
          PopupMenuItem(value: d, child: Text('Last $d days')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(label,
                key: ValueKey(label),
                style: PhlioTypography.body
                    .copyWith(color: PhlioColors.textMuted)),
          ),
          const Icon(Icons.expand_more_rounded,
              size: 18, color: PhlioColors.textMuted),
        ]),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.onClose, required this.onTurnOff});
  final VoidCallback onClose, onTurnOff;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: PhlioColors.surfaceElevated,
            border: Border.all(color: PhlioColors.borderSubtle),
          ),
          child: ClipOval(
            child: OverflowBox(
              maxWidth: 84,
              maxHeight: 84,
              alignment: const Alignment(0, -0.2),
              child: const FoxyPuppet(
                  act: FoxyAct.wave, size: 84, entrance: false, tapToHop: true),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Now you can see insights about your content and followers, all in one place.',
                style: PhlioTypography.body,
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: onTurnOff,
                child: Text('Turn off insights',
                    style: PhlioTypography.bodyStrong
                        .copyWith(color: PhlioColors.brandViolet)),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Dismiss',
          icon: const Icon(Icons.close_rounded,
              size: 20, color: PhlioColors.textMuted),
          onPressed: onClose,
        ),
      ]),
    );
  }
}

/// Foxy's one-line read of the numbers, with a matching act.
class _FoxyCoach extends StatelessWidget {
  const _FoxyCoach({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final views = data['views'] as Map;
    final followers = data['followers'] as Map;
    final change = (views['change'] as num?)?.toDouble();
    final peak = data['peak_hour'] as int?;
    final (act, line) = (views['value'] as num) == 0
        ? (
            FoxyAct.think,
            'No views in this range yet. Share something and I\'ll keep count!'
          )
        : change != null && change > 0
            ? (
                FoxyAct.hooray,
                'Views are up ${change.round()}%! ${(followers['value'] as num) > 0 ? '${followers['value']} new followers too.' : 'Keep it going.'}'
              )
            : change != null && change < 0
                ? (
                    FoxyAct.sad,
                    'Views dipped ${change.abs().round()}%.${peak != null ? ' Try posting around ${_hour(peak)}, when your audience is most active.' : ''}'
                  )
                : (
                    FoxyAct.happy,
                    'Steady week.${peak != null ? ' Your audience is most active around ${_hour(peak)}.' : ''}'
                  );
    return _Staggered(
      index: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 16, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          FoxyPuppet(act: act, size: 92, entrance: true),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 18),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: PhlioColors.surfaceElevated,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                  bottomLeft: Radius.circular(4),
                ),
                border: Border.all(color: PhlioColors.borderSubtle),
              ),
              child: Text(line, style: PhlioTypography.body),
            ),
          ),
        ]),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.metric,
    required this.data,
    required this.open,
    required this.onTap,
  });
  final _Metric metric;
  final Map<String, dynamic> data;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final block = data[metric.name] as Map;
    final value = (block['value'] as num).toInt();
    final change = (block['change'] as num?)?.toDouble();
    final up = change != null && change > 0;
    final down = change != null && change < 0;
    return Column(children: [
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 14, 16),
          child: Row(children: [
            Text(metric.label, style: PhlioTypography.title.copyWith(fontWeight: FontWeight.w500)),
            const Spacer(),
            if (up || down)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  up ? Icons.north_east_rounded : Icons.south_east_rounded,
                  size: 20,
                  color: up ? PhlioColors.success : PhlioColors.danger,
                ),
              ),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value.toDouble()),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Text(_compact(v.round()),
                  style: PhlioTypography.title),
            ),
            const SizedBox(width: 6),
            AnimatedRotation(
              turns: open ? 0.25 : 0,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              child: const Icon(Icons.chevron_right_rounded,
                  color: PhlioColors.textMuted),
            ),
          ]),
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: open
            ? _MetricDetail(metric: metric, data: data, change: change)
            : const SizedBox(width: double.infinity),
      ),
    ]);
  }
}

class _MetricDetail extends StatelessWidget {
  const _MetricDetail(
      {required this.metric, required this.data, required this.change});
  final _Metric metric;
  final Map<String, dynamic> data;
  final double? change;

  @override
  Widget build(BuildContext context) {
    final series = (data['series'] as List).cast<Map>();
    final seriesKey = metric.seriesKey;
    final children = <Widget>[];
    if (change != null) {
      children.add(Text(
        '${change! > 0 ? '+' : ''}${change!.toStringAsFixed(change!.abs() < 10 ? 1 : 0)}% vs the previous ${data['days']} days',
        style: PhlioTypography.caption.copyWith(
            color: change! >= 0 ? PhlioColors.success : PhlioColors.danger),
      ));
      children.add(const SizedBox(height: 10));
    }
    if (seriesKey != null) {
      children.add(_ScrubChart(
        points: [
          for (final p in series)
            (p['day'] as String, (p[seriesKey] as num).toDouble())
        ],
        unit: metric == _Metric.views
            ? 'views'
            : metric == _Metric.followers
                ? 'new followers'
                : 'interactions',
      ));
    }
    if (metric == _Metric.interactions) {
      final block = data['interactions'] as Map;
      children.add(const SizedBox(height: 14));
      children.add(_Breakdown(items: [
        ('Likes', (block['liked'] as num).toInt(), PhlioColors.brandPink),
        ('Comments', (block['commented'] as num).toInt(), PhlioColors.brandBlue),
        ('Saves', (block['saved'] as num).toInt(), PhlioColors.brandViolet),
        ('Shares', (block['shared'] as num).toInt(), PhlioColors.domainRooms),
        ('Reposts', (block['reposted'] as num).toInt(), PhlioColors.brandOrange),
      ]));
    }
    if (metric == _Metric.followers || metric == _Metric.views) {
      final hours = (data['active_hours'] as List).cast<num>();
      if (hours.any((h) => h > 0)) {
        children.add(const SizedBox(height: 16));
        children.add(Text('When your audience is active',
            style: PhlioTypography.bodyStrong));
        children.add(const SizedBox(height: 8));
        children.add(_HourBars(hours: hours, peak: data['peak_hour'] as int?));
      }
    }
    if (metric == _Metric.content) {
      children.add(Text(
        (data['content'] as Map)['value'] == 0
            ? 'Nothing posted in this range. Posts, videos, clips and moments all count.'
            : 'Posts, videos, clips and moments you shared in this range.',
        style: PhlioTypography.body.copyWith(color: PhlioColors.textSecondary),
      ));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

/// An area chart you can drag across: a cursor, a dot and a tooltip follow
/// the finger, with a tick of haptics on each new day.
class _ScrubChart extends StatefulWidget {
  const _ScrubChart({required this.points, required this.unit});
  final List<(String, double)> points;
  final String unit;

  @override
  State<_ScrubChart> createState() => _ScrubChartState();
}

class _ScrubChartState extends State<_ScrubChart>
    with SingleTickerProviderStateMixin {
  int? _index;
  late final AnimationController _draw = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..forward();

  @override
  void didUpdateWidget(_ScrubChart old) {
    super.didUpdateWidget(old);
    if (old.points.length != widget.points.length) _draw.forward(from: 0);
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  void _at(double x, double width) {
    final n = widget.points.length;
    if (n < 2) return;
    final i = ((x / width) * (n - 1)).round().clamp(0, n - 1);
    if (i != _index) {
      HapticFeedback.selectionClick();
      setState(() => _index = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final total = points.fold<double>(0, (s, p) => s + p.$2);
    final i = _index;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: Text(
          i == null
              ? '${_compact(total.round())} ${widget.unit} · drag the chart'
              : '${_shortDate(points[i].$1)} · ${points[i].$2.round()} ${widget.unit}',
          key: ValueKey(i),
          style: PhlioTypography.bodyStrong,
        ),
      ),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, box) => GestureDetector(
          onHorizontalDragStart: (d) => _at(d.localPosition.dx, box.maxWidth),
          onHorizontalDragUpdate: (d) => _at(d.localPosition.dx, box.maxWidth),
          onHorizontalDragEnd: (_) => setState(() => _index = null),
          onTapDown: (d) => _at(d.localPosition.dx, box.maxWidth),
          onTapUp: (_) =>
              Future.delayed(const Duration(milliseconds: 900), () {
            if (mounted) setState(() => _index = null);
          }),
          child: AnimatedBuilder(
            animation: _draw,
            builder: (context, _) => CustomPaint(
              size: Size(box.maxWidth, 140),
              painter: _ChartPainter(points.map((p) => p.$2).toList(), i,
                  Curves.easeOutCubic.transform(_draw.value)),
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      if (points.length > 1)
        Row(children: [
          Text(_shortDate(points.first.$1), style: PhlioTypography.caption),
          const Spacer(),
          Text(_shortDate(points.last.$1), style: PhlioTypography.caption),
        ]),
    ]);
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.values, this.index, this.progress);
  final List<double> values;
  final int? index;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxV = math.max(1.0, values.reduce(math.max));
    final dx = size.width / (values.length - 1);
    Offset at(int i) => Offset(
        i * dx, size.height - 8 - (values[i] / maxV) * (size.height - 24) * progress);

    // Grid.
    final grid = Paint()
      ..color = PhlioColors.borderSubtle.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var g = 0; g < 3; g++) {
      final y = 16 + g * (size.height - 24) / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // Smooth line through the points.
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      final a = at(i - 1), b = at(i);
      final mid = (a.dx + b.dx) / 2;
      line.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            PhlioColors.brandViolet.withValues(alpha: 0.35),
            PhlioColors.brandViolet.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..shader = PhlioColors.sunsetGradient.createShader(Offset.zero & size),
    );

    final i = index;
    if (i != null) {
      final p = at(i);
      canvas.drawLine(
          Offset(p.dx, 8),
          Offset(p.dx, size.height),
          Paint()
            ..color = PhlioColors.textMuted.withValues(alpha: 0.6)
            ..strokeWidth = 1);
      canvas.drawCircle(p, 8, Paint()..color = PhlioColors.brandOrange.withValues(alpha: 0.25));
      canvas.drawCircle(p, 4.5, Paint()..color = PhlioColors.brandOrange);
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.index != index || old.progress != progress || old.values != values;
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.items});
  final List<(String, int, Color)> items;

  @override
  Widget build(BuildContext context) {
    final maxV = math.max(1, items.map((e) => e.$2).reduce(math.max));
    return Column(children: [
      for (final (i, (label, value, color)) in items.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            SizedBox(
                width: 82, child: Text(label, style: PhlioTypography.caption)),
            Expanded(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: value / maxV),
                duration: Duration(milliseconds: 600 + i * 80),
                curve: Curves.easeOutCubic,
                builder: (context, f, _) => Stack(children: [
                  Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: PhlioColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: f.clamp(0.0, 1.0),
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            SizedBox(
              width: 44,
              child: Text('$value',
                  textAlign: TextAlign.right, style: PhlioTypography.bodyStrong),
            ),
          ]),
        ),
    ]);
  }
}

class _HourBars extends StatelessWidget {
  const _HourBars({required this.hours, required this.peak});
  final List<num> hours;
  final int? peak;

  @override
  Widget build(BuildContext context) {
    final maxV = math.max(1, hours.map((h) => h.toInt()).reduce(math.max));
    return Column(children: [
      SizedBox(
        height: 64,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var h = 0; h < 24; h++)
            Expanded(
              child: Tooltip(
                message: '${_hour(h)} · ${hours[h]}',
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: hours[h] / maxV),
                  duration: Duration(milliseconds: 500 + h * 20),
                  curve: Curves.easeOutBack,
                  builder: (context, f, _) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    height: math.max(3, 64 * f.clamp(0.0, 1.2)),
                    decoration: BoxDecoration(
                      color: h == peak
                          ? PhlioColors.brandOrange
                          : PhlioColors.brandViolet.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 4),
      Row(children: [
        Text('12 am', style: PhlioTypography.caption),
        const Spacer(),
        if (peak != null)
          Text('Peak ${_hour(peak!)}',
              style: PhlioTypography.caption
                  .copyWith(color: PhlioColors.brandOrange)),
        const Spacer(),
        Text('11 pm', style: PhlioTypography.caption),
      ]),
    ]);
  }
}

class _TopContent extends StatelessWidget {
  const _TopContent({required this.items});
  final List<Map> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 168,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final item = items[i];
          final image = item['image_url'] as String?;
          return _Staggered(
            index: i,
            child: Container(
              width: 120,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: PhlioColors.surfaceElevated,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(fit: StackFit.expand, children: [
                if (image != null)
                  Image.network(AppConfig.mediaUrl(image),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink())
                else
                  const Center(
                      child: Icon(Icons.article_outlined,
                          color: PhlioColors.textMuted)),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xCC000000)],
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['title'] as String? ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: PhlioTypography.caption
                              .copyWith(color: Colors.white)),
                      Row(children: [
                        const Icon(Icons.visibility_outlined,
                            size: 12, color: Colors.white70),
                        const SizedBox(width: 3),
                        Text(_compact(item['views'] as num),
                            style: PhlioTypography.caption.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700)),
                      ]),
                    ],
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.isNew = false,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool isNew;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
        child: Row(children: [
          Icon(icon, size: 28, color: PhlioColors.textPrimary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: PhlioTypography.title
                        .copyWith(fontWeight: FontWeight.w500)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: PhlioTypography.body
                          .copyWith(color: PhlioColors.textMuted)),
              ],
            ),
          ),
          if (isNew)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                gradient: PhlioColors.sunsetGradient,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('New',
                  style: PhlioTypography.label
                      .copyWith(color: PhlioColors.textOnBrand)),
            ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: PhlioColors.textMuted),
        ]),
      ),
    );
  }
}

class _InsightsOff extends StatelessWidget {
  const _InsightsOff({required this.onTurnOn, super.key});
  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const FoxyPuppet(act: FoxyAct.sleep, size: 180),
          const SizedBox(height: 12),
          Text('Insights are off', style: PhlioTypography.headline),
          const SizedBox(height: 6),
          Text(
            'Turn them back on any time to see views, interactions and follower growth.',
            textAlign: TextAlign.center,
            style: PhlioTypography.body.copyWith(color: PhlioColors.textMuted),
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: onTurnOn, child: const Text('Turn on insights')),
        ]),
      ),
    );
  }
}

// -- Sheets ---------------------------------------------------------------------------------

class _IntroSheet extends StatelessWidget {
  const _IntroSheet();

  @override
  Widget build(BuildContext context) {
    const rows = [
      (
        Icons.bar_chart_rounded,
        'Content insights',
        'See how many views and interactions your content has received over time.'
      ),
      (
        Icons.person_add_alt_outlined,
        'Follower insights',
        'Track your follower growth and learn when your audience is most active on Phlio.'
      ),
      (
        Icons.lightbulb_outline_rounded,
        'Personalised tips and recommendations',
        'Get advice from Foxy on how to improve your content\'s reach and engagement.'
      ),
    ];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: PhlioColors.border,
                    borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const Center(child: FoxyPuppet(act: FoxyAct.phone, size: 170)),
            Text('See insights about your content and followers',
                style: PhlioTypography.headline.copyWith(fontSize: 24)),
            const SizedBox(height: 18),
            for (final (i, (icon, title, body)) in rows.indexed)
              _Staggered(
                index: i + 1,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 28),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: PhlioTypography.bodyStrong),
                            Text(body,
                                style: PhlioTypography.body
                                    .copyWith(color: PhlioColors.textMuted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: PhlioColors.sunsetGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text('Continue',
                      style: PhlioTypography.bodyStrong
                          .copyWith(color: PhlioColors.textOnBrand)),
                ),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Turn off insights',
                    style: PhlioTypography.bodyStrong
                        .copyWith(color: PhlioColors.brandViolet)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _sheet(BuildContext context, Widget child) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PhlioColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: child,
        ),
      ),
    );

void _showRecap(BuildContext context, Map<String, dynamic> data) {
  final recap = data['recap'] as Map;
  final stats = [
    ('Views', recap['views'] as num, Icons.visibility_outlined),
    ('Interactions', recap['interactions'] as num, Icons.favorite_border_rounded),
    ('New followers', recap['followers'] as num, Icons.person_add_alt_outlined),
    ('Shared', recap['shared'] as num, Icons.grid_view_rounded),
  ];
  final quiet = stats.every((s) => s.$2 == 0);
  _sheet(
    context,
    Column(mainAxisSize: MainAxisSize.min, children: [
      FoxyPuppet(act: quiet ? FoxyAct.chill : FoxyAct.hooray, size: 170),
      Text('${recap['month']} recap', style: PhlioTypography.headline),
      const SizedBox(height: 4),
      Text(
        quiet
            ? 'A quiet month. Post something and next month\'s recap is all yours.'
            : 'Here\'s what you made happen.',
        textAlign: TextAlign.center,
        style: PhlioTypography.body.copyWith(color: PhlioColors.textMuted),
      ),
      const SizedBox(height: 18),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.7,
        children: [
          for (final (i, (label, value, icon)) in stats.indexed)
            _Staggered(
              index: i,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: PhlioColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 18, color: PhlioColors.brandOrange),
                    const Spacer(),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: value.toDouble()),
                      duration: Duration(milliseconds: 900 + i * 150),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => Text(_compact(v.round()),
                          style: PhlioTypography.headline),
                    ),
                    Text(label, style: PhlioTypography.caption),
                  ],
                ),
              ),
            ),
        ],
      ),
    ]),
  );
}

void _showTips(BuildContext context, Map<String, dynamic>? data) {
  final peak = data?['peak_hour'] as int?;
  final tags = ((data?['trending_tags'] as List?) ?? const [])
      .cast<Map>()
      .take(3)
      .map((t) => '#${t['tag']}')
      .join(' ');
  final tips = [
    (
      FoxyAct.ready,
      'Post when people are around',
      peak == null
          ? 'Once your posts get views, I\'ll show the hour your audience is most active.'
          : 'Your audience is most active around ${_hour(peak)}. Posting just before then gets you more early views.'
    ),
    (
      FoxyAct.think,
      'Hook them in 3 seconds',
      'Open videos and clips with the best moment. Most people decide in the first few seconds.'
    ),
    (
      FoxyAct.happy,
      'Use tags people follow',
      tags.isEmpty
          ? 'Add 2–4 specific tags so the right people find your content.'
          : 'Trending on Phlio right now: $tags. Add 2–4 tags that fit your post.'
    ),
    (
      FoxyAct.talk,
      'Talk back',
      'Replying to comments in the first hour keeps the conversation going and lifts your reach.'
    ),
    (
      FoxyAct.clap,
      'Be consistent',
      'A steady rhythm (say, 3 posts a week) beats bursts. Your followers learn when to expect you.'
    ),
  ];
  _sheet(context, _TipsPager(tips: tips));
}

class _TipsPager extends StatefulWidget {
  const _TipsPager({required this.tips});
  final List<(FoxyAct, String, String)> tips;
  @override
  State<_TipsPager> createState() => _TipsPagerState();
}

class _TipsPagerState extends State<_TipsPager> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tip = widget.tips[_page];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('Best practices', style: PhlioTypography.headline),
      FoxyPuppet(act: tip.$1, size: 150, poseBlend: const Duration(milliseconds: 260)),
      SizedBox(
        height: 120,
        child: PageView.builder(
          controller: _pages,
          itemCount: widget.tips.length,
          onPageChanged: (i) {
            HapticFeedback.selectionClick();
            setState(() => _page = i);
          },
          itemBuilder: (_, i) => Column(children: [
            Text(widget.tips[i].$2,
                textAlign: TextAlign.center, style: PhlioTypography.title),
            const SizedBox(height: 6),
            Text(widget.tips[i].$3,
                textAlign: TextAlign.center,
                style: PhlioTypography.body
                    .copyWith(color: PhlioColors.textSecondary)),
          ]),
        ),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < widget.tips.length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.all(3),
            width: i == _page ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == _page ? PhlioColors.brandOrange : PhlioColors.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ]),
    ]);
  }
}

void _showInspiration(BuildContext context, Map<String, dynamic> data) {
  final tags = (data['trending_tags'] as List).cast<Map>();
  _sheet(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Center(child: FoxyPuppet(act: FoxyAct.peek, size: 140)),
        Text('Inspiration', style: PhlioTypography.headline),
        const SizedBox(height: 4),
        Text('What people on Phlio are posting about right now.',
            style: PhlioTypography.body.copyWith(color: PhlioColors.textMuted)),
        const SizedBox(height: 14),
        if (tags.isEmpty)
          Text('Nothing trending yet.', style: PhlioTypography.body)
        else
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (i, t) in tags.indexed)
              _Staggered(
                index: i,
                child: ActionChip(
                  label: Text('#${t['tag']} · ${t['count']}'),
                  backgroundColor: PhlioColors.surfaceElevated,
                  side: BorderSide.none,
                  onPressed: () {
                    Navigator.pop(context);
                    switchPlatform(context, PhlioPlatform.social);
                    context.go('/explore');
                  },
                ),
              ),
          ]),
      ],
    ),
  );
}

void _showMonetization(BuildContext context) {
  _sheet(
    context,
    Column(mainAxisSize: MainAxisSize.min, children: [
      const FoxyPuppet(act: FoxyAct.cheer, size: 150),
      Text('Get paid on Phlio', style: PhlioTypography.headline),
      const SizedBox(height: 6),
      Text(
        'Fans can already send you money in DMs with Phlio Pay. Creator subscriptions and gifts are next.',
        textAlign: TextAlign.center,
        style: PhlioTypography.body.copyWith(color: PhlioColors.textMuted),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: () {
          Navigator.pop(context);
          switchPlatform(context, PhlioPlatform.pay);
          context.go('/home');
        },
        icon: const Icon(Icons.account_balance_wallet_outlined),
        label: const Text('Open Phlio Pay'),
      ),
    ]),
  );
}
