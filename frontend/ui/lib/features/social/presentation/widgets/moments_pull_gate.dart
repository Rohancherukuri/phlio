// Pull-down on the Social home: the first pull reveals people's moments,
// the next pull (with moments already showing) refreshes the feed.
//
// SocialHomeScreen keeps [socialMomentsOpen] in sync with the stories
// header. The Posts / Videos tabs pass [socialRefreshPredicate] to their
// RefreshIndicator so a pull that starts while moments are hidden only
// opens them. RefreshIndicator decides whether to start at the beginning of
// a drag, so a single pull never does both.

import 'package:flutter/widgets.dart';

/// Whether the moments row is fully shown on the Social home.
final socialMomentsOpen = ValueNotifier<bool>(false);

/// True while a SocialHomeScreen (which owns the moments header) is mounted.
/// Elsewhere the feed views refresh normally.
int socialMomentsGateUsers = 0;

bool socialRefreshPredicate(ScrollNotification n) =>
    n.depth == 0 && (socialMomentsGateUsers == 0 || socialMomentsOpen.value);
