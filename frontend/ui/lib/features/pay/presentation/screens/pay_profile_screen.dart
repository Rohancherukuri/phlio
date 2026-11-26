// Phlio Pay profile — opened from your photo (with the scanner badge) at the
// top-left of Phlio Pay.
//
//   your photo, name and number · "Receiving money on Phlio Pay"
//   QR codes: one per UPI id (swipe between banks), share / copy
//   bank accounts (primary for receiving) · debit and credit cards
//   settings: Autopay, Pay with fingerprint, International, UPI settings,
//   Shake to scan · Refer & earn · Help & support
//
// Phlio Pay runs on a simulated ledger: accounts and cards are **test
// accounts** (masked, last four digits only) and are labelled as such.
// Backend: GET /pay/profile, PATCH /pay/profile/settings, PUT /pay/profile/primary.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_card.dart' show PhlioAvatar;
import 'transaction_history_screen.dart';

final payProfileProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await getIt<ApiClient>().dio.get('/pay/profile');
  return Map<String, dynamic>.from(res.data as Map);
});

Color _hex(String? s) => Color(int.tryParse('FF${(s ?? '#8D78FF').replaceFirst('#', '')}', radix: 16) ?? 0xFF8D78FF);

class PayProfileScreen extends ConsumerStatefulWidget {
  const PayProfileScreen({super.key});

  @override
  ConsumerState<PayProfileScreen> createState() => _PayProfileScreenState();
}

class _PayProfileScreenState extends ConsumerState<PayProfileScreen> {
  final _pages = PageController(viewportFraction: .78);
  int _page = 0;
  Map<String, dynamic>? _settings;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _set(String key, bool value) async {
    final before = _settings;
    setState(() => _settings = {...?_settings, key: value});
    try {
      final res = await getIt<ApiClient>().dio.patch('/pay/profile/settings', data: {key: value});
      if (mounted) setState(() => _settings = Map<String, dynamic>.from(res.data as Map));
      ref.invalidate(payProfileProvider);
    } catch (_) {
      if (mounted) {
        setState(() => _settings = before);
        _toast('Couldn’t save that. Try again.');
      }
    }
  }

  Future<void> _makePrimary(Map a) async {
    try {
      await getIt<ApiClient>().dio.put('/pay/profile/primary', data: {'account_id': a['id']});
      ref.invalidate(payProfileProvider);
      _toast('Money you receive now goes to ${a['short']} ••${a['last4']}.');
    } catch (_) {
      _toast('Couldn’t change the primary account.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(payProfileProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pay profile'),
        actions: [
          IconButton(tooltip: 'Help & support', icon: const Icon(Icons.help_outline_rounded), onPressed: () => _help(context)),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: TextButton(onPressed: () => ref.invalidate(payProfileProvider), child: const Text('Couldn’t load your Pay profile. Retry')),
        ),
        data: (p) {
          _settings ??= Map<String, dynamic>.from(p['settings'] as Map);
          final accounts = [for (final a in p['accounts'] as List) Map<String, dynamic>.from(a as Map)];
          final cards = [for (final c in p['cards'] as List) Map<String, dynamic>.from(c as Map)];
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(payProfileProvider),
            child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
              _header(p),
              if (p['test_mode'] == true) _testBanner(),
              const SizedBox(height: 8),
              _qrCarousel(p, accounts),
              _section('Bank accounts'),
              for (final a in accounts) _accountTile(a),
              _section('Cards'),
              for (final c in cards) _cardTile(c),
              _section('Payment settings'),
              _switchTile(Icons.autorenew_rounded, 'Autopay', 'Let trusted billers collect recurring payments', 'autopay'),
              _switchTile(Icons.fingerprint_rounded, 'Pay with fingerprint', 'Confirm small payments with your fingerprint', 'fingerprint'),
              _switchTile(Icons.public_rounded, 'International', 'Pay with UPI abroad, where it’s accepted', 'international'),
              _switchTile(Icons.vibration_rounded, 'Shake to scan', 'Shake your phone on Phlio Pay to open the scanner', 'shake_to_scan'),
              _linkTile(Icons.account_balance_wallet_outlined, 'UPI settings', 'UPI ids, UPI PIN and linked accounts',
                  () => _upiSettings(context, p, accounts)),
              _section('More'),
              _linkTile(Icons.card_giftcard_rounded, 'Refer & earn', '${(p['refer'] as Map)['reward']}', () => _refer(context, p)),
              _linkTile(Icons.support_agent_rounded, 'Help & support', 'Payments, refunds and your account', () => _help(context)),
            ]),
          );
        },
      ),
    );
  }

  Widget _header(Map p) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Row(children: [
          PhlioAvatar(name: '${p['name']}', imageUrl: p['avatar_url'] as String?, size: 64, showMomentRing: false),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: PhlioTypography.title),
              Text(p['phone'] != null ? '${p['phone']}' : '@${p['username']}', style: PhlioTypography.caption),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: PhlioColors.success.withValues(alpha: .14), borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.check_circle_rounded, size: 15, color: PhlioColors.success),
                  const SizedBox(width: 6),
                  Text('Receiving money on Phlio Pay',
                      style: PhlioTypography.caption.copyWith(color: PhlioColors.success, fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
          ),
        ]),
      );

  Widget _testBanner() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: PhlioColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: PhlioColors.border),
        ),
        child: Row(children: [
          const Icon(Icons.science_outlined, size: 18, color: PhlioColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Test mode: these accounts and cards are simulated, so no real money moves.',
                style: PhlioTypography.caption.copyWith(color: PhlioColors.textSecondary)),
          ),
        ]),
      );

  Widget _qrCarousel(Map p, List<Map<String, dynamic>> accounts) {
    final current = accounts[_page.clamp(0, accounts.length - 1)];
    return Column(children: [
      SizedBox(
        height: 330,
        child: PageView.builder(
          controller: _pages,
          itemCount: accounts.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) {
            final a = accounts[i];
            return AnimatedScale(
              duration: const Duration(milliseconds: 220),
              scale: i == _page ? 1 : .92,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                child: Column(children: [
                  Expanded(
                    child: QrImageView(
                      data: '${a['qr']}',
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.H,
                      embeddedImage: const AssetImage('assets/images/logo/logo_mark.png'),
                      embeddedImageStyle: const QrEmbeddedImageStyle(size: Size(42, 48)),
                      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF0B0F17)),
                      dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF0B0F17)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _BankBadge(a, size: 22),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text('${a['short']} - ${a['last4']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFF111111), fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  Text('${a['upi_id']}', style: const TextStyle(color: Color(0xFF666666), fontSize: 12)),
                ]),
              ),
            );
          },
        ),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < accounts.length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: i == _page ? 22 : 7,
            height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: i == _page ? PhlioColors.textPrimary : PhlioColors.textMuted.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ]),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy UPI ID'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: '${current['upi_id']}'));
                _toast('Copied ${current['upi_id']}');
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              label: const Text('Share QR'),
              onPressed: () => SharePlus.instance.share(ShareParams(
                text: 'Pay ${p['name']} on Phlio Pay: ${current['upi_id']}\n${current['qr']}',
              )),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 6),
        child: Text(title, style: PhlioTypography.title.copyWith(fontSize: 17)),
      );

  Widget _accountTile(Map<String, dynamic> a) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: _BankBadge(a, size: 40),
        title: Text('${a['bank']}', style: PhlioTypography.bodyStrong),
        subtitle: Text('${a['type']} ••${a['last4']} · ${a['upi_id']}', maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: a['primary'] == true
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: PhlioColors.surfaceElevated, borderRadius: BorderRadius.circular(8)),
                child: Text('Primary', style: PhlioTypography.caption.copyWith(fontWeight: FontWeight.w700)),
              )
            : TextButton(onPressed: () => _makePrimary(a), child: const Text('Make primary')),
        onTap: () => _toast('Checking balances needs a live bank connection; test accounts don’t have one.'),
      );

  Widget _cardTile(Map<String, dynamic> c) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: Container(
          width: 52,
          height: 34,
          decoration: BoxDecoration(color: _hex(c['colour'] as String?).withValues(alpha: .22), borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _hex(c['colour'] as String?).withValues(alpha: .6))),
          alignment: Alignment.center,
          child: Icon(c['kind'] == 'credit' ? Icons.credit_card_rounded : Icons.payment_rounded, size: 20, color: _hex(c['colour'] as String?)),
        ),
        title: Text('${c['bank']} ${c['kind'] == 'credit' ? 'Credit' : 'Debit'} Card', style: PhlioTypography.bodyStrong),
        subtitle: Text('${c['network']} ••••${c['last4']}${c['upi_linked'] == true ? ' · Linked to UPI' : ''}'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _toast('Card details stay with your bank; Phlio only shows the last four digits.'),
      );

  Widget _switchTile(IconData icon, String title, String subtitle, String key) => SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        secondary: Icon(icon, color: PhlioColors.brandViolet),
        title: Text(title, style: PhlioTypography.bodyStrong),
        subtitle: Text(subtitle),
        value: _settings?[key] == true,
        onChanged: (v) => _set(key, v),
      );

  Widget _linkTile(IconData icon, String title, String subtitle, VoidCallback onTap) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: Icon(icon, color: PhlioColors.brandViolet),
        title: Text(title, style: PhlioTypography.bodyStrong),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      );

  void _upiSettings(BuildContext context, Map p, List<Map<String, dynamic>> accounts) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => SafeArea(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 16), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('UPI settings', style: PhlioTypography.title),
            ),
            for (final a in accounts)
              ListTile(
                leading: _BankBadge(a, size: 34),
                title: Text('${a['upi_id']}'),
                subtitle: Text('${a['short']} ••${a['last4']}${a['primary'] == true ? ' · primary' : ''}'),
                trailing: IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () => Clipboard.setData(ClipboardData(text: '${a['upi_id']}')),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.wallet_rounded),
              title: Text('${p['wallet_upi']}'),
              subtitle: const Text('Phlio Pay wallet'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.password_rounded),
              title: const Text('Set or change UPI PIN'),
              subtitle: const Text('Needs a live bank connection (not available in test mode)'),
              enabled: false,
            ),
          ]),
        ),
      );

  void _refer(BuildContext context, Map p) {
    final code = '${(p['refer'] as Map)['code']}';
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Refer & earn', style: PhlioTypography.title),
            const SizedBox(height: 6),
            Text('${(p['refer'] as Map)['reward']}.', style: PhlioTypography.body),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: PhlioColors.surfaceElevated, borderRadius: BorderRadius.circular(14), border: Border.all(color: PhlioColors.border)),
              child: SelectableText(code, style: PhlioTypography.title.copyWith(letterSpacing: 2)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Invite friends'),
                onPressed: () => SharePlus.instance.share(ShareParams(text: 'Join me on Phlio! Use my code $code when you sign up.')),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _help(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(8, 0, 8, 16), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text('Help & support', style: PhlioTypography.title),
            ),
            for (final (q, a) in const [
              ('My payment failed but money was deducted', 'In test mode no real money moves. With a live bank, failed payments are reversed to your account within 48 hours.'),
              ('How do I receive money?', 'Share your QR code or UPI ID from this page. Money goes to your primary account.'),
              ('Is Phlio Pay safe?', 'Phlio never asks for your UPI PIN outside the payment screen and only shows the last four digits of accounts and cards.'),
              ('How does Shake to scan work?', 'Turn it on, open Phlio Pay and give your phone a quick shake: the QR scanner opens.'),
            ])
              ExpansionTile(title: Text(q, style: PhlioTypography.bodyStrong), children: [
                Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Text(a, style: PhlioTypography.body)),
              ]),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('Your transactions'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TransactionHistoryScreen()));
              },
            ),
          ]),
        ),
      );
}

class _BankBadge extends StatelessWidget {
  const _BankBadge(this.account, {this.size = 36});
  final Map account;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = _hex(account['colour'] as String?);
    final short = '${account['short'] ?? '?'}';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.withValues(alpha: .2), shape: BoxShape.circle),
      child: Icon(Icons.account_balance_rounded, size: size * .5, color: c, semanticLabel: short),
    );
  }
}

/// Your photo with a small scanner badge, for the top-left of Phlio Pay.
/// Tapping it opens the Pay profile.
class PayProfileButton extends StatelessWidget {
  const PayProfileButton({required this.name, this.avatarUrl, super.key});
  final String name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Your QR codes, accounts and pay settings',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Navigator.of(context, rootNavigator: true)
              .push(MaterialPageRoute<void>(builder: (_) => const PayProfileScreen())),
          child: SizedBox(
            width: 44,
            height: 46,
            child: Stack(clipBehavior: Clip.none, children: [
              PhlioAvatar(name: name, imageUrl: avatarUrl, size: 38, showMomentRing: false),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: PhlioColors.surfaceElevated,
                    shape: BoxShape.circle,
                    border: Border.all(color: PhlioColors.background, width: 2),
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded, size: 12, color: PhlioColors.textPrimary),
                ),
              ),
            ]),
          ),
        ),
      );
}
