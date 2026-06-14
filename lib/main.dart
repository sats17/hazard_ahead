import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';
import 'dart:io';

// IMPORTANT: Ensure these paths match your actual project structure
import 'core/constants/hazard_type.dart';
import 'core/services/hazard_service.dart';
import 'database/database_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: SpeedBreakerApp()));
}

class SpeedBreakerApp extends StatelessWidget {
  const SpeedBreakerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SpeedBreaker Alert',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  // --- Services & Database State ---
  late Future<int> _hazardCount;
  late HazardService hazardService;

  // --- Location & Alert State ---
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  String _locationStatus = 'Checking permissions...';

  Hazard? _nearestHazard;
  double? _distanceToNearest;
  bool _isDangerZone = false;

  // --- Voice Engine State ---
  final FlutterTts _flutterTts = FlutterTts();
  bool _isTtsInitialized = false;
  int? _lastAlertedHazardId; // Memory cache to prevent repeating alerts

  @override
  void initState() {
    super.initState();
    final dbService = ref.read(databaseServiceProvider);
    _hazardCount = dbService.getHazardCount();
    hazardService = ref.read(hazardServiceProvider);

    _initTts();
    _startLocationTracking();
  }

  // --- 1. TTS INITIALIZATION ---
  Future<void> _initTts() async {
    await _flutterTts.setLanguage("en-IN");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    await _flutterTts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playback,
      [IosTextToSpeechAudioCategoryOptions.mixWithOthers],
    );

    setState(() {
      _isTtsInitialized = true;
    });
  }

  // --- 2. VOICE ALERT TRIGGER ---
  Future<void> _triggerHardwareAlert(String hazardName) async {
    if (_isTtsInitialized) {
      await _flutterTts.speak("Caution, $hazardName ahead");
    }
  }

  // --- 3. MATH HELPER: BEARING/DIRECTION ---
  bool _isHazardInFront(double userHeading, double bearingToHazard, {double toleranceDegrees = 45.0}) {
    if (userHeading < 0) return true; // Safe fallback if moving too slow

    double diff = (bearingToHazard - userHeading).abs();

    // Handle compass wrap-around (e.g., heading 350, bearing 10)
    if (diff > 180.0) {
      diff = 360.0 - diff;
    }

    return diff <= toleranceDegrees;
  }

  // --- 4. MASTER GPS STREAM ---
  Future<void> _startLocationTracking() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Check Permissions
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _locationStatus = 'Location services disabled.');
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _locationStatus = 'Location permissions denied.');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => _locationStatus = 'Permissions permanently denied.');
      return;
    }

    setState(() => _locationStatus = 'Tracking active');

    // Start Streaming (Updates every 5 meters)
    LocationSettings locationSettings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position? position) async {
      if (position == null) return;

      final dbService = ref.read(databaseServiceProvider);

      // A. Get Bounding Box Hazards (~500m area)
      final nearbyHazards = await dbService.getNearbyHazards(
        position.latitude,
        position.longitude,
      );

      Hazard? closest;
      double minDistance = double.infinity;
      double currentHeading = position.heading;

      // B. Filter by Direction & Calculate Exact Distance
      for (var hazard in nearbyHazards) {
        double distanceInMeters = Geolocator.distanceBetween(
          position.latitude, position.longitude,
          hazard.latitude, hazard.longitude,
        );

        double bearingToHazard = Geolocator.bearingBetween(
          position.latitude, position.longitude,
          hazard.latitude, hazard.longitude,
        );

        if (_isHazardInFront(currentHeading, bearingToHazard)) {
          if (distanceInMeters < minDistance) {
            minDistance = distanceInMeters;
            closest = hazard;
          }
        }
      }

      // C. Calculate Dynamic Speed Threshold
      double currentSpeedMps = position.speed > 0 ? position.speed : 0.0;
      // 6-second warning, clamped safely between 50m and 200m
      double dynamicAlertDistance = (currentSpeedMps * 6.0).clamp(50.0, 200.0);

      bool isApproachingFast = closest != null && minDistance <= dynamicAlertDistance;

      // D. Smart Voice Trigger
      if (isApproachingFast && closest != null) {
        if (_lastAlertedHazardId != closest.id) {
          _triggerHardwareAlert(closest.name);
          _lastAlertedHazardId = closest.id;   // Cache the ID to prevent spam
        }
      }

      // Clear memory cache if we drive far enough away
      if (closest == null || minDistance > 300) {
        _lastAlertedHazardId = null;
      }

      // E. Update State / UI
      setState(() {
        _currentPosition = position;
        _nearestHazard = closest;
        _distanceToNearest = closest != null ? minDistance : null;
        _isDangerZone = isApproachingFast;
      });
    });
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('SpeedBreaker Alert'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // --- WIDGET 1: Database Count ---
                FutureBuilder<int>(
                  future: _hazardCount,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const CircularProgressIndicator();
                    } else if (snapshot.hasError) {
                      return Text('Error connecting to DB: ${snapshot.error}');
                    } else {
                      return Column(
                        children: [
                          const Icon(Icons.storage, size: 64, color: Colors.grey),
                          const SizedBox(height: 8),
                          Text(
                            'Hazards in Database:',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            '${snapshot.data}',
                            style: Theme.of(context).textTheme.displayLarge?.copyWith(
                              color: Colors.deepOrange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      );
                    }
                  },
                ),

                const SizedBox(height: 20),

                // --- WIDGET 2: Live GPS Data ---
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Icon(Icons.gps_fixed, size: 32, color: Colors.blue),
                        const SizedBox(height: 8),
                        Text(_locationStatus, style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(
                          _currentPosition != null
                              ? 'Lat: ${_currentPosition!.latitude.toStringAsFixed(5)}\nLon: ${_currentPosition!.longitude.toStringAsFixed(5)}\nSpeed: ${(_currentPosition!.speed * 3.6).toStringAsFixed(1)} km/h'
                              : 'Waiting for GPS signal...',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // --- WIDGET 3: Smart Visual Alert ---
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  color: _isDangerZone ? Colors.red.shade100 : Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Icon(
                            _isDangerZone ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                            size: 48,
                            color: _isDangerZone ? Colors.red : Colors.green
                        ),
                        const SizedBox(height: 8),
                        Text(
                            _isDangerZone ? 'HAZARD APPROACHING!' : 'Path Clear',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: _isDangerZone ? Colors.red.shade900 : Colors.green.shade900
                            )
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _nearestHazard != null && _distanceToNearest != null
                              ? '${_nearestHazard!.name}\nDistance: ${_distanceToNearest!.toStringAsFixed(0)}m'
                              : 'No hazards in path',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // --- WIDGET 4: Action Buttons ---
        floatingActionButton: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FloatingActionButton.extended(
                heroTag: "btn_test",
                icon: const Icon(Icons.volume_up),
                label: const Text('Test Voice'),
                backgroundColor: Colors.red.shade100,
                onPressed: () => _triggerHardwareAlert("Speed Breaker"),
              ),

              const SizedBox(height: 16),

              FloatingActionButton.extended(
                heroTag: "btn_csv",
                icon: const Icon(Icons.upload_file),
                label: const Text('Import CSV'),
                onPressed: () async {
                  FilePickerResult? result = await FilePicker.platform.pickFiles(
                    type: FileType.any,
                  );

                  if (result != null && result.files.single.path != null) {
                    File file = File(result.files.single.path!);
                    final csvString = await file.readAsString();

                    List<List<dynamic>> csvTable = const CsvToListConverter(
                      eol: '\n',
                      shouldParseNumbers: true,
                    ).convert(csvString);

                    await hazardService.processCsvData(csvTable);

                    setState(() {
                      final dbService = ref.read(databaseServiceProvider);
                      _hazardCount = dbService.getHazardCount();
                    });
                  }
                },
              )
            ]
        )
    );
  }
}