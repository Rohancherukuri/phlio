// Phlio Pay — Scan & Pay (the bottom-nav center button while on Pay).
//
// Opens the camera (requesting the CAMERA permission through the scanner
// plugin on first use), detects QR codes, and turns UPI payment QRs into a
// confirmable transfer: `upi://pay?pa=…&pn=…&am=…` payloads decode into
// payee + amount and flow through the same simulated ledger as manual
// sends — scan only *prepares* the payment, the user always confirms.
// Non-UPI QRs show their decoded text.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/radii.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_button.dart';
import '../../../../design_system/widgets/phlio_fox.dart';
import '../../../../design_system/widgets/phlio_text_field.dart';
import '../controllers/pay_controller.dart';

class QrScannerScreen extends ConsumerStatefulWidget {
  const QrScannerScreen({super.key});

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();

  bool _handledScan = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handledScan) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;
      _handledScan = true;
      _controller.stop();
      _handleQrValue(value);
      return;
    }
  }

  Future<void> _handleQrValue(String value) async {
    final upi = _parseUpiUri(value);
    if (!mounted) return;

    if (upi == null) {
      // Not a payment QR — show what it decodes to.
      await showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(PhlioSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('QR code', style: PhlioTypography.headline),
                const SizedBox(height: PhlioSpacing.md),
                Container(
                  padding: const EdgeInsets.all(PhlioSpacing.md),
                  decoration: BoxDecoration(
                    color: PhlioColors.surfaceElevated,
                    borderRadius: PhlioRadii.mdRadius,
                  ),
                  child: SelectableText(value, style: PhlioTypography.body),
                ),
                const SizedBox(height: PhlioSpacing.lg),
                PhlioSecondaryButton(
                  label: 'Scan again',
                  onPressed: () => Navigator.of(sheetContext).pop(),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      await _openPaymentSheet(upi);
    }

    if (mounted) {
      // Resume scanning after the sheet closes.
      setState(() => _handledScan = false);
      _controller.start();
    }
  }

  /// `upi://pay?pa=vpa@bank&pn=Name&am=120.00&cu=INR` → params map, or null
  /// if this isn't a UPI payment URI.
  Map<String, String>? _parseUpiUri(String value) {
    if (!value.toLowerCase().startsWith('upi://pay')) return null;
    final query = Uri.tryParse(value)?.queryParameters ?? const {};
    return query.isEmpty ? null : Map<String, String>.from(query);
  }

  Future<void> _openPaymentSheet(Map<String, String> upi) async {
    final payee = upi['pa'] ?? 'Unknown payee';
    final payeeName = upi['pn'] ?? payee;
    final prefilledAmount = double.tryParse(upi['am'] ?? '');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _ScanPaymentSheet(
        payee: payee,
        payeeName: payeeName,
        prefilledAmount: prefilledAmount,
      ),
    );

    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Scan & Pay'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_rounded),
            tooltip: 'Toggle torch',
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              final isPermission = error.errorCode == MobileScannerErrorCode.permissionDenied;
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(PhlioSpacing.xxl),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const PhlioFox(size: 110, pose: PhlioFoxPose.curious),
                      const SizedBox(height: PhlioSpacing.lg),
                      Text(
                        isPermission ? 'Camera permission needed' : 'Camera unavailable',
                        style: PhlioTypography.headline.copyWith(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: PhlioSpacing.sm),
                      Text(
                        isPermission
                            ? 'Phlio needs the camera to scan QR codes. '
                                'Grant the permission in Settings and try again.'
                            : 'The camera could not start on this device.',
                        textAlign: TextAlign.center,
                        style: PhlioTypography.body.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          // Scan window + hint.
          IgnorePointer(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      border: Border.all(color: PhlioColors.brandOrange, width: 3),
                      borderRadius: PhlioRadii.xlRadius,
                    ),
                  ),
                  const SizedBox(height: PhlioSpacing.xl),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Point at a UPI QR code to pay',
                      style: PhlioTypography.body.copyWith(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Confirmable transfer built from the scanned QR. Amount is prefilled when
/// the QR carries one (`am=`); the user can edit it — nothing moves without
/// tapping Pay.
class _ScanPaymentSheet extends ConsumerStatefulWidget {
  const _ScanPaymentSheet({
    required this.payee,
    required this.payeeName,
    required this.prefilledAmount,
  });

  final String payee;
  final String payeeName;
  final double? prefilledAmount;

  @override
  ConsumerState<_ScanPaymentSheet> createState() => _ScanPaymentSheetState();
}

class _ScanPaymentSheetState extends ConsumerState<_ScanPaymentSheet> {
  late final TextEditingController _amountController = TextEditingController(
    text: widget.prefilledAmount?.toStringAsFixed(0) ?? '',
  );
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    final amount = double.tryParse(_amountController.text.trim().replaceAll(',', ''));
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
      counterparty: widget.payeeName,
      amountMinorUnits: (amount * 100).round(),
      note: 'Scan & pay · ${widget.payee}',
    );

    if (!mounted) return;
    result.when(
      success: (txn) {
        ref.invalidate(walletProvider);
        ref.invalidate(transactionsProvider);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Paid ${txn.displayAmount.substring(1)} to ${txn.counterparty}.')),
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
            Text('Pay via QR', style: PhlioTypography.headline),
            const SizedBox(height: PhlioSpacing.xs),
            Text(
              'Scanned payee: ${widget.payeeName}\n${widget.payee}',
              style: PhlioTypography.body,
            ),
            const SizedBox(height: PhlioSpacing.lg),
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
            PhlioPrimaryButton(label: 'Pay', isLoading: _isSubmitting, onPressed: _pay),
          ],
        ),
      ),
    );
  }
}
