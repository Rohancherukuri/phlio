// Phlio Stream · Music — the Explore page for audio.
//
// Stream's Explore tab shows this page while music mode (headphones) is on:
// the search bar with the Phlio Code scanner, then the Audius Discover feed
// (genre charts, this week / month / all time, underground, trending
// playlists). Home ([RetroMusicHome]) keeps your library; Explore is where
// you find new music.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'music_home.dart' show MusicSearchBar, MusicSettingsScreen;
import 'music_ui.dart';
import 'now_playing.dart';
import 'open_music_api.dart';

/// Explore for music and podcasts: search + scanner on top, Audius charts
/// below, the mini player docked at the bottom.
class MusicExploreScreen extends ConsumerWidget {
  const MusicExploreScreen({this.onSwitchToVideo, super.key});

  /// Switches Stream back to movies and shows (the film icon). Null hides it.
  final VoidCallback? onSwitchToVideo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(retroPaletteProvider);
    return Theme(
      data: pal.theme(context),
      child: RetroPaletteScope(
        palette: pal,
        child: Scaffold(
          backgroundColor: pal.bg,
          body: SafeArea(
            bottom: false,
            child: Column(children: [
              // Title row: page name, the video switch and music settings.
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 6, 2),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Explore', style: TextStyle(color: pal.text, fontSize: 24, fontWeight: FontWeight.w900)),
                      Text('New music from the open web', style: TextStyle(color: pal.muted, fontSize: 12.5)),
                    ]),
                  ),
                  if (onSwitchToVideo != null)
                    IconButton(
                      tooltip: 'Switch to movies and shows',
                      icon: Icon(Icons.movie_outlined, color: pal.text),
                      onPressed: onSwitchToVideo,
                    ),
                  IconButton(
                    tooltip: 'Music settings',
                    icon: Icon(Icons.tune_rounded, color: pal.text),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MusicSettingsScreen())),
                  ),
                ]),
              ),
              const MusicSearchBar(),
              // The Audius feed scrolls under the fixed header.
              const Expanded(child: DiscoverTab()),
            ]),
          ),
          bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
        ),
      ),
    );
  }
}
