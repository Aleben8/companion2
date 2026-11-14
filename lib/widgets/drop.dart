import 'package:flutter/material.dart';

import '../constants.dart';
import '../theme.dart';
import 'common.dart';

/// Colori sfumati di un tipo (o neutri se sconosciuto).
List<Color> typeColors(String? type) {
  if (type == null || type.trim().isEmpty) return Pal.neutral;
  return kTypeGradients[cap(type.trim())] ?? Pal.neutral;
}

/// Scheda "a goccia": bordo sfumato, etichetta verticale a sinistra e
/// foglia/goccia all'angolo in alto a destra (stile delle schede degli strumenti).
class DropCard extends StatelessWidget {
  final Widget child;
  final List<Color> colors;
  final String? label; // etichetta della scheda
  final bool labelOnTop; // true = etichetta in alto (orizzontale), false = a sinistra (verticale)
  final Widget? expanded; // sezione che si apre sotto il contenuto (con animazione)
  final bool leaf; // foglia decorativa
  final bool selected; // bordo spesso + alone + spunta
  final bool dimmed; // sbiadita (non selezionabile)
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final double radius;
  final double border;
  final Color? fill;

  const DropCard({
    super.key,
    required this.child,
    this.colors = Pal.neutral,
    this.label,
    this.labelOnTop = false,
    this.expanded,
    this.leaf = true,
    this.selected = false,
    this.dimmed = false,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.fromLTRB(0, 10, 0, 10),
    this.radius = 22,
    this.border = 3,
    this.fill,
  });

  @override
  Widget build(BuildContext context) {
    final b = selected ? border + 2 : border;
    final topLabel = label != null && labelOnTop;
    final sideLabel = label != null && !labelOnTop;
    final body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (topLabel)
        Padding(
          padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, 0),
          child: Align(alignment: Alignment.centerLeft, child: _TopLabel(label!, colors)),
        ),
      Padding(padding: topLabel ? padding.copyWith(top: 12) : padding, child: child),
      AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: expanded ?? const SizedBox(width: double.infinity),
      ),
    ]);
    final inner = ClipRRect(
      borderRadius: BorderRadius.circular(radius - b),
      child: Container(
        color: fill ?? Colors.white,
        child: sideLabel
            ? Stack(children: [
                Padding(padding: const EdgeInsets.only(left: 36), child: body),
                Positioned(left: 0, top: 0, bottom: 0, width: 36, child: _SideLabel(label!, colors)),
              ])
            : body,
      ),
    );
    final framed = Container(
      padding: EdgeInsets.all(b),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: selected
            ? [BoxShadow(color: colors.first.withOpacity(0.45), blurRadius: 18, spreadRadius: 1)]
            : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: inner,
    );
    Widget w = Stack(clipBehavior: Clip.none, children: [
      framed,
      if (leaf)
        Positioned(
          top: -12,
          right: -8,
          child: IgnorePointer(child: CustomPaint(size: const Size(62, 32), painter: _LeafPainter(colors))),
        ),
      if (selected)
        Positioned(
          top: -10,
          left: -6,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: colors.first, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
            child: const Icon(Icons.check, size: 16, color: Colors.white),
          ),
        ),
    ]);
    w = Padding(padding: margin, child: w);
    if (onTap != null) w = GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: w);
    return AnimatedOpacity(opacity: dimmed ? 0.45 : 1, duration: const Duration(milliseconds: 200), child: w);
  }
}

class _TopLabel extends StatelessWidget {
  final String text;
  final List<Color> colors;
  const _TopLabel(this.text, this.colors);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
            topRight: Radius.circular(5),
            bottomLeft: Radius.circular(5),
          ),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
      );
}

class _SideLabel extends StatelessWidget {
  final String text;
  final List<Color> colors;
  const _SideLabel(this.text, this.colors);

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: colors),
        ),
        child: Center(
          child: RotatedBox(
            quarterTurns: 3,
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ),
      );
}

class _LeafPainter extends CustomPainter {
  final List<Color> colors;
  _LeafPainter(this.colors);

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final p = Path()
      ..moveTo(0, h)
      ..cubicTo(0, h * 0.35, w * 0.30, 0, w, 0)
      ..cubicTo(w, h * 0.65, w * 0.70, h, 0, h)
      ..close();
    c.drawPath(p, Paint()..color = Colors.white);
    c.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..shader = LinearGradient(colors: colors).createShader(Offset.zero & s),
    );
  }

  @override
  bool shouldRepaint(covariant _LeafPainter old) => old.colors != colors;
}

/// Pulsante a foglia (angoli opposti arrotondati) con sfumatura.
class DropButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final List<Color> colors;
  final VoidCallback? onTap; // null = disattivato
  final bool busy;
  final bool expand;
  final double height;
  const DropButton({
    super.key,
    required this.label,
    this.icon,
    this.colors = const [Pal.accent, Color(0xFF9C7BE0)],
    this.onTap,
    this.busy = false,
    this.expand = true,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final on = onTap != null && !busy;
    final btn = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(26),
          bottomRight: Radius.circular(26),
          topRight: Radius.circular(8),
          bottomLeft: Radius.circular(8),
        ),
        boxShadow: on ? [BoxShadow(color: colors.first.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4))] : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (busy)
          const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        else if (icon != null)
          Icon(icon, color: Colors.white, size: 20),
        if (busy || icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: GestureDetector(onTap: on ? onTap : null, child: expand ? SizedBox(width: double.infinity, child: btn) : btn),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 0, 4),
        child: Row(children: [
          const Icon(Icons.water_drop, size: 16, color: Pal.accent),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Pal.ink)),
        ]),
      );
}

class InfoChip extends StatelessWidget {
  final String text;
  final Color color;
  const InfoChip(this.text, {super.key, this.color = Pal.accent});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

/// Barra PS animata (si muove quando i PS cambiano).
class HpBar extends StatelessWidget {
  final int current;
  final int max;
  const HpBar({super.key, required this.current, required this.max});

  @override
  Widget build(BuildContext context) {
    final ratio = max == 0 ? 0.0 : (current / max).clamp(0.0, 1.0).toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: ratio),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        final c = v > 0.5 ? const Color(0xFF58C46B) : (v > 0.2 ? Pal.warn : Pal.bad);
        return Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('PS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Pal.sub)),
            Text('$current / $max', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: v, minHeight: 12, backgroundColor: Pal.line, color: c),
          ),
        ]);
      },
    );
  }
}

/// Energia come gocce piene/vuote.
class EnergyDrops extends StatelessWidget {
  final int current;
  final int max;
  final Color color;
  const EnergyDrops({super.key, required this.current, required this.max, required this.color});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 1,
        runSpacing: 1,
        children: [
          for (var i = 0; i < max; i++)
            Icon(i < current ? Icons.water_drop : Icons.water_drop_outlined,
                size: 15, color: i < current ? color : Pal.line),
        ],
      );
}
