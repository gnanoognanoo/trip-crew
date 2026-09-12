import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:tripcrew/features/maps/models/live_location_model.dart';
import 'package:tripcrew/features/maps/utils/location_calculator.dart';

/// CustomPainter rendering a tactical "Crew Radar" visualizing members relative to the current user.
class CrewRadarPainter extends CustomPainter {
  final List<LiveLocationModel> members;
  final Map<String, double> distances;
  final Map<String, double> bearings;
  final String? selectedMemberUid;
  final double animationValue; // 0.0 to 1.0 for radar sweep & pulse ripple
  final bool isUserSharing;

  const CrewRadarPainter({
    required this.members,
    required this.distances,
    required this.bearings,
    this.selectedMemberUid,
    required this.animationValue,
    required this.isUserSharing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2 - 24;

    // 1. Calculate dynamic scale (max distance to represent on radar)
    double maxDistance = 500.0; // Default 500 meters
    for (final d in distances.values) {
      if (d > maxDistance) {
        maxDistance = d;
      }
    }
    // Round up to clean increments (e.g. 500m, 1000m, 2000m, 5000m)
    if (maxDistance > 2000) {
      maxDistance = (maxDistance / 1000).ceil() * 1000.0;
    } else if (maxDistance > 500) {
      maxDistance = (maxDistance / 500).ceil() * 500.0;
    }

    // 2. Draw Radar Background Gradient
    final bgPaint = Paint()
      ..shader = RadialGradient(
        colors: [const Color(0xFF0F172A), const Color(0xFF020617)],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius));
    canvas.drawCircle(center, maxRadius, bgPaint);

    // 3. Draw Concentric Range Rings
    final ringPaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final rings = [0.25, 0.5, 0.75, 1.0];
    for (final fraction in rings) {
      final r = maxRadius * fraction;
      canvas.drawCircle(center, r, ringPaint);

      // Label distance ring
      final ringMeters = maxDistance * fraction;
      final label = LocationCalculator.formatCompactDistance(ringMeters);
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: const Color(0xFF10B981).withValues(alpha: 0.6),
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(canvas, Offset(center.dx + 4, center.dy - r + 2));
    }

    // 4. Draw Crosshair Axes (N, S, E, W)
    final axisPaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.12)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(center.dx - maxRadius, center.dy),
      Offset(center.dx + maxRadius, center.dy),
      axisPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - maxRadius),
      Offset(center.dx, center.dy + maxRadius),
      axisPaint,
    );

    // Cardinal direction labels
    _drawCardinalLabel(
      canvas,
      'N',
      Offset(center.dx, center.dy - maxRadius - 14),
    );
    _drawCardinalLabel(
      canvas,
      'S',
      Offset(center.dx, center.dy + maxRadius + 4),
    );
    _drawCardinalLabel(
      canvas,
      'E',
      Offset(center.dx + maxRadius + 6, center.dy - 6),
    );
    _drawCardinalLabel(
      canvas,
      'W',
      Offset(center.dx - maxRadius - 16, center.dy - 6),
    );

    // 5. Draw Radar Rotating Sweep Beam
    final sweepAngle = animationValue * 2 * math.pi;
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        center: FractionalOffset.center,
        startAngle: 0.0,
        endAngle: math.pi / 2,
        colors: [
          const Color(0xFF10B981).withValues(alpha: 0.25),
          Colors.transparent,
        ],
        transform: GradientRotation(sweepAngle),
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius));
    canvas.drawCircle(center, maxRadius, sweepPaint);

    // 6. Draw Members on Radar
    for (final member in members) {
      if (!member.isSharing || member.isExpired || !member.hasCoordinates) {
        continue;
      }

      final dist = distances[member.uid];
      final bearing = bearings[member.uid];
      if (dist == null || bearing == null) continue;

      // Convert bearing (0 = N, 90 = E) to canvas radians (-pi/2 = N)
      final bearingRad = (bearing - 90) * (math.pi / 180.0);
      final clampedDist = math.min(dist, maxDistance);
      final r = (clampedDist / maxDistance) * maxRadius;

      final memberX = center.dx + r * math.cos(bearingRad);
      final memberY = center.dy + r * math.sin(bearingRad);
      final memberOffset = Offset(memberX, memberY);

      final isSelected = member.uid == selectedMemberUid;
      final isAway = dist > kTogetherThresholdMeters;
      final isStale = member.freshness == LocationFreshness.stale;
      final Color markerColor = isStale
          ? const Color(0xFF94A3B8)
          : (isAway ? const Color(0xFFF59E0B) : const Color(0xFF10B981));

      // Selected ring
      if (isSelected) {
        final selectPaint = Paint()
          ..color = markerColor.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;
        canvas.drawCircle(memberOffset, 16, selectPaint);
      }

      // Member marker dot
      final markerPaint = Paint()..color = markerColor;
      canvas.drawCircle(memberOffset, 9, markerPaint);

      final innerPaint = Paint()..color = Colors.white;
      canvas.drawCircle(memberOffset, 7, innerPaint);

      // Member initial
      final initial = member.displayName.isNotEmpty
          ? member.displayName[0].toUpperCase()
          : 'M';
      final initialPainter = TextPainter(
        text: TextSpan(
          text: initial,
          style: TextStyle(
            color: markerColor,
            fontSize: 9,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      initialPainter.paint(
        canvas,
        Offset(
          memberOffset.dx - initialPainter.width / 2,
          memberOffset.dy - initialPainter.height / 2,
        ),
      );

      // Optional small pulse icon next to radar marker (e.g. ●🍔)
      final pulseEmoji = member.radarPulseEmoji;
      if (pulseEmoji != null) {
        final emojiPainter = TextPainter(
          text: TextSpan(
            text: pulseEmoji,
            style: const TextStyle(fontSize: 11),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        emojiPainter.paint(
          canvas,
          Offset(memberOffset.dx + 7, memberOffset.dy - 11),
        );
      }

      // Member Name & Distance Label
      final nameSnippet = member.displayName.split(' ').first;
      final distSnippet = LocationCalculator.formatCompactDistance(dist);
      final distText = isStale
          ? '$distSnippet (Stale)'
          : (isAway ? '$distSnippet ⚠️' : distSnippet);
      final labelSpan = TextSpan(
        children: [
          TextSpan(
            text: '$nameSnippet\n',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
            ),
          ),
          TextSpan(
            text: distText,
            style: TextStyle(
              color: markerColor,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              shadows: const [Shadow(color: Colors.black87, blurRadius: 4)],
            ),
          ),
        ],
      );

      final labelPainter = TextPainter(
        text: labelSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();

      // Position label slightly below marker
      labelPainter.paint(
        canvas,
        Offset(memberOffset.dx - labelPainter.width / 2, memberOffset.dy + 12),
      );
    }

    // 7. Draw Center "YOU" Beacon with Animated Pulse
    if (isUserSharing) {
      final rippleRadius = 10 + (animationValue * 14);
      final ripplePaint = Paint()
        ..color = const Color(
          0xFF38BDF8,
        ).withValues(alpha: (1.0 - animationValue) * 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(center, rippleRadius, ripplePaint);
    }

    final youPaint = Paint()..color = const Color(0xFF38BDF8);
    canvas.drawCircle(center, 7, youPaint);

    final youInnerPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, 4, youInnerPaint);

    // "YOU" Label
    final youPainter = TextPainter(
      text: const TextSpan(
        text: 'YOU',
        style: TextStyle(
          color: Color(0xFF38BDF8),
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    youPainter.paint(
      canvas,
      Offset(center.dx - youPainter.width / 2, center.dy + 9),
    );
  }

  void _drawCardinalLabel(Canvas canvas, String label, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(offset.dx - painter.width / 2, offset.dy));
  }

  @override
  bool shouldRepaint(covariant CrewRadarPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.distances != distances ||
        oldDelegate.bearings != bearings ||
        oldDelegate.selectedMemberUid != selectedMemberUid ||
        oldDelegate.isUserSharing != isUserSharing ||
        oldDelegate.members.length != members.length;
  }
}
