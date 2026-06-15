import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../database/database_service.dart';
import '../constants/hazard_type.dart';

// IMPORTANT: Import your actual files here
// import '../../database/database_service.dart';
// import '../models/hazard.dart';

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
      double distance = Geolocator.distanceBetween(
        position.latitude, position.longitude,
        hazard.latitude, hazard.longitude,
      );
      double bearing = Geolocator.bearingBetween(
        position.latitude, position.longitude,
        hazard.latitude, hazard.longitude,
      );

      if (isHazardInFront(position.heading, bearing)) {
        if (distance < minDistance) {
          minDistance = distance;
          closest = hazard;
        }
      }
    }

    // C. Trigger Logic
    double speedMps = position.speed > 0 ? position.speed : 0.0;
    double alertDistance = (speedMps * 6.0).clamp(50.0, 200.0);
    bool isDanger = closest != null && minDistance <= alertDistance;

    if (isDanger && closest != null) {
      if (lastAlertedHazardId != closest.id) {
        await flutterTts.speak("Caution, ${closest.name} ahead");
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
      'hazardName': closest?.name,
      'distance': minDistance == double.infinity ? null : minDistance,
      'isDanger': isDanger,
    });
  });
}