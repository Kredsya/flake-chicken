import 'package:flutter/material.dart';

import '../theme.dart';

class ChickenMark extends StatelessWidget {
  const ChickenMark({super.key, this.size = 36});
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ChickenPainter()),
    ),
  );
}

class _ChickenPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 40, size.height / 40);
    final body = Path()
      ..moveTo(20, 9)
      ..cubicTo(11, 9, 5, 22, 4, 29)
      ..cubicTo(3, 39, 36, 39, 36, 29)
      ..cubicTo(35, 21, 29, 9, 20, 9)
      ..close();
    canvas.drawPath(body, Paint()..color = Colors.white);
    canvas.drawPath(
      body,
      Paint()
        ..color = AppColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25,
    );
    final comb = Paint()..color = AppColors.pink;
    canvas.drawCircle(const Offset(17, 8), 3.2, comb);
    canvas.drawCircle(const Offset(21, 5.5), 3.8, comb);
    canvas.drawCircle(const Offset(24, 8), 3, comb);
    final eyes = Paint()..color = AppColors.ink;
    canvas.drawCircle(const Offset(15, 23), 1.15, eyes);
    canvas.drawCircle(const Offset(25, 23), 1.15, eyes);
    canvas.drawPath(
      Path()
        ..moveTo(18, 25)
        ..lineTo(22, 25)
        ..lineTo(20, 28)
        ..close(),
      Paint()..color = const Color(0xFFE5B45C),
    );
    canvas.drawCircle(
      const Offset(11, 26),
      1.7,
      Paint()..color = AppColors.pink.withValues(alpha: 0.35),
    );
    canvas.drawCircle(
      const Offset(29, 26),
      1.7,
      Paint()..color = AppColors.pink.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_ChickenPainter oldDelegate) => false;
}
