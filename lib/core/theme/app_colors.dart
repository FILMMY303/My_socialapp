import 'package:flutter/material.dart';

import 'theme_controller.dart';

/// Colors that look the same in light and dark mode.
const Color kGreen = Color(0xFF059669);
const Color kRed = Color(0xFFE53935);

/// Text and icons on top of green / red / dark overlays.
const Color kWhite = Color(0xFFFFFFFF);

/// Colors that follow [ThemeController]. They are getters, so widgets read the
/// current palette on every build.
class AppPalette {
  const AppPalette({
    required this.background,
    required this.headerYellow,
    required this.inputBg,
    required this.surface,
    required this.mainText,
    required this.secondaryText,
    required this.muted,
    required this.paleGreen,
  });

  final Color background;
  final Color headerYellow;
  final Color inputBg;
  final Color surface;
  final Color mainText;
  final Color secondaryText;
  final Color muted;
  final Color paleGreen;

  static const light = AppPalette(
    background: Color(0xFFFEFCE8),
    headerYellow: Color(0xFFFCFFB1),
    inputBg: Color(0xFFF6F7FB),
    surface: Color(0xFFFFFFFF),
    mainText: Color(0xFF171A22),
    secondaryText: Color(0xFF687080),
    muted: Color(0xFF9BA2B1),
    paleGreen: Color(0xFFE8F8F0),
  );

  static const dark = AppPalette(
    background: Color(0xFF121418),
    headerYellow: Color(0xFF2B2C1F),
    inputBg: Color(0xFF262A33),
    surface: Color(0xFF1C1F26),
    mainText: Color(0xFFECEEF2),
    secondaryText: Color(0xFFA9B0BD),
    muted: Color(0xFF7D8595),
    paleGreen: Color(0xFF16352A),
  );
}

AppPalette get _palette =>
    ThemeController.instance.isDark ? AppPalette.dark : AppPalette.light;

Color get kCream => _palette.background;
Color get kHeaderYellow => _palette.headerYellow;
Color get kInputBg => _palette.inputBg;
Color get kCardWhite => _palette.surface;
Color get kMainText => _palette.mainText;
Color get kSecondaryText => _palette.secondaryText;
Color get kMuted => _palette.muted;
Color get kPaleGreen => _palette.paleGreen;
