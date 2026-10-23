import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/di/service_locator.dart';
import '../../core/storage/token_storage.dart';
import '../../design_system/widgets/phlio_card.dart';
import '../../features/profile/presentation/controllers/avatar_controller.dart';
import '../../features/authentication/data/models/user_model.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';
import '../config/app_config.dart';

final accountSessionApiProvider = Provider<Dio>((ref) {
  final api = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15)));
  ref.onDispose(api.close);
  return api;
});

Future<void> showAccountSwitcher(BuildContext context) =>
    showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        showDragHandle: true,
        builder: (_) => const AccountSwitcher());

class AccountSwitcher extends ConsumerStatefulWidget {
  const AccountSwitcher({super.key});
  @override
  ConsumerState<AccountSwitcher> createState() => _AccountSwitcherState();
}

class _AccountSwitcherState extends ConsumerState<AccountSwitcher> {
  List<Map<String, dynamic>> accounts = [];
  bool busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final user = ref.read(authControllerProvider).valueOrNull;
      final storage = getIt<TokenStorage>();
      if (user != null)
        await storage.rememberAccount(
            id: user.id, username: user.username, avatarUrl: user.avatarUrl);
      final result = await storage.savedAccounts();
      if (mounted) setState(() => accounts = result);
    } catch (_) {
      if (mounted)
        setState(() => error = 'Could not read saved accounts. Try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> select(Map<String, dynamic> account) async {
    if (busy) return;
    if (account['id'] == ref.read(authControllerProvider).valueOrNull?.id) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    // Validate the candidate session separately before replacing the active one.
    final api = ref.read(accountSessionApiProvider);
    try {
      var access = account['access_token'] as String;
      Response<dynamic> response;
      try {
        response = await api.get('/auth/me',
            options: Options(headers: {'Authorization': 'Bearer $access'}));
      } on DioException catch (e) {
        if (e.response?.statusCode != 401) rethrow;
        final renewed = await api.post('/auth/refresh',
            data: {'refresh_token': account['refresh_token']});
        access = renewed.data['access_token'] as String;
        response = await api.get('/auth/me',
            options: Options(headers: {'Authorization': 'Bearer $access'}));
      }
      final user =
          UserModel.fromJson(Map<String, dynamic>.from(response.data as Map))
              .toEntity();
      if (user.id != account['id']) throw StateError('Account mismatch');
      final storage = getIt<TokenStorage>();
      await storage.saveTokens(AuthTokens(
          accessToken: access,
          refreshToken: account['refresh_token'] as String));
      await storage.rememberAccount(
          id: user.id, username: user.username, avatarUrl: user.avatarUrl);
      if (!mounted) return;
      ref.read(authControllerProvider.notifier).activateAccount(user);
      Navigator.pop(context);
      context.go('/profile');
    } catch (_) {
      if (mounted)
        setState(() => error =
            'Could not switch accounts. Check your connection or add this account again to sign in.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authControllerProvider).valueOrNull;
    return PopScope(
        canPop: !busy,
        child: SafeArea(
            child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .7),
                child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                              tooltip: 'Close accounts',
                              onPressed:
                                  busy ? null : () => Navigator.pop(context),
                              icon: const Icon(Icons.close))),
                      if (busy) const LinearProgressIndicator(),
                      if (error != null)
                        Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(error!)),
                      for (final account in accounts)
                        ListTile(
                            leading: account['id'] == me?.id
                                ? MeAvatar(name: me!.fullName, size: 44)
                                : PhlioAvatar(
                                    name: account['username'] as String,
                                    imageUrl: account['avatar_url'] as String?,
                                    size: 44),
                            title: Text(account['username'] as String,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: account['id'] == me?.id
                                ? const Icon(Icons.check_circle,
                                    color: Color(0xFF72A7FF))
                                : null,
                            onTap: busy ? null : () => select(account)),
                      const Divider(),
                      ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.add)),
                          title: const Text('Add Phlio account'),
                          onTap: busy
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  context.push('/add-account');
                                }),
                    ]))));
  }
}

class AddAccountScreen extends ConsumerStatefulWidget {
  const AddAccountScreen({super.key});
  @override
  ConsumerState<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends ConsumerState<AddAccountScreen> {
  final identifier = TextEditingController(),
      password = TextEditingController();
  bool busy = false, obscure = true;
  String? error;
  @override
  void dispose() {
    identifier.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (busy || identifier.text.trim().isEmpty || password.text.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final storage = getIt<TokenStorage>();
      final current = ref.read(authControllerProvider).valueOrNull;
      if (current != null)
        await storage.rememberAccount(
            id: current.id,
            username: current.username,
            avatarUrl: current.avatarUrl);
      final result = await ref
          .read(authControllerProvider.notifier)
          .login(identifier: identifier.text.trim(), password: password.text);
      await result.when(success: (user) async {
        await storage.rememberAccount(
            id: user.id, username: user.username, avatarUrl: user.avatarUrl);
        if (mounted) context.go('/profile');
      }, failure: (failure) async {
        if (mounted) setState(() => error = failure.message);
      });
    } catch (_) {
      if (mounted)
        setState(() => error = 'Could not add account. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: Scaffold(
          appBar: AppBar(title: const Text('Add Phlio account')),
          body: ListView(padding: const EdgeInsets.all(24), children: [
            const Text('Log in to another account',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            const Text('Your current account stays saved on this device.'),
            const SizedBox(height: 28),
            TextField(
                controller: identifier,
                enabled: !busy,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(
                    labelText: 'Username, email or phone')),
            const SizedBox(height: 16),
            TextField(
                controller: password,
                enabled: !busy,
                obscureText: obscure,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                        tooltip: 'Show or hide password',
                        onPressed: () => setState(() => obscure = !obscure),
                        icon: Icon(obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined))),
                onSubmitted: (_) => login()),
            if (error != null)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(error!)),
            const SizedBox(height: 24),
            FilledButton(
                onPressed: busy ? null : login,
                child: Text(busy ? 'Signing in…' : 'Log in')),
          ])));
}
