# Protect Background Service native code
-keep class id.flutter.flutter_background_service.** { *; }

# Protect Geolocator native code
-keep class com.baseflow.geolocator.** { *; }

# Protect standard Android location classes
-keep class android.location.** { *; }