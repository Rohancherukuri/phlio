// Payments in chat. A completed Phlio Pay payment is posted into the DM as
// ordinary message text (so every client can read it):
//
//   💸 Paid ₹500 to Ananya Rao
//   dinner
//   phlio-pay:<base64url JSON>
//
// [parsePaymentMessage] reads it back; [PaymentMessageCard] draws the
// Phlio-themed receipt bubble; tapping it opens [showPaymentDetails] with
// the full details and a way into Phlio Pay.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/platform/phlio_platform.dart';
import '../../app/shell/platform_home_screen.dart' show switchPlatform;
import '../../design_system/colors.dart';
import '../../design_system/typography.dart';
import '../../features/pay/presentation/screens/transaction_history_screen.dart';
import 'phlio_currency.dart';

class ChatPayment {
  const ChatPayment({
    required this.txnId,
    required this.amountMinor,
    required this.currency,
    required this.fromUser,
    required this.fromName,
    required this.toUser,
    required this.toName,
    required this.note,
    required this.at,
  });

  final String txnId;
  final int amountMinor;
  final String currency;
  final String fromUser, fromName, toUser, toName;
  final String note;
  final DateTime at;

  String get amount => currencyByCode(currency).format(amountMinor);

  Map<String, dynamic> toJson() => {
        't': txnId,
        'a': amountMinor,
        'c': currency,
        'f': fromUser,
        'fn': fromName,
        'to': toUser,
        'tn': toName,
        'n': note,
        'at': at.toUtc().toIso8601String(),
      };

  static ChatPayment fromJson(Map j) => ChatPayment(
        txnId: '${j['t'] ?? ''}',
        amountMinor: (j['a'] as num?)?.toInt() ?? 0,
        currency: '${j['c'] ?? 'INR'}',
        fromUser: '${j['f'] ?? ''}',
        fromName: '${j['fn'] ?? j['f'] ?? ''}',
        toUser: '${j['to'] ?? ''}',
        toName: '${j['tn'] ?? j['to'] ?? ''}',
        note: '${j['n'] ?? ''}',
        at: DateTime.tryParse('${j['at']}') ?? DateTime.now(),
      );
}

/// Message text for a completed payment.
String paymentMessage(ChatPayment p) {
  final data = base64Url.encode(utf8.encode(jsonEncode(p.toJson())));
  return [
    '💸 Paid ${p.amount} to ${p.toName}',
    if (p.note.isNotEmpty) p.note,
    'phlio-pay:$data',
  ].join('\n');
}

final _payLine = RegExp(r'phlio-pay:([A-Za-z0-9_\-=]+)');

/// The payment in [text], or null if it isn't a payment message.
ChatPayment? parsePaymentMessage(String? text) {
  if (text == null || !text.contains('phlio-pay:')) return null;
  final m = _payLine.firstMatch(text);
  if (m == null) return null;
  try {
    final raw = utf8.decode(base64Url.decode(base64Url.normalize(m.group(1)!)));
    return ChatPayment.fromJson(jsonDecode(raw) as Map);
  } catch (_) {
    return null;
  }
}

String _time(BuildContext context, DateTime t) =>
    TimeOfDay.fromDateTime(t.toLocal()).format(context);

String _first(String name) => name.trim().split(RegExp(r'\s+')).first;

// ---------------------------------------------------------------------------
// The bubble

class PaymentMessageCard extends StatelessWidget {
  const PaymentMessageCard({super.key, required this.payment, required this.mine});

  final ChatPayment payment;

  /// True when the signed-in person sent this payment.
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final currency = currencyByCode(p.currency);
    return GestureDetector(
      onTap: () => showPaymentDetails(context, payment: p, mine: mine),
      child: Container(
        width: 262,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(24),
            topRight: const Radius.circular(24),
            bottomLeft: Radius.circular(mine ? 24 : 6),
            bottomRight: Radius.circular(mine ? 6 : 24),
          ),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF8D78FF), Color(0xFFE795D7), Color(0xFFFFB58F)],
          ),
        ),
        padding: const EdgeInsets.all(1.4),
        child: ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(23),
            topRight: const Radius.circular(23),
            bottomLeft: Radius.circular(mine ? 23 : 5),
            bottomRight: Radius.circular(mine ? 5 : 23),
          ),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF231B4D), Color(0xFF161229)],
              ),
            ),
            child: Stack(children: [
              const Positioned.fill(child: CustomPaint(painter: _WavesPainter())),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  child: Row(children: [
                    CurrencyGlyph(currency: currency, size: 16, color: const Color(0xFFE795D7)),
                    const SizedBox(width: 6),
                    Text('Phlio Pay',
                        style: PhlioTypography.caption.copyWith(
                            color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                    const Spacer(),
                    Icon(mine ? Icons.north_east_rounded : Icons.south_west_rounded,
                        size: 16, color: Colors.white54),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
                  child: Center(
                    child: ShaderMask(
                      shaderCallback: (r) => const LinearGradient(
                        colors: [Color(0xFFFFFFFF), Color(0xFFFFE3D2)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ).createShader(r),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(p.amount,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                      ),
                    ),
                  ),
                ),
                if (p.note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text('“${p.note}”',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: PhlioTypography.caption.copyWith(color: Colors.white70, fontStyle: FontStyle.italic)),
                  ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  color: Colors.white.withValues(alpha: 0.06),
                  child: Row(children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF2ECC8F)),
                      child: const Icon(Icons.check_rounded, size: 17, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          mine ? 'Sent to ${p.toName}' : 'You received from ${_first(p.fromName)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PhlioTypography.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                        Text('Completed',
                            style: PhlioTypography.caption.copyWith(
                                color: const Color(0xFF5BE3A8), fontWeight: FontWeight.w800)),
                      ]),
                    ),
                    Text(_time(context, p.at), style: PhlioTypography.caption.copyWith(color: Colors.white60, fontSize: 11)),
                  ]),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Soft concentric waves in brand colours behind the amount.
class _WavesPainter extends CustomPainter {
  const _WavesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width * 0.85, -size.height * 0.15);
    for (var i = 0; i < 9; i++) {
      final r = 40.0 + i * 22;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Color.lerp(const Color(0xFF8D78FF), const Color(0xFFFFB58F), i / 8)!.withValues(alpha: 0.10),
      );
    }
    final glowRect = Rect.fromCircle(center: Offset(size.width * 0.5, size.height * 0.38), radius: size.width * 0.45);
    canvas.drawCircle(
      glowRect.center,
      glowRect.width / 2,
      Paint()
        ..shader = RadialGradient(colors: [
          const Color(0xFF8D78FF).withValues(alpha: 0.18),
          Colors.transparent,
        ]).createShader(glowRect),
    );
  }

  @override
  bool shouldRepaint(_WavesPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Details

Future<void> showPaymentDetails(BuildContext context, {required ChatPayment payment, required bool mine}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF141A24),
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => _PaymentDetails(payment: payment, mine: mine),
  );
}

class _PaymentDetails extends StatelessWidget {
  const _PaymentDetails({required this.payment, required this.mine});

  final ChatPayment payment;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final local = p.at.toLocal();
    final date = MaterialLocalizations.of(context).formatFullDate(local);
    final peer = mine ? p.toUser : p.fromUser;
    final peerName = mine ? p.toName : p.fromName;

    Widget row(String label, String value, {bool copy = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 112,
              child: Text(label, style: PhlioTypography.body.copyWith(color: PhlioColors.textMuted)),
            ),
            Expanded(child: Text(value, style: PhlioTypography.body.copyWith(color: Colors.white))),
            if (copy)
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: value));
                  HapticFeedback.selectionClick();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied')));
                },
                child: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.copy_rounded, size: 18, color: PhlioColors.brandPeach),
                ),
              ),
          ]),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Animated success badge.
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOutBack,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [Color(0xFF2ECC8F), Color(0xFF6FD6B5)]),
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(p.amount,
                style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(mine ? 'Paid to ${p.toName}' : 'Received from ${p.fromName}',
                style: PhlioTypography.bodyLarge.copyWith(color: Colors.white)),
          ),
          const SizedBox(height: 8),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF2ECC8F).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('Completed · $date, ${_time(context, p.at)}',
                  style: PhlioTypography.caption.copyWith(color: const Color(0xFF5BE3A8), fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: const Color(0xFF1B2230), borderRadius: BorderRadius.circular(20)),
            child: Column(children: [
              row('To', '${p.toName}\n${p.toUser.toLowerCase()}@phlio'),
              const Divider(height: 1, color: Color(0xFF2A3242)),
              row('From', '${p.fromName}\n${p.fromUser.toLowerCase()}@phlio'),
              const Divider(height: 1, color: Color(0xFF2A3242)),
              if (p.note.isNotEmpty) ...[
                row('Note', p.note),
                const Divider(height: 1, color: Color(0xFF2A3242)),
              ],
              row('Paid with', 'Phlio Pay wallet · ${p.currency}'),
              const Divider(height: 1, color: Color(0xFF2A3242)),
              row('Transaction ID', p.txnId, copy: true),
            ]),
          ),
          const SizedBox(height: 18),
          DecoratedBox(
            decoration: BoxDecoration(gradient: PhlioColors.brandGradient, borderRadius: BorderRadius.circular(999)),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  navigator.push(MaterialPageRoute(
                    builder: (_) => TransactionHistoryScreen(
                      withUsername: peer,
                      withName: peerName,
                      highlightId: p.txnId,
                    ),
                  ));
                },
                child: SizedBox(
                  height: 52,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.receipt_long_rounded, color: PhlioColors.textOnBrand),
                    const SizedBox(width: 8),
                    Text('View in Phlio Pay',
                        style: PhlioTypography.bodyLarge.copyWith(color: PhlioColors.textOnBrand, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () {
              final router = GoRouter.of(context);
              switchPlatform(context, PhlioPlatform.pay);
              Navigator.of(context).pop();
              router.go('/home');
            },
            child: const Text('Open Phlio Pay'),
          ),
        ]),
      ),
    );
  }
}

/// One-line description for reply bars and previews.
String paymentSnippet(ChatPayment p, {required bool mine}) =>
    mine ? 'Payment · ${p.amount} sent' : 'Payment · ${p.amount} received';

