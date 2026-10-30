// "New video" / "New clip" now open the full-screen gallery upload flow
// (see video_upload_flow.dart). Kept as a thin wrapper so existing call
// sites keep working.

import 'package:flutter/material.dart';

import 'video_upload_flow.dart';

Future<void> showVideoPublisher(BuildContext context, {required String kind}) =>
    openVideoUpload(context, kind: kind);
