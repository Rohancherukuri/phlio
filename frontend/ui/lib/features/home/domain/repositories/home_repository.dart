import '../../../../core/result/result.dart';
import '../entities/home_overview_entity.dart';

abstract interface class HomeRepository {
  Future<Result<HomeOverviewEntity>> getOverview();
}
