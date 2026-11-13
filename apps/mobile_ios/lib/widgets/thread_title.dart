import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A conversation's app-bar title: the avatar, the name, and an optional
/// line under it (a group's member count).
///
/// The group thread's title was a name over a member count in the default
/// 56 dp toolbar: 44 dp of text at 1.0x, 57 dp at 1.3x and 88 dp at 2x, so
/// from 1.3x the count and the bottom of the name were clipped (issue #1374
/// TO-8). The app bar takes [toolbarHeight], which grows with the text the
/// title holds, and the DM and group headers share this one title.
class ThreadTitle extends StatelessWidget {
  const ThreadTitle({
    super.key,
    required this.avatar,
    required this.title,
    this.subtitle,
    this.titleKey,
    this.subtitleKey,
  });

  final Widget avatar;
  final String title;
  final String? subtitle;
  final Key? titleKey;
  final Key? subtitleKey;

  /// The toolbar height a [ThreadTitle] needs at the reader's text scale:
  /// Material's 56 dp until the title's lines (`titleLarge`'s 28 dp, plus
  /// `labelSmall`'s 16 dp when there is a [subtitle]) and 12 dp of breathing
  /// room outgrow it.
  static double toolbarHeight(BuildContext context, {required bool subtitle}) {
    final scaler = MediaQuery.textScalerOf(context);
    final lines = scaler.scale(28) + (subtitle ? scaler.scale(16) : 0);
    return math.max(kToolbarHeight, lines + 12);
  }

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    return Row(
      children: [
        avatar,
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                key: titleKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (sub != null)
                Text(
                  sub,
                  key: subtitleKey,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
