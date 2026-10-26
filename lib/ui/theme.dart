/// Earshot's look: design direction B "Now Playing" (chosen by Phil,
/// 2026-10-26). Dark and light versions; the app follows the phone's
/// setting. Tokens live here; see docs/design-brief.md.
library;

import 'package:flutter/material.dart';

/// The colour tokens. Read them with `EarshotColors.of(context)`.
@immutable
class EarshotColors extends ThemeExtension<EarshotColors> {
  const EarshotColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.track,
    required this.text,
    required this.muted,
    required this.dim,
    required this.accent,
    required this.accentStrong,
    required this.onAccent,
    required this.highlight,
    required this.selected,
  });

  /// Page background.
  final Color bg;

  /// Cards, sheets, secondary buttons.
  final Color surface;

  /// Controls on top of a surface (chips, stepper buttons).
  final Color surface2;

  /// Empty part of progress bars.
  final Color track;

  final Color text;

  /// Secondary text (meta lines, labels). ≥4.5:1 on bg.
  final Color muted;

  /// The sentences either side of the current one. ≥4.5:1 on bg.
  final Color dim;

  /// Amber: the play button and "you are here" marks. A fill, not text.
  final Color accent;

  /// Accent for thin marks and text on bg (progress fill, links): passes
  /// contrast where the plain accent wouldn't on the light theme.
  final Color accentStrong;

  /// Icons and text on an accent fill.
  final Color onAccent;

  /// The current sentence in the read-along view (a marker-pen tint).
  final Color highlight;

  /// A selected row's tint.
  final Color selected;

  static const dark = EarshotColors(
    bg: Color(0xFF0E1014),
    surface: Color(0xFF181B21),
    surface2: Color(0xFF22262E),
    track: Color(0xFF2A2F38),
    text: Color(0xFFF2F3F5),
    muted: Color(0xFF9AA1AD),
    dim: Color(0xFF7D8492),
    accent: Color(0xFFF5B544),
    accentStrong: Color(0xFFF5B544),
    onAccent: Color(0xFF1A1300),
    highlight: Color(0xFF3A3122),
    selected: Color(0xFF2A2418),
  );

  static const light = EarshotColors(
    bg: Color(0xFFF7F7F5),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFECEDEF),
    track: Color(0xFFE2E4E8),
    text: Color(0xFF14161A),
    muted: Color(0xFF5B6270),
    dim: Color(0xFF6B7280),
    accent: Color(0xFFF2A93B),
    accentStrong: Color(0xFF9A6200),
    onAccent: Color(0xFF1A1300),
    highlight: Color(0xFFFBE7C2),
    selected: Color(0xFFFDF1DC),
  );

  static EarshotColors of(BuildContext context) =>
      Theme.of(context).extension<EarshotColors>()!;

  @override
  EarshotColors copyWith() => this;

  @override
  EarshotColors lerp(EarshotColors? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

/// Text in Manrope at any weight (it's a variable font, so the weight is
/// set on its 'wght' axis as well as fontWeight).
TextStyle ui(
  double size, {
  int weight = 500,
  Color? color,
  double? height,
  double? spacing,
}) => TextStyle(
  fontFamily: 'Manrope',
  fontSize: size,
  fontWeight: FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)],
  fontVariations: [FontVariation('wght', weight.toDouble())],
  color: color,
  height: height,
  letterSpacing: spacing,
);

/// Reading text for the read-along view (Literata, variable).
TextStyle reading(double size, {int weight = 400, Color? color}) => TextStyle(
  fontFamily: 'Literata',
  fontSize: size,
  height: 1.6,
  fontWeight: FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)],
  fontVariations: [
    FontVariation('wght', weight.toDouble()),
    FontVariation('opsz', size.clamp(7, 72).toDouble()),
  ],
  color: color,
);

ThemeData earshotTheme(Brightness brightness) {
  final c = brightness == Brightness.dark
      ? EarshotColors.dark
      : EarshotColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.accentStrong,
    onSecondary: c.onAccent,
    error: const Color(0xFFE5484D),
    onError: Colors.white,
    surface: c.bg,
    onSurface: c.text,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.surface2,
    outline: c.track,
  );
  return ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: c.bg,
    fontFamily: 'Manrope',
    extensions: [c],
    splashFactory: InkSparkle.splashFactory,
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.surface2,
      contentTextStyle: ui(14, weight: 600, color: c.text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: ui(20, weight: 800, color: c.text),
      contentTextStyle: ui(15, color: c.muted, height: 1.45),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      dragHandleColor: c.track,
      showDragHandle: true,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.onAccent : c.muted,
      ),
      // Off: a visible track even on a card.
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : c.track,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.transparent : c.muted,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
  );
}

/// The library's width cap on wide screens (Windows), so lines and cards
/// don't stretch across a monitor.
const libraryMaxWidth = 720.0;

/// From this width up, the player shows the text beside it.
const wideBreakpoint = 900.0;
