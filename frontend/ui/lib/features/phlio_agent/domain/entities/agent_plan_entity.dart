import 'package:equatable/equatable.dart';

enum PlanItemKind { room, product, post, book }

class PlanItemEntity extends Equatable {
  const PlanItemEntity({
    required this.kind,
    required this.refId,
    required this.title,
    required this.subtitle,
    this.imageUrl,
    this.priceMinorUnits,
    this.currency,
  });

  final PlanItemKind kind;
  final String refId;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final int? priceMinorUnits;
  final String? currency;

  String? get displayPrice {
    if (priceMinorUnits == null) return null;
    final major = priceMinorUnits! / 100;
    final symbol = currency == 'INR' ? '₹' : '${currency ?? ''} ';
    return '$symbol${major.toStringAsFixed(0)}';
  }

  @override
  List<Object?> get props => [kind, refId, title];
}

class AgentPlanEntity extends Equatable {
  const AgentPlanEntity({
    required this.id,
    required this.summary,
    required this.items,
    required this.estimatedTotalMinMinorUnits,
    required this.estimatedTotalMaxMinorUnits,
    required this.currency,
  });

  final String id;
  final String summary;
  final List<PlanItemEntity> items;
  final int estimatedTotalMinMinorUnits;
  final int estimatedTotalMaxMinorUnits;
  final String currency;

  String get displayEstimatedRange {
    final symbol = currency == 'INR' ? '₹' : '$currency ';
    final min = (estimatedTotalMinMinorUnits / 100).toStringAsFixed(0);
    final max = (estimatedTotalMaxMinorUnits / 100).toStringAsFixed(0);
    if (min == max) return '$symbol$min';
    return '$symbol$min – $symbol$max';
  }

  @override
  List<Object?> get props => [id, summary, items];
}
