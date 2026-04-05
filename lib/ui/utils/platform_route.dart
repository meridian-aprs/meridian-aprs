import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Returns a [CupertinoPageRoute] on iOS and a [MaterialPageRoute] on all
/// other platforms. Use this everywhere a push navigation is needed so that
/// the swipe-back gesture and slide transition feel native on iOS.
Route<T> buildPlatformRoute<T>(WidgetBuilder builder) {
  if (!kIsWeb && Platform.isIOS) {
    return CupertinoPageRoute<T>(builder: builder);
  }
  return MaterialPageRoute<T>(builder: builder);
}
