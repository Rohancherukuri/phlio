enum ChatAudience { rooms, publicChat, directMessage }

const dmImageLimit = 8000000;
const dmMediaLimit = 25000000;
const dmImageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'];
const dmVideoExtensions = ['mp4', 'mov', 'm4v', 'webm'];
const dmAudioExtensions = ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac'];

String? dmMediaError(String name, int size) {
  final ext = name.split('.').last.toLowerCase();
  final image = dmImageExtensions.contains(ext);
  if (!image &&
      !dmVideoExtensions.contains(ext) &&
      !dmAudioExtensions.contains(ext)) {
    return 'Messages support images, GIFs, audio and videos. Share documents in Rooms.';
  }
  final limit = image ? dmImageLimit : dmMediaLimit;
  if (size > limit)
    return '${image ? 'Images/GIFs' : 'Audio/videos'} must be ${limit ~/ 1000000} MB or smaller.';
  if (size <= 0) return 'This file is empty.';
  return null;
}
