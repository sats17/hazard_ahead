Phase 1: The Core Data & Database (Local Storage)
Goal: Get data saving permanently so you don't lose it when the app closes.

Step 1.1: Define the Models & Enums

Create the HazardType enum and the immutable Hazard class.

Result: App runs, but nothing visible changes yet.

Step 1.2: Initialize SQLite & Create the Table

Write the database helper class to create the hazards table.

Add a simple count query on app startup.

Result: App runs, connects to the database file, and displays "0 hazards found" on a blank screen.

Step 1.3: Build a Mock Data Injector

Add a temporary floating action button that inserts 3 hardcoded hazards into the database on click.

Result: Press button -> restart app -> see "3 hazards found" on screen. Your persistence goal is proven right here!

Phase 2: The CSV File Import Engine
Goal: Move from hardcoded mock data to real files provided by the user.

Step 2.1: Implement File Picker & CSV Parser

Add the file_picker (if needed, or standard document picker) and integrate the csv package to read text lines.

Result: App allows you to select a .csv file from your device downloads and prints the raw rows to the debug console.

Step 2.2: Add Data Validation & Bulk Insert

Write the validation rule (confirming latitude, longitude, and type match your enum).

Save valid rows into SQLite and display a success dialog: "Successfully imported 150 hazards! 2 failed."

Result: You can select a real CSV file, see the number update on screen, restart the app, and the data is still there.

Phase 3: Foreground Location & Distance Math
Goal: Get the phone's GPS talking to your newly imported database.

Step 3.1: Request GPS Permissions & Stream Location

Configure native Android permissions and stream the user's live latitude/longitude to a simple text widget on screen.

Result: Walk around or use emulator spoofing; see the coordinates change on screen in real time.

Step 3.2: Implement Bounding Box Search & Haversine Math

Write the database query that pulls only hazards within ~500 meters of your live coordinates.

Run the Haversine math to find the exact distance in meters to those filtered hazards.

Result: The screen prints out: "Nearest Hazard: Speed Breaker, Distance: 142 meters."

Phase 4: Alerting & Proximity Triggers
Goal: Make the phone react when you hit that 100-meter mark.

Step 4.1: TTS Voice & Vibration Engine

Initialize flutter_tts and the vibration plugin.

Add a test button to trigger a voice sample.

Result: Press button -> phone vibrates and says aloud, "Speed breaker ahead."

Step 4.2: Trigger Loop & Cache Prevention

Connect the distance math to the TTS engine: if (distance <= 100) -> speak.

Implement the 300-second/200-meter memory cache so it doesn't repeat the phrase every single second.

Result: Spoof a drive toward a hazard; the voice speaks exactly once at 100 meters and remains silent as you pass it.

Phase 5: Background Mode & UI Polish
Goal: Keep it running invisibly and wrap it in a clean package.

Step 5.1: Background Service Isolation

Move the location stream and trigger logic into flutter_background_service.

Result: Lock the phone screen or switch to Google Maps; the voice alerts continue firing while driving.

Step 5.2: Simple UI & Settings Dashboard

Design a simple toggle screen for adjusting distance thresholds, clearing the database, or turning voice off.

Result: Complete, production-ready MVP application.

Let's execute Step 1.1 right now!
Create a new file called hazard_model.dart inside your lib/features/hazards/domain/ directory. Copy this code into it: