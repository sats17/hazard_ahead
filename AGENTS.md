AGENTS.md

Project Name

SpeedBreaker Alert

Project Vision

Build a Flutter-based companion application that warns drivers about upcoming speed breakers, potholes, railway crossings, and other road hazards.

The application is NOT a navigation app.

Users continue using Google Maps or another navigation app while this application runs in the foreground or background and provides proximity-based alerts.

---

MVP Goal

When a user approaches a known hazard location within 100 meters:

- Play an audible warning
- Vibrate device
- Show notification
- Prevent duplicate alerts

Example:

"Speed breaker ahead in 100 meters"

---

Technology Stack

Frontend:

- Flutter
- Dart

Local Database:

- SQLite (preferred)
- Drift ORM optional

Maps:

- Google Maps Flutter

Location:

- geolocator

Background Processing:

- flutter_background_service

Voice Alerts:

- flutter_tts

State Management:

- Riverpod

Dependency Injection:

- Riverpod Providers

Architecture:

- Clean Architecture

---

Project Structure

/lib

/core

- constants
- utils
- services

/features

/location

- data
- domain
- presentation

/hazards

- data
- domain
- presentation

/alerts

- data
- domain
- presentation

/database

/shared

main.dart

---

Hazard Types

Initial supported hazards:

- Speed Breaker
- Pothole
- Railway Crossing
- School Zone
- Sharp Curve

Store as enum.

Example:

enum HazardType {
speedBreaker,
pothole,
railwayCrossing,
schoolZone,
sharpCurve
}

---

Data Source

Hazards can be imported from CSV.

Example CSV:

id,type,latitude,longitude,name

1,speedBreaker,19.0760,72.8777,Speed Breaker A

2,pothole,19.0765,72.8781,Pothole 1

3,railwayCrossing,19.0772,72.8795,Crossing A

---

Database Schema

Table: hazards

Fields:

id INTEGER PRIMARY KEY

type TEXT

name TEXT

latitude REAL

longitude REAL

created_at DATETIME

updated_at DATETIME

---

Import Process

User selects CSV file.

System validates:

- latitude exists
- longitude exists
- type exists

Then import into SQLite.

Show:

- imported count
- failed rows

---

Distance Calculation

Use Haversine formula.

Inputs:

- current latitude
- current longitude
- hazard latitude
- hazard longitude

Output:

- distance in meters

---

Alert Logic

Default warning distance:

100 meters

Configurable later.

Pseudo:

if distance <= 100m
and not already alerted

trigger alert

---

Duplicate Alert Prevention

Once alerted:

store hazard id in memory

do not alert again for:

300 seconds

or

until user moves 200 meters away

---

GPS Update Strategy

Update every:

1 second

or

5 meters movement

Use battery-efficient settings.

---

Performance Requirements

The system must support:

- 10 hazards
- 100 hazards
- 1,000 hazards
- 10,000 hazards

without noticeable lag.

Do NOT calculate distance against every hazard.

Implement spatial filtering.

Recommended:

Geohash

or

R-Tree

or

Bounding Box search

---

Background Mode

Android support required.

App should:

- continue tracking
- continue warning
- survive screen lock

Use foreground service notification.

---

Permissions

Android:

- ACCESS_FINE_LOCATION
- ACCESS_COARSE_LOCATION
- ACCESS_BACKGROUND_LOCATION

Handle denied permissions gracefully.

---

Voice Alerts

Examples:

Speed breaker ahead

Pothole ahead

Railway crossing ahead

Alert should play only once per event.

---

Settings Screen

User can configure:

- Warning distance
- Voice on/off
- Vibration on/off
- Background mode on/off

---

Future Features

Phase 2

- Crowd-sourced hazard reporting
- Firebase sync
- Online updates
- Admin dashboard
- Route-aware hazard detection
- AI hazard detection from phone camera

Phase 3

- Community moderation
- Hazard voting
- Road quality analytics
- Fleet management support

---

Coding Standards

- Null safety required
- Unit tests required
- Repository pattern
- Clean architecture
- No business logic in widgets
- Use immutable models

---

Definition of Done

A build is considered complete when:

1. User imports CSV
2. Hazards saved to SQLite
3. GPS tracking starts
4. Distance calculated correctly
5. Alert triggers at 100 meters
6. Duplicate alerts prevented
7. App works in background
8. Unit tests pass

---

Sample User Flow

1. User opens app
2. User imports hazards.csv
3. App stores hazards
4. User starts driving
5. App receives GPS updates
6. User approaches speed breaker
7. Distance becomes 100m
8. Voice alert plays
9. Notification appears
10. User passes hazard
11. Alert does not repeat unnecessarily

---

Success Metric

A driver receives a warning 100 meters before reaching a hazard location with greater than 95% reliability.