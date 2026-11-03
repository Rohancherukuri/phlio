import '../../domain/entities/room_entity.dart';

class RoomModel {
  const RoomModel({
    required this.id,
    required this.name,
    required this.slug,
    required this.description,
    required this.category,
    required this.icon,
    required this.isPrivate,
    required this.memberCount,
    required this.createdAt,
    this.iconUrl,
    this.bannerUrl,
    this.credit,
    this.activeCount = 0,
  });

  factory RoomModel.fromJson(Map<String, dynamic> json) {
    return RoomModel(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      description: json['description'] as String? ?? '',
      category: RoomCategory.fromApiValue(json['category'] as String),
      icon: json['icon'] as String? ?? '💬',
      isPrivate: json['is_private'] as bool? ?? false,
      memberCount: json['member_count'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      iconUrl: json['icon_url'] as String?,
      bannerUrl: json['banner_url'] as String?,
      credit: json['credit'] as String?,
      activeCount: json['active_count'] as int? ?? 0,
    );
  }

  final String id;
  final String name;
  final String slug;
  final String description;
  final RoomCategory category;
  final String icon;
  final bool isPrivate;
  final int memberCount;
  final DateTime createdAt;
  final String? iconUrl;
  final String? bannerUrl;
  final String? credit;
  final int activeCount;

  RoomEntity toEntity() => RoomEntity(
        id: id,
        name: name,
        slug: slug,
        description: description,
        category: category,
        icon: icon,
        isPrivate: isPrivate,
        memberCount: memberCount,
        createdAt: createdAt,
        iconUrl: iconUrl,
        bannerUrl: bannerUrl,
        credit: credit,
        activeCount: activeCount,
      );
}
