import '../../../../core/result/result.dart';
import '../entities/comment_entity.dart';
import '../repositories/social_repository.dart';

class AddCommentUseCase {
  const AddCommentUseCase(this._repository);

  final SocialRepository _repository;

  Future<Result<CommentEntity>> call({required String postId, required String text}) {
    return _repository.addComment(postId: postId, text: text);
  }
}
