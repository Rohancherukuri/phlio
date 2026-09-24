// DTO for the `/auth/*` and `/users/*` endpoints' user JSON shape.
//
// Deliberately separate from `UserEntity` (see domain/entities/user_entity.dart)
// even though the fields overlap almost entirely today — this is the layer
// that's allowed to know about JSON keys, and the one that would absorb a
// backend field rename without the domain layer ever noticing.

import '../../domain/entities/user_entity.dart';

class UserModel {
  const UserModel({
    required this.id,
    required this.username,
    required this.fullName,
    required this.email,
    required this.bio,
    required this.interests,
    required this.isVerified,
    required this.createdAt,
    this.avatarUrl,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      username: json['username'] as String,
      fullName: json['full_name'] as String,
      email: json['email'] as String,
      avatarUrl: json['avatar_url'] as String?,
      bio: json['bio'] as String? ?? '',
      interests: (json['interests'] as List<dynamic>? ?? []).cast<String>(),
      isVerified: json['is_verified'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String username;
  final String fullName;
  final String email;
  final String? avatarUrl;
  final String bio;
  final List<String> interests;
  final bool isVerified;
  final DateTime createdAt;

  UserEntity toEntity() => UserEntity(
        id: id,
        username: username,
        fullName: fullName,
        email: email,
        avatarUrl: avatarUrl,
        bio: bio,
        interests: interests,
        isVerified: isVerified,
        createdAt: createdAt,
      );
}
