import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/local_store.dart';
import '../theme.dart';

/// A pointer-transparent, silent burst, consumed once per cancelled appointment.
class CancellationConfetti extends StatefulWidget {
  const CancellationConfetti({
    super.key,
    required this.store,
    required this.child,
  });
  final AppStore? store;
  final Widget child;
  @override
  State<CancellationConfetti> createState() => _CancellationConfettiState();
}

class _CancellationConfettiState extends State<CancellationConfetti>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _animation =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2800),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _particles = []);
          _schedule();
        }
      });
  List<_Particle> _particles = [];
  bool _claiming = false;
  bool _pendingBurst = false;
  bool _scheduled = false;
  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.store?.addListener(_schedule);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  @override
  void didUpdateWidget(CancellationConfetti oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _pendingBurst = false;
      oldWidget.store?.removeListener(_schedule);
      widget.store?.addListener(_schedule);
      _schedule();
    }
  }

  void _schedule() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) unawaited(_considerBurst());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _considerBurst() async {
    final store = widget.store;
    if (!_foreground ||
        store == null ||
        _claiming ||
        _animation.isAnimating ||
        (!_pendingBurst && !store.hasUnseenCancellation)) {
      return;
    }
    _claiming = true;
    try {
      if (!_pendingBurst) {
        final claimed = await store.claimCancellationCelebration();
        if (!mounted || widget.store != store) return;
        _pendingBurst = claimed;
      }
      if (!_pendingBurst || !_foreground) return;
      _pendingBurst = false;
      if (MediaQuery.disableAnimationsOf(context)) return;
      setState(() => _particles = _Particle.generate());
      _animation.forward(from: 0);
    } catch (_) {
      // No extra UI; a later foreground refresh can retry a failed local write.
    } finally {
      _claiming = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _schedule();
    } else if (_particles.isNotEmpty) {
      _animation.stop();
      setState(() => _particles = []);
    }
  }

  @override
  void dispose() {
    widget.store?.removeListener(_schedule);
    WidgetsBinding.instance.removeObserver(this);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      widget.child,
      if (_particles.isNotEmpty)
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _ConfettiPainter(_animation, _particles),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _Particle {
  const _Particle(
    this.side,
    this.vx,
    this.vy,
    this.delay,
    this.spin,
    this.width,
    this.color,
  );
  final int side;
  final double vx, vy, delay, spin, width;
  final Color color;
  static List<_Particle> generate() {
    final random = math.Random();
    const colors = [
      AppColors.blueStrong,
      AppColors.pink,
      AppColors.rose,
      Color(0xFFE8B856),
      Color(0xFF77BEAC),
    ];
    return List.generate(
      110,
      (i) => _Particle(
        i % 2,
        .05 + random.nextDouble() * .55,
        -.55 - random.nextDouble() * .4,
        random.nextDouble() * .16,
        (random.nextDouble() - .5) * 20,
        4 + random.nextDouble() * 4,
        colors[random.nextInt(colors.length)],
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.animation, this.particles) : super(repaint: animation);
  final Animation<double> animation;
  final List<_Particle> particles;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final paint = Paint();
    for (final p in particles) {
      final t = animation.value * 2.8 - p.delay;
      if (t < 0) continue;
      final direction = p.side == 0 ? 1 : -1;
      final x = size.width * ((p.side == 0 ? .1 : .9) + direction * p.vx * t);
      final y = size.height * (.68 + p.vy * t + .325 * t * t);
      final opacity = ((2.8 - t) / .6).clamp(0.0, 1.0);
      paint.color = p.color.withValues(alpha: opacity);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * t);
      canvas.scale(1, .4 + .6 * math.sin(t * 9 + p.spin).abs());
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.width,
            height: p.width * 1.8,
          ),
          const Radius.circular(.8),
        ),
        paint,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.particles != particles;
}
