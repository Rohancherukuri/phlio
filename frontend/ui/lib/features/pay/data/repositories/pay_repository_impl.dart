import 'package:dio/dio.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/pay_entities.dart';
import '../../domain/repositories/pay_repository.dart';
import '../datasources/pay_remote_datasource.dart';
import '../models/pay_models.dart';

final _logger = createLogger('phlio.pay');

class PayRepositoryImpl implements PayRepository {
  const PayRepositoryImpl(this._remoteDataSource);

  final PayRemoteDataSource _remoteDataSource;

  @override
  Future<Result<WalletEntity>> overview() async {
    try {
      final json = await _remoteDataSource.overview();
      return Result.success(
        WalletEntity(
          balanceMinorUnits: json['balance_minor_units'] as int? ?? 0,
          currency: json['currency'] as String? ?? 'INR',
          upiHandle: json['upi_handle'] as String? ?? '',
          recentTransactions: ((json['recent_transactions'] as List<dynamic>? ?? []))
              .map((t) => TransactionModel.fromJson(t as Map<String, dynamic>).toEntity())
              .toList(),
        ),
      );
    } on DioException catch (e) {
      _logger.warning('pay.overview failed', error: e);
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<List<TransactionEntity>>> transactions({String? cursor}) async {
    try {
      final json = await _remoteDataSource.transactions(cursor: cursor);
      final items = ((json['items'] as List<dynamic>? ?? []))
          .map((t) => TransactionModel.fromJson(t as Map<String, dynamic>).toEntity())
          .toList();
      return Result.success(items);
    } on DioException catch (e) {
      _logger.warning('pay.transactions failed', error: e);
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<TransactionEntity>> sendMoney({
    required String counterparty,
    required int amountMinorUnits,
    String note = '',
  }) async {
    try {
      final json = await _remoteDataSource.sendMoney(
        counterparty: counterparty,
        amountMinorUnits: amountMinorUnits,
        note: note,
      );
      return Result.success(TransactionModel.fromJson(json).toEntity());
    } on DioException catch (e) {
      _logger.warning('pay.send_money failed', error: e);
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<SplitEntity>> createSplit({
    required int totalMinorUnits,
    required List<String> participantNames,
    String note = '',
  }) async {
    try {
      final json = await _remoteDataSource.createSplit(
        totalMinorUnits: totalMinorUnits,
        participantNames: participantNames,
        note: note,
      );
      return Result.success(SplitModel.fromJson(json).toEntity());
    } on DioException catch (e) {
      _logger.warning('pay.create_split failed', error: e);
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<List<SplitEntity>>> splits({String? cursor}) async {
    try {
      final json = await _remoteDataSource.splits(cursor: cursor);
      final items = ((json['items'] as List<dynamic>? ?? []))
          .map((s) => SplitModel.fromJson(s as Map<String, dynamic>).toEntity())
          .toList();
      return Result.success(items);
    } on DioException catch (e) {
      _logger.warning('pay.splits failed', error: e);
      return Result.failure(mapDioErrorToFailure(e));
    }
  }
}
