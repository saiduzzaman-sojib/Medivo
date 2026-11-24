import 'package:flutter/material.dart';

/// The MEDIVO mark. The file is a transparent PNG, so it sits on any surface.
class MedivoLogo extends StatelessWidget {
  const MedivoLogo({super.key, this.size = 72, this.animate = false});

  final double size;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      'assets/images/medivo_logo.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.high,
      semanticLabel: 'MEDIVO logo',
    );
    if (!animate) return image;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.86, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.scale(scale: v, child: child),
      ),
      child: image,
    );
  }
}