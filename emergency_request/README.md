# Emergency Request

Patient-side Flutter app: SOS → GPS → Mapbox map + reverse geocode →
`create_emergency_request` on Supabase.

Maps use **flutter_map** + Mapbox Streets v12 raster tiles. There is no
`google_maps_flutter` and no native Mapbox SDK.

## Folder structure

```
emergency_request/
├── pubspec.yaml
├── analysis_options.yaml
├── dart_defines.example.json
├── dart_defines.json          # local only, gitignored
├── README.md
└── lib/
    ├── main.dart
    ├── config/
    │   └── env.dart
    ├── maps/
    │   ├── mapbox_tile_layer.dart
    │   ├── mapbox_map_view.dart
    │   └── mapbox_geocoding.dart
    ├── services/
    │   ├── location_service.dart
    │   └── emergency_service.dart
    └── screens/
        ├── home_screen.dart
        ├── request_screen.dart
        └── submitted_screen.dart
```

## Add to GitHub

```bash
cd emergency_request
git init
git add .
git commit -m "Initial emergency request app (Mapbox + Supabase)"
git branch -M main
git remote add origin git@github.com:YOUR_USER/emergency_request.git
git push -u origin main
```

Copy `dart_defines.example.json` → `dart_defines.json` locally. Do not
commit `dart_defines.json`.

## Generate Android / iOS shells

This repo is Dart-only. From the project root:

```bash
flutter create --project-name emergency_request --org com.example .
```

That writes `android/` and `ios/` without overwriting `lib/` or
`pubspec.yaml`.

### Android — `android/app/src/main/AndroidManifest.xml`

Inside `<manifest>`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

Do **not** add `com.google.android.geo.API_KEY`.

### iOS — `ios/Runner/Info.plist`

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Your location is sent with the emergency request so responders can find you.</string>
```

Do **not** add `GMSApiKey`.

## Run

```bash
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_KEY \
  --dart-define=MAPBOX_ACCESS_TOKEN=pk.eyJ...
```

Or:

```bash
flutter run --dart-define-from-file=dart_defines.json
```

## RPC

`EmergencyService` calls:

```
create_emergency_request(p_lat, p_lng, p_address)
```

Rename those arguments in `lib/services/emergency_service.dart` if the
live function uses different names. Reverse geocode failures become a
plain `"lat, lng"` string and do not block submit.
