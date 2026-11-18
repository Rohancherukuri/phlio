// Creator memberships in Phlio Social: the "Members only" tag on videos,
// the Join sheet (Razorpay Checkout in test mode — no real money), the
// Join button on creator pages and the creator's Membership settings.
//
// Backend: /api/v1/memberships (backend/app/api/v1/memberships.py). Locked
// videos come from the server without a playback URL; opening one asks
// [membershipGate] to show the Join sheet instead of playing.

import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../controllers/video_library.dart';

const kMemberGold = Color(0xFFFFC94D);

/// A locked video someone tried to open; [MembershipGateListener] shows the
/// Join sheet for it.
final membershipGate = ValueNotifier<PlayableVideo?>(null);

final creatorMembershipProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, username) async {
  ref.watch(membershipChangedProvider);
  final res = await getIt<ApiClient>().dio.get<dynamic>('/memberships/creators/${Uri.encodeComponent(username)}');
  return Map<String, dynamic>.from(res.data as Map);
});

String rupees(num minor) {
  final r = minor / 100;
  return r == r.roundToDouble() ? '₹${r.toStringAsFixed(0)}' : '₹${r.toStringAsFixed(2)}';
}

String _error(Object e) {
  if (e is DioException && e.response?.data is Map) {
    final d = e.response!.data as Map;
    final msg = d['detail'] ?? (d['error'] is Map ? (d['error'] as Map)['message'] : null);
    if (msg is String) return msg;
  }
  if (e is DioException && e.response?.statusCode == 404) return 'Memberships aren\'t on the server yet.';
  return 'Something went wrong. Try again.';
}

/// The gold "Members only" tag (with a lock while you're not a member).
class MembersOnlyTag extends StatelessWidget {
  const MembersOnlyTag({super.key, this.locked = false, this.compact = false});
  final bool locked, compact;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 2 : 4),
        decoration: BoxDecoration(color: kMemberGold, borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(locked ? Icons.lock_rounded : Icons.workspace_premium_rounded, size: compact ? 12 : 14, color: Colors.black),
          const SizedBox(width: 4),
          Text('Members only',
              style: TextStyle(color: Colors.black, fontSize: compact ? 10.5 : 12, fontWeight: FontWeight.w800)),
        ]),
      );
}

/// Dark veil with a lock and the price, laid over a locked thumbnail.
class LockedVeil extends StatelessWidget {
  const LockedVeil({required this.video, super.key});
  final PlayableVideo video;

  @override
  Widget build(BuildContext context) {
    final price = video.membership?['price_minor_units'] as num?;
    return IgnorePointer(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_rounded, color: Colors.white, size: 30),
          const SizedBox(height: 6),
          Text(price == null ? 'Join to watch' : 'Join for ${rupees(price)}/month',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}

/// Listens for locked videos being opened and shows the Join sheet. Put it
/// once around the Social home.
class MembershipGateListener extends StatefulWidget {
  const MembershipGateListener({required this.child, super.key});
  final Widget child;

  @override
  State<MembershipGateListener> createState() => _MembershipGateListenerState();
}

class _MembershipGateListenerState extends State<MembershipGateListener> {
  @override
  void initState() {
    super.initState();
    membershipGate.addListener(_open);
  }

  @override
  void dispose() {
    membershipGate.removeListener(_open);
    super.dispose();
  }

  void _open() {
    final video = membershipGate.value;
    if (video == null || !mounted) return;
    membershipGate.value = null;
    showJoinMembership(context, video.creator, video: video);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Join button for a creator page; hidden when the creator has no plan.
class CreatorJoinButton extends ConsumerWidget {
  const CreatorJoinButton({required this.username, super.key});
  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(creatorMembershipProvider(username)).valueOrNull;
    if (info == null || info['plan'] == null || info['is_creator'] == true) return const SizedBox.shrink();
    final member = info['member'] == true;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        height: 44,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: member ? PhlioColors.surfaceElevated : kMemberGold,
            foregroundColor: member ? PhlioColors.textPrimary : Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
          onPressed: () => showJoinMembership(context, username),
          icon: Icon(member ? Icons.workspace_premium_rounded : Icons.star_rounded, size: 18),
          label: Text(member ? 'Member' : 'Join'),
        ),
      ),
    );
  }
}

Future<void> showJoinMembership(BuildContext context, String username, {PlayableVideo? video}) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: PhlioColors.surface,
      builder: (_) => _JoinSheet(username: username, video: video),
    );

class _JoinSheet extends ConsumerStatefulWidget {
  const _JoinSheet({required this.username, this.video});
  final String username;
  final PlayableVideo? video;

  @override
  ConsumerState<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends ConsumerState<_JoinSheet> {
  final _api = getIt<ApiClient>().dio;
  Razorpay? _checkout;
  Map? _order;
  String? _requestId, error;
  bool busy = false, joined = false;

  bool get _supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (_supported) {
      _checkout = Razorpay()
        ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _paid)
        ..on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
          if (mounted) {
            setState(() {
              busy = false;
              error = r.code == Razorpay.PAYMENT_CANCELLED ? null : (r.message ?? 'Payment failed.');
            });
          }
        });
    }
  }

  @override
  void dispose() {
    _checkout?.clear();
    super.dispose();
  }

  String _newRequestId() {
    final random = Random.secure();
    final hex = List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-4${hex.substring(13, 16)}-a${hex.substring(17, 20)}-${hex.substring(20)}';
  }

  Future<void> _join(Map info) async {
    if (!_supported) {
      setState(() => error = 'Checkout works in the Android and iOS apps.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      _requestId ??= _newRequestId();
      final order = (await _api.post<dynamic>('/memberships/creators/${Uri.encodeComponent(widget.username)}/join',
              data: {'request_id': _requestId}))
          .data as Map;
      _order = order;
      _checkout!.open({
        'key': order['key_id'],
        'order_id': order['razorpay_order_id'],
        'amount': order['amount'],
        'currency': 'INR',
        'name': 'Phlio',
        'description': 'Membership: ${info['creator_name'] ?? widget.username} (test mode)',
        'theme': {'color': '#9568E8'},
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = _error(e);
        });
      }
    }
  }

  Future<void> _paid(PaymentSuccessResponse r) async {
    final order = _order;
    if (order == null) return;
    // Razorpay can take a moment to mark the payment captured.
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        await _api.post<dynamic>('/memberships/orders/${order['id']}/verify',
            data: {'payment_id': r.paymentId, 'signature': r.signature});
        ref.read(membershipChangedProvider.notifier).state++;
        if (mounted) {
          setState(() {
            busy = false;
            joined = true;
          });
        }
        return;
      } catch (e) {
        final retry = e is DioException && e.response?.statusCode == 409;
        if (!retry || attempt == 3) {
          if (mounted) {
            setState(() {
              busy = false;
              error = _error(e);
            });
          }
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(creatorMembershipProvider(widget.username));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: async.when(
          loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => SizedBox(height: 160, child: Center(child: Text(_error(e)))),
          data: (info) {
            final plan = info['plan'] as Map?;
            if (plan == null) {
              return const SizedBox(
                  height: 140, child: Center(child: Text("This creator doesn't offer a membership right now.")));
            }
            final member = joined || info['member'] == true;
            final perks = (plan['perks'] as List? ?? const []).cast<String>();
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(
                child: PhlioAvatar(
                    name: '${info['creator_name'] ?? widget.username}', imageUrl: info['avatar_url'] as String?, size: 64),
              ),
              const SizedBox(height: 10),
              Text('${info['creator_name'] ?? widget.username}',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                  widget.video != null && !member
                      ? '"${widget.video!.title}" is for members'
                      : '${plan['title']} membership',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: PhlioColors.textMuted)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kMemberGold.withValues(alpha: 0.6)),
                  color: kMemberGold.withValues(alpha: 0.08),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const MembersOnlyTag(),
                    const Spacer(),
                    Text('${rupees(plan['price_minor_units'] as num)} / month',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                  ]),
                  const SizedBox(height: 12),
                  const _Perk('Watch members-only videos and clips'),
                  for (final p in perks) _Perk(p),
                ]),
              ),
              const SizedBox(height: 12),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF5C5C))),
                ),
              if (member)
                Column(children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF39D98A), size: 36),
                  const SizedBox(height: 6),
                  Text(joined ? "You're a member! Enjoy." : "You're a member.",
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (info['until'] != null)
                    Text('Until ${'${info['until']}'.split('T').first}',
                        style: const TextStyle(color: PhlioColors.textMuted)),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
                ])
              else
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: busy ? null : () => _join(info),
                    style: FilledButton.styleFrom(
                      backgroundColor: kMemberGold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('Join for ${rupees(plan['price_minor_units'] as num)}/month',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ),
              const SizedBox(height: 8),
              const Text('Test mode: Razorpay sandbox, no real money is charged. One month, renew any time.',
                  textAlign: TextAlign.center, style: TextStyle(color: PhlioColors.textMuted, fontSize: 11.5)),
            ]);
          },
        ),
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.check_rounded, size: 18, color: kMemberGold),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ]),
      );
}

/// Creator settings: turn the membership on, set the price and perks.
class MembershipSettingsScreen extends StatefulWidget {
  const MembershipSettingsScreen({super.key});

  @override
  State<MembershipSettingsScreen> createState() => _MembershipSettingsScreenState();
}

class _MembershipSettingsScreenState extends State<MembershipSettingsScreen> {
  final _api = getIt<ApiClient>().dio;
  final _price = TextEditingController(text: '49');
  final _title = TextEditingController(text: 'Member');
  final _perks = <TextEditingController>[];
  bool enabled = true, loading = true, saving = false;
  int members = 0;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _price.dispose();
    _title.dispose();
    for (final p in _perks) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = (await _api.get<dynamic>('/memberships/plan')).data as Map;
      final raw = (data['raw'] as Map?) ?? const {};
      if (raw.isNotEmpty) {
        _price.text = ((raw['price_minor_units'] as num) / 100).toStringAsFixed(0);
        _title.text = '${raw['title'] ?? 'Member'}';
        enabled = raw['enabled'] == true;
        for (final p in (raw['perks'] as List? ?? const [])) {
          _perks.add(TextEditingController(text: '$p'));
        }
      }
      members = (data['active_members'] as num?)?.toInt() ?? 0;
    } catch (e) {
      error = _error(e);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    final price = double.tryParse(_price.text.trim());
    if (price == null || price < 10 || price > 5000) {
      setState(() => error = 'Price must be between ₹10 and ₹5,000 a month.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await _api.put<dynamic>('/memberships/plan', data: {
        'enabled': enabled,
        'price_minor_units': (price * 100).round(),
        'title': _title.text.trim().isEmpty ? 'Member' : _title.text.trim(),
        'perks': [for (final p in _perks) if (p.text.trim().isNotEmpty) p.text.trim()],
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Membership saved')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = _error(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Membership')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(20), children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: enabled,
                onChanged: (v) => setState(() => enabled = v),
                title: const Text('Offer a membership', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('$members active member${members == 1 ? '' : 's'}'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Price per month', prefixText: '₹ '),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                maxLength: 40,
                decoration: const InputDecoration(labelText: 'Membership name', hintText: 'e.g. Studio pass'),
              ),
              const Text('Perks', style: TextStyle(fontWeight: FontWeight.w700)),
              for (var i = 0; i < _perks.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextField(
                    controller: _perks[i],
                    maxLength: 80,
                    decoration: InputDecoration(
                      hintText: 'e.g. Early access to videos',
                      suffixIcon: IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() => _perks.removeAt(i).dispose()),
                      ),
                    ),
                  ),
                ),
              if (_perks.length < 6)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _perks.add(TextEditingController())),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add a perk'),
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                  'Mark videos "Members only" when you upload them, or from a video\'s ⋮ menu. Payments run in Razorpay test mode.',
                  style: TextStyle(color: PhlioColors.textMuted, fontSize: 12.5)),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!, style: const TextStyle(color: Color(0xFFFF5C5C))),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: saving ? null : _save,
                child: saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ]),
    );
  }
}

/// Owner menu action: toggle members-only on one of my videos.
Future<bool?> setVideoMembersOnly(BuildContext context, String videoId, bool value) async {
  try {
    await getIt<ApiClient>().dio.put<dynamic>('/memberships/videos/$videoId', data: {'members_only': value});
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value ? 'Now members only' : 'Now visible to everyone')));
    }
    return value;
  } catch (e) {
    if (context.mounted) {
      final setup = e is DioException && e.response?.statusCode == 409;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_error(e)),
        action: setup
            ? SnackBarAction(
                label: 'Set up',
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => const MembershipSettingsScreen())))
            : null,
      ));
    }
    return null;
  }
}

// Keep `unawaited` available for callers that fire-and-forget the sheet.
void openJoin(BuildContext context, String username) => unawaited(showJoinMembership(context, username));
