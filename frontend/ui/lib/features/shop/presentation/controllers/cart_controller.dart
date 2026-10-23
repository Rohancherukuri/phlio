import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';

final cartProvider =
    AsyncNotifierProvider<CartController, Map<String, dynamic>>(
        CartController.new);

class CartController extends AsyncNotifier<Map<String, dynamic>> {
  @override
  Future<Map<String, dynamic>> build() async {
    final user = ref.watch(authControllerProvider).valueOrNull;
    if (user == null)
      return {'items': <dynamic>[], 'totals': <String, dynamic>{}, 'count': 0};
    return Map<String, dynamic>.from(
        (await getIt<ApiClient>().dio.get('/shop/cart')).data as Map);
  }

  bool busy = false;
  Future<void> setQuantity(String id, int quantity) async {
    if (busy) throw StateError('A cart update is already in progress.');
    final owner = ref.read(authControllerProvider).valueOrNull?.id;
    busy = true;
    try {
      final result = await getIt<ApiClient>()
          .dio
          .put('/shop/cart/$id', data: {'quantity': quantity});
      if (owner != null &&
          ref.read(authControllerProvider).valueOrNull?.id == owner) {
        state = AsyncData(Map<String, dynamic>.from(result.data as Map));
      }
    } finally {
      busy = false;
    }
  }

  Future<void> add(String id) async {
    final current = await future;
    final items = current['items'] as List;
    final matches = items.where((row) => row['product']['id'] == id);
    final quantity = matches.isEmpty ? 0 : matches.first['quantity'] as int;
    if (quantity >= 99) throw StateError('Maximum quantity is 99.');
    await setQuantity(id, quantity + 1);
  }
}
