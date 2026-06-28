import '../constants/hazard_type.dart';
import '../../database/database_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';



class HazardService {

  final DatabaseService _dbService;
  HazardService(this._dbService);


  Future<void> processCsvData(List<List<dynamic>> csvData) async {
    List<Hazard> validHazards = [];
    int failedCount = 0;
    bool isFirstRow = true;

    for (var row in csvData) {
      // Skip the header row if it exists
      if (isFirstRow) {
        isFirstRow = false;
        if (row.isNotEmpty && row[0].toString().toLowerCase() == 'type') {
          continue;
        }
      }

      try {

        // 1. Fixed csv columns to match the Hazard model
        String typeString = row[0].toString().trim();
        double lat = double.parse(row[1].toString());
        double lon = double.parse(row[2].toString());
        String name = row[3].toString().trim();
        double? heading;
        // Optional heading column
        if (row.length > 4 && row[4] != null) {
          heading = double.parse(row[4].toString());
        }

        // 2. Validate Enum mapping
        HazardType type = HazardType.values.firstWhere(
              (e) => e.name.toLowerCase() == typeString.toLowerCase(),
          orElse: () => throw Exception('Invalid hazard type: $typeString'),
        );

        // 3. Create the Hazard object
        validHazards.add(Hazard(
            type: type,
            latitude: lat,
            longitude: lon,
            name: name,
            heading: heading
        ));

      } catch (e) {
        // Print the error to your debug console so you can see exactly which row failed
        print('Row import failed: $row. Error: $e');
        failedCount++;
      }
    }

    if (validHazards.isNotEmpty) {
      await _dbService.insertHazardsBulk(validHazards);
    }

  }
}

final hazardServiceProvider = Provider<HazardService>((ref) {
  final dbService = ref.watch(databaseServiceProvider);

  return HazardService(dbService);
});
