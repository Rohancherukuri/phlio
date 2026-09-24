import '../../domain/entities/agent_plan_entity.dart';

class PlanItemModel {
  const PlanItemModel({
    required this.kind,
    required this.refId,
    required this.title,
    required this.subtitle,
    this.imageUrl,
    this.priceMinorUnits,
    this.currency,
  });

  factory PlanItemModel.fromJson(Map<String, dynamic> json) {
    return PlanItemModel(
      kind: _kindFromApiValue(json['kind'] as String),
      refId: json['ref_id'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String,
      imageUrl: json['image_url'] as String?,
      priceMinorUnits: json['price_minor_units'] as int?,
      currency: json['currency'] as String?,
    );
  }

  final PlanItemKind kind;
  final String refId;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final int? priceMinorUnits;
  final String? currency;

  static PlanItemKind _kindFromApiValue(String value) {
    return switch (value) {
      'room' => PlanItemKind.room,
      'product' => PlanItemKind.product,
      _ => PlanItemKind.post,
    };
  }

  PlanItemEntity toEntity() => PlanItemEntity(
        kind: kind,
        refId: refId,
        title: title,
        subtitle: subtitle,
        imageUrl: imageUrl,
        priceMinorUnits: priceMinorUnits,
        currency: currency,
      );
}

class AgentPlanModel {
  const AgentPlanModel({
    required this.id,
    required this.summary,
    required this.items,
    required this.estimatedTotalMinMinorUnits,
    required this.estimatedTotalMaxMinorUnits,
    required this.currency,
  });

  factory AgentPlanModel.fromJson(Map<String, dynamic> json) {
    return AgentPlanModel(
      id: json['id'] as String,
      summary: json['summary'] as String,
      items: (json['items'] as List<dynamic>)
          .map((item) => PlanItemModel.fromJson(item as Map<String, dynamic>))
          .toList(),
      estimatedTotalMinMinorUnits: json['estimated_total_min_minor_units'] as int,
      estimatedTotalMaxMinorUnits: json['estimated_total_max_minor_units'] as int,
      currency: json['currency'] as String? ?? 'INR',
    );
  }

  final String id;
  final String summary;
  final List<PlanItemModel> items;
  final int estimatedTotalMinMinorUnits;
  final int estimatedTotalMaxMinorUnits;
  final String currency;

  AgentPlanEntity toEntity() => AgentPlanEntity(
        id: id,
        summary: summary,
        items: items.map((i) => i.toEntity()).toList(),
        estimatedTotalMinMinorUnits: estimatedTotalMinMinorUnits,
        estimatedTotalMaxMinorUnits: estimatedTotalMaxMinorUnits,
        currency: currency,
      );
}
