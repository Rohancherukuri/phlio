import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../domain/entities/home_overview_entity.dart';
import '../../domain/repositories/home_repository.dart';

final homeRepositoryProvider = Provider<HomeRepository>((ref) => getIt<HomeRepository>());

final homeOverviewProvider = FutureProvider.autoDispose<HomeOverviewEntity>((ref) async {
  final repository = ref.watch(homeRepositoryProvider);
  final result = await repository.getOverview();
  return result.when(success: (overview) => overview, failure: (failure) => throw failure);
});
