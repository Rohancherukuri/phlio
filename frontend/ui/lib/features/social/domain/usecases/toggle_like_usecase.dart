import '../../../../core/result/result.dart';
import '../entities/post_entity.dart';
import '../repositories/social_repository.dart';

class ToggleLikeUseCase {
  const ToggleLikeUseCase(this._repository);

  final SocialRepository _repository;

  Future<Result<PostEntity>> call(String postId) =>
      _repository.toggleLike(postId);
}
