import '../../domain/entities/pay_entities.dart';

class TransactionModel {
  const TransactionModel({
    required this.id,
    required this.type,
    required this.counterparty,
    required this.amountMinorUnits,
    required this.note,
    required this.currency,
    required this.status,
    required this.createdAt,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id'] as String,
      type: json['type'] as String? ?? 'send',
      counterparty: json['counterparty'] as String? ?? '',
      amountMinorUnits: json['amount_minor_units'] as int? ?? 0,
      note: json['note'] as String? ?? '',
      currency: json['currency'] as String? ?? 'INR',
      status: json['status'] as String? ?? 'success',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String type;
  final String counterparty;
  final int amountMinorUnits;
  final String note;
  final String currency;
  final String status;
  final DateTime createdAt;

  TransactionEntity toEntity() => TransactionEntity(
        id: id,
        type: type,
        counterparty: counterparty,
        amountMinorUnits: amountMinorUnits,
        note: note,
        currency: currency,
        status: status,
        createdAt: createdAt,
      );
}

class SplitModel {
  const SplitModel({
    required this.id,
    required this.note,
    required this.totalMinorUnits,
    required this.currency,
    required this.participants,
    required this.createdAt,
  });

  factory SplitModel.fromJson(Map<String, dynamic> json) {
    return SplitModel(
      id: json['id'] as String,
      note: json['note'] as String? ?? '',
      totalMinorUnits: json['total_minor_units'] as int? ?? 0,
      currency: json['currency'] as String? ?? 'INR',
      participants: ((json['participants'] as List<dynamic>? ?? []))
          .map((p) => SplitParticipantEntity(
                name: (p as Map<String, dynamic>)['name'] as String? ?? '',
                amountMinorUnits: p['amount_minor_units'] as int? ?? 0,
                hasPaid: p['has_paid'] as bool? ?? false,
              ))
          .toList(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String note;
  final int totalMinorUnits;
  final String currency;
  final List<SplitParticipantEntity> participants;
  final DateTime createdAt;

  SplitEntity toEntity() => SplitEntity(
        id: id,
        note: note,
        totalMinorUnits: totalMinorUnits,
        currency: currency,
        participants: participants,
        createdAt: createdAt,
      );
}
