// Talks to `/api/v1/home/overview` and maps the response onto the
// `HomeOverviewEntity`, reusing the other features' own `*Model` classes
// for the nested rooms/products/posts rather than re-declaring parsing
// logic that already exists.

import '../../../../core/network/api_client.dart';
import '../../../rooms/data/models/room_model.dart';
import '../../../shop/data/models/product_model.dart';
import '../../../social/data/models/post_model.dart';
import '../../domain/entities/home_overview_entity.dart';
import '../../domain/entities/quick_action_entity.dart';

class HomeRemoteDataSource {
  const HomeRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<HomeOverviewEntity> getOverview() async {
    final response = await _apiClient.dio.get('/home/overview');
    final json = response.data as Map<String, dynamic>;

    final quickActions = (json['quick_actions'] as List<dynamic>)
        .map(
          (item) => QuickActionEntity.fromApiValue(
            (item as Map<String, dynamic>)['kind'] as String,
            item['label'] as String,
            item['is_available'] as bool,
          ),
        )
        .toList();

    return HomeOverviewEntity(
      greetingName: json['greeting_name'] as String,
      quickActions: quickActions,
      featuredRooms: (json['featured_rooms'] as List<dynamic>)
          .map((r) => RoomModel.fromJson(r as Map<String, dynamic>).toEntity())
          .toList(),
      featuredProducts: (json['featured_products'] as List<dynamic>)
          .map((p) => ProductModel.fromJson(p as Map<String, dynamic>).toEntity())
          .toList(),
      recentPosts: (json['recent_posts'] as List<dynamic>)
          .map((p) => PostModel.fromJson(p as Map<String, dynamic>).toEntity())
          .toList(),
    );
  }
}
