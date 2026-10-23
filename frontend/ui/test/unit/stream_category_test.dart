import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/shared/content/stream_screen.dart';
void main() {
  test('Stream categorizes audio and video metadata', () {
    expect(streamCategory({'kind': 'audio', 'category': 'podcast'}), 'Podcasts');
    expect(streamCategory({'kind': 'audio'}), 'Music');
    expect(streamCategory({'kind': 'song'}), 'Music');
    expect(streamCategory({'kind': 'video', 'category': 'reality'}), 'Reality Shows');
    expect(streamCategory({'kind': 'episode'}), 'TV Series');
    expect(streamCategory({'kind': 'movie'}), 'Movies');
  });
}
