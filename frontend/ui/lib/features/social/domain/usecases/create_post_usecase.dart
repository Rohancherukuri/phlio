import '../../../../core/result/result.dart';
import '../entities/post_entity.dart';
import '../repositories/social_repository.dart';

class CreatePostUseCase {
  const CreatePostUseCase(this._repository);

  final SocialRepository _repository;

  Future<Result<PostEntity>> call(
      {required String text, List<String> tags = const [], String? musicId}) {
    return _repository.createPost(text: text, tags: tags, musicId: musicId);
  }
}
