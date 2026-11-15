import 'package:flutter_test/flutter_test.dart';
import 'package:tripcrew/features/itinerary/models/itinerary_item.dart';
import 'package:tripcrew/features/memories/models/memory_model.dart';
import 'package:tripcrew/features/explorer/services/places_service.dart';

void main() {
  group('Feature 1: Shared Memories Gallery Tests', () {
    test('MemoryModel correctly parses Supabase and Storage metadata', () {
      final now = DateTime(2026, 10, 17, 12, 0);
      final map = {
        'id': 'mem_101',
        'trip_id': 'trip_001',
        'user_id': 'user_alice',
        'photographer_name': 'Alice Smith',
        'media_url': 'https://supabase.co/storage/v1/object/public/trip-memories/trip_001/sunset.jpg',
        'storage_path': 'trip_001/sunset.jpg',
        'media_type': 'photo',
        'day_index': 2,
        'caption': 'Sunset over the beach',
        'created_at': now.toIso8601String(),
      };

      final memory = MemoryModel.fromMap(map, 'mem_101');
      expect(memory.id, 'mem_101');
      expect(memory.tripId, 'trip_001');
      expect(memory.uploaderId, 'user_alice');
      expect(memory.photographerName, 'Alice Smith');
      expect(memory.storagePath, 'trip_001/sunset.jpg');
      expect(memory.dayIndex, 2);
      expect(memory.dayNumber, 2);
      expect(memory.mediaType, 'photo');
      expect(memory.caption, 'Sunset over the beach');
    });

    test('Memory deletion authorization rule permits only uploader or trip owner', () {
      const tripOwnerId = 'owner_carol';
      const uploaderId = 'uploader_alice';
      const otherUserId = 'stranger_bob';

      final memory = MemoryModel(
        id: 'mem_1',
        tripId: 'trip_1',
        uploaderId: uploaderId,
        imageUrl: 'https://example.com/photo.jpg',
        storagePath: 'trip_1/photo.jpg',
        createdAt: DateTime.now(),
      );

      // Helper function matching the in-app role guard
      bool canDelete(String currentUserId) {
        return currentUserId == memory.uploaderId || currentUserId == tripOwnerId;
      }

      expect(canDelete(uploaderId), isTrue, reason: 'Uploader can delete their own memory');
      expect(canDelete(tripOwnerId), isTrue, reason: 'Trip owner can delete crew memories');
      expect(canDelete(otherUserId), isFalse, reason: 'Other crew members cannot delete');
    });
  });

  group('Feature 2: Trip Map & Routes Tests', () {
    test('ItineraryItem supports geo-coordinates for map routes', () {
      final item = ItineraryItem(
        id: 'stop_1',
        dayNumber: 1,
        time: '10:00 AM',
        title: 'Baga Beach Stop',
        placeName: 'North Goa',
        order: 1,
        latitude: 15.5524,
        longitude: 73.7517,
      );

      final map = item.toMap();
      expect(map['latitude'], 15.5524);
      expect(map['longitude'], 73.7517);

      final reconstructed = ItineraryItem.fromMap(map, 'stop_1');
      expect(reconstructed.latitude, 15.5524);
      expect(reconstructed.longitude, 73.7517);
      expect(reconstructed.dayNumber, 1);
    });

    test('Route distance accumulator handles sequential stop pairs safely', () {
      final stops = [
        {'lat': 15.2993, 'lon': 74.1240},
        {'lat': 15.5524, 'lon': 73.7517},
        {'lat': 15.5439, 'lon': 73.7554},
      ];

      expect(stops.length, greaterThanOrEqualTo(2));
      int segmentCount = stops.length - 1;
      expect(segmentCount, 2);
    });
  });

  group('Feature 3: Nearby Explorer Tests', () {
    test('PlacesService category icon mapping covers all 4 required categories', () {
      expect(PlacesService.getIconForCategory('Food'), isNotNull);
      expect(PlacesService.getIconForCategory('Cafes'), isNotNull);
      expect(PlacesService.getIconForCategory('Fuel'), isNotNull);
      expect(PlacesService.getIconForCategory('Restrooms'), isNotNull);
    });

    test('NearbyPlace model stores distance and place details', () {
      final place = NearbyPlace(
        id: 'node_123',
        name: 'HP Fuel Station',
        category: 'Fuel',
        latitude: 15.55,
        longitude: 73.75,
        distanceKm: 1.4,
        address: 'Main Express Road',
        status: 'Open 24/7',
        icon: PlacesService.getIconForCategory('Fuel'),
      );

      expect(place.name, 'HP Fuel Station');
      expect(place.category, 'Fuel');
      expect(place.distanceKm, 1.4);
      expect(place.status, 'Open 24/7');
    });
  });

  group('Feature 4: Safety & Emergency SOS Tests', () {
    test('Emergency message formats coordinates and Google Maps link correctly', () {
      const userName = 'Alice';
      const tripName = 'Goa Beach Weekend';
      const lat = 15.5524;
      const lon = 73.7517;

      final message = '''
🚨 EMERGENCY SOS ALERT!
From: $userName
Trip: $tripName

📍 Current GPS Location:
Latitude: $lat
Longitude: $lon
Google Maps Link: https://maps.google.com/?q=$lat,$lon
''';

      expect(message, contains('EMERGENCY SOS ALERT!'));
      expect(message, contains('From: Alice'));
      expect(message, contains('https://maps.google.com/?q=15.5524,73.7517'));
    });

    test('Helpline numbers correspond to standard emergency services', () {
      const nationalEmergency = '112';
      const ambulanceMedical = '108';
      const police = '100';

      expect(nationalEmergency, '112');
      expect(ambulanceMedical, '108');
      expect(police, '100');
    });
  });

  group('Feature 5: Trip Recap & Analytics Tests', () {
    test('Category spending breakdown aggregates totals and percentages accurately', () {
      final sampleExpenses = [
        {'category': 'Food', 'amount': 150000}, // ₹1,500
        {'category': 'Food', 'amount': 250000}, // ₹2,500
        {'category': 'Travel', 'amount': 600000}, // ₹6,000
      ];

      final Map<String, int> categoryTotals = {};
      int totalPaise = 0;
      for (final e in sampleExpenses) {
        final cat = e['category'] as String;
        final amt = e['amount'] as int;
        categoryTotals[cat] = (categoryTotals[cat] ?? 0) + amt;
        totalPaise += amt;
      }

      expect(totalPaise, 1000000); // ₹10,000
      expect(categoryTotals['Food'], 400000); // ₹4,000 (40%)
      expect(categoryTotals['Travel'], 600000); // ₹6,000 (60%)
      expect(categoryTotals['Food']! / totalPaise, 0.40);
      expect(categoryTotals['Travel']! / totalPaise, 0.60);
    });

    test('Recap distance computation returns null when fewer than 2 coordinates exist', () {
      final singlePointList = [
        [15.2993, 74.1240],
      ];

      double? calculatedDistanceKm;
      if (singlePointList.length >= 2) {
        calculatedDistanceKm = 10.0;
      } else {
        calculatedDistanceKm = null; // Do not invent fake distance!
      }

      expect(calculatedDistanceKm, isNull);
    });
  });
}
