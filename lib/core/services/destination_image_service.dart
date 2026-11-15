import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripcrew/core/services/location_service.dart';

/// Information about a destination resolved via Google Places API / Google Maps.
class DestinationPlaceInfo {
  final String photoUrl;
  final String placeName;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? placeId;

  const DestinationPlaceInfo({
    required this.photoUrl,
    required this.placeName,
    this.address,
    this.latitude,
    this.longitude,
    this.placeId,
  });
}

/// Service to resolve authentic destination photos via Google Places API (New)
/// with instant caching and contextual travel photography fallbacks.
class DestinationImageService {
  static const String _apiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  static final Map<String, String> _memoryCache = {};

  /// Pre-curated, authentic destination photos tailored to Indian & global travel destinations.
  /// Avoids misleading generic foreign stock photos (like the Roman Colosseum for Chennai or VR Mall).
  static const Map<String, String> _curatedFallbacks = {
    'pondi': 'https://images.unsplash.com/photo-1582510003544-4d00b7f74220?w=1200&auto=format&fit=crop&q=80', // Pondicherry Promenade / Rock Beach
    'pondy': 'https://images.unsplash.com/photo-1582510003544-4d00b7f74220?w=1200&auto=format&fit=crop&q=80',
    'pondicherry': 'https://images.unsplash.com/photo-1582510003544-4d00b7f74220?w=1200&auto=format&fit=crop&q=80', // White Town Promenade
    'puducherry': 'https://images.unsplash.com/photo-1582510003544-4d00b7f74220?w=1200&auto=format&fit=crop&q=80',
    'vr': 'https://images.unsplash.com/photo-1568605117036-5fe5e7bab0b7?w=1200&auto=format&fit=crop&q=80', // VR Mall / Chennai city skyline
    'vr mall': 'https://images.unsplash.com/photo-1568605117036-5fe5e7bab0b7?w=1200&auto=format&fit=crop&q=80',
    'chennai': 'https://images.unsplash.com/photo-1582510003544-4d00b7f74220?w=1200&auto=format&fit=crop&q=80', // Chennai Marina & architecture
    'avadi': 'https://images.unsplash.com/photo-1582510003544-4d00b7f74220?w=1200&auto=format&fit=crop&q=80',
    'goa': 'https://images.unsplash.com/photo-1512343879784-a960bf40e7f2?w=1200&auto=format&fit=crop&q=80', // Goa beach & palms
    'bengaluru': 'https://images.unsplash.com/photo-1596176530529-78163a4f7af2?w=1200&auto=format&fit=crop&q=80', // Bangalore Vidhana Soudha
    'bangalore': 'https://images.unsplash.com/photo-1596176530529-78163a4f7af2?w=1200&auto=format&fit=crop&q=80',
    'mumbai': 'https://images.unsplash.com/photo-1570168007204-dfb528c6958f?w=1200&auto=format&fit=crop&q=80', // Gateway of India / Marine Drive
    'delhi': 'https://images.unsplash.com/photo-1587474260584-136574528ed5?w=1200&auto=format&fit=crop&q=80', // India Gate
    'kerala': 'https://images.unsplash.com/photo-1602216056096-3b40cc0c9944?w=1200&auto=format&fit=crop&q=80', // Alleppey backwaters
    'ooty': 'https://images.unsplash.com/photo-1589182373726-e4f658ab50f0?w=1200&auto=format&fit=crop&q=80', // Nilgiri hills & tea estate
    'kodaikanal': 'https://images.unsplash.com/photo-1589182373726-e4f658ab50f0?w=1200&auto=format&fit=crop&q=80',
    'jaipur': 'https://images.unsplash.com/photo-1599661046289-e31897846e41?w=1200&auto=format&fit=crop&q=80', // Hawa Mahal
    'manali': 'https://images.unsplash.com/photo-1626621341517-bbf3d9990a23?w=1200&auto=format&fit=crop&q=80', // Himalayas snow peaks
    'marina': 'https://images.unsplash.com/photo-1582510003544-4d00b7f74220?w=1200&auto=format&fit=crop&q=80', // Marina Beach Chennai
    'marina beach': 'https://images.unsplash.com/photo-1582510003544-4d00b7f74220?w=1200&auto=format&fit=crop&q=80',
  };

  /// Normalizes colloquial destination names to get scenic tourism imagery from Google Places.
  static String normalizeLocationQuery(String destination) {
    final lower = destination.trim().toLowerCase();
    if (lower.contains('marina')) {
      return 'Marina Beach promenade lighthouse Triplicane Chennai Tamil Nadu India';
    }
    if (lower == 'pondi' || lower == 'pondy' || lower.contains('pondi') || lower.contains('puducherry')) {
      return 'Pondicherry Rock Beach promenade tourism Puducherry India';
    }
    if (lower == 'vr' || lower == 'vr mall') {
      return 'VR Mall Chennai Anna Nagar';
    }
    if (lower == 'avadi') {
      return 'Avadi Chennai Tamil Nadu';
    }
    return '$destination famous tourist landmark scenic travel destination';
  }

  /// Returns a fast, synchronous fallback photo URL matching the destination.
  static String getQuickDestinationPhoto(String destination, {String? tripType, String? coverPhotoUrl}) {
    if (coverPhotoUrl != null && coverPhotoUrl.trim().isNotEmpty) {
      return coverPhotoUrl.trim();
    }
    final key = destination.trim().toLowerCase();
    if (_memoryCache.containsKey(key)) {
      return _memoryCache[key]!;
    }
    for (final entry in _curatedFallbacks.entries) {
      if (key == entry.key || key.contains(entry.key) || entry.key.contains(key)) {
        return entry.value;
      }
    }
    // High-resolution road trip & adventure highway photography
    if (tripType != null && tripType.toLowerCase().contains('road')) {
      return 'https://images.unsplash.com/photo-1469854523086-cc02fe5d8800?w=1200&auto=format&fit=crop&q=80';
    }
    return 'https://images.unsplash.com/photo-1488646953014-85cb44e25828?w=1200&auto=format&fit=crop&q=80';
  }

  /// Searches Google Places API to resolve place details, address, coordinates, and authentic photo.
  static Future<DestinationPlaceInfo> searchPlace(String destination, {String? tripType}) async {
    final cleanDest = destination.trim();
    final defaultCoords = LocationService.getCityCoordinates(cleanDest);
    final fallbackCoordsLat = defaultCoords.isNotEmpty ? defaultCoords[0] : 13.0827;
    final fallbackCoordsLng = defaultCoords.length > 1 ? defaultCoords[1] : 80.2707;

    if (cleanDest.isEmpty) {
      return DestinationPlaceInfo(
        photoUrl: getQuickDestinationPhoto(cleanDest, tripType: tripType),
        placeName: 'Destination',
        latitude: fallbackCoordsLat,
        longitude: fallbackCoordsLng,
      );
    }

    try {
      final query = normalizeLocationQuery(cleanDest);
      final url = Uri.parse('https://places.googleapis.com/v1/places:searchText');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask': 'places.id,places.displayName,places.formattedAddress,places.location,places.photos',
        },
        body: jsonEncode({
          'textQuery': query,
          'maxResultCount': 1,
        }),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final places = data['places'] as List?;
        if (places != null && places.isNotEmpty) {
          final firstPlace = places.first as Map<String, dynamic>;
          final displayNameMap = firstPlace['displayName'] as Map<String, dynamic>?;
          final placeName = displayNameMap?['text'] as String? ?? cleanDest;
          final formattedAddress = firstPlace['formattedAddress'] as String?;
          final location = firstPlace['location'] as Map<String, dynamic>?;
          final lat = (location?['latitude'] as num?)?.toDouble() ?? fallbackCoordsLat;
          final lng = (location?['longitude'] as num?)?.toDouble() ?? fallbackCoordsLng;
          final placeId = firstPlace['id'] as String?;

          final photos = firstPlace['photos'] as List?;
          if (photos != null && photos.isNotEmpty) {
            final photoName = photos.first['name'] as String?;
            if (photoName != null && photoName.isNotEmpty) {
              final photoUrl =
                  'https://places.googleapis.com/v1/$photoName/media?maxHeightPx=1200&maxWidthPx=1200&key=$_apiKey';
              final key = cleanDest.toLowerCase();
              _memoryCache[key] = photoUrl;
              try {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('dest_photo_$key', photoUrl);
              } catch (_) {}
              return DestinationPlaceInfo(
                photoUrl: photoUrl,
                placeName: placeName,
                address: formattedAddress,
                latitude: lat,
                longitude: lng,
                placeId: placeId,
              );
            }
          }
          return DestinationPlaceInfo(
            photoUrl: getQuickDestinationPhoto(cleanDest, tripType: tripType),
            placeName: placeName,
            address: formattedAddress,
            latitude: lat,
            longitude: lng,
            placeId: placeId,
          );
        }
      }
    } catch (e) {
      developer.log('[DEST_SEARCH_PLACE_ERROR] $e', name: 'DestinationImageService');
    }

    final fallback = getQuickDestinationPhoto(cleanDest, tripType: tripType);
    return DestinationPlaceInfo(
      photoUrl: fallback,
      placeName: cleanDest,
      latitude: fallbackCoordsLat,
      longitude: fallbackCoordsLng,
    );
  }

  /// Returns Google Maps address autocomplete suggestions for a query.
  static Future<List<DestinationPlaceInfo>> searchPlaceSuggestions(String query, {int limit = 5}) async {
    final clean = query.trim();
    if (clean.length < 2) return [];

    try {
      final url = Uri.parse('https://places.googleapis.com/v1/places:searchText');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask': 'places.id,places.displayName,places.formattedAddress,places.location,places.photos',
        },
        body: jsonEncode({
          'textQuery': clean,
          'maxResultCount': limit,
        }),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final places = data['places'] as List?;
        if (places != null && places.isNotEmpty) {
          final results = <DestinationPlaceInfo>[];
          for (final p in places) {
            final place = p as Map<String, dynamic>;
            final displayNameMap = place['displayName'] as Map<String, dynamic>?;
            final placeName = displayNameMap?['text'] as String? ?? clean;
            final formattedAddress = place['formattedAddress'] as String?;
            final location = place['location'] as Map<String, dynamic>?;
            final lat = (location?['latitude'] as num?)?.toDouble();
            final lng = (location?['longitude'] as num?)?.toDouble();
            final placeId = place['id'] as String?;

            String photoUrl = getQuickDestinationPhoto(placeName);
            final photos = place['photos'] as List?;
            if (photos != null && photos.isNotEmpty) {
              final photoName = photos.first['name'] as String?;
              if (photoName != null && photoName.isNotEmpty) {
                photoUrl =
                    'https://places.googleapis.com/v1/$photoName/media?maxHeightPx=800&maxWidthPx=800&key=$_apiKey';
              }
            }

            results.add(DestinationPlaceInfo(
              photoUrl: photoUrl,
              placeName: placeName,
              address: formattedAddress,
              latitude: lat,
              longitude: lng,
              placeId: placeId,
            ));
          }
          return results;
        }
      }
    } catch (e) {
      developer.log('[SEARCH_SUGGESTIONS_ERROR] $e', name: 'DestinationImageService');
    }

    return [];
  }

  /// Asynchronously queries Google Places Text Search (New) for the authentic destination photo.
  static Future<String> getDestinationPhoto(
    String destination, {
    String? tripType,
    String? coverPhotoUrl,
  }) async {
    if (coverPhotoUrl != null && coverPhotoUrl.trim().isNotEmpty) {
      return coverPhotoUrl.trim();
    }
    final cleanDest = destination.trim();
    if (cleanDest.isEmpty) {
      return getQuickDestinationPhoto(cleanDest, tripType: tripType);
    }

    final cacheKey = cleanDest.toLowerCase();
    // Special guard: if colloquial pondi/pondy, always prefer the authentic beach photo
    if (cacheKey == 'pondi' || cacheKey == 'pondy') {
      const pondiUrl = 'https://images.unsplash.com/photo-1582510003544-4d00b7f74220?w=1200&auto=format&fit=crop&q=80';
      _memoryCache[cacheKey] = pondiUrl;
      return pondiUrl;
    }

    if (_memoryCache.containsKey(cacheKey)) {
      return _memoryCache[cacheKey]!;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('dest_photo_$cacheKey');
      if (cached != null && cached.isNotEmpty) {
        _memoryCache[cacheKey] = cached;
        return cached;
      }
    } catch (_) {}

    final placeInfo = await searchPlace(cleanDest, tripType: tripType);
    _memoryCache[cacheKey] = placeInfo.photoUrl;
    return placeInfo.photoUrl;
  }

  /// Retrieves multiple authentic high-resolution Google Places photos for a destination.
  static Future<List<String>> getDestinationPhotos(String destination, {int limit = 8}) async {
    final cleanDest = destination.trim();
    if (cleanDest.isEmpty) return [];

    try {
      final query = normalizeLocationQuery(cleanDest);
      final url = Uri.parse('https://places.googleapis.com/v1/places:searchText');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask': 'places.id,places.displayName,places.photos',
        },
        body: jsonEncode({
          'textQuery': query,
          'maxResultCount': 1,
        }),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final places = data['places'] as List?;
        if (places != null && places.isNotEmpty) {
          final firstPlace = places.first as Map<String, dynamic>;
          final photos = firstPlace['photos'] as List?;
          if (photos != null && photos.isNotEmpty) {
            final photoUrls = <String>[];
            for (final p in photos.take(limit)) {
              final photoName = p['name'] as String?;
              if (photoName != null && photoName.isNotEmpty) {
                photoUrls.add(
                  'https://places.googleapis.com/v1/$photoName/media?maxHeightPx=1200&maxWidthPx=1200&key=$_apiKey',
                );
              }
            }
            if (photoUrls.isNotEmpty) return photoUrls;
          }
        }
      }
    } catch (e) {
      developer.log('[GET_DEST_PHOTOS_ERROR] $e', name: 'DestinationImageService');
    }

    final lower = cleanDest.toLowerCase();
    if (lower.contains('marina')) {
      return [
        'https://images.unsplash.com/photo-1582510003544-4d00b7f74220?w=1200&auto=format&fit=crop&q=80',
        'https://images.unsplash.com/photo-1568605117036-5fe5e7bab0b7?w=1200&auto=format&fit=crop&q=80',
        'https://images.unsplash.com/photo-1588416936097-41850ab3d86d?w=1200&auto=format&fit=crop&q=80',
      ];
    }

    final single = getQuickDestinationPhoto(cleanDest);
    return [single];
  }
}

