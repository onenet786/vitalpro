import 'package:flutter/material.dart';

class VitalProLogo extends StatelessWidget {
  const VitalProLogo({
    super.key,
    this.size = 72,
    this.showWordmark = true,
    this.subtitle,
  });

  final double size;
  final bool showWordmark;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0A6D88),
            Color(0xFF0E496A),
            Color(0xFF102B46),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF102B46).withValues(alpha: 0.18),
            blurRadius: size * 0.22,
            offset: Offset(0, size * 0.12),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _VitalProMarkPainter(),
      ),
    );

    if (!showWordmark) {
      return mark;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'VitalPro',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0A2540),
                letterSpacing: -0.6,
              ),
            ),
            Text(
              subtitle ?? 'Reporting Workspace',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: const Color(0xFF486173),
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _VitalProMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final accentPaint = Paint()
      ..color = const Color(0xFF7BE0D6)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = size.width * 0.075;

    final shieldPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    final shield = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.18,
        size.height * 0.14,
        size.width * 0.64,
        size.height * 0.72,
      ),
      Radius.circular(size.width * 0.18),
    );
    canvas.drawRRect(shield, shieldPaint);

    strokePaint.strokeWidth = size.width * 0.1;
    final vPath = Path()
      ..moveTo(size.width * 0.28, size.height * 0.28)
      ..lineTo(size.width * 0.47, size.height * 0.72)
      ..lineTo(size.width * 0.72, size.height * 0.28);
    canvas.drawPath(vPath, strokePaint);

    final pulsePath = Path()
      ..moveTo(size.width * 0.21, size.height * 0.56)
      ..lineTo(size.width * 0.33, size.height * 0.56)
      ..lineTo(size.width * 0.40, size.height * 0.46)
      ..lineTo(size.width * 0.48, size.height * 0.64)
      ..lineTo(size.width * 0.56, size.height * 0.40)
      ..lineTo(size.width * 0.64, size.height * 0.56)
      ..lineTo(size.width * 0.79, size.height * 0.56);
    canvas.drawPath(pulsePath, accentPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
