import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tripcrew/core/constants/app_constants.dart';

/// Screen 14: Live Crew Location map screen matching UI design mockup.
class LiveCrewLocationScreen extends ConsumerStatefulWidget {
  const LiveCrewLocationScreen({super.key});

  @override
  ConsumerState<LiveCrewLocationScreen> createState() =>
      _LiveCrewLocationScreenState();
}

class _LiveCrewLocationScreenState
    extends ConsumerState<LiveCrewLocationScreen> {
  String _sharingOption =
      'Until End of Day'; // Off, 1 Hour, Until End of Day, Trip End

  void _showPrivacyOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Live Location Sharing Privacy',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              const SizedBox(height: 6),
              const Text(
                'TripCrew respects your privacy. Location sharing is explicit opt-in and battery-optimized.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              _buildOptionTile('Off', 'Do not broadcast GPS coordinates'),
              _buildOptionTile('1 Hour', 'Share temporarily while regrouping'),
              _buildOptionTile(
                'Until End of Day',
                'Active until 11:59 PM today',
              ),
              _buildOptionTile('Trip End', 'Share throughout Goa Trip'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile(String option, String subtitle) {
    final isSelected = _sharingOption == option;
    return ListTile(
      title: Text(option, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: Color(0xFF10B981))
          : null,
      onTap: () {
        setState(() => _sharingOption = option);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location sharing updated to: $option')),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Crew Location'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.security_rounded),
            onPressed: _showPrivacyOptions,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map Background Surface
          Container(
            color: const Color(0xFFDCEAF2),
            child: Stack(
              children: [
                // Simulated terrain/coastlines & roads
                Positioned(
                  left: -50,
                  top: 0,
                  bottom: 0,
                  width: 140,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF8AC4D0),
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(80),
                        bottomRight: Radius.circular(120),
                      ),
                    ),
                  ),
                ),
                // Road traces
                CustomPaint(size: Size.infinite, painter: _MapCanvasPainter()),

                // Marker 1: Kowshik
                _buildMarker(
                  top: 140,
                  left: 170,
                  name: 'Kowshik',
                  status: '250 m away',
                  color: Colors.orange,
                  isOwner: true,
                ),

                // Marker 2: Rahul
                _buildMarker(
                  top: 260,
                  left: 90,
                  name: 'Rahul',
                  status: '1.2 km away',
                  color: Colors.blue,
                ),

                // Marker 3: Praveen
                _buildMarker(
                  top: 320,
                  left: 210,
                  name: 'Praveen',
                  status: 'With Group',
                  color: Colors.purple,
                ),

                // Marker 4: Arun
                _buildMarker(
                  top: 350,
                  left: 180,
                  name: 'Arun',
                  status: 'With Group',
                  color: Colors.teal,
                ),
              ],
            ),
          ),

          // Privacy status chip at top
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: InkWell(
              onTap: _showPrivacyOptions,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sharing: $_sharingOption',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.tune_rounded,
                      size: 16,
                      color: Colors.grey,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom "Everyone is together!" Banner Card
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.spaceMd),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF10B981),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: AppConstants.spaceMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Everyone is together!',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'All 4 crew members are within 1.5 km of meeting point.',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarker({
    required double top,
    required double left,
    required String name,
    required String status,
    required Color color,
    bool isOwner = false,
  }) {
    return Positioned(
      top: top,
      left: left,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                Text(
                  status,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    name[0],
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MapCanvasPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(60, 0);
    path.quadraticBezierTo(200, 150, 180, 300);
    path.quadraticBezierTo(160, 450, 300, 600);
    canvas.drawPath(path, roadPaint);

    final roadPaint2 = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    final path2 = Path();
    path2.moveTo(180, 250);
    path2.lineTo(350, 220);
    canvas.drawPath(path2, roadPaint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
