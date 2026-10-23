import 'package:flutter/material.dart';

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

  String get displayBalance {
    final value = balanceMinorUnits / 100;
    final text = value % 1 == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
    return '₹$text';
  }
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

  String get displayAmount {
    final value = amountMinorUnits / 100;
    final text = value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
    return '${isReceive ? '+' : '−'}₹$text';
  }
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

  String get displayTotal => '₹${(totalMinorUnits / 100).toStringAsFixed(0)}';
}
