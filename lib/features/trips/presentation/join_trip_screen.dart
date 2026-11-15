import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Screen 6: Join a Trip with deep linking and live camera QR scanner.
class JoinTripScreen extends ConsumerStatefulWidget {
  final String? initialCode;
  const JoinTripScreen({super.key, this.initialCode});

  @override
  ConsumerState<JoinTripScreen> createState() => _JoinTripScreenState();
}

class _JoinTripScreenState extends ConsumerState<JoinTripScreen> {
  late final TextEditingController _codeController;
  bool _isJoining = false;
  String? _error;

  static String extractCleanCode(String raw) {
    String code = raw.trim();
    final uri = Uri.tryParse(code);
    if (uri != null) {
      if (uri.queryParameters.containsKey('code')) {
        code = uri.queryParameters['code']!;
      } else if (uri.queryParameters.containsKey('invite')) {
        code = uri.queryParameters['invite']!;
      } else if (uri.pathSegments.isNotEmpty) {
        final last = uri.pathSegments.last;
        if (last.isNotEmpty && last.toLowerCase() != 'join') {
          code = last;
        }
      }
    }
    return code.toUpperCase().trim();
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCode != null ? extractCleanCode(widget.initialCode!) : '';
    _codeController = TextEditingController(text: initial);
    if (initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handleJoinTrip();
      });
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleJoinTrip() async {
    if (_isJoining) return;
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Please enter an invite code.');
      return;
    }

    setState(() {
      _isJoining = true;
      _error = null;
    });

    try {
      final trip = await ref.read(tripsProvider.notifier).joinTripByCode(code);
      if (mounted && trip != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully joined ${trip.name}!')),
        );
        context.go('/workspace');
      }
    } catch (e) {
      debugPrint('[JoinTripScreen] Failed to join trip: $e');
      final rawError = e.toString();
      if (rawError.contains('permission-denied') ||
          rawError.contains('PERMISSION_DENIED')) {
        setState(
          () => _error =
              "We couldn't join this trip. Check the invite code and try again.",
        );
      } else {
        setState(() => _error = rawError.replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  void _processScannedCode(String raw) {
    final code = extractCleanCode(raw);
    if (code.isNotEmpty) {
      _codeController.text = code;
      _handleJoinTrip();
    }
  }

  Future<void> _pickQrFromGallery({BuildContext? modalCtx, MobileScannerController? activeController}) async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      final controller = activeController ?? MobileScannerController();
      final BarcodeCapture? capture = await controller.analyzeImage(image.path);
      if (activeController == null) {
        controller.dispose();
      }

      if (capture != null && capture.barcodes.isNotEmpty) {
        for (final barcode in capture.barcodes) {
          final raw = barcode.rawValue;
          if (raw != null && raw.isNotEmpty) {
            if (activeController != null) {
              activeController.dispose();
            }
            if (modalCtx != null && modalCtx.mounted) {
              Navigator.pop(modalCtx);
            }
            _processScannedCode(raw);
            return;
          }
        }
      }

      final targetContext = modalCtx ?? context;
      if (targetContext.mounted) {
        ScaffoldMessenger.of(targetContext).showSnackBar(
          const SnackBar(
            content: Text('No QR code found in the selected image. Please try another.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
    } catch (e) {
      final targetContext = modalCtx ?? context;
      if (targetContext.mounted) {
        ScaffoldMessenger.of(targetContext).showSnackBar(
          SnackBar(
            content: Text('Error analyzing image: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _openQrScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final controller = MobileScannerController(
          detectionSpeed: DetectionSpeed.noDuplicates,
        );

        return SafeArea(
          child: Container(
            height: MediaQuery.of(ctx).size.height * 0.78,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Scan Trip QR Code',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.photo_library_rounded, color: Colors.white),
                          tooltip: 'Upload QR from Gallery',
                          onPressed: () => _pickQrFromGallery(modalCtx: ctx, activeController: controller),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () {
                            controller.dispose();
                            Navigator.pop(ctx);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        MobileScanner(
                          controller: controller,
                          onDetect: (capture) {
                            final List<Barcode> barcodes = capture.barcodes;
                            for (final barcode in barcodes) {
                              final raw = barcode.rawValue;
                              if (raw != null && raw.isNotEmpty) {
                                controller.dispose();
                                Navigator.pop(ctx);
                                _processScannedCode(raw);
                                break;
                              }
                            }
                          },
                        ),
                        // Scanner Viewfinder Overlay
                        Container(
                          width: 230,
                          height: 230,
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFF258CF4), width: 3),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF258CF4).withValues(alpha: 0.3),
                                blurRadius: 16,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Button to upload QR from gallery inside modal
                OutlinedButton.icon(
                  onPressed: () => _pickQrFromGallery(modalCtx: ctx, activeController: controller),
                  icon: const Icon(Icons.photo_library_outlined, color: Colors.white, size: 18),
                  label: const Text(
                    'Upload QR from Gallery',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Point camera at QR code or upload an image from gallery',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Join a Trip'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
          ),
        ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceLg),
          child: Column(
            children: [
              const SizedBox(height: AppConstants.spaceLg),
              // Illustration Container
              Container(
                height: 160,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.3,
                  ),
                  borderRadius: BorderRadius.circular(AppConstants.radiusXl),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.group_work_rounded,
                        size: 64,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Join your crew journey',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spaceXl),

              Text(
                'Got an invite code?',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppConstants.spaceXs),
              Text(
                'Enter it below to join the shared crew workspace.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppConstants.spaceXl),

              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppConstants.spaceSm),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(
                      alpha: 0.6,
                    ),
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppConstants.spaceMd),
              ],

              // Invite Code TextField with live QR scanner trigger
              TextField(
                controller: _codeController,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'TRIP-XXXXX',
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.photo_library_outlined),
                        tooltip: 'Upload QR from Gallery',
                        onPressed: () => _pickQrFromGallery(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        tooltip: 'Scan Trip QR Code',
                        onPressed: _openQrScanner,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spaceSm),
              Text(
                'Invite codes are typically 6-10 characters',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppConstants.space2xl),

              // Join Trip Button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isJoining ? null : _handleJoinTrip,
                  child: _isJoining
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Join Trip'),
                ),
              ),
              const SizedBox(height: AppConstants.spaceLg),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
