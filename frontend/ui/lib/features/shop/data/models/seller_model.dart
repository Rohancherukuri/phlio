import '../../domain/entities/seller_entity.dart';

class SellerModel {
  const SellerModel({
    required this.id,
    this.userId,
    this.avatarUrl,
    required this.displayName,
    required this.handle,
    required this.specialty,
    required this.bio,
    required this.followersCount,
  });

  factory SellerModel.fromJson(Map<String, dynamic> json) {
    return SellerModel(
      id: json['id'] as String,
      userId: json['user_id'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      displayName: json['display_name'] as String,
      handle: json['handle'] as String,
      specialty: json['specialty'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      followersCount: json['followers_count'] as int? ?? 0,
    );
  }

  final String id;
  final String? userId;
  final String? avatarUrl;
  final String displayName;
  final String handle;
  final String specialty;
  final String bio;
  final int followersCount;

  SellerEntity toEntity() => SellerEntity(
        id: id,
        userId: userId,
        avatarUrl: avatarUrl,
        displayName: displayName,
        handle: handle,
        specialty: specialty,
        bio: bio,
        followersCount: followersCount,
      );
}
