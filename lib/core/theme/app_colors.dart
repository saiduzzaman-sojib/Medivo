import 'package:flutter/material.dart';

/// Solid design tokens taken from the approved prototype.
/// Read them anywhere with `context.mc`.
@immutable
class MedivoColors extends ThemeExtension<MedivoColors> {
  const MedivoColors({
    required this.bg,
    required this.surface,
    required this.raised,
    required this.line,
    required this.ink,
    required this.muted,
    required this.primary,
    required this.secondary,
    required this.warning,
    required this.danger,
    required this.violet,
  });

  final Color bg;
  final Color surface;
  final Color raised;
  final Color line;
  final Color ink;
  final Color muted;
  final Color primary;
  final Color secondary;
  final Color warning;
  final Color danger;
  final Color violet;

  /// Brand colours that do not change with the theme.
  static const Color brandDeep = Color(0xFF04281F);
  static const Color brandPanel = Color(0xFF061014);
  static const Color hero = Color(0xFF0E4650);
  static const Color onPrimary = Color(0xFF04211C);

  static const MedivoColors dark = MedivoColors(
    bg: Color(0xFF0A1014),
    surface: Color(0xFF111A1F),
    raised: Color(0xFF19262C),
    line: Color(0x14FFFFFF),
    ink: Color(0xFFE8EEF1),
    muted: Color(0xFF8093A0),
    primary: Color(0xFF3FA796),
    secondary: Color(0xFF5B8DEF),
    warning: Color(0xFFD9A441),
    danger: Color(0xFFE0605A),
    violet: Color(0xFF9B87D9),
  );

  static const MedivoColors light = MedivoColors(
    bg: Color(0xFFEDF0F3),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFF2F4F7),
    line: Color(0x170C1C26),
    ink: Color(0xFF0E1C26),
    muted: Color(0xFF586A76),
    primary: Color(0xFF177F70),
    secondary: Color(0xFF2F5FD0),
    warning: Color(0xFFA8741A),
    danger: Color(0xFFC93C36),
    violet: Color(0xFF6F58BE),
  );

  @override
  MedivoColors copyWith({
    Color? bg,
    Color? surface,
    Color? raised,
    Color? line,
    Color? ink,
    Color? muted,
    Color? primary,
    Color? secondary,
    Color? warning,
    Color? danger,
    Color? violet,
  }) {
    return MedivoColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      raised: raised ?? this.raised,
      line: line ?? this.line,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      violet: violet ?? this.violet,
    );
  }

  @override
  MedivoColors lerp(ThemeExtension<MedivoColors>? other, double t) {
    if (other is! MedivoColors) return this;
    return MedivoColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      line: Color.lerp(line, other.line, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      violet: Color.lerp(violet, other.violet, t)!,
    );
  }
}

extension MedivoThemeX on BuildContext {
  MedivoColors get mc => Theme.of(this).extension<MedivoColors>()!;
}