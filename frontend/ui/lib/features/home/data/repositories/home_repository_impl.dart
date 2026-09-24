import 'package:dio/dio.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/home_overview_entity.dart';
import '../../domain/repositories/home_repository.dart';
import '../datasources/home_remote_datasource.dart';

class HomeRepositoryImpl implements HomeRepository {
  const HomeRepositoryImpl(this._remoteDataSource);

  final HomeRemoteDataSource _remoteDataSource;

  @override
  Future<Result<HomeOverviewEntity>> getOverview() async {
    try {
      final overview = await _remoteDataSource.getOverview();
      return Result.success(overview);
    } on DioException catch (e) {
      return Result.failure(mapDioErrorToFailure(e));
    }
  }
}
