import 'package:flutter_test/flutter_test.dart';
import 'package:waiting_room_app_5/location_utils.dart';

void main() {
  group('calculateDistance', () {
    test('returns 0 for identical coordinates', () {
      final distance = calculateDistance(36.8, 10.2, 36.8, 10.2);
      expect(distance, 0);
    });

    test('returns a small non-zero value for small coordinate difference', () {
      final distance = calculateDistance(36.8, 10.2, 36.801, 10.201);
      expect(distance, greaterThan(0));
      expect(distance, lessThan(0.2)); // around 100–150 meters
    });

    test('returns approximately correct distance between known cities', () {
      // Tunis (36.8065, 10.1815) to Sousse (35.8256, 10.63699)
      final distance = calculateDistance(36.8065, 10.1815, 35.8256, 10.63699);
      // Actual distance ≈ 115 km, allow ±10 km tolerance
      expect(distance, closeTo(115, 10));
    });
  });
}
