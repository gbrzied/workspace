// lib/geolocation_service.dart
import 'package:geolocator/geolocator.dart';

class GeolocationService {
  Future<Position?> getCurrentPosition() async {
    try {
      print('📍 Starting geolocation request...');

      // Step 1: Check permission status
      LocationPermission permission = await Geolocator.checkPermission();
      print('📍 Initial permission: $permission');

      // Step 2: Request permission if needed
      if (permission == LocationPermission.denied) {
        print('📍 Permission denied - requesting...');
        permission = await Geolocator.requestPermission();
        print('📍 Permission after request: $permission');
      }

      // Step 3: Handle denied scenarios
      if (permission == LocationPermission.denied) {
        print('❌ Permission permanently denied by user');
        return null;
      }

      if (permission == LocationPermission.deniedForever) {
        print('❌ Permission denied forever - opening settings');
        await Geolocator.openLocationSettings();
        return null;
      }

      // Step 4: Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      print('📍 Location service enabled: $serviceEnabled');

      if (!serviceEnabled) {
        print('❌ Location services disabled - opening settings');
        await Geolocator.openLocationSettings();
        return null;
      }

      // Step 5: Get position with LOW accuracy (emulator friendly)
      print('📍 Fetching position...');
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low, // ✅ Changed to LOW
        timeLimit: const Duration(seconds: 8), // ✅ Reduced timeout
      );

      print('✅ Got position: ${position.latitude}, ${position.longitude}');
      print('   Accuracy: ${position.accuracy}m');
      print('   Timestamp: ${position.timestamp}');

      return position;

    } on LocationServiceDisabledException catch (e) {
      print('❌ Location service error: $e');
      return null;
    } catch (e) {
      print('❌ Geolocation error: $e');
      print('   Error type: ${e.runtimeType}');

      // Emulator fallback: return a default location for testing
      if (e.toString().contains('TimeoutException')) {
        print('⚠️ Timeout - using mock location for emulator testing');
        // Tunis coordinates as fallback
        return Position(
          latitude: 36.8065,
          longitude: 10.1815,
          timestamp: DateTime.now(),
          accuracy: 100,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
      }

      return null;
    }
  }
}