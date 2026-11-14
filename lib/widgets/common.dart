import 'package:flutter/material.dart';

import '../constants.dart';

String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

/// Icona del tipo elementale (assets/images/icons/tipi/<Tipo>.png).
class TypeIcon extends StatelessWidget {
  final String type;
  final double size;
  const TypeIcon(this.type, {super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final name = cap(type.trim());
    return Image.asset(
      'assets/images/icons/tipi/$name.png',
      width: size,
      height: size,
      errorBuilder: (_, __, ___) => Tooltip(
        message: name,
        child: Icon(Icons.circle_outlined, size: size, color: Colors.white54),
      ),
    );
  }
}

/// Immagine del Pokémon: assets/images/<Nome>.png, con fallback.
class PokemonImage extends StatelessWidget {
  final String name;
  final double size;
  const PokemonImage(this.name, {super.key, this.size = 200});

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/images/$name.png',
        height: size,
        width: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => SizedBox(
          height: size,
          width: size,
          child: Icon(Icons.catching_pokemon, size: size * 0.6, color: Colors.black26),
        ),
      );
}

/// Testo con gradiente (per le statistiche).
class GradientText extends StatelessWidget {
  final String text;
  final List<Color> colors;
  final TextStyle? style;
  const GradientText(this.text, {super.key, required this.colors, this.style});

  @override
  Widget build(BuildContext context) => ShaderMask(
        shaderCallback: (r) => LinearGradient(colors: colors).createShader(r),
        child: Text(text, style: (style ?? const TextStyle()).copyWith(color: Colors.white)),
      );
}

/// Barra statistica: bordo a gradiente con interno bianco.
class StatBar extends StatelessWidget {
  final int value;
  final List<Color> colors;
  final double maxWidth;
  const StatBar({super.key, required this.value, required this.colors, this.maxWidth = 300});

  @override
  Widget build(BuildContext context) {
    final w = (value.clamp(1, kStatMax) / kStatMax) * maxWidth;
    return Container(
      width: w < 60 ? 60 : w,
      height: 26,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

/// Pulsante "etichetta" inclinato (Crea / Unisciti / Difesa / Schiva).
class SlantedTag extends StatelessWidget {
  final String label;
  final List<Color> colors;
  final IconData? icon;
  final bool leftSide;
  final VoidCallback? onTap;
  final double width;
  const SlantedTag({
    super.key,
    required this.label,
    required this.colors,
    this.icon,
    this.leftSide = true,
    this.onTap,
    this.width = 120,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: ClipPath(
          clipper: _TagClipper(leftSide),
          child: Container(
            width: width,
            height: 44,
            alignment: leftSide ? Alignment.centerLeft : Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, color: Colors.white, size: 22), const SizedBox(width: 6)],
                Text(label,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TagClipper extends CustomClipper<Path> {
  final bool left;
  _TagClipper(this.left);
  @override
  Path getClip(Size s) {
    const k = 22.0;
    return left
        ? (Path()
          ..moveTo(0, 0)
          ..lineTo(s.width, 0)
          ..lineTo(s.width - k, s.height)
          ..lineTo(0, s.height)
          ..close())
        : (Path()
          ..moveTo(k, 0)
          ..lineTo(s.width, 0)
          ..lineTo(s.width, s.height)
          ..lineTo(0, s.height)
          ..close());
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> old) => false;
}

void snack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
}
