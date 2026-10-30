import 'dart:math';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import 'payment_status_view.dart';

class PayGatewayScreen extends StatefulWidget {
  const PayGatewayScreen({super.key});
  @override
  State<PayGatewayScreen> createState() => _PayGatewayScreenState();
}

class _PayGatewayScreenState extends State<PayGatewayScreen> {
  final api = getIt<ApiClient>().dio;
  final amount = TextEditingController(text: '1.00');
  Razorpay? checkout;
  Map? config, current;
  List payments = [], statements = [];
  String? error;
  bool busy = false;
  String? pendingRequest;
  int? pendingAmount;
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  @override
  void initState() {
    super.initState();
    if (supported) {
      checkout = Razorpay();
      checkout!.on(Razorpay.EVENT_PAYMENT_SUCCESS,
          (PaymentSuccessResponse response) async {
        if (current == null) return;
        await work(() async {
          current = (await api
                  .post('/pay/gateway/orders/${current!['id']}/verify', data: {
            'payment_id': response.paymentId,
            'signature': response.signature
          }))
              .data as Map;
          await load();
        });
      });
      checkout!.on(Razorpay.EVENT_PAYMENT_ERROR,
          (PaymentFailureResponse response) async {
        // A dismissed/failed client checkout is not proof that no money moved.
        await check();
      });
    }
    work(load);
  }

  @override
  void dispose() {
    checkout?.clear();
    amount.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final c = (await api.get('/pay/gateway/config')).data as Map;
    final h = (await api.get('/pay/gateway/history')).data as Map;
    if (!mounted) return;
    setState(() {
      config = c;
      payments = h['payments'] as List;
      statements = h['statements'] as List;
    });
  }

  Future<void> work(Future<void> Function() action) async {
    if (!mounted || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted)
        setState(() => error = e is DioException &&
                e.response?.data is Map &&
                e.response!.data['detail'] is String
            ? e.response!.data['detail'] as String
            : 'Could not reach Phlio Pay. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> check() => work(() async {
        if (current != null)
          current = (await api.get('/pay/gateway/orders/${current!['id']}'))
              .data as Map;
        await load();
      });
  String requestId() {
    final random = Random.secure();
    final hex =
        List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-4${hex.substring(13, 16)}-a${hex.substring(17, 20)}-${hex.substring(20)}';
  }

  Future<void> pay() => work(() async {
        final input = amount.text.trim();
        if (!RegExp(r'^\d{1,6}(\.\d{1,2})?$').hasMatch(input)) {
          setState(
              () => error = 'Enter an amount with at most two decimal places.');
          return;
        }
        final parts = input.split('.');
        final minor = int.parse(parts[0]) * 100 +
            (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
        if (minor < 100 || minor > 10000000) {
          setState(() => error = 'Enter INR 1 to INR 100,000.');
          return;
        }
        if (pendingAmount != null && pendingAmount != minor) {
          setState(() => error =
              'Check the previous payment in history before changing the amount.');
          return;
        }
        pendingRequest ??= requestId();
        pendingAmount = minor;
        final order = (await api.post('/pay/gateway/orders', data: {
          'amount_minor_units': minor,
          'request_id': pendingRequest
        }))
            .data as Map;
        if (!mounted) return;
        setState(() => current = order);
        checkout!.open({
          'key': order['key_id'],
          'order_id': order['order_id'],
          'amount': order['amount'],
          'currency': 'INR',
          'name': 'Phlio Pay',
          'description': 'Sandbox merchant payment',
          'theme': {'color': '#9568E8'}
        });
      });
  Future<void> importCsv() => work(() async {
        final picked = await FilePicker.pickFiles(
            type: FileType.custom, allowedExtensions: ['csv'], withData: true);
        if (picked == null) return;
        final file = picked.files.single;
        if (file.size > 2 * 1024 * 1024) {
          setState(() => error = 'Choose a CSV smaller than 2 MB.');
          return;
        }
        final preview = (await api.post('/pay/gateway/statements/preview',
                data: FormData.fromMap({
                  'file':
                      MultipartFile.fromBytes(file.bytes!, filename: file.name)
                })))
            .data as Map;
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
                    title: Text('Import ${preview['count']} transactions?'),
                    content: SizedBox(
                        width: 360,
                        height: 300,
                        child: ListView(children: [
                          const Text(
                              'Imported history only. This does not move money or change your wallet balance.'),
                          for (final item in preview['items'] as List)
                            ListTile(
                                dense: true,
                                title: Text(item['description']),
                                subtitle: Text(
                                    "${item['date']} · ${item['method']} · ${item['direction']}"),
                                trailing: Text(
                                    (item['amount_minor_units'] / 100)
                                        .toStringAsFixed(2))),
                        ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Import'))
                    ]));
        if (confirmed != true) return;
        final result = (await api.post('/pay/gateway/statements/import',
                data: {'token': preview['token']}))
            .data as Map;
        await load();
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  "${result['imported']} imported · ${result['duplicates']} duplicates skipped")));
      });
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Payments & statements')),
      body: RefreshIndicator(
          onRefresh: () => work(load),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            const Text('SANDBOX · NO REAL MONEY',
                style: TextStyle(
                    color: Color(0xFFFFB38E), fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('UPI & card checkout',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const Text(
                'Merchant checkout using Razorpay. Person-to-person UPI transfers are not connected.'),
            if (config?['configured'] != true)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                      'Checkout setup pending. Add Razorpay test keys on the server. Statement import and animation previews are available now.')),
            TextField(
                controller: amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Amount in INR', helperText: 'INR 1–100,000')),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: busy || !supported || config?['configured'] != true
                    ? null
                    : pay,
                child: const Text('Open sandbox checkout')),
            if (current != null && current!['status'] != 'processing')
              TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                            current = null;
                            pendingRequest = null;
                            pendingAmount = null;
                          }),
                  child: const Text('New sandbox payment')),
            if (error != null)
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(error!,
                      style: const TextStyle(color: Colors.orangeAccent))),
            if (busy) const LinearProgressIndicator(),
            if (current != null) ...[
              PaymentStatusView(
                  status: current!['status'], amount: current!['amount']),
              Text('Order: ${current!['order_id'] ?? current!['id']}'),
              TextButton(
                  onPressed: busy ? null : check,
                  child: const Text('Check payment status')),
            ],
            ExpansionTile(
                title: const Text('Preview payment animations'),
                children: [
                  Wrap(spacing: 8, children: [
                    for (final state in ['processing', 'success', 'failed'])
                      TextButton(
                          onPressed: () => showModalBottomSheet(
                              context: context,
                              showDragHandle: true,
                              builder: (_) => SafeArea(
                                  child: PaymentStatusView(
                                      status: state, preview: true))),
                          child: Text(state)),
                  ])
                ]),
            const Divider(height: 32),
            const Text('Bank & card statements',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Text(
                'Import a UTF-8 CSV with: date (YYYY-MM-DD), description, amount, direction (debit/credit), method (upi/debit_card/credit_card/bank/cash/other), account (nickname or last four digits). Optional: reference.'),
            OutlinedButton.icon(
                onPressed: busy ? null : importCsv,
                icon: const Icon(Icons.upload_file),
                label: const Text('Preview statement import')),
            for (final row in statements)
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(row['method'] == 'upi'
                      ? Icons.qr_code
                      : row['method'].toString().contains('card')
                          ? Icons.credit_card
                          : Icons.account_balance_outlined),
                  title: Text(row['description']),
                  subtitle: Text(
                      "${row['date']} · ${row['method']} · ${row['account']}\nImported statement"),
                  trailing: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                        "${row['direction'] == 'debit' ? '-' : '+'} INR ${(row['amount_minor_units'] / 100).toStringAsFixed(2)}"),
                    InkWell(
                        onTap: busy
                            ? null
                            : () => work(() async {
                                  await api.delete(
                                      '/pay/gateway/statements/${row['id']}');
                                  await load();
                                }),
                        child: const Padding(
                            padding: EdgeInsets.all(6), child: Text('Remove')))
                  ])),
            const Divider(height: 32),
            const Text('Sandbox payment history',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            if (payments.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No sandbox payments yet.')),
            for (final row in payments)
              ListTile(
                  title: Text(
                      'INR ${(row['amount'] / 100).toStringAsFixed(2)} · ${row['status']}'),
                  subtitle:
                      Text(row['order_id'] ?? 'Order creation unresolved'),
                  trailing: const Icon(Icons.refresh),
                  onTap: busy
                      ? null
                      : () {
                          setState(() => current = row);
                          check();
                        }),
          ])));
}
