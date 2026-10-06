// Pay feature state management (Riverpod).
//
// `walletProvider` is the source of truth for the balance card; sending
// money or creating a split invalidates it (plus the transactions list) so
// the next read refetches. Plain `FutureProvider`s are enough — no
// optimistic local mutations needed at this stage.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../domain/entities/pay_entities.dart';
import '../../domain/repositories/pay_repository.dart';

final payRepositoryProvider = Provider<PayRepository>((ref) => getIt<PayRepository>());

final walletProvider = FutureProvider.autoDispose<WalletEntity>((ref) async {
  final repository = ref.watch(payRepositoryProvider);
  final result = await repository.overview();
  return result.when(success: (wallet) => wallet, failure: (failure) => throw failure);
});

final transactionsProvider = FutureProvider.autoDispose<List<TransactionEntity>>((ref) async {
  final repository = ref.watch(payRepositoryProvider);
  final result = await repository.transactions();
  return result.when(success: (items) => items, failure: (failure) => throw failure);
});
