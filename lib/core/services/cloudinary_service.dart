import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:tripcrew/core/services/firebase_service.dart';

/// Validation failure during file inspection prior to Cloudinary upload.
class CloudinaryValidationException implements Exception {
  final String message;
  const CloudinaryValidationException(this.message);

  @override
  String toString() => 'CloudinaryValidationException: $message';
}

/// Authorization failure during pre-upload permission checks.
class CloudinaryAuthException implements Exception {
  final String message;
  const CloudinaryAuthException(this.message);

  @override
  String toString() => 'CloudinaryAuthException: $message';
}

/// Network or API failure during Cloudinary image upload.
class CloudinaryUploadException implements Exception {
  final String message;
  final int? statusCode;
  const CloudinaryUploadException(this.message, [this.statusCode]);

  @override
  String toString() =>
      'CloudinaryUploadException (status $statusCode): $message';
}

/// Result object returned by [CloudinaryService] after a successful image upload.
class CloudinaryUploadResult {
  final String secureUrl;
  final String publicId;
  final String? format;
  final int? bytes;
  final int? width;
  final int? height;
  final DateTime createdAt;

  const CloudinaryUploadResult({
    required this.secureUrl,
    required this.publicId,
    this.format,
    this.bytes,
    this.width,
    this.height,
    required this.createdAt,
  });

  factory CloudinaryUploadResult.fromJson(Map<String, dynamic> json) {
    String rawUrl = json['secure_url'] as String? ?? '';
    // Enforce HTTPS
    if (rawUrl.startsWith('http://')) {
      rawUrl = rawUrl.replaceFirst('http://', 'https://');
    }

    return CloudinaryUploadResult(
      secureUrl: rawUrl,
      publicId: json['public_id'] as String? ?? '',
      format: json['format'] as String?,
      bytes: (json['bytes'] as num?)?.toInt(),
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// Hardened service handling media uploads to the Cloudinary free tier.
///
/// ============================================================================
/// SECURITY & PRIVACY ARCHITECTURE NOTICE
/// ============================================================================
/// 1. ZERO SECRETS IN CLIENT:
///    The Cloudinary API Secret is NEVER bundled inside this Flutter application
///    or committed to version control.
///
/// 2. UNSIGNED UPLOAD PRESETS:
///    Client-side direct uploads use Cloudinary unsigned upload presets:
///    - `tripcrew_avatar_upload` for user avatars (max 5 MB)
///    - `tripcrew_memory_upload` for trip memories (max 10 MB)
///    Both presets should be configured in the Cloudinary Console with:
///      * Mode: Unsigned
///      * Allowed Formats: jpg, jpeg, png, webp
///      * Disallow Overwrite (overwrite: false)
///      * Strip Metadata: true
///      * Auto quality and max dimension limits
///
/// 3. PRIVACY WARNING (PUBLIC CDN DELIVERY):
///    Images uploaded via unsigned presets receive public CDN URLs
///    (`https://res.cloudinary.com/...`). Anyone in possession of the URL can
///    view the media. Trip memories are NOT end-to-end encrypted or private
///    merely because Firestore metadata is guarded.
///    True private delivery requires a backend server generating signed URLs.
///
/// 4. REMOTE DELETION:
///    Deleting assets from Cloudinary requires the API Secret (destroy endpoint).
///    Because no secret is stored in Flutter, remote deletion cannot be performed
///    directly by the mobile client. Only Firestore metadata is deleted on the
///    client; remote asset cleanup requires a secure backend service.
/// ============================================================================
class CloudinaryService {
  CloudinaryService._();

  /// Cloudinary Cloud Name. Configurable via `--dart-define=CLOUDINARY_CLOUD_NAME=...`.
  static const String cloudName = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
    defaultValue: 'tripcrew',
  );

  /// Preset for user avatars (max 5 MB).
  static const String avatarPreset = String.fromEnvironment(
    'CLOUDINARY_AVATAR_PRESET',
    defaultValue: 'tripcrew_avatar_upload',
  );

  /// Preset for trip shared memories (max 10 MB).
  static const String memoryPreset = String.fromEnvironment(
    'CLOUDINARY_MEMORY_PRESET',
    defaultValue: 'tripcrew_memory_upload',
  );

  /// General fallback preset.
  static const String fallbackPreset = String.fromEnvironment(
    'CLOUDINARY_UPLOAD_PRESET',
    defaultValue: 'tripcrew_unsigned',
  );

  /// Maximum file size limits in bytes.
  static const int maxAvatarSizeBytes = 5 * 1024 * 1024; // 5 MB
  static const int maxMemorySizeBytes = 10 * 1024 * 1024; // 10 MB

  /// Allowed image file extensions (lowercase).
  static const Set<String> allowedExtensions = {'jpg', 'jpeg', 'png', 'webp'};

  static Uri get _uploadEndpoint =>
      Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');

  // --------------------------------------------------------------------------
  // Client-Side Validation
  // --------------------------------------------------------------------------

  /// Validates file extension and size before network transmission.
  static void validateFile({
    required String filename,
    required int byteLength,
    required int maxSizeBytes,
  }) {
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == filename.length - 1) {
      throw const CloudinaryValidationException(
        'Selected file has no extension. Only jpg, jpeg, png, and webp are allowed.',
      );
    }

    final ext = filename.substring(dotIndex + 1).toLowerCase();
    if (!allowedExtensions.contains(ext)) {
      throw CloudinaryValidationException(
        'Unsupported file format: .$ext. Allowed formats: ${allowedExtensions.join(', ')}.',
      );
    }

    if (byteLength <= 0) {
      throw const CloudinaryValidationException(
        'Selected file is empty (0 bytes).',
      );
    }

    if (byteLength > maxSizeBytes) {
      final maxMb = (maxSizeBytes / (1024 * 1024)).toStringAsFixed(0);
      final fileMb = (byteLength / (1024 * 1024)).toStringAsFixed(2);
      throw CloudinaryValidationException(
        'File size (${fileMb}MB) exceeds maximum permitted size of ${maxMb}MB.',
      );
    }
  }

  // --------------------------------------------------------------------------
  // Authorization Guards
  // --------------------------------------------------------------------------

  /// Verifies the current user is authenticated and authorized to upload to [tripId].
  /// Checks Firestore `trips/{tripId}/members/{uid}` and `trips/{tripId}.ownerId`.
  static Future<void> verifyTripMemberAuthorization({
    required String tripId,
    required String uid,
  }) async {
    if (!FirebaseService.isInitialized) {
      if (uid.isEmpty) {
        throw const CloudinaryAuthException(
          'Authentication required to upload trip media.',
        );
      }
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw const CloudinaryAuthException(
        'User must be signed in with Firebase to upload trip memories.',
      );
    }

    if (currentUser.uid != uid) {
      throw const CloudinaryAuthException(
        'Authenticated user ID does not match the uploader ID.',
      );
    }

    try {
      final tripDoc = await FirebaseFirestore.instance
          .collection('trips')
          .doc(tripId)
          .get();

      if (!tripDoc.exists) {
        throw CloudinaryAuthException('Trip $tripId does not exist.');
      }

      final ownerId = tripDoc.data()?['ownerId'] as String?;
      if (ownerId == uid) {
        // Owner is authorized
        return;
      }

      final memberDoc = await FirebaseFirestore.instance
          .collection('trips')
          .doc(tripId)
          .collection('members')
          .doc(uid)
          .get();

      if (!memberDoc.exists) {
        throw CloudinaryAuthException(
          'User is not a member of trip $tripId. Upload denied.',
        );
      }
    } on CloudinaryAuthException {
      rethrow;
    } catch (e) {
      throw CloudinaryAuthException('Failed to verify trip membership: $e');
    }
  }

  /// Verifies that the user is authenticated and uploading their own avatar.
  static void verifyAvatarAuthorization(String uid) {
    if (!FirebaseService.isInitialized) {
      if (uid.isEmpty) {
        throw const CloudinaryAuthException(
          'Authentication required to upload avatar.',
        );
      }
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw const CloudinaryAuthException(
        'User must be signed in with Firebase to update avatar.',
      );
    }

    if (currentUser.uid != uid) {
      throw const CloudinaryAuthException(
        'Cannot upload avatar on behalf of another user.',
      );
    }
  }

  // --------------------------------------------------------------------------
  // Upload Workflows
  // --------------------------------------------------------------------------

  /// Uploads a user avatar to `tripcrew/avatars/{uid}` using [avatarPreset].
  static Future<CloudinaryUploadResult> uploadAvatar({
    required Uint8List bytes,
    required String filename,
    required String uid,
    http.Client? client,
  }) async {
    // 1. Authorization
    verifyAvatarAuthorization(uid);

    // 2. Validation
    validateFile(
      filename: filename,
      byteLength: bytes.length,
      maxSizeBytes: maxAvatarSizeBytes,
    );

    // 3. Execution with strict folder structure
    return _performUpload(
      bytes: bytes,
      filename: filename,
      preset: avatarPreset,
      folder: 'tripcrew/avatars/$uid',
      tags: ['tripcrew', 'avatar', uid],
      client: client,
    );
  }

  /// Uploads a trip memory photo to `tripcrew/memories/{tripId}/{uid}` using [memoryPreset].
  static Future<CloudinaryUploadResult> uploadMemory({
    required Uint8List bytes,
    required String filename,
    required String tripId,
    required String uid,
    http.Client? client,
  }) async {
    // 1. Authorization
    await verifyTripMemberAuthorization(tripId: tripId, uid: uid);

    // 2. Validation
    validateFile(
      filename: filename,
      byteLength: bytes.length,
      maxSizeBytes: maxMemorySizeBytes,
    );

    // 3. Execution with strict folder structure
    return _performUpload(
      bytes: bytes,
      filename: filename,
      preset: memoryPreset,
      folder: 'tripcrew/memories/$tripId/$uid',
      tags: ['tripcrew', 'memory', tripId, uid],
      client: client,
    );
  }

  /// Internal worker executing the multipart POST request.
  static Future<CloudinaryUploadResult> _performUpload({
    required Uint8List bytes,
    required String filename,
    required String preset,
    required String folder,
    required List<String> tags,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    final shouldClose = client == null;

    try {
      final request = http.MultipartRequest('POST', _uploadEndpoint);

      // Secure unsigned parameters
      request.fields['upload_preset'] = preset;
      request.fields['folder'] = folder;
      request.fields['tags'] = tags.join(',');

      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );

      final streamedResponse = await httpClient.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        developer.log(
          'Cloudinary upload success: ${data['public_id']} (${data['secure_url']})',
          name: 'CloudinaryService',
        );
        return CloudinaryUploadResult.fromJson(data);
      } else {
        developer.log(
          'Cloudinary upload failed (HTTP ${response.statusCode}): ${response.body}',
          name: 'CloudinaryService',
          level: 900,
        );
        throw CloudinaryUploadException(
          'Upload service returned error ${response.statusCode}.',
          response.statusCode,
        );
      }
    } on CloudinaryValidationException {
      rethrow;
    } on CloudinaryAuthException {
      rethrow;
    } on CloudinaryUploadException {
      rethrow;
    } catch (e, stack) {
      developer.log(
        'Cloudinary upload network error: $e',
        name: 'CloudinaryService',
        stackTrace: stack,
        level: 900,
      );
      throw const CloudinaryUploadException(
        'Network error while connecting to media server. Please check your connection.',
      );
    } finally {
      if (shouldClose) {
        httpClient.close();
      }
    }
  }

  // --------------------------------------------------------------------------
  // Deletion Architecture Notice
  // --------------------------------------------------------------------------

  /// Remote Cloudinary asset deletion is intentionally NOT implemented on the client.
  ///
  /// EXPLANATION:
  /// Cloudinary's `/image/destroy` endpoint requires cryptographic HMAC-SHA1
  /// signature generation using the account's API Secret.
  /// Placing the API Secret inside Flutter would violate security constraints.
  /// Remote asset destruction must be performed by a trusted server/backend.
  static Future<void> deleteAsset(String publicId) {
    developer.log(
      'UNSUPPORTED_ACTION: Attempted to delete remote asset [$publicId] from Flutter. '
      'Remote deletion requires a trusted backend signature service.',
      name: 'CloudinaryService',
      level: 900,
    );
    throw UnsupportedError(
      'Remote Cloudinary asset deletion is not supported directly in Flutter. '
      'Remote cleanup must be scheduled via a secure backend service.',
    );
  }
}
