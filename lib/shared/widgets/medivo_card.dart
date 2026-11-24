import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Solid card used across the app (radius 22, 1 px line).
class MedivoCard extends StatelessWidget {
  const MedivoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.line),
      ),
      child: child,
    );
  }
}