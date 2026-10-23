import 'package:dio/dio.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/activity_entity.dart';
import '../../domain/repositories/activity_repository.dart';
import '../datasources/activity_remote_datasource.dart';
import '../models/activity_model.dart';

final _logger = createLogger('phlio.activity');

class ActivityRepositoryImpl implements ActivityRepository {
  const ActivityRepositoryImpl(this._remoteDataSource);

  final ActivityRemoteDataSource _remoteDataSource;

  @override
  Future<Result<List<ActivityItemEntity>>> feed({String? cursor}) async {
    try {
      final json = await _remoteDataSource.feed(cursor: cursor);
      final items = ((json['items'] as List<dynamic>? ?? []))
          .map((item) => ActivityItemModel.fromJson(item as Map<String, dynamic>))
          .toList();
      return Result.success(items);
    } on DioException catch (e) {
      _logger.warning('activity.feed failed', error: e);
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<void>> markAllRead() async {
    try {
      await _remoteDataSource.markAllRead();
      return const Result.success(null);
    } on DioException catch (e) {
      _logger.warning('activity.mark_all_read failed', error: e);
      return Result.failure(mapDioErrorToFailure(e));
    }
  }
}
