import 'dart:math' as math;

import 'package:flutter/material.dart';

class GoldGlow extends StatefulWidget {
  const GoldGlow({
    super.key,
    required this.enabled,
    required this.child,
    this.circle = false,
  });
  final bool enabled, circle;
  final Widget child;
  @override
  State<GoldGlow> createState() => _GoldGlowState();
}

class _GoldGlowState extends State<GoldGlow>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  void _sync() {
    if (widget.enabled && !MediaQuery.disableAnimationsOf(context)) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(GoldGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _pulse,
      child: widget.child,
      builder: (context, child) {
        final strength = .5 + .5 * math.sin(_pulse.value * 2 * math.pi);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.circle ? 100 : 16),
            border: Border.all(
              color: const Color(0xFFE6BA4D)
                  .withValues(alpha: .6 + .4 * strength),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFC83D)
                    .withValues(alpha: .18 + .25 * strength),
                blurRadius: 10 + strength * 12,
                spreadRadius: 1 + strength * 2,
              ),
            ],
          ),
          child: child,
        );
      },
    );
  }
}
