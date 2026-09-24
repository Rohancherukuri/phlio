import 'package:equatable/equatable.dart';

enum RoomCategory {
  techAndAi('tech_and_ai', 'Tech & AI', '💻'),
  gaming('gaming', 'Gaming', '🎮'),
  artAndCreators('art_and_creators', 'Art & Creators', '🎨'),
  travelAndExplore('travel_and_explore', 'Travel & Explore', '✈️'),
  foodAndLifestyle('food_and_lifestyle', 'Food & Lifestyle', '🍜'),
  sportsAndFitness('sports_and_fitness', 'Sports & Fitness', '🏸'),
  moviesAndMusic('movies_and_music', 'Movies & Music', '🎬'),
  studyAndLearn('study_and_learn', 'Study & Learn', '📚'),
  localNearby('local_nearby', 'Local (Nearby)', '📍');

  const RoomCategory(this.apiValue, this.label, this.emoji);

  final String apiValue;
  final String label;
  final String emoji;

  static RoomCategory fromApiValue(String value) =>
      RoomCategory.values.firstWhere((c) => c.apiValue == value, orElse: () => RoomCategory.localNearby);
}

class RoomEntity extends Equatable {
  const RoomEntity({
    required this.id,
    required this.name,
    required this.slug,
    required this.description,
    required this.category,
    required this.icon,
    required this.isPrivate,
    required this.memberCount,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String slug;
  final String description;
  final RoomCategory category;
  final String icon;
  final bool isPrivate;
  final int memberCount;
  final DateTime createdAt;

  @override
  List<Object?> get props => [id, name, memberCount];
}
