import 'package:dio/dio.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/agent_attachment_entity.dart';
import '../../domain/entities/agent_message_entity.dart';
import '../../domain/repositories/agent_repository.dart';
import '../datasources/agent_remote_datasource.dart';

class AgentRepositoryImpl implements AgentRepository {
  const AgentRepositoryImpl(this._remoteDataSource);

  final AgentRemoteDataSource _remoteDataSource;

  @override
  Future<Result<AgentMessageEntity>> sendMessage({
    required String text,
    String? conversationId,
    List<String> attachmentIds = const [],
  }) async {
    try {
      final message = await _remoteDataSource.sendMessage(
          text: text, conversationId: conversationId, attachmentIds: attachmentIds);
      return Result.success(message.toEntity());
    } on DioException catch (e) {
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<List<AgentAttachmentEntity>>> uploadFiles(
    List<String> paths, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      return Result.success(await _remoteDataSource.uploadFiles(paths, onProgress: onProgress));
    } on DioException catch (e) {
      return Result.failure(mapDioErrorToFailure(e));
    }
  }

  @override
  Future<Result<List<AgentMessageEntity>>> getConversation(String conversationId) async {
    try {
      final messages = await _remoteDataSource.getConversation(conversationId);
      return Result.success(messages.map((m) => m.toEntity()).toList());
    } on DioException catch (e) {
      return Result.failure(mapDioErrorToFailure(e));
    }
  }
}
