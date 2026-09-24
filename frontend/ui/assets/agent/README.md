# Agent mascot asset

`fox.svg` is Twitter's **Twemoji** fox emoji (U+1F98A), used as the Phlio
Agent's mascot illustration.

- Source: https://github.com/twitter/twemoji
- License: **CC-BY 4.0** (https://creativecommons.org/licenses/by/4.0/)
- Copyright: Twitter, Inc and other contributors
- Attribution requirement: satisfied by this file — if you redistribute
  this asset outside this repository, keep this attribution notice with it.

Rendered via `flutter_svg` in `lib/design_system/widgets/phlio_fox.dart`,
which falls back to a small hand-drawn `CustomPainter` illustration (no
asset dependency) if the SVG ever fails to load — see that file for why
both exist.
