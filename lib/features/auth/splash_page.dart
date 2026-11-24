import 'package:flutter/material.dart';

import '../../shared/widgets/medivo_logo.dart';

/// Shown for a moment while the app checks for a saved session.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: MedivoLogo(size: 96, animate: true)),
    );
  }
}