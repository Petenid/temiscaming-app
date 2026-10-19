import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Lays out [children] in a column that is centred on the screen when it fits,
/// and scrolls when it doesn't (large text sizes, small phones, landscape).
///
/// Width is capped so lines stay readable on desktop windows and tablets.
class CenteredScrollColumn extends StatelessWidget {
  const CenteredScrollColumn({super.key, required this.children});

  final List<Widget> children;

  static const _padding = EdgeInsets.all(24);
  static const _maxWidth = 480.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: _padding,
        child: ConstrainedBox(
          // At least as tall as the screen, so short content is centred.
          constraints: BoxConstraints(
            minHeight: math.max(0, constraints.maxHeight - _padding.vertical),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
