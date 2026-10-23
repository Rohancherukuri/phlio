import '../../../../core/result/result.dart';
import '../entities/activity_entity.dart';

abstract interface class ActivityRepository {
  Future<Result<List<ActivityItemEntity>>> feed({String? cursor});

  Future<Result<void>> markAllRead();
}
