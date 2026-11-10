// Settings → Two-factor authentication.
//
// Authenticator-app codes (Google Authenticator, Microsoft Authenticator,
// 1Password, Authy…): scan the QR code or copy the key, confirm with a code,
// then save the ten backup codes. When it's on, every sign-in (password,
// Google or Apple) asks for a code too. Server: /auth/2fa/*.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/foxy_puppet.dart';
import '../auth_flows.dart' show authErrorMessage;

enum _Stage { loading, off, setup, codes, on, error }

class TwoFactorScreen extends StatefulWidget {
  const TwoFactorScreen({super.key});

  @override
  State<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends State<TwoFactorScreen> {
  final _api = getIt<ApiClient>().dio;
  final _code = TextEditingController();
  _Stage _stage = _Stage.loading;
  bool _busy = false;
  String? _error, _secret, _uri, _enabledAt;
  int _codesLeft = 0;
  List<String> _backupCodes = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = (await _api.get('/auth/2fa')).data as Map;
      if (!mounted) return;
      setState(() {
        _stage = r['enabled'] == true ? _Stage.on : _Stage.off;
        _codesLeft = (r['backup_codes_left'] as num?)?.toInt() ?? 0;
        _enabledAt = r['enabled_at'] as String?;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _stage = _Stage.error;
          _error = authErrorMessage(e);
        });
      }
    }
  }

  Future<void> _startSetup() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = (await _api.post('/auth/2fa/setup')).data as Map;
      setState(() {
        _secret = r['secret'] as String;
        _uri = r['otpauth_uri'] as String;
        _stage = _Stage.setup;
        _code.clear();
      });
    } catch (e) {
      setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    if (_code.text.trim().length != 6 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = (await _api.post('/auth/2fa/enable',
              data: {'code': _code.text.trim()}))
          .data as Map;
      HapticFeedback.heavyImpact();
      setState(() {
        _backupCodes = (r['backup_codes'] as List).cast<String>();
        _codesLeft = _backupCodes.length;
        _stage = _Stage.codes;
      });
    } catch (e) {
      HapticFeedback.mediumImpact();
      setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Asks for a current code, then runs [path] with it.
  Future<Map?> _withCode(String title, String action, String path) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 9,
          keyboardType: TextInputType.text,
          decoration: const InputDecoration(
              hintText: 'Authenticator or backup code', counterText: ''),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialog, controller.text.trim()),
              child: Text(action)),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.isEmpty || !mounted) return null;
    try {
      return (await _api.post(path, data: {'code': code})).data as Map;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(authErrorMessage(e))));
      }
      return null;
    }
  }

  Future<void> _turnOff() async {
    final r = await _withCode(
        'Turn off two-factor?', 'Turn off', '/auth/2fa/disable');
    if (r != null && mounted) {
      setState(() => _stage = _Stage.off);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Two-factor authentication is off.')));
    }
  }

  Future<void> _newCodes() async {
    final r = await _withCode(
        'New backup codes', 'Create', '/auth/2fa/backup-codes');
    if (r != null && mounted) {
      setState(() {
        _backupCodes = (r['backup_codes'] as List).cast<String>();
        _codesLeft = _backupCodes.length;
        _stage = _Stage.codes;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Two-factor authentication')),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        child: KeyedSubtree(key: ValueKey(_stage), child: _body()),
      ),
    );
  }

  Widget _body() {
    switch (_stage) {
      case _Stage.loading:
        return const Center(child: CircularProgressIndicator());
      case _Stage.error:
        return _centered(FoxyAct.oops, 'Couldn\'t load this',
            _error ?? 'Try again.', 'Retry', () {
          setState(() => _stage = _Stage.loading);
          _load();
        });
      case _Stage.off:
        return ListView(padding: const EdgeInsets.all(24), children: [
          const Center(child: FoxyPuppet(act: FoxyAct.phone, size: 170)),
          Text('Add an extra lock to your account',
              textAlign: TextAlign.center, style: PhlioTypography.headline),
          const SizedBox(height: 10),
          Text(
            'When you sign in, Phlio will also ask for a 6-digit code from an '
            'authenticator app on your phone, so a stolen password isn\'t enough.',
            textAlign: TextAlign.center,
            style: PhlioTypography.body.copyWith(color: PhlioColors.textMuted),
          ),
          const SizedBox(height: 24),
          for (final (icon, text) in const [
            (Icons.qr_code_2_rounded, 'Scan a QR code with your authenticator app'),
            (Icons.pin_outlined, 'Confirm with the code it shows'),
            (Icons.key_rounded, 'Save 10 backup codes for when your phone isn\'t handy'),
          ])
            ListTile(
              leading: Icon(icon, color: PhlioColors.brandOrange),
              title: Text(text, style: PhlioTypography.body),
            ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: PhlioTypography.body
                      .copyWith(color: PhlioColors.danger)),
            ),
          FilledButton.icon(
            onPressed: _busy ? null : _startSetup,
            icon: const Icon(Icons.shield_outlined),
            label: const Text('Set up authenticator app'),
          ),
        ]);
      case _Stage.setup:
        return ListView(padding: const EdgeInsets.all(24), children: [
          Text('1. Add Phlio to your authenticator app',
              style: PhlioTypography.title),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: QrImageView(data: _uri ?? '', size: 190),
            ),
          ),
          const SizedBox(height: 12),
          Text('Or enter this key:',
              textAlign: TextAlign.center, style: PhlioTypography.caption),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(
              child: SelectableText(_secret ?? '',
                  textAlign: TextAlign.center,
                  style: PhlioTypography.bodyStrong
                      .copyWith(fontFamily: 'monospace', letterSpacing: 1.5)),
            ),
            IconButton(
              tooltip: 'Copy key',
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: () {
                Clipboard.setData(
                    ClipboardData(text: (_secret ?? '').replaceAll(' ', '')));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Key copied')));
              },
            ),
          ]),
          TextButton.icon(
            onPressed: () async {
              final ok = await launchUrl(Uri.parse(_uri ?? ''),
                  mode: LaunchMode.externalApplication);
              if (!ok && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text(
                        'No authenticator app found. Install one, then scan the code.')));
              }
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Open in authenticator app on this phone'),
          ),
          const SizedBox(height: 18),
          Text('2. Enter the 6-digit code it shows',
              style: PhlioTypography.title),
          const SizedBox(height: 10),
          TextField(
            controller: _code,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: PhlioTypography.headline.copyWith(letterSpacing: 10),
            decoration: InputDecoration(
                counterText: '', hintText: '••••••', errorText: _error),
            onChanged: (v) {
              if (_error != null) setState(() => _error = null);
              if (v.length == 6) _confirm();
            },
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _busy ? null : _confirm,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Turn on'),
          ),
        ]);
      case _Stage.codes:
        return ListView(padding: const EdgeInsets.all(24), children: [
          const Center(child: FoxyPuppet(act: FoxyAct.hooray, size: 140)),
          Text('Save your backup codes',
              textAlign: TextAlign.center, style: PhlioTypography.headline),
          const SizedBox(height: 8),
          Text(
            'If you lose your phone, each of these lets you sign in once. '
            'Keep them somewhere safe — they won\'t be shown again.',
            textAlign: TextAlign.center,
            style: PhlioTypography.body.copyWith(color: PhlioColors.textMuted),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: PhlioColors.surfaceElevated,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                for (final code in _backupCodes)
                  SizedBox(
                    width: 120,
                    child: Text(code,
                        textAlign: TextAlign.center,
                        style: PhlioTypography.bodyStrong.copyWith(
                            fontFamily: 'monospace', letterSpacing: 1.2)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _backupCodes.join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Backup codes copied')));
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy all'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => setState(() {
              _backupCodes = const [];
              _stage = _Stage.on;
            }),
            child: const Text('I saved them'),
          ),
        ]);
      case _Stage.on:
        return ListView(padding: const EdgeInsets.all(24), children: [
          const Center(child: FoxyPuppet(act: FoxyAct.ready, size: 150)),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.verified_user_rounded, color: PhlioColors.success),
            const SizedBox(width: 8),
            Text('Two-factor is on', style: PhlioTypography.headline),
          ]),
          const SizedBox(height: 8),
          Text(
            'Sign-ins ask for a code from your authenticator app.'
            '${_enabledAt != null ? ' On since ${_enabledAt!.split('T').first}.' : ''}',
            textAlign: TextAlign.center,
            style: PhlioTypography.body.copyWith(color: PhlioColors.textMuted),
          ),
          const SizedBox(height: 20),
          ListTile(
            leading: const Icon(Icons.key_rounded),
            title: const Text('Backup codes'),
            subtitle: Text('$_codesLeft left'),
            trailing: TextButton(
                onPressed: _newCodes, child: const Text('Get new codes')),
          ),
          const Divider(),
          ListTile(
            leading:
                const Icon(Icons.no_encryption_outlined, color: PhlioColors.danger),
            title: const Text('Turn off two-factor',
                style: TextStyle(color: PhlioColors.danger)),
            onTap: _turnOff,
          ),
        ]);
    }
  }

  Widget _centered(FoxyAct act, String title, String body, String action,
      VoidCallback onTap) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          FoxyPuppet(act: act, size: 150),
          Text(title, style: PhlioTypography.headline),
          const SizedBox(height: 6),
          Text(body,
              textAlign: TextAlign.center,
              style: PhlioTypography.body.copyWith(color: PhlioColors.textMuted)),
          const SizedBox(height: 16),
          FilledButton(onPressed: onTap, child: Text(action)),
        ]),
      ),
    );
  }
}
