import 'dart:async';
import 'package:flutter/material.dart';

/// One player modal per navigator, including its closing animation.
class PlayerModal {
  static final _opened = Expando<Future<void>>();

  static Future<void> show(
    BuildContext context,
    Future<void> Function(void Function(BuildContext)) present,
  ) {
    final navigator = Navigator.of(context, rootNavigator: true);
    final existing = _opened[navigator];
    if (existing != null) return existing;
    final done = Completer<void>();
    _opened[navigator] = done.future;
    TransitionRoute<dynamic>? route;
    () async {
      try {
        await present((context) {
          final current = ModalRoute.of(context);
          if (current is TransitionRoute<dynamic>) route = current;
        });
        await route?.completed;
        done.complete();
      } catch (error, stack) {
        done.completeError(error, stack);
      } finally {
        _opened[navigator] = null;
      }
    }();
    return done.future;
  }
}
