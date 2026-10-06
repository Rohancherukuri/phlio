// Phlio Pay — the Pay platform's home, formatted after the reference
// payments apps (PhonePe-style) in Phlio's design language:
//
//   banner → Offline Wallet card → Money Transfers → Recharge & Bills →
//   Loans → recent activity
//
// Scan & Pay lives on the bottom-nav center button while this platform is
// active (qr_scanner_screen.dart). Transfers are real against the simulated
// ledger; recharge/bill/loan services are honest "coming soon" entries —
// real rails require regulated partners (blueprint section 4).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/result/result.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/radii.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_button.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../../../design_system/widgets/phlio_fox.dart';
import '../../../../design_system/widgets/phlio_text_field.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../domain/entities/pay_entities.dart';
import '../controllers/pay_controller.dart';

class PayScreen extends ConsumerWidget {
  const PayScreen({super.key});

  void _comingSoon(BuildContext context, String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what — coming soon.')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync = ref.watch(walletProvider);
    final transactionsAsync = ref.watch(transactionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Phlio Pay'),
            Text('Scan. Pay. Earn.', style: PhlioTypography.caption.copyWith(height: 1.2)),
          ],
        ),
      ),
      body: walletAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => PhlioErrorView(
          failure: error is Failure ? error : const Failure.unknown(),
          onRetry: () => ref.invalidate(walletProvider),
        ),
        data: (wallet) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(walletProvider);
            ref.invalidate(transactionsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              PhlioSpacing.lg, PhlioSpacing.md, PhlioSpacing.lg, PhlioSpacing.xxl,
            ),
            children: [
              // -- Promo banner -------------------------------------------------
              _PromoBanner(),
              const SizedBox(height: PhlioSpacing.xl),

              // -- Offline Wallet card ------------------------------------------
              _OfflineWalletCard(wallet: wallet),
              const SizedBox(height: PhlioSpacing.xl),

              // -- Money Transfers ----------------------------------------------
              _SectionHeader(title: 'Money Transfers'),
              const SizedBox(height: PhlioSpacing.md),
              Row(
                children: [
                  _transferAction(
                    context,
                    icon: Icons.person_rounded,
                    color: PhlioColors.domainPay,
                    label: 'To Mobile\nNumber',
                    onTap: () => _openSendSheet(context),
                  ),
                  _transferAction(
                    context,
                    icon: Icons.account_balance_rounded,
                    color: PhlioColors.domainSocial,
                    label: 'To Bank &\nSelf A/c',
                    onTap: () => _comingSoon(context, 'Bank transfers'),
                  ),
                  _transferAction(
                    context,
                    icon: Icons.offline_bolt_rounded,
                    color: PhlioColors.brandOrange,
                    label: 'Offline\nWallet',
                    onTap: () => _showWalletDetails(context, wallet),
                  ),
                  _transferAction(
                    context,
                    icon: Icons.account_balance_wallet_outlined,
                    color: PhlioColors.domainRooms,
                    label: 'Check\nBalance',
                    onTap: () => _showWalletDetails(context, wallet),
                  ),
                ],
              ),
              const SizedBox(height: PhlioSpacing.xl),

              // -- Recharge & Bills ---------------------------------------------
              _SectionHeader(title: 'Recharge & Bills'),
              const SizedBox(height: PhlioSpacing.md),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: PhlioSpacing.md,
                childAspectRatio: 0.78,
                children: [
                  _serviceTile(context, Icons.bolt_rounded, PhlioColors.brandOrange,
                      'Mobile\nRecharge'),
                  _serviceTile(context, Icons.live_tv_rounded, PhlioColors.domainStream,
                      'DTH\nRecharge'),
                  _serviceTile(context, Icons.lightbulb_rounded, PhlioColors.warning,
                      'Electricity\nBill'),
                  _serviceTile(context, Icons.local_fire_department_rounded, PhlioColors.danger,
                      'Gas\nBill'),
                  _serviceTile(context, Icons.water_drop_rounded, PhlioColors.info,
                      'Water\nBill'),
                  _serviceTile(context, Icons.wifi_rounded, PhlioColors.domainSocial,
                      'Broadband'),
                  _serviceTile(context, Icons.home_work_outlined, PhlioColors.domainRooms,
                      'Rent'),
                  _serviceTile(context, Icons.account_balance_rounded, PhlioColors.domainPay,
                      'Loan\nRepayment'),
                ],
              ),
              const SizedBox(height: PhlioSpacing.xl),

              // -- Loans ----------------------------------------------------------
              _SectionHeader(title: 'Loans'),
              const SizedBox(height: PhlioSpacing.md),
              SizedBox(
                height: 116,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _loanCard(
                      context,
                      title: 'Personal Loan',
                      detail: 'Up to ₹5,00,000 · money in 2 min',
                      color: PhlioColors.brandViolet,
                    ),
                    _loanCard(
                      context,
                      title: 'Gold Loan',
                      detail: 'Get ₹50,000 against gold',
                      color: PhlioColors.brandOrange,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: PhlioSpacing.xl),

              // -- Recent activity ------------------------------------------------
              _SectionHeader(title: 'Recent activity'),
              const SizedBox(height: PhlioSpacing.md),
              transactionsAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(PhlioSpacing.lg),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (e, _) => PhlioErrorView(
                  failure: e is Failure ? e : const Failure.unknown(),
                  onRetry: () => ref.invalidate(transactionsProvider),
                ),
                data: (transactions) {
                  if (transactions.isEmpty) {
                    return PhlioCard(
                      child: Row(
                        children: [
                          const PhlioFox(size: 44, pose: PhlioFoxPose.coffee, animate: false),
                          const SizedBox(width: PhlioSpacing.md),
                          Expanded(
                            child: Text(
                              'No payments yet — send your first one above.',
                              style: PhlioTypography.body,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final txn in transactions) _TransactionTile(txn: txn),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -- pieces -----------------------------------------------------------------

  Widget _transferAction(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: PhlioRadii.lgRadius,
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: PhlioSpacing.xs),
            Text(
              label,
              textAlign: TextAlign.center,
              style: PhlioTypography.caption.copyWith(height: 1.25),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _serviceTile(
    BuildContext context,
    IconData icon,
    Color color,
    String label,
  ) {
    return InkWell(
      borderRadius: PhlioRadii.mdRadius,
      onTap: () => _comingSoon(context, label.replaceAll('\n', ' ')),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: PhlioColors.surface,
              borderRadius: PhlioRadii.mdRadius,
              border: Border.all(color: PhlioColors.borderSubtle),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: PhlioSpacing.xs),
          Text(
            label,
            textAlign: TextAlign.center,
            style: PhlioTypography.caption.copyWith(height: 1.25),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _loanCard(
    BuildContext context, {
    required String title,
    required String detail,
    required Color color,
  }) {
    return GestureDetector(
      onTap: () => _comingSoon(context, 'Loans'),
      child: Container(
        width: 240,
        margin: const EdgeInsets.only(right: PhlioSpacing.md),
        padding: const EdgeInsets.all(PhlioSpacing.lg),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.55), color.withValues(alpha: 0.22)],
          ),
          borderRadius: PhlioRadii.xlRadius,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: PhlioTypography.title.copyWith(color: Colors.white)),
            const SizedBox(height: PhlioSpacing.xs),
            Expanded(
              child: Text(
                detail,
                style: PhlioTypography.caption.copyWith(color: Colors.white70),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Apply',
                  style: PhlioTypography.label.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showWalletDetails(BuildContext context, WalletEntity wallet) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PhlioColors.surface,
        shape: RoundedRectangleBorder(borderRadius: PhlioRadii.xlRadius),
        title: Text('Offline Wallet', style: PhlioTypography.headline),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(wallet.displayBalance, style: PhlioTypography.displayLarge),
            const SizedBox(height: PhlioSpacing.sm),
            Text('Handle: ${wallet.upiHandle}', style: PhlioTypography.body),
            const SizedBox(height: PhlioSpacing.xs),
            Text(
              'Works without internet — balances sync when you are back online.',
              style: PhlioTypography.caption,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _openSendSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SendMoneySheet(),
    );
  }
}

// -- Banner -------------------------------------------------------------------

class _PromoBanner extends StatelessWidget {
  const _PromoBanner();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rewards arrive with Phlio Stream — coming soon.')),
      ),
      child: Container(
        height: 118,
        padding: const EdgeInsets.all(PhlioSpacing.lg),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [PhlioColors.brandViolet, PhlioColors.brandOrange],
          ),
          borderRadius: PhlioRadii.xlRadius,
        ),
        child: Stack(
          children: [
            // Decorative circles.
            Positioned(
              right: -18,
              top: -18,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
            ),
            Positioned(
              right: 42,
              bottom: -24,
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Scan & Pay, earn rewards',
                  style: PhlioTypography.title.copyWith(color: Colors.white),
                ),
                const SizedBox(height: PhlioSpacing.xxs),
                Text(
                  'Tap the scanner below — every payment counts.',
                  style: PhlioTypography.caption.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// -- Offline Wallet card --------------------------------------------------------

class _OfflineWalletCard extends ConsumerWidget {
  const _OfflineWalletCard({required this.wallet});

  final WalletEntity wallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PhlioCard(
      padding: const EdgeInsets.all(PhlioSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: PhlioColors.brandOrange.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.offline_bolt_rounded,
                    color: PhlioColors.brandOrange, size: 20),
              ),
              const SizedBox(width: PhlioSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Offline Wallet', style: PhlioTypography.bodyStrong),
                    Text('Works without internet', style: PhlioTypography.caption),
                  ],
                ),
              ),
              // Flexible + ellipsis: UPI handles are user-scoped ids and can
              // be long — they must shrink, never overflow the row.
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: PhlioColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    wallet.upiHandle,
                    style: PhlioTypography.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: PhlioSpacing.md),
          Text(wallet.displayBalance, style: PhlioTypography.displayLarge),
          const SizedBox(height: PhlioSpacing.xl),
          Row(
            children: [
              Expanded(
                child: PhlioPrimaryButton(
                  label: 'Send',
                  size: PhlioButtonSize.medium,
                  icon: Icons.arrow_upward_rounded,
                  onPressed: () => _openSendSheet(context),
                ),
              ),
              const SizedBox(width: PhlioSpacing.md),
              Expanded(
                child: PhlioSecondaryButton(
                  label: 'Split bill',
                  size: PhlioButtonSize.medium,
                  onPressed: () => _openSplitSheet(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openSendSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SendMoneySheet(),
    );
  }

  void _openSplitSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SplitSheet(),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: PhlioTypography.headline);
  }
}

// -- Transaction list -----------------------------------------------------------

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.txn});

  final TransactionEntity txn;

  @override
  Widget build(BuildContext context) {
    final color = txn.isReceive ? PhlioColors.success : PhlioColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: PhlioSpacing.sm),
      child: PhlioCard(
        padding: const EdgeInsets.all(PhlioSpacing.md),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (txn.isReceive ? PhlioColors.success : PhlioColors.brandOrange)
                    .withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                txn.isReceive ? Icons.south_west_rounded : Icons.north_east_rounded,
                size: 18,
                color: txn.isReceive ? PhlioColors.success : PhlioColors.brandOrange,
              ),
            ),
            const SizedBox(width: PhlioSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(txn.counterparty, style: PhlioTypography.bodyStrong),
                  if (txn.note.isNotEmpty)
                    Text(
                      txn.note,
                      style: PhlioTypography.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  txn.displayAmount,
                  style: PhlioTypography.bodyStrong.copyWith(color: color),
                ),
                Text(
                  timeago.format(txn.createdAt),
                  style: PhlioTypography.caption,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// -- Send money sheet -------------------------------------------------------------

class _SendMoneySheet extends ConsumerStatefulWidget {
  const _SendMoneySheet();

  @override
  ConsumerState<_SendMoneySheet> createState() => _SendMoneySheetState();
}

class _SendMoneySheetState extends ConsumerState<_SendMoneySheet> {
  final _counterpartyController = TextEditingController();
  final _amountController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _counterpartyController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final amountText = _amountController.text.trim().replaceAll(',', '');
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final repository = ref.read(payRepositoryProvider);
    final result = await repository.sendMoney(
      counterparty: _counterpartyController.text.trim(),
      amountMinorUnits: (amount * 100).round(),
      note: 'Phlio Pay transfer',
    );

    if (!mounted) return;
    result.when(
      success: (txn) {
        ref.invalidate(walletProvider);
        ref.invalidate(transactionsProvider);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sent ${txn.displayAmount.substring(1)} to ${txn.counterparty}.')),
        );
      },
      failure: (failure) => setState(() {
        _isSubmitting = false;
        _error = failure.message;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: PhlioSpacing.xl,
          right: PhlioSpacing.xl,
          top: PhlioSpacing.xl,
          bottom: PhlioSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Send money', style: PhlioTypography.headline),
            const SizedBox(height: PhlioSpacing.lg),
            PhlioTextField(
              controller: _counterpartyController,
              hintText: 'Send to (name or handle)',
              semanticLabel: 'Recipient',
              prefixIcon: Icons.person_outline_rounded,
            ),
            const SizedBox(height: PhlioSpacing.md),
            PhlioTextField(
              controller: _amountController,
              hintText: 'Amount (₹)',
              semanticLabel: 'Amount in rupees',
              prefixIcon: Icons.currency_rupee_rounded,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() => _error = null),
            ),
            if (_error != null) ...[
              const SizedBox(height: PhlioSpacing.sm),
              Text(_error!, style: PhlioTypography.caption.copyWith(color: PhlioColors.danger)),
            ],
            const SizedBox(height: PhlioSpacing.lg),
            PhlioPrimaryButton(
              label: 'Send',
              isLoading: _isSubmitting,
              onPressed: _send,
            ),
          ],
        ),
      ),
    );
  }
}

// -- Split sheet --------------------------------------------------------------------

class _SplitSheet extends ConsumerStatefulWidget {
  const _SplitSheet();

  @override
  ConsumerState<_SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends ConsumerState<_SplitSheet> {
  final _totalController = TextEditingController();
  final _namesController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _totalController.dispose();
    _namesController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final total = double.tryParse(_totalController.text.trim().replaceAll(',', ''));
    final names = _namesController.text
        .split(',')
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        .toList();
    if (total == null || total <= 0) {
      setState(() => _error = 'Enter a valid total.');
      return;
    }
    if (names.isEmpty) {
      setState(() => _error = 'Add at least one friend (comma separated).');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final repository = ref.read(payRepositoryProvider);
    final result = await repository.createSplit(
      totalMinorUnits: (total * 100).round(),
      participantNames: names,
      note: 'Bill split',
    );

    if (!mounted) return;
    result.when(
      success: (split) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Split ${split.displayTotal} across ${split.participants.length} people created.',
            ),
          ),
        );
      },
      failure: (failure) => setState(() {
        _isSubmitting = false;
        _error = failure.message;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: PhlioSpacing.xl,
          right: PhlioSpacing.xl,
          top: PhlioSpacing.xl,
          bottom: PhlioSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Split the bill', style: PhlioTypography.headline),
            const SizedBox(height: PhlioSpacing.xs),
            Text(
              'Everyone pays an equal share — you cover the rounding.',
              style: PhlioTypography.body,
            ),
            const SizedBox(height: PhlioSpacing.lg),
            PhlioTextField(
              controller: _totalController,
              hintText: 'Total amount (₹)',
              semanticLabel: 'Total amount in rupees',
              prefixIcon: Icons.receipt_long_outlined,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: PhlioSpacing.md),
            PhlioTextField(
              controller: _namesController,
              hintText: 'Friends (comma separated)',
              semanticLabel: 'Participant names separated by commas',
              prefixIcon: Icons.group_outlined,
              onChanged: (_) => setState(() => _error = null),
            ),
            if (_error != null) ...[
              const SizedBox(height: PhlioSpacing.sm),
              Text(_error!, style: PhlioTypography.caption.copyWith(color: PhlioColors.danger)),
            ],
            const SizedBox(height: PhlioSpacing.lg),
            PhlioPrimaryButton(
              label: 'Create split',
              isLoading: _isSubmitting,
              onPressed: _create,
            ),
          ],
        ),
      ),
    );
  }
}
