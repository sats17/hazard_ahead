import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:csv/csv.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:io';

// IMPORTANT: Ensure these paths match your actual project structure
import 'core/services/hazard_service.dart';
import 'database/database_service.dart';
import 'core/services/background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the background service before the UI boots up
  await initializeBackgroundService();

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
  // --- Services State ---
  late Future<int> _hazardCount;
  late HazardService hazardService;

  // --- UI State ---
  double? _currentLat;
  double? _currentLon;
  double _currentSpeed = 0.0;
  double? _currentHeading;
  String? _nearestHazardName;
  double? _distanceToNearest;
  bool _isDangerZone = false;

  bool _isServiceRunning = false;
  String _locationStatus = 'Checking permissions...';

  // UI-Level GPS Stream
  StreamSubscription<Position>? _livePositionStream;

  @override
  void initState() {
    super.initState();
    final dbService = ref.read(databaseServiceProvider);
    _hazardCount = dbService.getHazardCount();
    hazardService = ref.read(hazardServiceProvider);

    _checkPermissions();
    _listenToBackgroundService();
    _checkServiceStatus();

    // Auto-sync from GitHub every time the app opens
    _syncDatabaseFromCloud();
  }

  @override
  void dispose() {
    _livePositionStream?.cancel();
    super.dispose();
  }

  // --- CLOUD SYNC DATABASE ---
// Replace the existing _syncDatabaseFromCloud method with this version:
  Future<void> _syncDatabaseFromCloud() async {
    const List<String> cloudCsvUrls = [
      'https://gist.githubusercontent.com/sats17/7d55b4913b91bf0ccd75c3ddf72ee017/raw/4cf78179cce2371d82f89cd33cecf9549a43c0cd/other_hazards.csv',
      'https://gist.githubusercontent.com/sats17/7d55b4913b91bf0ccd75c3ddf72ee017/raw/436a7c6a9afba8c5371c153a543b830385675f9f/villages.csv'
    ];

    if (cloudCsvUrls.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No cloud CSV URLs configured.')),
        );
      }
      return;
    }

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Syncing hazards from cloud...')),
        );
      }

      int successCount = 0;
      final List<String> failedUrls = [];

      for (final url in cloudCsvUrls) {
        try {
          final response = await http.get(Uri.parse(url));

          if (response.statusCode == 200) {
            // Normalize line endings and strip BOM if present
            String csvString = response.body.replaceAll('\r\n', '\n').replaceFirst('\uFEFF', '');

            List<List<dynamic>> csvTable = const CsvToListConverter(
              eol: '\n',
              shouldParseNumbers: true,
            ).convert(csvString);

            // Keep business logic same: processCsvData handles validation & insert.
            await hazardService.processCsvData(csvTable);

            successCount++;
          } else {
            failedUrls.add('$url (status ${response.statusCode})');
          }
        } catch (e) {
          // Log and continue with next URL
          debugPrint('Cloud sync error for $url: $e');
          failedUrls.add('$url (error: $e)');
        }
      }

      // Update local hazard count after processing all CSVs
      if (mounted) {
        setState(() {
          final dbService = ref.read(databaseServiceProvider);
          _hazardCount = dbService.getHazardCount();
        });
      }

      // Show a concise summary SnackBar
      if (mounted) {
        final summary = StringBuffer();
        summary.writeln('Cloud Sync finished: $successCount succeeded.');
        if (failedUrls.isNotEmpty) {
          summary.writeln('${failedUrls.length} failed.');
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(summary.toString()),
            backgroundColor: failedUrls.isEmpty ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('Overall cloud sync error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // --- 1. INITIAL PERMISSIONS & DIAGNOSTIC POSITION SEEDING ---
  Future<void> _checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _locationStatus = 'Location services disabled.');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
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

    setState(() => _locationStatus = 'Connecting to location framework...');

    try {
      // Switched to standard LocationSettings to leverage the Fused Provider pipeline
      Position initialPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      if (mounted) {
        setState(() {
          _currentLat = initialPosition.latitude;
          _currentLon = initialPosition.longitude;
          _currentSpeed = initialPosition.speed;
          _currentHeading = initialPosition.heading;
          _locationStatus = 'Ready to start driving.';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Startup Location Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
        setState(() => _locationStatus = 'Initial Fix Failed. Watching stream...');
      }
    }

    // Connect the live Fused stream pipeline
    _livePositionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1,
      ),
    ).listen(
          (Position position) {
        if (mounted) {
          setState(() {
            _currentLat = position.latitude;
            _currentLon = position.longitude;
            _currentSpeed = position.speed;
            _currentHeading = position.heading;
            _locationStatus = 'Tracking active.';
          });
        }
      },
      onError: (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Live Stream Error: $error'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 15),
            ),
          );
          setState(() {
            _locationStatus = 'Stream Error: $error';
            _currentLat = null;
            _currentLon = null;
            _currentSpeed = 0.0;
            _currentHeading = null;
          });
          debugPrint("GPS Stream Error: $error");
        }
      },
    );
  }

  // --- 2. BACKGROUND SERVICE COMMUNICATION ---
  void _listenToBackgroundService() {
    FlutterBackgroundService().on('updateUI').listen((event) {
      if (event != null && mounted) {
        setState(() {
          _nearestHazardName = event['hazardName'];
          _distanceToNearest = event['distance'];
          _isDangerZone = event['isDanger'] ?? false;
        });
      }
    });
  }

  Future<void> _checkServiceStatus() async {
    final isRunning = await FlutterBackgroundService().isRunning();
    setState(() {
      _isServiceRunning = isRunning;
      if (isRunning) _locationStatus = 'Tracking active in background';
    });
  }

  void _toggleDriveMode() async {
    final service = FlutterBackgroundService();
    var isRunning = await service.isRunning();

    if (isRunning) {
      service.invoke("stopService");
      setState(() {
        _isServiceRunning = false;
        _locationStatus = 'Tracking stopped.';
        _nearestHazardName = null;
        _distanceToNearest = null;
        _isDangerZone = false;
      });
    } else {
      service.startService();
      setState(() {
        _isServiceRunning = true;
        _locationStatus = 'Tracking active in background...';
      });
    }
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
                          Text('Hazards in Database:', style: Theme.of(context).textTheme.titleLarge),
                          Text(
                            '${snapshot.data}',
                            style: Theme.of(context).textTheme.displayLarge?.copyWith(
                              color: Colors.deepOrange, fontWeight: FontWeight.bold,
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
                          _currentLat != null
                              ? 'Lat: ${_currentLat!.toStringAsFixed(5)}\nLon: ${_currentLon!.toStringAsFixed(5)}\nSpeed: ${(_currentSpeed * 3.6).toStringAsFixed(1)} km/h\nHeading: ${_currentHeading?.toStringAsFixed(1) ?? 'N/A'}°'
                              : 'Acquiring GPS Signal wait...',
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
                          _nearestHazardName != null && _distanceToNearest != null
                              ? '$_nearestHazardName\nDistance: ${_distanceToNearest!.toStringAsFixed(0)}m'
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
                heroTag: "btn_drive",
                icon: Icon(_isServiceRunning ? Icons.stop : Icons.play_arrow),
                label: Text(_isServiceRunning ? 'Stop Drive' : 'Start Drive'),
                backgroundColor: _isServiceRunning ? Colors.red.shade200 : Colors.green.shade200,
                onPressed: _toggleDriveMode,
              ),
              const SizedBox(height: 16),
              FloatingActionButton.extended(
                heroTag: "btn_sync",
                icon: const Icon(Icons.cloud_download),
                label: const Text('Sync Cloud Data'),
                onPressed: _syncDatabaseFromCloud,
              )
            ]
        )
    );
  }
}