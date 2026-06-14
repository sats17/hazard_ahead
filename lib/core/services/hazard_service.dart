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
        if (row.isNotEmpty && row[0].toString().toLowerCase() == 'id') {
          continue;
        }
      }

      try {
        // Validate length based on your 5-column format
        if (row.length < 5) throw Exception('Invalid row length');

        // 1. Map columns to their specific indices
        int id = int.parse(row[0].toString());
        String typeString = row[1].toString().trim();
        double lat = double.parse(row[2].toString());
        double lon = double.parse(row[3].toString());
        String name = row[4].toString().trim();

        // 2. Validate Enum mapping
        HazardType type = HazardType.values.firstWhere(
              (e) => e.name.toLowerCase() == typeString.toLowerCase(),
          orElse: () => throw Exception('Invalid hazard type: $typeString'),
        );

        // 3. Create the Hazard object
        validHazards.add(Hazard(
            id: id,
            type: type,
            latitude: lat,
            longitude: lon,
            name: name
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
