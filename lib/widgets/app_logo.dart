import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The Status Saver logo: a green rounded square with a dashed "status ring"
/// around a download arrow. Same design as the Android launcher icon.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 108; // design grid is 108x108 (adaptive icon)
    final rect = Offset.zero & size;

    // Background
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2EE07A), Color(0xFF128C7E)],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.28)),
      bg,
    );

    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 * s
      ..strokeCap = StrokeCap.round;

    // Dashed status ring (8 segments, like WhatsApp's status ring)
    const segments = 8;
    const gap = 0.22;
    final ringRect = Rect.fromCircle(center: Offset(54 * s, 54 * s), radius: 30 * s);
    for (var i = 0; i < segments; i++) {
      final start = -math.pi / 2 + i * 2 * math.pi / segments + gap / 2;
      canvas.drawArc(ringRect, start, 2 * math.pi / segments - gap, false, white);
    }

    // Download arrow
    final arrow = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawLine(Offset(54 * s, 38 * s), Offset(54 * s, 64 * s), arrow);
    canvas.drawPath(
      Path()
        ..moveTo(43 * s, 54 * s)
        ..lineTo(54 * s, 65 * s)
        ..lineTo(65 * s, 54 * s),
      arrow,
    );
    canvas.drawLine(Offset(42 * s, 72 * s), Offset(66 * s, 72 * s), arrow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
