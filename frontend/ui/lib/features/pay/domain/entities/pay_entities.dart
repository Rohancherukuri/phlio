import 'package:flutter/material.dart';

import '../../../../shared/pay/phlio_currency.dart';

@immutable
class WalletEntity {
  const WalletEntity({
    required this.balanceMinorUnits,
    required this.currency,
    required this.upiHandle,
    required this.recentTransactions,
  });

  final int balanceMinorUnits;
  final String currency;
  final String upiHandle;
  final List<TransactionEntity> recentTransactions;

  String get displayBalance => currencyByCode(currency).format(balanceMinorUnits);
}

@immutable
class TransactionEntity {
  const TransactionEntity({
    required this.id,
    required this.type,
    required this.counterparty,
    required this.amountMinorUnits,
    required this.note,
    required this.currency,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String type; // 'send' | 'receive'
  final String counterparty;
  final int amountMinorUnits;
  final String note;
  final String currency;
  final String status;
  final DateTime createdAt;

  bool get isReceive => type == 'receive';

  String get displayAmount => currencyByCode(currency)
      .format(amountMinorUnits, signed: true, negative: !isReceive);
}

@immutable
class SplitParticipantEntity {
  const SplitParticipantEntity({
    required this.name,
    required this.amountMinorUnits,
    required this.hasPaid,
  });

  final String name;
  final int amountMinorUnits;
  final bool hasPaid;
}

@immutable
class SplitEntity {
  const SplitEntity({
    required this.id,
    required this.note,
    required this.totalMinorUnits,
    required this.currency,
    required this.participants,
    required this.createdAt,
  });

  final String id;
  final String note;
  final int totalMinorUnits;
  final String currency;
  final List<SplitParticipantEntity> participants;
  final DateTime createdAt;

  String get displayTotal => currencyByCode(currency).format(totalMinorUnits);
}
