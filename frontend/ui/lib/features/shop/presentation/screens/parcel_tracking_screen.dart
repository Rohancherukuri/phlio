// Phlio Shop › Track parcels. Paste any tracking number (Amazon, Flipkart,
// Delhivery, Blue Dart, UPS, FedEx, DHL...) and follow it here: status,
// a 4-step progress bar, the estimated delivery date and every checkpoint.
//
// Backend: /api/v1/shop/tracking (AfterShip, server-side key) —
// see backend/app/api/v1/shop_tracking.py.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/colors.dart';

final parcelsProvider = FutureProvider.autoDispose<(List<Map<String, dynamic>>, bool)>((ref) async {
  final res = await getIt<ApiClient>().dio.get<dynamic>('/shop/tracking');
  final body = Map<String, dynamic>.from(res.data as Map);
  return (
    [for (final p in (body['items'] as List? ?? const [])) Map<String, dynamic>.from(p as Map)],
    body['configured'] != false,
  );
});

String _errorText(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      final err = data['error'];
      final msg = err is Map ? err['message'] : data['detail'];
      if (msg is String && msg.isNotEmpty) return msg;
    }
    if (e.response == null) return 'You seem to be offline.';
  }
  return 'Something went wrong. Try again.';
}

String? _date(String? iso, {bool time = false}) {
  if (iso == null || iso.isEmpty) return null;
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  if (!time) return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${d.day} ${months[d.month - 1]}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

Color _tagColor(String? tag) => switch (tag) {
      'Delivered' => const Color(0xFF39D98A),
      'OutForDelivery' => const Color(0xFFFFB020),
      'Exception' || 'AttemptFail' || 'Expired' => const Color(0xFFFF5C5C),
      'AvailableForPickup' => const Color(0xFF4CC9F0),
      _ => PhlioColors.brandViolet,
    };

IconData _tagIcon(String? tag) => switch (tag) {
      'Delivered' => Icons.check_circle_rounded,
      'OutForDelivery' => Icons.delivery_dining_rounded,
      'Exception' || 'AttemptFail' => Icons.error_rounded,
      'AvailableForPickup' => Icons.storefront_rounded,
      'InfoReceived' || 'Pending' => Icons.inventory_2_rounded,
      _ => Icons.local_shipping_rounded,
    };

class ParcelTrackingScreen extends ConsumerWidget {
  const ParcelTrackingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(parcelsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Track parcels')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addParcel(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Track a parcel'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(parcelsProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            const SizedBox(height: 120),
            Center(child: Text(_errorText(e))),
            Center(child: TextButton(onPressed: () => ref.invalidate(parcelsProvider), child: const Text('Retry'))),
          ]),
          data: (data) {
            final (items, configured) = data;
            if (items.isEmpty) {
              return ListView(padding: const EdgeInsets.all(32), children: [
                const SizedBox(height: 60),
                const Icon(Icons.local_shipping_outlined, size: 72, color: PhlioColors.textMuted),
                const SizedBox(height: 16),
                const Text('No parcels yet',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  configured
                      ? 'Paste a tracking number from any store or courier and we\'ll keep an eye on it.'
                      : 'Parcel tracking isn\'t set up on this server yet.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: PhlioColors.textMuted),
                ),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _ParcelCard(parcel: items[i]),
            );
          },
        ),
      ),
    );
  }

  Future<void> _addParcel(BuildContext context, WidgetRef ref) async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AddParcelSheet(),
    );
    if (added == true) ref.invalidate(parcelsProvider);
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.step, required this.color});
  final int step;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const labels = ['Shipped', 'In transit', 'Out for delivery', 'Delivered'];
    return Column(children: [
      Row(children: [
        for (var i = 0; i < 4; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              height: 6,
              decoration: BoxDecoration(
                color: i < step ? color : PhlioColors.surfaceElevated,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          if (i < 3) const SizedBox(width: 4),
        ],
      ]),
      const SizedBox(height: 6),
      Row(children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: Text(labels[i],
                textAlign: i == 0 ? TextAlign.start : i == 3 ? TextAlign.end : TextAlign.center,
                style: TextStyle(
                    fontSize: 10.5,
                    color: i < step ? PhlioColors.textPrimary : PhlioColors.textMuted,
                    fontWeight: i == step - 1 ? FontWeight.w800 : FontWeight.w500)),
          ),
      ]),
    ]);
  }
}

class _ParcelCard extends StatelessWidget {
  const _ParcelCard({required this.parcel});
  final Map<String, dynamic> parcel;

  @override
  Widget build(BuildContext context) {
    final p = parcel;
    final color = _tagColor(p['tag'] as String?);
    final eta = _date(p['eta'] as String?);
    final latest = (p['checkpoints'] as List?)?.cast<Map>().firstOrNull;
    final step = (p['step'] as num?)?.toInt();
    return Material(
      color: PhlioColors.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ParcelDetailScreen(parcel: p))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.16), child: Icon(_tagIcon(p['tag'] as String?), color: color)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${p['title'] ?? p['tracking_number']}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('${(p['courier'] ?? p['slug'] ?? 'Detecting courier').toString().toUpperCase()} · ${p['tracking_number']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: PhlioColors.textMuted)),
                ]),
              ),
              Text('${p['status']}', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12.5)),
            ]),
            if (step != null && step > 0) ...[const SizedBox(height: 14), _Progress(step: step, color: color)],
            if (latest != null || eta != null) const SizedBox(height: 12),
            if (eta != null && p['tag'] != 'Delivered')
              Text('Arriving $eta', style: const TextStyle(fontWeight: FontWeight.w700)),
            if (latest != null)
              Text(
                [latest['message'], latest['location']].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: PhlioColors.textMuted, fontSize: 12.5),
              ),
          ]),
        ),
      ),
    );
  }
}

class ParcelDetailScreen extends ConsumerStatefulWidget {
  const ParcelDetailScreen({required this.parcel, super.key});
  final Map<String, dynamic> parcel;

  @override
  ConsumerState<ParcelDetailScreen> createState() => _ParcelDetailScreenState();
}

class _ParcelDetailScreenState extends ConsumerState<ParcelDetailScreen> {
  late Map<String, dynamic> p = widget.parcel;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await getIt<ApiClient>().dio.get<dynamic>('/shop/tracking/${widget.parcel['id']}');
      if (mounted) setState(() => p = Map<String, dynamic>.from(res.data as Map));
    } catch (_) {
      // Keep showing the last known status.
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _remove() async {
    try {
      await getIt<ApiClient>().dio.delete<dynamic>('/shop/tracking/${p['id']}');
      ref.invalidate(parcelsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_errorText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _tagColor(p['tag'] as String?);
    final checkpoints = (p['checkpoints'] as List? ?? const []).cast<Map>();
    final step = (p['step'] as num?)?.toInt();
    final eta = _date(p['eta'] as String?);
    final link = p['courier_link'] as String?;
    return Scaffold(
      appBar: AppBar(
        title: Text('${p['title'] ?? 'Parcel'}'),
        actions: [
          IconButton(
            tooltip: 'Copy tracking number',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: '${p['tracking_number']}'));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tracking number copied')));
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'remove' ? _remove() : null,
            itemBuilder: (_) => const [PopupMenuItem(value: 'remove', child: Text('Stop tracking'))],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          if (loading) const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 8),
          Row(children: [
            Icon(_tagIcon(p['tag'] as String?), color: color, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${p['status']}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
                if (p['detail'] != null) Text('${p['detail']}', style: const TextStyle(color: PhlioColors.textMuted)),
              ]),
            ),
          ]),
          if (eta != null && p['tag'] != 'Delivered') ...[
            const SizedBox(height: 12),
            Text('Estimated delivery: $eta', style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
          if (step != null && step > 0) ...[const SizedBox(height: 18), _Progress(step: step, color: color)],
          const SizedBox(height: 18),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${(p['courier'] ?? p['slug'] ?? 'Courier').toString().toUpperCase()}'),
            subtitle: Text('${p['tracking_number']}'),
            trailing: link == null
                ? null
                : TextButton.icon(
                    onPressed: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Courier site'),
                  ),
          ),
          const Divider(),
          if (checkpoints.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No updates from the courier yet. Couriers usually post the first scan within a day.',
                  style: TextStyle(color: PhlioColors.textMuted)),
            ),
          for (var i = 0; i < checkpoints.length; i++)
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(
                  width: 28,
                  child: Column(children: [
                    const SizedBox(height: 4),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle, color: i == 0 ? color : PhlioColors.surfaceElevated),
                    ),
                    if (i < checkpoints.length - 1)
                      Expanded(child: Container(width: 2, color: PhlioColors.surfaceElevated)),
                  ]),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${checkpoints[i]['message']}',
                          style: TextStyle(fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w500)),
                      Text(
                        [checkpoints[i]['location'], _date(checkpoints[i]['time'] as String?, time: true)]
                            .where((x) => x != null && '$x'.isNotEmpty)
                            .join(' · '),
                        style: const TextStyle(color: PhlioColors.textMuted, fontSize: 12.5),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 12),
          const Text('Tracking by AfterShip', style: TextStyle(color: PhlioColors.textMuted, fontSize: 11)),
        ]),
      ),
    );
  }
}

class _AddParcelSheet extends StatefulWidget {
  const _AddParcelSheet();

  @override
  State<_AddParcelSheet> createState() => _AddParcelSheetState();
}

class _AddParcelSheetState extends State<_AddParcelSheet> {
  final _number = TextEditingController();
  final _title = TextEditingController();
  List<Map<String, dynamic>> couriers = const [];
  String? slug, error;
  bool busy = false;

  @override
  void dispose() {
    _number.dispose();
    _title.dispose();
    super.dispose();
  }

  bool get _valid => RegExp(r'^[A-Za-z0-9][A-Za-z0-9\-_. ]{3,63}$').hasMatch(_number.text.trim());

  Future<void> _detect() async {
    if (!_valid) return;
    try {
      final res = await getIt<ApiClient>()
          .dio
          .post<dynamic>('/shop/tracking/detect', data: {'tracking_number': _number.text.trim()});
      final list = [for (final c in ((res.data as Map)['couriers'] as List? ?? const [])) Map<String, dynamic>.from(c as Map)];
      if (mounted) setState(() => couriers = list.take(6).toList());
    } catch (_) {}
  }

  Future<void> _submit() async {
    if (!_valid || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await getIt<ApiClient>().dio.post<dynamic>('/shop/tracking', data: {
        'tracking_number': _number.text.trim(),
        if (slug != null) 'slug': slug,
        if (_title.text.trim().isNotEmpty) 'title': _title.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = _errorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Track a parcel', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        TextField(
          controller: _number,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: 'Tracking number',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: 'Paste',
              icon: const Icon(Icons.content_paste_rounded),
              onPressed: () async {
                final clip = await Clipboard.getData(Clipboard.kTextPlain);
                if (clip?.text != null) {
                  _number.text = clip!.text!.trim();
                  setState(() {});
                  _detect();
                }
              },
            ),
          ),
          onChanged: (_) => setState(() {
            couriers = const [];
            slug = null;
          }),
          onEditingComplete: _detect,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          maxLength: 80,
          decoration: const InputDecoration(
              labelText: 'What is it? (optional)', hintText: 'e.g. Running shoes', border: OutlineInputBorder()),
        ),
        if (couriers.length > 1) ...[
          const Text('Courier', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            ChoiceChip(label: const Text('Auto-detect'), selected: slug == null, onSelected: (_) => setState(() => slug = null)),
            for (final c in couriers)
              ChoiceChip(
                label: Text('${c['name']}'),
                selected: slug == c['slug'],
                onSelected: (_) => setState(() => slug = c['slug'] as String?),
              ),
          ]),
          const SizedBox(height: 10),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(error!, style: const TextStyle(color: Color(0xFFFF5C5C))),
          ),
        FilledButton(
          onPressed: _valid && !busy ? _submit : null,
          child: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Start tracking'),
        ),
      ]),
    );
  }
}
