import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Lightweight, reusable motion details for the TripCrew field-notes theme.
/// Every animation respects the platform's reduced-motion setting.
class MagneticMotion extends StatefulWidget {
  const MagneticMotion({super.key, required this.child});

  final Widget child;

  @override
  State<MagneticMotion> createState() => _MagneticMotionState();
}

class _MagneticMotionState extends State<MagneticMotion> {
  Offset _offset = Offset.zero;
  bool _pressed = false;

  void _handleHover(PointerEvent event, Size size) {
    if (MediaQuery.disableAnimationsOf(context)) return;
    final width = size.width.isFinite ? size.width : 0.0;
    final height = size.height.isFinite ? size.height : 0.0;
    final delta = event.localPosition - Offset(width / 2, height / 2);
    setState(() {
      _offset = Offset(
        width > 0 ? (delta.dx * .12).clamp(-7.0, 7.0).toDouble() : 0,
        height > 0 ? (delta.dy * .12).clamp(-7.0, 7.0).toDouble() : 0,
      );
    });
  }

  void _release() {
    if (!mounted) return;
    setState(() {
      _pressed = false;
      _offset = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return MouseRegion(
          onHover: (event) => _handleHover(event, size),
          onExit: (_) => _release(),
          child: Listener(
            onPointerDown: (_) => setState(() => _pressed = true),
            onPointerUp: (_) => _release(),
            onPointerCancel: (_) => _release(),
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              transform: Matrix4.translationValues(_offset.dx, _offset.dy, 0),
              transformAlignment: Alignment.center,
              child: AnimatedScale(
                scale: _pressed ? .985 : 1,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: widget.child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A scroll-reactive layer. `velocity` is normalized from -1 (up) to 1 (down).
class ScrollVelocityParallax extends StatelessWidget {
  const ScrollVelocityParallax({
    super.key,
    required this.velocity,
    required this.child,
    this.depth = 1,
    this.distance = 14,
  });

  final ValueListenable<double> velocity;
  final Widget child;
  final double depth;
  final double distance;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: velocity,
      builder: (context, speed, child) {
        final motionAllowed = !MediaQuery.disableAnimationsOf(context);
        final offset = motionAllowed
            ? (speed * depth * distance).clamp(-distance, distance).toDouble()
            : 0.0;
        return Transform.translate(offset: Offset(0, -offset), child: child);
      },
      child: child,
    );
  }
}

/// A small, expressive sticker animation for the trip card and empty states.
class BobbingSticker extends StatefulWidget {
  const BobbingSticker({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 2200),
    this.distance = 5,
  });

  final Widget child;
  final Duration duration;
  final double distance;

  @override
  State<BobbingSticker> createState() => _BobbingStickerState();
}

class _BobbingStickerState extends State<BobbingSticker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant BobbingSticker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final travel =
            (Curves.easeInOutSine.transform(_controller.value) - .5) * 2;
        return Transform.translate(
          offset: Offset(0, -travel * widget.distance),
          child: Transform.rotate(angle: travel * .035, child: child),
        );
      },
    );
  }
}

/// Hand-drawn map lines and a dotted route for trip cards and map accents.
class TripcrewMapInk extends StatelessWidget {
  const TripcrewMapInk({super.key, this.color = Colors.white});

  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _TripcrewMapInkPainter(color),
    child: const SizedBox.expand(),
  );
}

class _TripcrewMapInkPainter extends CustomPainter {
  const _TripcrewMapInkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final contourPaint = Paint()
      ..color = color.withValues(alpha: .13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15;

    for (var i = 0; i < 5; i++) {
      final y = size.height * (.18 + i * .17);
      final path = Path()
        ..moveTo(-size.width * .08, y)
        ..cubicTo(
          size.width * .18,
          y - size.height * .26,
          size.width * .25,
          y + size.height * .31,
          size.width * .53,
          y - size.height * .08,
        )
        ..cubicTo(
          size.width * .74,
          y - size.height * .36,
          size.width * .78,
          y + size.height * .23,
          size.width * 1.08,
          y - size.height * .12,
        );
      canvas.drawPath(path, contourPaint);
    }

    final route = Path()
      ..moveTo(size.width * .48, size.height * .83)
      ..cubicTo(
        size.width * .3,
        size.height * .66,
        size.width * .7,
        size.height * .58,
        size.width * .62,
        size.height * .4,
      )
      ..cubicTo(
        size.width * .54,
        size.height * .23,
        size.width * .78,
        size.height * .23,
        size.width * .84,
        size.height * .12,
      );
    final routePaint = Paint()
      ..color = color.withValues(alpha: .6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    for (final metric in route.computeMetrics()) {
      for (var distance = 0.0; distance < metric.length; distance += 8) {
        canvas.drawPath(
          metric.extractPath(
            distance,
            (distance + 4.5).clamp(0.0, metric.length).toDouble(),
          ),
          routePaint,
        );
      }
    }
    final stopPaint = Paint()..color = color.withValues(alpha: .85);
    canvas.drawCircle(
      Offset(size.width * .48, size.height * .83),
      3,
      stopPaint,
    );
    canvas.drawCircle(
      Offset(size.width * .84, size.height * .12),
      3,
      stopPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _TripcrewMapInkPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Animated checkmark pop and spring-back when a packing item is checked.
/// Respects reduced-motion settings.
class TickItemMotion extends StatefulWidget {
  const TickItemMotion({
    super.key,
    required this.isChecked,
    required this.child,
  });

  final bool isChecked;
  final Widget child;

  @override
  State<TickItemMotion> createState() => _TickItemMotionState();
}

class _TickItemMotionState extends State<TickItemMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _popController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _scaleAnimation = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.0,
        end: 1.22,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 45,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.22,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOutQuad)),
      weight: 55,
    ),
  ]).animate(_popController);

  @override
  void didUpdateWidget(covariant TickItemMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isChecked && widget.isChecked) {
      if (!MediaQuery.disableAnimationsOf(context)) {
        _popController.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _popController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) => Transform.scale(
        scale: _popController.isAnimating ? _scaleAnimation.value : 1.0,
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Fine dotted route connector between two places with an accent emoji.
class DottedRouteLine extends StatelessWidget {
  const DottedRouteLine({
    super.key,
    this.color = Colors.white,
    this.dotColor,
    this.emoji = '✈️',
  });

  final Color color;
  final Color? dotColor;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    final effectiveDotColor = dotColor ?? color.withValues(alpha: 0.6);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          Container(
            width: 3.5,
            height: 3.5,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: effectiveDotColor,
              shape: BoxShape.circle,
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: BobbingSticker(
            distance: 2.5,
            duration: const Duration(milliseconds: 2400),
            child: Text(emoji, style: const TextStyle(fontSize: 14)),
          ),
        ),
        for (var i = 0; i < 3; i++) ...[
          Container(
            width: 3.5,
            height: 3.5,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: effectiveDotColor,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ],
    );
  }
}
