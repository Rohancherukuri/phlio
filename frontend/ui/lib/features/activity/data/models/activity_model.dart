import '../../domain/entities/activity_entity.dart';

class ActivityItemModel {
  const ActivityItemModel();

  static ActivityItemEntity fromJson(Map<String, dynamic> json) {
    return ActivityItemEntity(
      id: json['id'] as String,
      kind: json['kind'] as String? ?? 'social',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      icon: json['icon'] as String? ?? '🔔',
      refId: json['ref_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      isRead: json['is_read'] as bool? ?? false,
    );
  }
}
