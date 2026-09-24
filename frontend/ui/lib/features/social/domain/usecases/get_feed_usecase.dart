import '../../../../core/result/result.dart';
import '../../../../shared/models/paginated_response.dart';
import '../entities/post_entity.dart';
import '../repositories/social_repository.dart';

class GetFeedUseCase {
  const GetFeedUseCase(this._repository);

  final SocialRepository _repository;

  Future<Result<PaginatedResponse<PostEntity>>> call({String? cursor}) {
    return _repository.getFeed(cursor: cursor);
  }
}
