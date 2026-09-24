import '../../../rooms/domain/entities/room_entity.dart';
import '../../../shop/domain/entities/product_entity.dart';
import '../../../social/domain/entities/post_entity.dart';
import 'quick_action_entity.dart';

/// Composes entities from three other features (shop, rooms, social) — this
/// is the one intentional exception to "features don't depend on each
/// other," because Home genuinely *is* a cross-domain aggregation, both
/// here and on the backend (see `backend/app/domains/home/service.py`).
class HomeOverviewEntity {
  const HomeOverviewEntity({
    required this.greetingName,
    required this.quickActions,
    required this.featuredRooms,
    required this.featuredProducts,
    required this.recentPosts,
  });

  final String greetingName;
  final List<QuickActionEntity> quickActions;
  final List<RoomEntity> featuredRooms;
  final List<ProductEntity> featuredProducts;
  final List<PostEntity> recentPosts;
}
