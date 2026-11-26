// The bell and ⋮ on someone else's profile.
//
//  * [showProfileBell]  "Notifications from <name>": Posts, Videos, Clips,
//    Live, Moments, Snaps, Experiences, each All / Most relevant / Off,
//    plus "All profiles you follow" (your defaults).
//  * [showProfileMore]  About this account, See shared activity, Hide your
//    moments, Remove follower, Copy profile URL, Share this profile, QR code,
//    Restrict, Block, Report.
//
// Backend: backend/app/api/v1/profile_actions.py (+ /social/blocks/{target}).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../../../shared/content/content_surface.dart' show showProfileShare;

const _p = '/social/profiles';

String _enc(String s) => Uri.encodeComponent(s);

/// Notification levels for one profile: `{levels: {posts: all|relevant|off…}, all, off}`.
final profileNotifyProvider = FutureProvider.autoDispose.family<Map, String>((ref, username) async =>
    (await getIt<ApiClient>().dio.get('$_p/${_enc(username)}/notify')).data as Map);

final _relationshipProvider = FutureProvider.autoDispose.family<Map, String>((ref, username) async =>
    (await getIt<ApiClient>().dio.get('$_p/${_enc(username)}/relationship')).data as Map);

const _kinds = <(String, String, IconData)>[
  ('posts', 'Posts', Icons.photo_outlined),
  ('videos', 'Videos', Icons.smart_display_outlined),
  ('clips', 'Clips', Icons.slow_motion_video_rounded),
  ('live', 'Live videos', Icons.sensors_rounded),
  ('moments', 'Moments', Icons.motion_photos_on_outlined),
  ('snaps', 'Snaps', Icons.camera_outlined),
  ('experiences', 'Experiences', Icons.collections_outlined),
];

const _levels = <(String, String, String)>[
  ('all', 'All', 'Get a notification every time'),
  ('relevant', 'Most relevant', 'Only some of the time, based on what you usually like'),
  ('off', 'Off', 'No notifications'),
];

String _levelLabel(String? v) => switch (v) { 'all' => 'All', 'off' => 'Off', _ => 'Most relevant' };

void _say(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

String _problem(Object e, String fallback) {
  try {
    final data = (e as dynamic).response?.data;
    if (data is Map && data['detail'] is String) return data['detail'] as String;
  } catch (_) {}
  return fallback;
}

/// A dropdown panel in the top-right corner (like the platform menus).
Future<T?> _panel<T>(BuildContext context, Widget child) => showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withValues(alpha: .35),
      transitionDuration: const Duration(milliseconds: 180),
      transitionBuilder: (_, a, __, c) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          alignment: Alignment.topRight,
          scale: Tween<double>(begin: .92, end: 1).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: c,
        ),
      ),
      pageBuilder: (dialog, _, __) => SafeArea(
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(40, 52, 10, 16),
            child: Material(
              color: PhlioColors.surfaceElevated,
              borderRadius: BorderRadius.circular(22),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: 330, maxHeight: MediaQuery.sizeOf(dialog).height * .78),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );

// -- bell ---------------------------------------------------------------------------------

/// The bell button: filled when anything is set to "All".
class ProfileBellButton extends ConsumerWidget {
  const ProfileBellButton({required this.username, super.key});
  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(profileNotifyProvider(username)).valueOrNull;
    final on = data?['all'] == true;
    final off = data?['off'] == true;
    return IconButton(
      tooltip: 'Notifications from $username',
      icon: Icon(
          on
              ? Icons.notifications_active_rounded
              : off
                  ? Icons.notifications_off_outlined
                  : Icons.notifications_none_rounded,
          color: on ? PhlioColors.brandViolet : PhlioColors.textSecondary),
      onPressed: () async {
        HapticFeedback.selectionClick();
        await showProfileBell(context, username);
        ref.invalidate(profileNotifyProvider(username));
      },
    );
  }
}

Future<void> showProfileBell(BuildContext context, String username) =>
    _panel<void>(context, _BellPanel(username: username));

class _BellPanel extends StatefulWidget {
  const _BellPanel({required this.username});
  final String username;
  @override
  State<_BellPanel> createState() => _BellPanelState();
}

class _BellPanelState extends State<_BellPanel> {
  Map<String, String>? levels, defaults;
  String? kind; // the level picker is open for this kind
  bool editingDefaults = false;
  bool saving = false;

  String get _base => editingDefaults ? '$_p/notify-defaults' : '$_p/${_enc(widget.username)}/notify';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, String> _parse(dynamic data) =>
      {for (final e in ((data as Map)['levels'] as Map).entries) '${e.key}': '${e.value}'};

  Future<void> _load() async {
    try {
      final dio = getIt<ApiClient>().dio;
      final r = await dio.get('$_p/${_enc(widget.username)}/notify');
      final d = await dio.get('$_p/notify-defaults');
      if (!mounted) return;
      setState(() {
        levels = _parse(r.data);
        defaults = _parse(d.data);
      });
    } catch (_) {
      if (mounted) setState(() => levels = const {});
    }
  }

  Future<void> _set(String k, String level) async {
    setState(() => saving = true);
    try {
      final r = await getIt<ApiClient>().dio.put(_base, data: {k: level});
      if (!mounted) return;
      setState(() {
        if (editingDefaults) {
          defaults = _parse(r.data);
        } else {
          levels = _parse(r.data);
        }
        kind = null;
      });
      // Defaults change what "Most relevant" etc. fall back to here too.
      if (editingDefaults) await _load();
    } catch (e) {
      if (mounted) _say(context, _problem(e, 'Could not save. Try again.'));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = editingDefaults ? defaults : levels;
    if (current == null) {
      return const SizedBox(width: 300, height: 220, child: Center(child: CircularProgressIndicator()));
    }
    if (current.isEmpty) {
      return const SizedBox(
          width: 300, height: 120, child: Center(child: Text('Could not load notification settings.')));
    }
    final title = editingDefaults ? 'All profiles you follow' : 'Notifications from ${widget.username}';
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(kind != null || editingDefaults ? 6 : 20, 12, 16, 6),
            child: Row(children: [
              if (kind != null || editingDefaults)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  onPressed: () => setState(() {
                    if (kind != null) {
                      kind = null;
                    } else {
                      editingDefaults = false;
                    }
                  }),
                ),
              Expanded(
                child: Text(
                  kind == null ? title : _kinds.firstWhere((k) => k.$1 == kind).$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PhlioTypography.body.copyWith(color: PhlioColors.textMuted),
                ),
              ),
              if (saving) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
          ),
          if (kind == null) ...[
            for (final (k, label, icon) in _kinds)
              _Row(
                icon: icon,
                title: label,
                subtitle: _levelLabel(current[k]),
                chevron: true,
                onTap: () => setState(() => kind = k),
              ),
            if (!editingDefaults) ...[
              const Divider(height: 1, color: PhlioColors.border),
              _Row(
                icon: Icons.tune_rounded,
                title: 'All profiles you follow',
                subtitle: 'Your defaults',
                onTap: () => setState(() => editingDefaults = true),
              ),
            ],
            const SizedBox(height: 8),
          ] else ...[
            for (final (value, label, hint) in _levels)
              RadioListTile<String>(
                value: value,
                groupValue: current[kind],
                onChanged: saving ? null : (v) => _set(kind!, v!),
                activeColor: PhlioColors.brandViolet,
                title: Text(label, style: PhlioTypography.bodyStrong.copyWith(color: PhlioColors.textPrimary)),
                subtitle: Text(hint, style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted)),
              ),
            const SizedBox(height: 8),
          ],
        ]),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.onTap, this.subtitle, this.chevron = false, this.danger = false});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool chevron, danger;

  @override
  Widget build(BuildContext context) {
    final colour = danger ? PhlioColors.danger : PhlioColors.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(children: [
          Icon(icon, color: colour, size: 26),
          const SizedBox(width: 18),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: PhlioTypography.bodyLarge.copyWith(color: colour)),
              if (subtitle != null)
                Text(subtitle!, style: PhlioTypography.body.copyWith(color: PhlioColors.textMuted)),
            ]),
          ),
          if (chevron) const Icon(Icons.chevron_right_rounded, color: PhlioColors.textSecondary),
        ]),
      ),
    );
  }
}

// -- ⋮ menu -----------------------------------------------------------------------------------

/// The ⋮ on someone's profile. [onBlocked] runs after a block (leave the page).
Future<void> showProfileMore(BuildContext context, WidgetRef ref,
    {required String username, required String name, String? avatarUrl, VoidCallback? onBlocked}) async {
  final link = 'phlio://profile/$username';
  final action = await _panel<String>(context, Consumer(builder: (panel, ref, _) {
    final rel = ref.watch(_relationshipProvider(username)).valueOrNull ?? const {};
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _Row(icon: Icons.account_circle_outlined, title: 'About this account', onTap: () => Navigator.pop(panel, 'about')),
        _Row(icon: Icons.people_outline_rounded, title: 'See shared activity', onTap: () => Navigator.pop(panel, 'shared')),
        _Row(
            icon: rel['hidden_moments'] == true ? Icons.motion_photos_on_outlined : Icons.motion_photos_off_outlined,
            title: rel['hidden_moments'] == true ? 'Show your moments' : 'Hide your moments',
            onTap: () => Navigator.pop(panel, 'hide')),
        if (rel['follows_you'] == true)
          _Row(icon: Icons.person_remove_outlined, title: 'Remove follower', onTap: () => Navigator.pop(panel, 'remove')),
        _Row(icon: Icons.link_rounded, title: 'Copy profile URL', onTap: () => Navigator.pop(panel, 'copy')),
        _Row(icon: Icons.share_outlined, title: 'Share this profile', onTap: () => Navigator.pop(panel, 'share')),
        _Row(icon: Icons.qr_code_2_rounded, title: 'QR code', onTap: () => Navigator.pop(panel, 'qr')),
        _Row(
            icon: Icons.do_not_disturb_on_outlined,
            title: rel['restricted'] == true ? 'Unrestrict' : 'Restrict',
            onTap: () => Navigator.pop(panel, 'restrict')),
        _Row(
            icon: Icons.block_rounded,
            title: rel['blocked'] == true ? 'Unblock' : 'Block',
            onTap: () => Navigator.pop(panel, 'block')),
        _Row(icon: Icons.report_gmailerrorred_rounded, title: 'Report', danger: true, onTap: () => Navigator.pop(panel, 'report')),
      ]),
    );
  }));
  if (action == null || !context.mounted) return;
  final dio = getIt<ApiClient>().dio;
  final rel = ref.read(_relationshipProvider(username)).valueOrNull ?? const {};
  try {
    switch (action) {
      case 'about':
        await _sheet(context, _AboutSheet(username: username));
      case 'shared':
        await _sheet(context, _SharedSheet(username: username, name: name));
      case 'hide':
        final hide = rel['hidden_moments'] != true;
        if (await _confirm(context,
            title: hide ? 'Hide your moments from $username?' : 'Show your moments to $username?',
            body: hide
                ? "They won't see your moments or snaps. They won't be told."
                : 'They can see your moments again (if your audience includes them).',
            action: hide ? 'Hide' : 'Show')) {
          await dio.put('$_p/${_enc(username)}/hide-moments', data: {'hidden': hide});
          if (context.mounted) _say(context, hide ? 'Your moments are hidden from $username' : 'Moments visible again');
        }
      case 'remove':
        if (await _confirm(context,
            title: 'Remove follower?',
            body: "Phlio won't tell $username they were removed from your followers.",
            action: 'Remove',
            danger: true)) {
          await dio.delete('$_p/${_enc(username)}/follower');
          if (context.mounted) _say(context, 'Removed $username from your followers');
        }
      case 'copy':
        await Clipboard.setData(ClipboardData(text: link));
        if (context.mounted) _say(context, 'Profile link copied');
      case 'share':
        await showProfileShare(context, username);
      case 'qr':
        await _sheet(context, _QrSheet(username: username, name: name, avatarUrl: avatarUrl, link: link));
      case 'restrict':
        final restrict = rel['restricted'] != true;
        if (await _confirm(context,
            title: restrict ? 'Restrict $username?' : 'Unrestrict $username?',
            body: restrict
                ? 'Their new comments on your posts will only be visible to them and you, and their messages '
                    'go to Requests without notifications. They won\'t be told.'
                : 'Their comments and messages go back to normal.',
            action: restrict ? 'Restrict' : 'Unrestrict')) {
          await dio.put('$_p/${_enc(username)}/restrict', data: {'restricted': restrict});
          if (context.mounted) _say(context, restrict ? 'Restricted $username' : 'Unrestricted $username');
        }
      case 'block':
        final block = rel['blocked'] != true;
        if (await _confirm(context,
            title: block ? 'Block $username?' : 'Unblock $username?',
            body: block
                ? "They won't be able to find your profile, posts or moments, or message you. They won't be told."
                : 'They will be able to see your profile and follow you again.',
            action: block ? 'Block' : 'Unblock',
            danger: block)) {
          if (block) {
            await dio.put('/social/blocks/${_enc(username)}');
            if (context.mounted) _say(context, 'Blocked $username');
            onBlocked?.call();
          } else {
            await dio.delete('/social/blocks/${_enc(username)}');
            if (context.mounted) _say(context, 'Unblocked $username');
          }
        }
      case 'report':
        final reason = await _sheet<String>(context, const _ReportSheet());
        if (reason != null) {
          await dio.post('$_p/${_enc(username)}/report', data: {'reason': reason});
          if (context.mounted) _say(context, "Thanks for reporting. We'll take a look.");
        }
    }
  } catch (e) {
    if (context.mounted) _say(context, _problem(e, 'Something went wrong. Try again.'));
  }
  ref.invalidate(_relationshipProvider(username));
}

Future<T?> _sheet<T>(BuildContext context, Widget child) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: PhlioColors.surface,
      builder: (_) => child,
    );

Future<bool> _confirm(BuildContext context,
    {required String title, required String body, required String action, bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(d, true),
          child: Text(action, style: TextStyle(color: danger ? PhlioColors.danger : PhlioColors.brandViolet)),
        ),
      ],
    ),
  );
  return ok == true;
}

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October',
  'November', 'December'];

class _AboutSheet extends StatelessWidget {
  const _AboutSheet({required this.username});
  final String username;

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: getIt<ApiClient>().dio.get('$_p/${_enc(username)}/about'),
        builder: (_, s) {
          if (s.hasError) {
            return const SizedBox(height: 200, child: Center(child: Text('Could not load this account.')));
          }
          if (!s.hasData) return const SizedBox(height: 260, child: Center(child: CircularProgressIndicator()));
          final d = s.data!.data as Map;
          final p = d['profile'] as Map;
          final joined = DateTime.tryParse('${d['joined'] ?? ''}');
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                PhlioAvatar(
                    name: '${p['display_name'] ?? ''}', imageUrl: p['avatar_url'] as String?, size: 84, showMomentRing: false),
                const SizedBox(height: 12),
                Text('${p['username']}', style: PhlioTypography.title.copyWith(color: PhlioColors.textPrimary)),
                const SizedBox(height: 6),
                Text(
                  'To help keep our community authentic, we show information about accounts on Phlio.',
                  textAlign: TextAlign.center,
                  style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted),
                ),
                const SizedBox(height: 18),
                if (joined != null)
                  _Fact(Icons.calendar_month_outlined, 'Date joined', '${_months[joined.month - 1]} ${joined.year}'),
                _Fact(Icons.verified_outlined, 'Verified', d['verified'] == true ? 'Yes' : 'No'),
                _Fact(Icons.groups_outlined, 'Followers', '${d['followers']} · following ${d['following']}'),
                _Fact(Icons.people_alt_outlined, 'Followers you know', '${d['mutual_followers']}'),
              ]),
            ),
          );
        },
      );
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.title, this.value);
  final IconData icon;
  final String title, value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(icon, color: PhlioColors.textSecondary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: PhlioTypography.bodyStrong.copyWith(color: PhlioColors.textPrimary)),
              Text(value, style: PhlioTypography.body.copyWith(color: PhlioColors.textMuted)),
            ]),
          ),
        ]),
      );
}

class _SharedSheet extends StatelessWidget {
  const _SharedSheet({required this.username, required this.name});
  final String username, name;

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: getIt<ApiClient>().dio.get('$_p/${_enc(username)}/shared'),
        builder: (_, s) {
          if (s.hasError) return const SizedBox(height: 200, child: Center(child: Text('Could not load shared activity.')));
          if (!s.hasData) return const SizedBox(height: 260, child: Center(child: CircularProgressIndicator()));
          final d = s.data!.data as Map;
          final both = d['both_follow'] as Map;
          final people = (both['people'] as List).cast<Map>();
          return SafeArea(
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
              Text('Shared activity', style: PhlioTypography.title.copyWith(color: PhlioColors.textPrimary)),
              const SizedBox(height: 4),
              Text('What you and $name have in common on Phlio.',
                  style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted)),
              const SizedBox(height: 14),
              _Fact(Icons.favorite_border_rounded, 'Posts you liked', '${d['liked_posts']} of their posts'),
              _Fact(Icons.chat_bubble_outline_rounded, 'Messages', '${d['messages']} in your chat'),
              _Fact(Icons.alternate_email_rounded, 'Moments that mention you', '${d['moment_mentions']}'),
              _Fact(Icons.swap_horiz_rounded, 'Follow each other',
                  d['follows_you'] == true && d['you_follow'] == true
                      ? 'Yes'
                      : d['you_follow'] == true
                          ? 'You follow them'
                          : d['follows_you'] == true
                              ? 'They follow you'
                              : 'No'),
              const SizedBox(height: 8),
              Text('You both follow · ${both['count']}',
                  style: PhlioTypography.bodyStrong.copyWith(color: PhlioColors.textPrimary)),
              for (final p in people)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: PhlioAvatar(
                      name: '${p['display_name'] ?? ''}', imageUrl: p['avatar_url'] as String?, size: 40, showMomentRing: false),
                  title: Text('${p['display_name'] ?? p['username']}'),
                  subtitle: Text('@${p['username']}'),
                  onTap: () {
                    final router = GoRouter.of(context);
                    Navigator.pop(context);
                    router.push('/creator/${_enc('${p['username']}')}');
                  },
                ),
            ]),
          );
        },
      );
}

class _QrSheet extends StatelessWidget {
  const _QrSheet({required this.username, required this.name, required this.link, this.avatarUrl});
  final String username, name, link;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                QrImageView(
                  data: link,
                  size: 220,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: Color(0xFF6236F5)),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: Color(0xFF14161C)),
                ),
                const SizedBox(height: 10),
                Text('@$username',
                    style: const TextStyle(color: Color(0xFF6236F5), fontSize: 20, fontWeight: FontWeight.w800)),
              ]),
            ),
            const SizedBox(height: 14),
            Text('Scan with Phlio to open $name\'s profile',
                style: PhlioTypography.body.copyWith(color: PhlioColors.textMuted)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: link));
                    if (context.mounted) _say(context, 'Profile link copied');
                  },
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('Copy link'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => showProfileShare(context, username),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share'),
                ),
              ),
            ]),
          ]),
        ),
      );
}

class _ReportSheet extends StatelessWidget {
  const _ReportSheet();
  static const reasons = [
    "It's spam",
    'Pretending to be someone else',
    'They may be under 13',
    'Bullying or harassment',
    'Hate speech or symbols',
    'Nudity or sexual activity',
    'Violence or dangerous organisations',
    'Scam or fraud',
    'Something else',
  ];

  @override
  Widget build(BuildContext context) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 16), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Why are you reporting this account?',
                style: PhlioTypography.title.copyWith(color: PhlioColors.textPrimary)),
          ),
          for (final r in reasons)
            ListTile(
              title: Text(r),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(context, r),
            ),
        ]),
      );
}
