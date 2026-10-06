import '../../../../core/result/result.dart';
import '../entities/pay_entities.dart';

abstract interface class PayRepository {
  Future<Result<WalletEntity>> overview();

  Future<Result<List<TransactionEntity>>> transactions({String? cursor});

  Future<Result<TransactionEntity>> sendMoney({
    required String counterparty,
    required int amountMinorUnits,
    String note,
  });

  Future<Result<SplitEntity>> createSplit({
    required int totalMinorUnits,
    required List<String> participantNames,
    String note,
  });

  Future<Result<List<SplitEntity>>> splits({String? cursor});
}
