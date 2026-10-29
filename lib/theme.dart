import 'package:flutter/material.dart';

/// Design tokens. Light mode is parchment and ink with a lamp-gold accent (Psalm 119:105);
/// dark mode is a lamp-lit study. Hex values live only in this file.
abstract final class BereaColors {
  static const parchment = Color(0xFFF6F1E8);
  static const parchmentDeep = Color(0xFFEBE3D3);
  static const ink = Color(0xFF1E1A15);
  static const inkMuted = Color(0xFF6B6257);
  // 5.9:1 on parchment, 5.3:1 on parchmentDeep, 4.6:1 under the 18% highlight wash.
  static const gold = Color(0xFF75571C);
  static const ember = Color(0xFF9B3B2E);

  static const night = Color(0xFF161310);
  static const nightRaised = Color(0xFF231F19);
  static const linen = Color(0xFFEAE2D4);
  static const linenMuted = Color(0xFF9C9183);
  static const goldDark = Color(0xFFD4A94E);
  static const emberDark = Color(0xFFD8705F);
}

const scriptureFontFallback = ['Georgia', 'Times New Roman', 'serif'];
const contentMaxWidth = 760.0;
const fieldRadius = 14.0;
const focusRingWidth = 2.0;

/// From this width the shell shows the sidebar and places may show two panes.
const wideLayoutBreakpoint = 760.0;

ThemeData bereaTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: dark ? BereaColors.goldDark : BereaColors.gold,
    onPrimary: dark ? BereaColors.night : BereaColors.parchment,
    secondary: dark ? BereaColors.linenMuted : BereaColors.inkMuted,
    onSecondary: dark ? BereaColors.night : BereaColors.parchment,
    error: dark ? BereaColors.emberDark : BereaColors.ember,
    onError: dark ? BereaColors.night : BereaColors.parchment,
    surface: dark ? BereaColors.night : BereaColors.parchment,
    onSurface: dark ? BereaColors.linen : BereaColors.ink,
    surfaceContainerHighest: dark ? BereaColors.nightRaised : BereaColors.parchmentDeep,
    onSurfaceVariant: dark ? BereaColors.linenMuted : BereaColors.inkMuted,
    outline: dark ? BereaColors.linenMuted : BereaColors.inkMuted,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    textTheme: base.textTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: BorderSide(color: scheme.primary, width: focusRingWidth),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: BorderSide(color: scheme.error, width: focusRingWidth),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: scheme.surfaceContainerHighest,
      side: BorderSide.none,
      labelStyle: TextStyle(color: scheme.onSurface),
    ),
  );
}

TextStyle scriptureStyle(BuildContext context) => TextStyle(
  fontFamilyFallback: scriptureFontFallback,
  fontSize: 16,
  height: 1.5,
  color: Theme.of(context).colorScheme.onSurface,
);
