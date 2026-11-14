import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette dell'app: sfondo chiaro, inchiostro scuro, accenti sfumati.
class Pal {
  static const bg = Color(0xFFF7F6FB);
  static const ink = Color(0xFF2B2B3A);
  static const sub = Color(0xFF70708A);
  static const line = Color(0xFFE4E1EF);
  static const accent = Color(0xFF6750A4);
  static const ok = Color(0xFF43A047);
  static const warn = Color(0xFFF2A74B);
  static const bad = Color(0xFFE05555);
  static const gold = [Color(0xFFF4C542), Color(0xFFF2A74B)];
  static const neutral = [Color(0xFF8E8AA8), Color(0xFFC9C5DC)];
}

Color lighten(Color c, [double t = 0.35]) => Color.lerp(c, Colors.white, t)!;

ThemeData buildTheme() {
  final base = ThemeData(useMaterial3: true, colorSchemeSeed: Pal.accent, brightness: Brightness.light);
  return base.copyWith(
    scaffoldBackgroundColor: Pal.bg,
    textTheme: GoogleFonts.montserratTextTheme(base.textTheme).apply(bodyColor: Pal.ink, displayColor: Pal.ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Pal.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
    ),
  );
}
