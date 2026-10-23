import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/config/app_config.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';
final privatePhotoProvider = FutureProvider.autoDispose.family<Uint8List,String>((ref, path) async {
  ref.watch(authControllerProvider.select((v) => v.valueOrNull?.id));
  final result = await getIt<ApiClient>().dio.get<List<int>>(path, options: Options(responseType: ResponseType.bytes));
  return Uint8List.fromList(result.data!);
});
class MemoryPhoto extends ConsumerWidget {
  const MemoryPhoto(this.url, {super.key, this.fit = BoxFit.cover});
  final String url;
  final BoxFit fit;
  @override Widget build(BuildContext context, WidgetRef ref) {
    if (!url.startsWith('/social/memories/')) return Image.network(AppConfig.mediaUrl(url), fit: fit, errorBuilder: (_,__,___) => const Icon(Icons.broken_image_outlined));
    return ref.watch(privatePhotoProvider(url)).when(data: (bytes) => Image.memory(bytes, fit: fit, width: double.infinity, height: double.infinity), loading: () => const Center(child: CircularProgressIndicator()), error: (_,__) => const Center(child: Text('Photo unavailable')));
  }
}
