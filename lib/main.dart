import 'package:flutter/material.dart';

import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';

void main() => runApp(const MedivoApp());

class MedivoApp extends StatelessWidget {
  const MedivoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MEDIVO',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const _ThemeCheck(),
    );
  }
}

class _ThemeCheck extends StatelessWidget {
  const _ThemeCheck();

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/medivo_logo.png', width: 120),
            const SizedBox(height: 16),
            const Text('MEDIVO',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: 4)),
            const SizedBox(height: 6),
            Text('Theme and logo check', style: TextStyle(color: c.muted)),
            const SizedBox(height: 24),
            SizedBox(
              width: 220,
              child: FilledButton(onPressed: () {}, child: const Text('It works')),
            ),
          ],
        ),
      ),
    );
  }
}