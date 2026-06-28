import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../database/database_service.dart';
import '../constants/hazard_type.dart';

// --- 1. INITIALIZE THE SERVICE ---
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  // Setup Notification Channel for Android
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'speedbreaker_alert_channel',
    'SpeedBreaker Alerts',
    description: 'Running in background to alert for hazards.',
    importance: Importance.low, // Low importance so it doesn't beep constantly
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // Create channel on the device
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false, // We will start it manually with a button
      isForegroundMode: true,
      notificationChannelId: 'speedbreaker_alert_channel',
      initialNotificationTitle: 'SpeedBreaker Alert Active',
      initialNotificationContent: 'Scanning for hazards in background...',
      foregroundServiceNotificationId: 888,
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// --- 2. THE HEADLESS LOGIC (Runs Invisibly) ---
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Ensure Flutter engine is running
  DartPluginRegistrant.ensureInitialized();

  // 1. Setup TTS in background
  final FlutterTts flutterTts = FlutterTts();
  await flutterTts.setLanguage("en-IN");
  await flutterTts.setSpeechRate(0.5);
  await flutterTts.setVolume(1.0);

  // 2. Setup Database connection directly (Riverpod is hard to use in background isolates)
  final dbService = DatabaseService();
  int? lastAlertedHazardId;

  // 3. Listen for "Stop" command from the UI
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // 4. Math Helper Function
  bool isHazardInFront(double userHeading, double bearingToHazard) {
    if (userHeading < 0) return true;
    double diff = (bearingToHazard - userHeading).abs();
    if (diff > 180.0) diff = 360.0 - diff;
    return diff <= 45.0; // 45 degree tolerance
  }

  bool isHazardWithCorrectHeading(double userHeading, double? hazardHeading) {
    if (hazardHeading == null) return true; // If hazard has no heading, assume it's valid
    double diff = (hazardHeading - userHeading).abs();
    // Handle the compass wrap-around (e.g., 359 to 6)
    if (diff > 180.0) {
      diff = 360.0 - diff;
    }
    return diff <= 15.0; // 15 degree tolerance
  }

  // 5. Start GPS Stream
  Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // Reverted to standard settings for Fused pipeline support (WiFi + GPS + Mock)
    ),
  ).listen((Position? position) async {
    if (position == null) return;

    // A. Query DB
    final nearbyHazards = await dbService.getNearbyHazards(position.latitude, position.longitude);

    Hazard? closest;
    double minDistance = double.infinity;

    // B. Calculate Distance & Direction
    for (var hazard in nearbyHazards) {
      print("Hazard: ${hazard.name}, Lat: ${hazard.latitude}, Lon: ${hazard.longitude}, Heading: ${hazard.heading}");
      double distance = Geolocator.distanceBetween(
        position.latitude, position.longitude,
        hazard.latitude, hazard.longitude,
      );
      double bearing = Geolocator.bearingBetween(
        position.latitude, position.longitude,
        hazard.latitude, hazard.longitude,
      );

      if (isHazardInFront(position.heading, bearing) && isHazardWithCorrectHeading(position.heading, hazard.heading)) {
        if (distance < minDistance) {
          print(position.heading);
          minDistance = distance;
          closest = hazard;
        }
      }
    }

    // C. Trigger Logic
    double speedMps = position.speed > 0 ? position.speed : 0.0;
    double speedKmh = speedMps * 3.6;
    double alertDistance;

    // If driving 40 km/h or faster, look 500 meters ahead
    if (speedKmh >= 60.0) {
      alertDistance = 500.0;
    }
    // If driving under 40 km/h, use the standard 12-second window (clamped to 100m min)
    else {
      alertDistance = (speedMps * 12.0).clamp(100.0, 500.0);
    }
    bool isDanger = closest != null && minDistance <= alertDistance;

    if (isDanger && closest != null) {

      if (lastAlertedHazardId != closest.id) {
        await flutterTts.speak("Caution, ${closest.name} ahead, ${minDistance.toStringAsFixed(0)} meters away.");
        lastAlertedHazardId = closest.id;
      }
    }

    if (closest == null || minDistance > 300) {
      lastAlertedHazardId = null;
    }

    // D. Send Live Data Back to UI (So the screen still updates if the app is open!)
    service.invoke('updateUI', {
      'lat': position.latitude,
      'lon': position.longitude,
      'speed': position.speed,
      'heading': position.heading,
      'hazardName': closest?.name,
      'distance': minDistance == double.infinity ? null : minDistance,
      'isDanger': isDanger,
    });
  });
}