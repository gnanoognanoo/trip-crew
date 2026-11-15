import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/analytics_service.dart';
import 'package:tripcrew/features/trips/models/trip_model.dart';

/// Service to handle trip invite link sharing, QR generation, and native app sharing.
class TripShareService {
  /// Formats the trip invitation text message for sharing across external apps.
  static String formatInviteMessage({
    required String tripName,
    required String inviteCode,
    String? startingPlace,
    String? destination,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final dateFormat = DateFormat('dd MMM yyyy');
    final dateSnippet = (startDate != null && endDate != null)
        ? '${dateFormat.format(startDate)} – ${dateFormat.format(endDate)}'
        : (startDate != null ? dateFormat.format(startDate) : null);

    final destSnippet = (destination != null && destination.isNotEmpty)
        ? (startingPlace != null && startingPlace.isNotEmpty
            ? '$startingPlace → $destination'
            : destination)
        : null;

    final buffer = StringBuffer();
    buffer.writeln('🚀 Join our trip "$tripName" on TripCrew!');
    if (destSnippet != null) {
      buffer.writeln('📍 Destination: $destSnippet');
    }
    if (dateSnippet != null) {
      buffer.writeln('🗓 Dates: $dateSnippet');
    }
    buffer.writeln('🔑 Invite Code: $inviteCode');
    buffer.writeln();
    buffer.writeln('👉 Tap to join directly in the app:');
    buffer.writeln('https://tripcrew-travel-2026.web.app/join/$inviteCode');
    buffer.writeln();

    return buffer.toString().trim();
  }

  /// Generates a high-contrast, solid white background invite card with the QR code.
  /// Prevents black box rendering when shared to WhatsApp or other dark-mode apps.
  static Future<Uint8List> generateInviteCardPng({
    required String inviteCode,
    required String tripName,
    String? startingPlace,
    String? destination,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 800, 1050));

    // 1. Solid pure white background
    final bgPaint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 800, 1050), bgPaint);

    // 2. Card header accent banner
    final headerPaint = Paint()..color = const Color(0xFF0F1E36);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(30, 30, 740, 180),
        const Radius.circular(24),
      ),
      headerPaint,
    );

    // Header tag: "TRIPCREW INVITE"
    final tagPainter = TextPainter(
      text: const TextSpan(
        text: '🚀  T R I P C R E W   I N V I T E',
        style: TextStyle(
          color: Color(0xFF258CF4),
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: 2.0,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: 680);
    tagPainter.paint(canvas, const Offset(60, 56));

    // Trip Name
    final titlePainter = TextPainter(
      text: TextSpan(
        text: tripName,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 34,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: 680);
    titlePainter.paint(canvas, const Offset(60, 95));

    // Destination & Dates subtitle
    final destText = (destination != null && destination.isNotEmpty)
        ? (startingPlace != null && startingPlace.isNotEmpty
            ? '$startingPlace → $destination'
            : destination)
        : 'Explore together';
    final subPainter = TextPainter(
      text: TextSpan(
        text: '📍 $destText',
        style: const TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 18,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: 680);
    subPainter.paint(canvas, const Offset(60, 150));

    // 3. QR Code Container Box
    final qrBoxPaint = Paint()
      ..color = const Color(0xFFF8FAFC)
      ..style = PaintingStyle.fill;
    final qrBorderPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final qrRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(110, 245, 580, 580),
      const Radius.circular(28),
    );
    canvas.drawRRect(qrRect, qrBoxPaint);
    canvas.drawRRect(qrRect, qrBorderPaint);

    // Paint QR Code in center with dark navy modules
    final qrPainter = QrPainter(
      data: 'https://tripcrew-travel-2026.web.app/join/$inviteCode',
      version: QrVersions.auto,
      gapless: true,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Color(0xFF0F172A),
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Color(0xFF0F172A),
      ),
    );

    canvas.save();
    canvas.translate(150, 285);
    qrPainter.paint(canvas, const Size(500, 500));
    canvas.restore();

    // 4. Invite Code Pill
    final pillPaint = Paint()..color = const Color(0xFFF1F5F9);
    final pillRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(180, 855, 440, 70),
      const Radius.circular(35),
    );
    canvas.drawRRect(pillRect, pillPaint);

    final codePainter = TextPainter(
      text: TextSpan(
        text: inviteCode,
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 26,
          fontWeight: FontWeight.w900,
          letterSpacing: 3.0,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    codePainter.paint(
      canvas,
      Offset(400 - (codePainter.width / 2), 875),
    );

    // 5. Footer Instructions
    final footerPainter = TextPainter(
      text: const TextSpan(
        text: 'Scan with phone camera or TripCrew to join instantly',
        style: TextStyle(
          color: Color(0xFF64748B),
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    footerPainter.paint(
      canvas,
      Offset(400 - (footerPainter.width / 2), 950),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(800, 1050);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Opens the system app share sheet (WhatsApp, Telegram, Messages, Gmail, etc.)
  /// with the formatted trip invite text, deep link, and high-visibility QR invite card.
  static Future<void> shareTripInvite({
    required TripModel trip,
    BuildContext? context,
  }) async {
    final message = formatInviteMessage(
      tripName: trip.name,
      inviteCode: trip.inviteCode,
      startingPlace: trip.startingPlace,
      destination: trip.destination,
      startDate: trip.startDate,
      endDate: trip.endDate,
    );

    try {
      AnalyticsService.logInviteShared(trip.id);

      // Render high-contrast solid white invite card
      final bytes = await generateInviteCardPng(
        inviteCode: trip.inviteCode,
        tripName: trip.name,
        startingPlace: trip.startingPlace,
        destination: trip.destination,
        startDate: trip.startDate,
        endDate: trip.endDate,
      );

      final tempDir = await getTemporaryDirectory();
      final cleanCode = trip.inviteCode.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      final file = File('${tempDir.path}/tripcrew_invite_$cleanCode.png');
      await file.writeAsBytes(bytes, flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png', name: 'tripcrew_invite_$cleanCode.png')],
          text: message,
          subject: 'Join my trip on TripCrew: ${trip.name}',
          title: 'Share Trip Invite',
        ),
      );
    } catch (e) {
      developer.log('Error sharing trip invite: $e', name: 'TripShareService');
      try {
        await SharePlus.instance.share(
          ShareParams(
            text: message,
            subject: 'Join my trip on TripCrew: ${trip.name}',
            title: 'Share Trip Invite',
          ),
        );
      } catch (_) {
        if (context != null && context.mounted) {
          Clipboard.setData(ClipboardData(text: message));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open share apps. Invite copied to clipboard!'),
            ),
          );
        }
      }
    }
  }

  /// Renders a QR code to PNG bytes and shares it as an image file alongside the
  /// invitation message using the system app share sheet.
  static Future<void> shareTripQrCode({
    required String inviteCode,
    String? tripName,
    String? tripId,
    String? startingPlace,
    String? destination,
    DateTime? startDate,
    DateTime? endDate,
    BuildContext? context,
  }) async {
    final message = formatInviteMessage(
      tripName: tripName ?? 'Trip',
      inviteCode: inviteCode,
      startingPlace: startingPlace,
      destination: destination,
      startDate: startDate,
      endDate: endDate,
    );

    if (tripId != null) {
      AnalyticsService.logInviteShared(tripId);
    }

    try {
      final bytes = await generateInviteCardPng(
        inviteCode: inviteCode,
        tripName: tripName ?? 'TripCrew',
        startingPlace: startingPlace,
        destination: destination,
        startDate: startDate,
        endDate: endDate,
      );

      final tempDir = await getTemporaryDirectory();
      final cleanCode = inviteCode.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      final file = File('${tempDir.path}/tripcrew_invite_$cleanCode.png');
      await file.writeAsBytes(bytes, flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png', name: 'tripcrew_invite_$cleanCode.png')],
          text: message,
          subject: 'Trip QR Code: ${tripName ?? 'TripCrew'}',
          title: 'Share Trip QR Code',
        ),
      );
      return;
    } catch (e) {
      developer.log('QR image generation error, falling back to text share: $e',
          name: 'TripShareService');
    }

    // Fallback: share text invitation if image generation or file share is unsupported
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: message,
          subject: 'Trip QR Code: ${tripName ?? 'TripCrew'}',
          title: 'Share Trip QR Code',
        ),
      );
    } catch (e) {
      if (context != null && context.mounted) {
        Clipboard.setData(ClipboardData(text: 'https://tripcrew-travel-2026.web.app/join/$inviteCode'));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invite link copied to clipboard!')),
        );
      }
    }
  }

  /// Displays an interactive QR modal dialog with QR image and "Share via Apps" action.
  static void showQrModal(
    BuildContext context, {
    required String inviteCode,
    required String tripName,
    String? tripId,
    String? startingPlace,
    String? destination,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          ),
          title: Row(
            children: [
              Icon(Icons.qr_code_2_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Trip QR Code',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tripName.isNotEmpty) ...[
                Text(
                  tripName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                if (destination != null && destination.isNotEmpty)
                  Text(
                    destination,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                const SizedBox(height: AppConstants.spaceMd),
              ],

              // QR Code container with solid white background for reliable camera scanning
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: QrImageView(
                    data: 'https://tripcrew-travel-2026.web.app/join/$inviteCode',
                    version: QrVersions.auto,
                    size: 200,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF000000),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF000000),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spaceMd),

              // Code Display Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      inviteCode,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      tooltip: 'Copy Code',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: inviteCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Code $inviteCode copied to clipboard!'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Point camera or share via apps to invite your crew',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.share_rounded, size: 18),
              label: const Text('Share Card'),
              onPressed: () {
                Navigator.pop(ctx);
                shareTripQrCode(
                  inviteCode: inviteCode,
                  tripName: tripName,
                  tripId: tripId,
                  startingPlace: startingPlace,
                  destination: destination,
                  startDate: startDate,
                  endDate: endDate,
                  context: context,
                );
              },
            ),
          ],
        );
      },
    );
  }
}
