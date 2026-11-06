import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Offline, vector route artwork for the UI preview; not a live Maps response.
class RouteMap extends StatelessWidget {
  const RouteMap({
    super.key,
    this.variant = 0,
    this.cancelled = false,
    this.connected = false,
    this.image,
    this.message,
  });
  final int variant;
  final bool cancelled;
  final bool connected;
  final Uint8List? image;
  final String? message;

  @override
  Widget build(BuildContext context) => Semantics(
    label: cancelled ? '파토난 약속의 경로' : '대중교통 경로 미리보기',
    image: true,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (connected)
            ColoredBox(
              color: const Color(0xFFEDF0F2),
              child: image != null
                  ? Image.memory(
                      image!,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => const Center(
                        child: Icon(Icons.map_outlined, color: AppColors.muted),
                      ),
                    )
                  : Tooltip(
                      message: message ?? '경로를 불러오는 중이에요.',
                      child: const Center(
                        child: Icon(Icons.map_outlined, color: AppColors.muted),
                      ),
                    ),
            )
          else
            Opacity(
              opacity: cancelled ? .48 : 1,
              child: CustomPaint(painter: _RoutePainter(variant)),
            ),
          if (cancelled)
            LayoutBuilder(
              builder: (context, constraints) => Center(
                child: Transform.rotate(
                  angle: -0.17,
                  child: SizedBox(
                    width: constraints.maxWidth * 0.84,
                    height: constraints.maxWidth * 0.43,
                    child: CustomPaint(
                      painter: _StampBorderPainter(),
                      child: Center(
                        child: Text(
                          '파 토',
                          style: TextStyle(
                            fontSize: constraints.maxWidth * 0.245,
                            fontWeight: FontWeight.w900,
                            color: AppColors.red,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _RoutePainter extends CustomPainter {
  _RoutePainter(this.variant);
  final int variant;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / 160, size.height / 144);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 160, 144),
      Paint()..color = const Color(0xFFEBEDE9),
    );
    canvas.save();
    canvas.translate(80, 72);
    canvas.rotate(-0.43 + (variant % 3) * 0.12);
    final park = Paint()..color = const Color(0xFFD4E9C5);
    for (final rect in [
      const Rect.fromLTWH(-98, -80, 32, 37),
      const Rect.fromLTWH(-32, -24, 16, 26),
      const Rect.fromLTWH(42, -75, 39, 28),
      const Rect.fromLTWH(13, 35, 27, 26),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        park,
      );
    }
    final roadOutline = Paint()
      ..color = const Color(0xFFD8DDE2)
      ..strokeWidth = 7;
    final road = Paint()
      ..color = Colors.white
      ..strokeWidth = 4.8;
    for (double x = -160; x < 170; x += 23) {
      canvas.drawLine(Offset(x, -180), Offset(x, 180), roadOutline);
      canvas.drawLine(Offset(x, -180), Offset(x, 180), road);
    }
    for (double y = -160; y < 170; y += 19) {
      canvas.drawLine(Offset(-180, y), Offset(180, y), roadOutline);
      canvas.drawLine(Offset(-180, y), Offset(180, y), road);
    }
    canvas.restore();
    final river = Path()
      ..moveTo(-10, variant % 3 == 2 ? 103 : 159)
      ..cubicTo(48, 93, 100, 112, 180, variant % 3 == 2 ? 68 : 101);
    canvas.drawPath(
      river,
      Paint()
        ..color = const Color(0xFFF7FBEE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 28,
    );
    canvas.drawPath(
      river,
      Paint()
        ..color = const Color(0xFFBCDFEE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 20,
    );
    canvas.drawLine(
      const Offset(83, 122),
      const Offset(101, 91),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 5,
    );
    final routes = [
      [
        const Offset(18, 121),
        const Offset(37, 100),
        const Offset(62, 105),
        const Offset(79, 84),
        const Offset(88, 57),
        const Offset(119, 46),
        const Offset(139, 29),
      ],
      [
        const Offset(21, 120),
        const Offset(40, 102),
        const Offset(35, 86),
        const Offset(65, 70),
        const Offset(76, 51),
        const Offset(107, 55),
        const Offset(132, 28),
      ],
      [
        const Offset(22, 118),
        const Offset(49, 95),
        const Offset(72, 93),
        const Offset(98, 77),
        const Offset(119, 59),
        const Offset(139, 43),
      ],
    ];
    final points = routes[variant % routes.length];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    final routePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    canvas.drawPath(path, routePaint);
    canvas.drawPath(
      path,
      routePaint
        ..strokeWidth = 4.3
        ..color = const Color(0xFF2487E8),
    );
    canvas.drawCircle(points.first, 6.2, Paint()..color = Colors.white);
    canvas.drawCircle(
      points.first,
      6.2,
      Paint()
        ..color = const Color(0xFF24A66B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.7,
    );
    final end = points.last;
    final pin = Path()
      ..moveTo(end.dx, end.dy + 3)
      ..cubicTo(
        end.dx - 2,
        end.dy - 1,
        end.dx - 9,
        end.dy - 7,
        end.dx - 9,
        end.dy - 13,
      )
      ..cubicTo(
        end.dx - 9,
        end.dy - 25,
        end.dx + 9,
        end.dy - 25,
        end.dx + 9,
        end.dy - 13,
      )
      ..cubicTo(
        end.dx + 9,
        end.dy - 7,
        end.dx + 2,
        end.dy - 1,
        end.dx,
        end.dy + 3,
      )
      ..close();
    canvas.drawPath(
      pin,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawPath(pin, Paint()..color = const Color(0xFFF26A68));
    canvas.drawCircle(
      Offset(end.dx, end.dy - 13),
      3.3,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_RoutePainter oldDelegate) =>
      oldDelegate.variant != variant;
}

class _StampBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(17);
    final rect = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
    final path = Path();
    final corners = [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
      rect.topLeft,
    ];
    path.moveTo(rect.left, rect.top);
    for (var side = 0; side < 4; side++) {
      for (var step = 1; step <= 20; step++) {
        final point = Offset.lerp(corners[side], corners[side + 1], step / 20)!;
        path.lineTo(
          point.dx + (random.nextDouble() - .5) * .7,
          point.dy + (random.nextDouble() - .5) * .7,
        );
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8,
    );
    canvas.drawRect(
      rect.deflate(4),
      Paint()
        ..color = AppColors.red.withValues(alpha: .7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .65,
    );
  }

  @override
  bool shouldRepaint(_StampBorderPainter oldDelegate) => false;
}
