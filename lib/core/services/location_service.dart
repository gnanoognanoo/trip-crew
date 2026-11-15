import 'dart:convert';
import 'dart:developer' as developer;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class LocationData {
  final double latitude;
  final double longitude;
  final String city;
  final String country;

  const LocationData({ 
    required this.latitude,
    required this.longitude,
    required this.city,
    required this.country,
  });

  LocationData copyWith({
    double? latitude,
    double? longitude,
    String? city,
    String? country,
  }) {
    return LocationData(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      city: city ?? this.city,
      country: country ?? this.country,
    );
  }
}

class LocationService {
  static LocationData? _cachedLocation;
  static LocationData? get cachedLocation => _cachedLocation;

  static const Map<String, List<double>> _knownCities = {
    'chennai': [13.0827, 80.2707],
    'marina': [13.0500, 80.2824],
    'marina beach': [13.0500, 80.2824],
    'avadi': [13.1147, 80.1008],
    'bengaluru': [12.9716, 77.5946],
    'bangalore': [12.9716, 77.5946],
    'mumbai': [19.0760, 72.8777],
    'delhi': [28.6139, 77.2090],
    'goa': [15.2993, 74.1240],
    'hyderabad': [17.3850, 78.4867],
    'kolkata': [22.5726, 88.3639],
    'pune': [18.5204, 73.8567],
    'jaipur': [26.9124, 75.7873],
    'kochi': [9.9312, 76.2673],
    'coimbatore': [11.0168, 76.9558],
    'pondy': [11.9416, 79.8083],
    'pondicherry': [11.9416, 79.8083],
    'manali': [32.2432, 77.1892],
    'rome': [41.9028, 12.4964],
    'paris': [48.8566, 2.3522],
    'tokyo': [35.6762, 139.6503],
    'bali': [-8.3405, 115.0920],
  };

  /// Quickly retrieves the fastest available location without blocking for GPS lock.
  /// 1. Checks memory cache.
  /// 2. Checks OS last known position (<15ms).
  static Future<LocationData?> getFastLocation() async {
    if (_cachedLocation != null) return _cachedLocation;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null) {
        final geo = await reverseGeocode(lastPos.latitude, lastPos.longitude);
        _cachedLocation = LocationData(
          latitude: lastPos.latitude,
          longitude: lastPos.longitude,
          city: geo['city'] ?? 'Local Area',
          country: geo['country'] ?? 'India',
        );
        return _cachedLocation;
      }
    } catch (e) {
      developer.log('Fast location error: $e', name: 'LocationService');
    }
    return null;
  }

  /// Obtains the fresh, highly accurate device position.
  static Future<LocationData?> getFreshLocation({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return _cachedLocation;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return _cachedLocation;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: timeout,
        ),
      );

      final geo = await reverseGeocode(pos.latitude, pos.longitude);
      _cachedLocation = LocationData(
        latitude: pos.latitude,
        longitude: pos.longitude,
        city: geo['city'] ?? 'Local Area',
        country: geo['country'] ?? 'India',
      );
      return _cachedLocation;
    } catch (e) {
      developer.log('Fresh location error: $e', name: 'LocationService');
      return _cachedLocation;
    }
  }

  /// Reverse geocodes latitude/longitude to city and country names.
  static Future<Map<String, String>> reverseGeocode(
    double lat,
    double lon,
  ) async {
    if (_cachedLocation != null) {
      final dist = Geolocator.distanceBetween(
        lat,
        lon,
        _cachedLocation!.latitude,
        _cachedLocation!.longitude,
      );
      if (dist < 2000) {
        return {
          'city': _cachedLocation!.city,
          'country': _cachedLocation!.country,
        };
      }
    }

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon&zoom=14&addressdetails=1',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'TripCrew-TravelApp/1.0 (contact@tripcrew.app)'},
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final address = json['address'] as Map<String, dynamic>? ?? {};

        final city = address['city'] as String? ??
            address['town'] as String? ??
            address['suburb'] as String? ??
            address['municipality'] as String? ??
            address['village'] as String? ??
            address['county'] as String? ??
            address['state_district'] as String?;
        final country = address['country'] as String? ?? 'India';

        if (city != null && city.isNotEmpty) {
          return {
            'city': city,
            'country': country,
          };
        }
      }
    } catch (e) {
      developer.log('Nominatim reverse geocode error: $e', name: 'LocationService');
    }

    return _matchNearestCity(lat, lon);
  }

  static Map<String, String> _matchNearestCity(double lat, double lon) {
    final cities = [
      {'city': 'Avadi', 'country': 'India', 'lat': 13.1147, 'lon': 80.1008},
      {'city': 'Chennai', 'country': 'India', 'lat': 13.0827, 'lon': 80.2707},
      {'city': 'Bengaluru', 'country': 'India', 'lat': 12.9716, 'lon': 77.5946},
      {'city': 'Mumbai', 'country': 'India', 'lat': 19.0760, 'lon': 72.8777},
      {'city': 'Delhi', 'country': 'India', 'lat': 28.6139, 'lon': 77.2090},
      {'city': 'Hyderabad', 'country': 'India', 'lat': 17.3850, 'lon': 78.4867},
      {'city': 'Goa', 'country': 'India', 'lat': 15.2993, 'lon': 74.1240},
      {'city': 'Kolkata', 'country': 'India', 'lat': 22.5726, 'lon': 88.3639},
      {'city': 'Pune', 'country': 'India', 'lat': 18.5204, 'lon': 73.8567},
      {'city': 'Jaipur', 'country': 'India', 'lat': 26.9124, 'lon': 75.7873},
      {'city': 'Kochi', 'country': 'India', 'lat': 9.9312, 'lon': 76.2673},
      {'city': 'Coimbatore', 'country': 'India', 'lat': 11.0168, 'lon': 76.9558},
      {'city': 'Rome', 'country': 'Italy', 'lat': 41.9028, 'lon': 12.4964},
      {'city': 'Paris', 'country': 'France', 'lat': 48.8566, 'lon': 2.3522},
      {'city': 'London', 'country': 'UK', 'lat': 51.5074, 'lon': -0.1278},
      {'city': 'Tokyo', 'country': 'Japan', 'lat': 35.6762, 'lon': 139.6503},
      {'city': 'Bali', 'country': 'Indonesia', 'lat': -8.3405, 'lon': 115.0920},
      {'city': 'New York', 'country': 'USA', 'lat': 40.7128, 'lon': -74.0060},
    ];

    double minDistance = double.infinity;
    Map<String, dynamic> closest = cities.first;

    for (final c in cities) {
      final d = Geolocator.distanceBetween(
        lat,
        lon,
        c['lat'] as double,
        c['lon'] as double,
      );
      if (d < minDistance) {
        minDistance = d;
        closest = c;
      }
    }

    if (minDistance < 250000) {
      return {
        'city': closest['city'] as String,
        'country': closest['country'] as String,
      };
    }

    final isIndia = lat > 8 && lat < 37 && lon > 68 && lon < 97;
    return {
      'city': isIndia ? 'Local Area' : 'Local Area',
      'country': isIndia ? 'India' : 'World',
    };
  }

  static List<double> getCityCoordinates(String dest) {
    final clean = dest.toLowerCase().trim();
    for (final entry in _knownCities.entries) {
      if (clean.contains(entry.key)) {
        return entry.value;
      }
    }
    return [13.0827, 80.2707]; // Default Chennai/Tamil Nadu center if unmapped
  }
}
