import 'package:flutter_test/flutter_test.dart';
import 'package:tripcrew/features/trips/services/trip_share_service.dart';

void main() {
  group('TripShareService Tests', () {
    test('formatInviteMessage formats full trip details with dates, destination, and join link', () {
      final msg = TripShareService.formatInviteMessage(
        tripName: 'Goa Sun & Sand',
        inviteCode: 'TC-GOA-7788',
        startingPlace: 'Bangalore',
        destination: 'Goa',
        startDate: DateTime(2026, 11, 10),
        endDate: DateTime(2026, 11, 15),
      );

      expect(msg, contains('Goa Sun & Sand'));
      expect(msg, contains('Bangalore → Goa'));
      expect(msg, contains('10 Nov 2026 – 15 Nov 2026'));
      expect(msg, contains('TC-GOA-7788'));
      expect(msg, contains('https://tripcrew.app/join/TC-GOA-7788'));
    });

    test('formatInviteMessage gracefully formats when dates or starting place are omitted', () {
      final msg = TripShareService.formatInviteMessage(
        tripName: 'Manali Snow Trek',
        inviteCode: 'TC-MAN-1122',
        destination: 'Manali',
      );

      expect(msg, contains('Manali Snow Trek'));
      expect(msg, contains('📍 Destination: Manali'));
      expect(msg, contains('TC-MAN-1122'));
      expect(msg, contains('https://tripcrew.app/join/TC-MAN-1122'));
      expect(msg.contains('🗓 Dates:'), isFalse);
    });

    test('formatInviteMessage produces clean deep link without trailing spaces', () {
      final msg = TripShareService.formatInviteMessage(
        tripName: 'VR Trip',
        inviteCode: 'TC-THQ3-VSYY',
      );

      expect(msg, contains('https://tripcrew.app/join/TC-THQ3-VSYY'));
      expect(msg.endsWith('https://tripcrew.app/join/TC-THQ3-VSYY'), isTrue);
    });
  });
}
