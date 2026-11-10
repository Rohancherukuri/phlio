// Pay someone from a DM: tap the currency button (₹ / $ / € …) in the
// composer → this sheet: their Phlio Pay ID, their Pay QR code, "View
// transactions" (your Phlio Pay history with them) and "Pay with Phlio Pay"
// → amount → paid. On success the chat gets a "Sent ₹500 via Phlio Pay"
// message.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../design_system/colors.dart';
import '../../design_system/radii.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../design_system/widgets/phlio_card.dart';
import '../../features/pay/presentation/controllers/pay_controller.dart';
import '../../features/pay/presentation/screens/transaction_history_screen.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';
import 'payment_message.dart';
import 'phlio_currency.dart';

typedef _Peer = ({String username, String name, String? avatar});

final _peerProvider = FutureProvider.autoDispose.family<_Peer, String>((ref, username) async {
  try {
    final r = await getIt<ApiClient>().dio.get('/users/$username');
    final j = r.data as Map<String, dynamic>;
    return (
      username: j['username'] as String? ?? username,
      name: (j['full_name'] as String?)?.trim().isNotEmpty == true ? j['full_name'] as String : username,
      avatar: j['avatar_url'] as String?,
    );
  } catch (_) {
    return (username: username, name: username, avatar: null);
  }
});

String phlioPayId(String username) => '${username.toLowerCase()}@phlio';

/// Opens the pay sheet for [username]. Returns the chat message to post
/// when a payment went through.
Future<String?> showDmPaySheet(BuildContext context, {required String username}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: PhlioColors.surfaceElevated,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => _PaySheet(username: username.replaceFirst('@', '')),
  );
}

class _PaySheet extends ConsumerWidget {
  const _PaySheet({required this.username});

  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peer = ref.watch(_peerProvider(username)).valueOrNull ??
        (username: username, name: username, avatar: null);
    final currency = ref.watch(userCurrencyProvider);
    final id = phlioPayId(peer.username);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(PhlioSpacing.xl, 0, PhlioSpacing.md, PhlioSpacing.lg),
            child: Row(children: [
              PhlioAvatar(name: peer.name, imageUrl: peer.avatar, profileId: peer.username, size: 52),
              const SizedBox(width: PhlioSpacing.lg),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(peer.name, style: PhlioTypography.title),
                  const SizedBox(height: 2),
                  Text('Phlio Pay ID: $id',
                      style: PhlioTypography.body.copyWith(color: PhlioColors.textSecondary)),
                ]),
              ),
              IconButton(
                tooltip: 'Copy Pay ID',
                icon: const Icon(Icons.copy_rounded, color: PhlioColors.brandOrange),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: id));
                  HapticFeedback.selectionClick();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pay ID copied')));
                },
              ),
            ]),
          ),
          const Divider(height: 1, color: PhlioColors.border),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.xl),
            leading: const Icon(Icons.qr_code_2_rounded, color: PhlioColors.textPrimary),
            title: Text('Share Pay QR code', style: PhlioTypography.bodyLarge),
            onTap: () => _showQr(context, peer, id),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.xl),
            leading: const Icon(Icons.history_rounded, color: PhlioColors.textPrimary),
            title: Text('View transactions', style: PhlioTypography.bodyLarge),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => TransactionHistoryScreen(withUsername: peer.username, withName: peer.name),
            )),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(PhlioSpacing.xl, PhlioSpacing.md, PhlioSpacing.xl, PhlioSpacing.lg),
            child: _GradientButton(
              onTap: () async {
                final message = await Navigator.of(context).push<String>(MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => _PayAmountPage(peer: peer),
                ));
                if (message != null && context.mounted) Navigator.of(context).pop(message);
              },
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                CurrencyGlyph(currency: currency, size: 22, color: PhlioColors.textOnBrand),
                const SizedBox(width: 10),
                Text('Pay with Phlio Pay',
                    style: PhlioTypography.bodyLarge.copyWith(
                        color: PhlioColors.textOnBrand, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _showQr(BuildContext context, _Peer peer, String id) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: PhlioColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: PhlioRadii.xlRadius),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          PhlioAvatar(name: peer.name, imageUrl: peer.avatar, profileId: peer.username, size: 48),
          const SizedBox(height: PhlioSpacing.sm),
          Text(peer.name, style: PhlioTypography.title),
          Text(id, style: PhlioTypography.caption.copyWith(color: PhlioColors.textSecondary)),
          const SizedBox(height: PhlioSpacing.lg),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: QrImageView(
              data: 'phlio://pay/${peer.username}',
              size: 200,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: PhlioSpacing.md),
          Text('Scan with Phlio Pay to pay ${peer.name.split(' ').first}',
              textAlign: TextAlign.center,
              style: PhlioTypography.caption.copyWith(color: PhlioColors.textSecondary)),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: id));
              Navigator.pop(c);
            },
            child: const Text('Copy Pay ID'),
          ),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Done')),
        ],
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.onTap, required this.child, this.enabled = true});

  final VoidCallback? onTap;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: enabled ? 1 : 0.5,
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: PhlioColors.brandGradient, borderRadius: PhlioRadii.pillRadius),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: PhlioRadii.pillRadius,
              onTap: enabled ? onTap : null,
              child: SizedBox(height: 54, child: Center(child: child)),
            ),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Amount → pay → done

class _PayAmountPage extends ConsumerStatefulWidget {
  const _PayAmountPage({required this.peer});

  final _Peer peer;

  @override
  ConsumerState<_PayAmountPage> createState() => _PayAmountPageState();
}

class _PayAmountPageState extends ConsumerState<_PayAmountPage> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  bool _paying = false;
  String? _error;
  String? _paid; // formatted amount once done

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  int? get _minor {
    final v = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (v == null || v <= 0) return null;
    return (v * 100).round();
  }

  Future<void> _pay(PhlioCurrency currency) async {
    final minor = _minor;
    if (minor == null || _paying) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _paying = true;
      _error = null;
    });
    try {
      final response = await getIt<ApiClient>().dio.post('/pay/send-to-user', data: {
        'username': widget.peer.username,
        'amount_minor_units': minor,
        'note': _note.text.trim(),
      });
      final txn = response.data as Map;
      final me = ref.read(authControllerProvider).valueOrNull;
      ref.invalidate(walletProvider);
      ref.invalidate(transactionsProvider);
      HapticFeedback.heavyImpact();
      final amount = currency.format(minor);
      setState(() => _paid = amount);
      final note = _note.text.trim();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      // Posted into the chat as a Phlio Pay receipt card.
      Navigator.of(context).pop(paymentMessage(ChatPayment(
        txnId: '${txn['id'] ?? ''}',
        amountMinor: minor,
        currency: '${txn['currency'] ?? currency.code}',
        fromUser: me?.username ?? '',
        fromName: me?.fullName ?? 'You',
        toUser: widget.peer.username,
        toName: widget.peer.name,
        note: note,
        at: DateTime.tryParse('${txn['created_at']}') ?? DateTime.now(),
      )));
    } on DioException catch (e) {
      final data = e.response?.data;
      final detail = data is Map ? (data['detail'] ?? data['message'] ?? (data['error'] is Map ? data['error']['message'] : null)) : null;
      setState(() {
        _paying = false;
        _error = detail is String ? detail : 'Payment didn\'t go through. Please try again.';
      });
    } catch (_) {
      setState(() {
        _paying = false;
        _error = 'Payment didn\'t go through. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(userCurrencyProvider);
    final wallet = ref.watch(walletProvider).valueOrNull;
    final peer = widget.peer;

    if (_paid != null) {
      return Scaffold(
        body: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 550),
            curve: Curves.easeOutBack,
            builder: (context, v, child) => Transform.scale(scale: 0.6 + 0.4 * v, child: Opacity(opacity: v.clamp(0.0, 1.0), child: child)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: PhlioColors.success),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 56),
              ),
              const SizedBox(height: PhlioSpacing.lg),
              Text(_paid!, style: PhlioTypography.displayLarge),
              const SizedBox(height: 4),
              Text('Paid to ${peer.name}', style: PhlioTypography.bodyLarge),
            ]),
          ),
        ),
      );
    }

    final minor = _minor;
    return Scaffold(
      appBar: AppBar(leading: const CloseButton(), title: const Text('Phlio Pay')),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.all(PhlioSpacing.xl), children: [
              Center(child: PhlioAvatar(name: peer.name, imageUrl: peer.avatar, profileId: peer.username, size: 64)),
              const SizedBox(height: PhlioSpacing.sm),
              Center(child: Text('Paying ${peer.name}', style: PhlioTypography.title)),
              Center(
                child: Text(phlioPayId(peer.username),
                    style: PhlioTypography.caption.copyWith(color: PhlioColors.textSecondary)),
              ),
              const SizedBox(height: PhlioSpacing.xxl),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(currency.symbol.trim(), style: PhlioTypography.displayLarge.copyWith(fontSize: 40)),
                const SizedBox(width: 4),
                IntrinsicWidth(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 60),
                    child: TextField(
                      controller: _amount,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.numberWithOptions(decimal: currency.decimals > 0),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(currency.decimals > 0 ? r'^\d{0,9}(\.\d{0,2})?' : r'^\d{0,11}')),
                      ],
                      onChanged: (_) => setState(() => _error = null),
                      style: PhlioTypography.displayLarge.copyWith(fontSize: 44),
                      decoration: const InputDecoration(
                        hintText: '0',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: PhlioSpacing.md),
              Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                for (final q in currency.quickAmounts)
                  ActionChip(
                    label: Text(currency.format(q * 100)),
                    onPressed: () => setState(() {
                      _amount.text = '$q';
                      _error = null;
                    }),
                  ),
              ]),
              const SizedBox(height: PhlioSpacing.xl),
              TextField(
                controller: _note,
                maxLength: 140,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Add a note (optional)',
                  prefixIcon: Icon(Icons.edit_note_rounded),
                  counterText: '',
                ),
              ),
              if (wallet != null) ...[
                const SizedBox(height: PhlioSpacing.md),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 16, color: PhlioColors.textMuted),
                  const SizedBox(width: 6),
                  Text('Phlio Pay balance ${currencyByCode(wallet.currency).format(wallet.balanceMinorUnits)}',
                      style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted)),
                ]),
              ],
              if (_error != null) ...[
                const SizedBox(height: PhlioSpacing.md),
                Text(_error!, textAlign: TextAlign.center, style: PhlioTypography.body.copyWith(color: PhlioColors.danger)),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(PhlioSpacing.xl, 0, PhlioSpacing.xl, PhlioSpacing.lg),
            child: _GradientButton(
              enabled: minor != null && !_paying,
              onTap: () => _pay(currency),
              child: _paying
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: PhlioColors.textOnBrand))
                  : Text(minor == null ? 'Enter an amount' : 'Pay ${currency.format(minor)}',
                      style: PhlioTypography.bodyLarge.copyWith(color: PhlioColors.textOnBrand, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}
