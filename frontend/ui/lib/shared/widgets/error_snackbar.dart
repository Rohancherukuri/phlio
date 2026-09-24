// Shows a `Failure` as a snackbar — used for actions (like/comment/join)
// where a full error screen would be disruptive; the surrounding content
// stays visible and the user can just try again.

import 'package:flutter/material.dart';
import '../../core/result/result.dart';

void showErrorSnackBar(BuildContext context, Failure failure) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(failure.message)));
}
