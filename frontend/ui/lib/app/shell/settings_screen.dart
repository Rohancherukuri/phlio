import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/di/service_locator.dart';
import '../../core/storage/token_storage.dart';
import '../../design_system/colors.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';
import '../../features/social/presentation/screens/social_graph_screen.dart';
import '../../shared/content/content_surface.dart';
import '../../shared/content/playlists_screen.dart';
import 'account_switcher.dart';
import '../../features/authentication/presentation/screens/two_factor_screen.dart';
import '../../shared/appearance/appearance.dart'
    show accountPrivateProvider, setAccountPrivate;

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String query = '';
  bool busy = false;
  void page(Widget widget) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => widget));
  Future<void> logout() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Log out of this account?'),
                content: const Text(
                    'This account will be removed from saved accounts on this device.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Log out'))
                ]));
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      final id = ref.read(authControllerProvider).valueOrNull?.id;
      if (id != null) await getIt<TokenStorage>().forgetAccount(id);
      await ref.read(authControllerProvider.notifier).logout();
    } catch (_) {
      if (mounted) {
        setState(() => busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not log out. Try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final entries = <({
      String section,
      String title,
      String subtitle,
      IconData icon,
      VoidCallback tap
    })>[
      (
        section: 'Your account',
        title: 'Accounts',
        subtitle: 'Add or switch Phlio accounts',
        icon: Icons.account_circle_outlined,
        tap: () => showAccountSwitcher(context)
      ),
      (
        section: 'Your account',
        title: 'Personal details',
        subtitle: 'Your account information',
        icon: Icons.badge_outlined,
        tap: () => page(Scaffold(
            appBar: AppBar(title: const Text('Personal details')),
            body: ListView(children: [
              ListTile(
                  title: const Text('Name'),
                  subtitle: Text(user?.fullName ?? '')),
              ListTile(
                  title: const Text('Username'),
                  subtitle: Text(user?.username ?? '')),
              ListTile(
                  title: const Text('Email'),
                  subtitle: Text(user?.email ?? '')),
              ListTile(
                  title: const Text('Phone'),
                  subtitle: Text(user?.phoneNumber ?? 'Not provided')),
              ListTile(
                  title: const Text('Date of birth'),
                  subtitle: Text(
                      user?.dateOfBirth?.toIso8601String().split('T').first ??
                          'Not provided'))
            ])))
      ),
      (
        section: 'Your account',
        title: 'Two-factor authentication',
        subtitle: 'Codes from an authenticator app when you sign in',
        icon: Icons.verified_user_outlined,
        tap: () => page(const TwoFactorScreen())
      ),
      (
        section: 'Your account',
        title: 'Account privacy',
        subtitle: 'Private accounts show a lock; only followers see posts',
        icon: Icons.lock_outline_rounded,
        tap: () => page(const _PrivacyPage())
      ),
      (
        section: 'How you use Phlio',
        title: 'Take the tour',
        subtitle: 'Foxy shows you the important buttons again',
        icon: Icons.tour_outlined,
        tap: () => context.push('/tour')
      ),
      (
        section: 'How you use Phlio',
        title: 'Saved',
        subtitle: 'Your bookmarked content',
        icon: Icons.bookmark_border,
        tap: () => page(const ContentLibraryScreen(verb: 'saved'))
      ),
      (
        section: 'How you use Phlio',
        title: 'Your activity',
        subtitle: 'Friends, notes and shared activity',
        icon: Icons.history,
        tap: () => page(const SocialGraphScreen())
      ),
      (
        section: 'How you use Phlio',
        title: 'Reposts',
        subtitle: 'Content you have reposted',
        icon: Icons.repeat,
        tap: () => page(const ContentLibraryScreen(verb: 'reposted'))
      ),
      (
        section: 'How you use Phlio',
        title: 'News playlists',
        subtitle: 'Organize saved articles',
        icon: Icons.newspaper_outlined,
        tap: () => showPlaylists(context, 'news')
      ),
      (
        section: 'How you use Phlio',
        title: 'Stream playlists',
        subtitle: 'Organize saved videos',
        icon: Icons.playlist_play,
        tap: () => showPlaylists(context, 'stream')
      ),
      (
        section: 'Who can see your activity',
        title: 'Activity privacy',
        subtitle: 'Audiences, identity and agent access',
        icon: Icons.lock_outline,
        tap: () => page(const SocialGraphScreen(initialTab: 2))
      ),
      (
        section: 'Messages and updates',
        title: 'Messages',
        subtitle: 'Primary, requests and general',
        icon: Icons.chat_bubble_outline,
        tap: () => context.push('/chats')
      ),
      (
        section: 'Messages and updates',
        title: 'Notifications',
        subtitle: 'Your activity notifications',
        icon: Icons.notifications_none,
        tap: () => context.push('/activity')
      ),
      (
        section: 'Login',
        title: 'Add account',
        subtitle: 'Log in to another Phlio account',
        icon: Icons.person_add_alt,
        tap: () => context.push('/add-account')
      ),
      (
        section: 'Login',
        title: 'Log out',
        subtitle: 'Remove this saved session',
        icon: Icons.logout,
        tap: logout
      ),
    ]
        .where((entry) =>
            '${entry.title} ${entry.subtitle}'.toLowerCase().contains(query))
        .toList();
    return Scaffold(
        appBar: AppBar(title: const Text('Settings and activity')),
        body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              TextField(
                  onChanged: (value) =>
                      setState(() => query = value.toLowerCase().trim()),
                  decoration: InputDecoration(
                      hintText: 'Search settings',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24)))),
              if (busy) const LinearProgressIndicator(),
              if (entries.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No matching settings')),
              for (var i = 0; i < entries.length; i++) ...[
                if (i == 0 || entries[i].section != entries[i - 1].section)
                  Padding(
                      padding: const EdgeInsets.fromLTRB(8, 28, 8, 8),
                      child: Text(entries[i].section,
                          style: const TextStyle(
                              color: PhlioColors.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600))),
                ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(entries[i].icon),
                    title: Text(entries[i].title),
                    subtitle: Text(entries[i].subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: PhlioColors.textMuted)),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: busy ? null : entries[i].tap),
              ],
            ]));
  }
}

/// Settings → Account privacy: the private-account switch.
class _PrivacyPage extends ConsumerStatefulWidget {
  const _PrivacyPage();

  @override
  ConsumerState<_PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends ConsumerState<_PrivacyPage> {
  bool? _value;
  bool _busy = false;

  Future<void> _set(bool value) async {
    setState(() {
      _value = value;
      _busy = true;
    });
    try {
      await setAccountPrivate(value);
      ref.invalidate(accountPrivateProvider);
    } catch (_) {
      if (mounted) {
        setState(() => _value = !value);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not change account privacy. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value =
        _value ?? ref.watch(accountPrivateProvider).valueOrNull ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Account privacy')),
      body: ListView(children: [
        SwitchListTile(
          value: value,
          onChanged: _busy ? null : _set,
          secondary: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(value ? Icons.lock_rounded : Icons.lock_open_rounded,
                key: ValueKey(value)),
          ),
          title: const Text('Private account'),
          subtitle: Text(value
              ? 'Your profile shows a lock. Only your followers see your posts.'
              : 'Your profile is public: anyone can see your posts.'),
        ),
      ]),
    );
  }
}
