// Phlio Pay — full transaction history: every payment sent and received,
// grouped by day, with search, Sent/Received filters and an optional
// "with @someone" filter (opened from a DM's pay sheet).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/radii.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_fox.dart';
import '../../../../shared/pay/phlio_currency.dart';
import '../../data/models/pay_models.dart';
import '../../domain/entities/pay_entities.dart';

enum _Filter { all, sent, received }

class TransactionHistoryScreen extends ConsumerStatefulWidget {
  const TransactionHistoryScreen({super.key, this.withUsername, this.withName, this.highlightId});

  /// A transaction to pick out (e.g. opened from a payment in chat).
  final String? highlightId;

  /// Show only payments with this person (handle without "@").
  final String? withUsername;
  final String? withName;

  @override
  ConsumerState<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends ConsumerState<TransactionHistoryScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final List<TransactionEntity> _items = [];
  String? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;
  _Filter _filter = _Filter.all;
  String? _with;

  @override
  void initState() {
    super.initState();
    _with = widget.withUsername?.replaceFirst('@', '');
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _items.clear();
      _cursor = null;
      _hasMore = true;
      _error = null;
    });
    await _load();
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final response = await getIt<ApiClient>().dio.get('/pay/transactions', queryParameters: {
        'limit': 50,
        if (_cursor != null) 'cursor': _cursor,
      });
      final data = response.data as Map<String, dynamic>;
      final items = [
        for (final t in (data['items'] as List<dynamic>? ?? const []))
          TransactionModel.fromJson(t as Map<String, dynamic>).toEntity(),
      ];
      final meta = data['meta'] as Map<String, dynamic>? ?? const {};
      if (!mounted) return;
      setState(() {
        _items.addAll(items);
        _cursor = meta['next_cursor'] as String?;
        _hasMore = (meta['has_more'] as bool? ?? false) && _cursor != null;
        _error = null;
      });
      // Keep paging while a filter hides most of what came back.
      if (_hasMore && _visible.length < 12) _loadSoon();
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn\'t load your transactions.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _loadSoon() => WidgetsBinding.instance.addPostFrameCallback((_) => _load());

  List<TransactionEntity> get _visible {
    final q = _search.text.trim().toLowerCase();
    return [
      for (final t in _items)
        if ((_filter == _Filter.all ||
                (_filter == _Filter.sent && !t.isReceive) ||
                (_filter == _Filter.received && t.isReceive)) &&
            (_with == null || t.counterparty.toLowerCase().contains('@${_with!.toLowerCase()}')) &&
            (q.isEmpty ||
                t.counterparty.toLowerCase().contains(q) ||
                t.note.toLowerCase().contains(q)))
          t,
    ];
  }

  String _day(BuildContext context, DateTime d) {
    final local = d.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return MaterialLocalizations.of(context).formatMediumDate(local);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final rows = <Widget>[];
    String? lastDay;
    for (final t in visible) {
      final day = _day(context, t.createdAt);
      if (day != lastDay) {
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, PhlioSpacing.lg, 4, PhlioSpacing.sm),
          child: Text(day, style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted)),
        ));
        lastDay = day;
      }
      rows.add(_HistoryTile(txn: t, highlight: t.id == widget.highlightId));
    }
    final sent = visible.where((t) => !t.isReceive).fold<int>(0, (a, t) => a + t.amountMinorUnits);
    final received = visible.where((t) => t.isReceive).fold<int>(0, (a, t) => a + t.amountMinorUnits);
    final currency = visible.isNotEmpty ? currencyByCode(visible.first.currency) : ref.watch(userCurrencyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Transaction history')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(PhlioSpacing.lg, PhlioSpacing.sm, PhlioSpacing.lg, PhlioSpacing.xxl),
          children: [
            Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.md),
              decoration: BoxDecoration(
                color: PhlioColors.surfaceInput,
                borderRadius: PhlioRadii.pillRadius,
                border: Border.all(color: PhlioColors.border),
              ),
              child: Row(children: [
                const Icon(Icons.search_rounded, size: 20, color: PhlioColors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Search name or note',
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: PhlioSpacing.md),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (_with != null)
                InputChip(
                  avatar: const Icon(Icons.person_outline_rounded, size: 18),
                  label: Text('With ${widget.withName ?? '@$_with'}'),
                  onDeleted: () => setState(() => _with = null),
                ),
              for (final f in _Filter.values)
                ChoiceChip(
                  label: Text(switch (f) { _Filter.all => 'All', _Filter.sent => 'Sent', _Filter.received => 'Received' }),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
            ]),
            if (visible.isNotEmpty) ...[
              const SizedBox(height: PhlioSpacing.md),
              Row(children: [
                _Total(label: 'Sent', value: currency.format(sent), color: PhlioColors.brandOrange),
                const SizedBox(width: PhlioSpacing.sm),
                _Total(label: 'Received', value: currency.format(received), color: PhlioColors.success),
              ]),
            ],
            ...rows,
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(PhlioSpacing.xl),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(PhlioSpacing.xl),
                child: Column(children: [
                  Text(_error!, style: PhlioTypography.body),
                  TextButton(onPressed: () { setState(() => _hasMore = true); _load(); }, child: const Text('Try again')),
                ]),
              )
            else if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: PhlioSpacing.xxxl),
                child: Column(children: [
                  const PhlioFox(size: 110, pose: PhlioFoxPose.sleepy),
                  const SizedBox(height: PhlioSpacing.md),
                  Text(_with != null ? 'No payments with ${widget.withName ?? '@$_with'} yet' : 'No transactions yet',
                      style: PhlioTypography.title),
                  const SizedBox(height: 4),
                  Text('Payments you send and receive will show up here.',
                      style: PhlioTypography.caption.copyWith(color: PhlioColors.textSecondary)),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(PhlioSpacing.md),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: PhlioRadii.lgRadius,
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: PhlioTypography.caption.copyWith(color: PhlioColors.textSecondary)),
            const SizedBox(height: 2),
            Text(value, style: PhlioTypography.title.copyWith(color: color)),
          ]),
        ),
      );
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.txn, this.highlight = false});

  final TransactionEntity txn;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final tint = txn.isReceive ? PhlioColors.success : PhlioColors.brandOrange;
    final time = TimeOfDay.fromDateTime(txn.createdAt.toLocal()).format(context);
    return Container(
      margin: const EdgeInsets.only(bottom: PhlioSpacing.sm),
      padding: const EdgeInsets.all(PhlioSpacing.md),
      decoration: BoxDecoration(
        color: highlight ? PhlioColors.brandViolet.withValues(alpha: 0.16) : PhlioColors.surfaceElevated,
        borderRadius: PhlioRadii.lgRadius,
        border: highlight ? Border.all(color: PhlioColors.brandViolet, width: 1.4) : null,
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: tint.withValues(alpha: 0.14), shape: BoxShape.circle),
          child: Icon(txn.isReceive ? Icons.south_west_rounded : Icons.north_east_rounded, size: 18, color: tint),
        ),
        const SizedBox(width: PhlioSpacing.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${txn.isReceive ? 'From' : 'To'} ${txn.counterparty}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: PhlioTypography.bodyStrong),
            Text(
              [time, if (txn.note.isNotEmpty) txn.note].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PhlioTypography.caption,
            ),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(txn.displayAmount,
              style: PhlioTypography.bodyStrong.copyWith(color: txn.isReceive ? PhlioColors.success : PhlioColors.textPrimary)),
          Text(txn.status == 'success' ? 'Completed' : txn.status,
              style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted)),
        ]),
      ]),
    );
  }
}
