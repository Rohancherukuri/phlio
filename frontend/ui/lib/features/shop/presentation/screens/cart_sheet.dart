import '../../../../shared/content/content_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../design_system/colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/config/app_config.dart';
import '../../domain/entities/product_entity.dart';
import '../../data/models/product_model.dart';
import '../controllers/cart_controller.dart';

Future<void> showShopCart(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) =>
        const FractionallySizedBox(heightFactor: .85, child: CartSheet()));

class AddToCartButton extends ConsumerStatefulWidget {
  const AddToCartButton(
      {required this.product, this.compact = false, super.key});
  final ProductEntity product;

  /// A 34px circular icon button for product grid tiles; the full labelled
  /// button is used on the product sheet.
  final bool compact;
  @override
  ConsumerState<AddToCartButton> createState() => _AddToCartButtonState();
}

class _AddToCartButtonState extends ConsumerState<AddToCartButton> {
  bool busy = false;

  Future<void> _add() async {
    HapticFeedback.selectionClick();
    setState(() => busy = true);
    try {
      await ref.read(cartProvider.notifier).add(widget.product.id);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${widget.product.title} added to cart'),
            action: SnackBarAction(
                label: 'View cart', onPressed: () => showShopCart(context))));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not add to cart. Please try again.')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget get _spinner => const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(
          strokeWidth: 2, color: PhlioColors.brandViolet));

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return Tooltip(
          message: 'Add to cart',
          child: Semantics(
              button: true,
              label: 'Add ${widget.product.title} to cart',
              child: Material(
                  color: PhlioColors.brandViolet.withValues(alpha: 0.16),
                  shape: const CircleBorder(),
                  child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: busy ? null : _add,
                      child: SizedBox(
                          width: 34,
                          height: 34,
                          child: Center(
                              child: busy
                                  ? _spinner
                                  : const Icon(Icons.add_shopping_cart_rounded,
                                      size: 18,
                                      color: PhlioColors.brandViolet)))))));
    }
    return FilledButton.tonalIcon(
        style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: const StadiumBorder()),
        icon: busy
            ? _spinner
            : const Icon(Icons.add_shopping_cart_rounded, size: 20),
        label: const Text('Add to cart'),
        onPressed: busy ? null : _add);
  }
}

class CartSheet extends ConsumerStatefulWidget {
  const CartSheet({super.key});
  @override
  ConsumerState<CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends ConsumerState<CartSheet> {
  bool busy = false;
  String? error;
  Future<void> update(String id, int quantity) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(cartProvider.notifier).setQuantity(id, quantity);
    } catch (_) {
      if (mounted)
        setState(() => error = 'Could not update your cart. Try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: Column(children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const Expanded(
                  child: Text('Your cart',
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700))),
              IconButton(
                  tooltip: 'Close cart',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ])),
        if (error != null)
          Padding(padding: const EdgeInsets.all(8), child: Text(error!)),
        Expanded(
            child: ref.watch(cartProvider).when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => Center(
                    child: TextButton(
                        onPressed: () => ref.invalidate(cartProvider),
                        child: const Text('Could not load cart. Retry'))),
                data: (cart) {
                  final items = cart['items'] as List;
                  if (items.isEmpty)
                    return Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.shopping_cart_outlined, size: 48),
                      const SizedBox(height: 12),
                      const Text('Your cart is empty'),
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Browse products'))
                    ]));
                  return ListView(padding: const EdgeInsets.all(16), children: [
                    for (final row in items) _item(row as Map),
                    const Divider(),
                    for (final total in (cart['totals'] as Map).entries)
                      ListTile(
                          title: Text('Subtotal (${total.key})'),
                          trailing: Text(
                              '${total.key} ${(total.value / 100).toStringAsFixed(2)}')),
                    const Text(
                        'Imported prices are snapshots. Confirm availability and final pricing with the retailer. Checkout is not yet available.',
                        style: TextStyle(fontSize: 12)),
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Add more items')),
                  ]);
                })),
      ]));

  Widget _item(Map row) {
    final p =
        ProductModel.fromJson(Map<String, dynamic>.from(row['product'] as Map))
            .toEntity();
    final quantity = row['quantity'] as int;
    return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 64,
              height: 72,
              child: p.imageUrls.isEmpty
                  ? const Icon(Icons.shopping_bag_outlined)
                  : Image.network(AppConfig.mediaUrl(p.imageUrls.first),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image_outlined))),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(p.displayPrice),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                  IconButton(
                      tooltip: 'Decrease quantity',
                      onPressed: busy ? null : () => update(p.id, quantity - 1),
                      icon: const Icon(Icons.remove)),
                  Text('$quantity'),
                  IconButton(
                      tooltip: 'Increase quantity',
                      onPressed: busy || quantity >= 99
                          ? null
                          : () => update(p.id, quantity + 1),
                      icon: const Icon(Icons.add)),
                  IconButton(
                      tooltip: 'Remove item',
                      onPressed: busy ? null : () => update(p.id, 0),
                      icon: const Icon(Icons.delete_outline)),
                ])
              ])),
        ]));
  }
}

Future<void> showShopProduct(
    BuildContext context, ProductEntity product) async {
  trackContentView(context, 'shop/${product.id}');
  await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
          heightFactor: .8,
          child: SafeArea(
              top: false,
              child: ListView(padding: const EdgeInsets.all(20), children: [
                if (product.imageUrls.isNotEmpty)
                  Image.network(AppConfig.mediaUrl(product.imageUrls.first),
                      height: 240,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox(
                          height: 100,
                          child: Icon(Icons.image_not_supported_outlined))),
                const SizedBox(height: 16),
                Text(product.title,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
                Text(product.category.label),
                Text(product.displayPrice,
                    style: const TextStyle(fontSize: 20)),
                const SizedBox(height: 12),
                Text(product.description),
                const SizedBox(height: 12),
                const Text('Product specifications',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text('Category: ${product.category.label}'),
                Text('Condition: ${product.condition.name}'),
                const Text('Stock: check with seller'),
                const Text('Variations: not provided by seller'),
                const SizedBox(height: 16),
                AddToCartButton(product: product),
                if (RegExp(r'https://[^\s]+').hasMatch(product.description))
                  TextButton.icon(
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('View original product'),
                      onPressed: () => launchUrl(
                          Uri.parse(RegExp(r'https://[^\s]+')
                              .firstMatch(product.description)!
                              .group(0)!),
                          mode: LaunchMode.externalApplication)),
                const SizedBox(height: 16),
                EngagementRow(path: 'shop/${product.id}'),
              ]))));
}
