import 'package:equatable/equatable.dart';

class SellerEntity extends Equatable {
  const SellerEntity({
    required this.id,
    required this.displayName,
    required this.handle,
    required this.specialty,
    required this.bio,
    required this.followersCount,
  });

  final String id;
  final String displayName;
  final String handle;
  final String specialty;
  final String bio;
  final int followersCount;

  @override
  List<Object?> get props => [id, displayName, followersCount];
}
