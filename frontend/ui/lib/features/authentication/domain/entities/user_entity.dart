// Framework-agnostic domain entity for a Phlio user.
//
// Mirrors the shape of `backend/app/domains/identity/entities.py::User`
// (minus `hashed_password`, which never leaves the server). This class has
// no `fromJson`/`toJson` — that's a `data` layer concern
// (`data/models/user_model.dart`) so the domain layer stays free of any
// serialization library.

import 'package:equatable/equatable.dart';

class UserEntity extends Equatable {
  const UserEntity({
    required this.id,
    required this.username,
    required this.fullName,
    required this.email,
    required this.bio,
    required this.interests,
    required this.isVerified,
    required this.createdAt,
    this.avatarUrl,
    this.dateOfBirth,
    this.phoneNumber,
  });

  final String id;
  final String username;
  final String fullName;
  final String email;
  final String? avatarUrl;
  final DateTime? dateOfBirth;
  final String? phoneNumber;
  final String bio;
  final List<String> interests;
  final bool isVerified;
  final DateTime createdAt;

  @override
  List<Object?> get props => [
        id,
        username,
        fullName,
        email,
        avatarUrl,
        bio,
        interests,
        isVerified,
        dateOfBirth,
        phoneNumber
      ];
}
