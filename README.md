# ShootIQ

A Flutter basketball shot analysis app with a dark modern theme, Supabase authentication, video recording, and upload capabilities.

## Features

- **Login** — Email/password authentication via Supabase
- **Home** — Dashboard with stats and quick actions
- **Record** — In-app video recording with camera (stored on-device)
- **Upload** — Pick videos from gallery (stored on-device)
- **Results** — Shot analysis breakdown with form metrics (saved locally)
- **Navigation** — Bottom nav bar with auth-aware routing

### Video privacy

Basketball videos are **never** stored in Supabase Storage. They remain on the
user's device. Clips are sent temporarily to the local ShootIQ AI server for
analysis, then server temp copies are deleted. Supabase is used for
authentication, player profiles, and subscription status only.

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.2+)
- A [Supabase](https://supabase.com) project

## Setup

1. **Enter the project**

   ```bash
   cd ~/Projects/shootiq
   ```

2. **Generate platform files** (if not already present)

   ```bash
   flutter create . --project-name shootiq
   ```

3. **Install dependencies**

   ```bash
   flutter pub get
   ```

4. **Configure Supabase**

   Edit `lib/config/supabase_config.dart` with your project URL and anon key, or pass them at build time:

   ```bash
   flutter run \
     --dart-define=SUPABASE_URL=https://your-project.supabase.co \
     --dart-define=SUPABASE_ANON_KEY=your-anon-key
   ```

5. **Enable Email Auth in Supabase**

   In your Supabase dashboard: Authentication → Providers → Email → Enable.

   Also add this redirect URL under Authentication → URL Configuration:
   ```
   shootiq://login-callback/
   ```
   (used for email confirmation and password reset)

6. **Add platform permissions**

   **Android** — add to `android/app/src/main/AndroidManifest.xml`:

   ```xml
   <uses-permission android:name="android.permission.CAMERA" />
   <uses-permission android:name="android.permission.RECORD_AUDIO" />
   ```

   **iOS** — add to `ios/Runner/Info.plist`:

   ```xml
   <key>NSCameraUsageDescription</key>
   <string>ShootIQ needs camera access to record your shot.</string>
   <key>NSMicrophoneUsageDescription</key>
   <string>ShootIQ needs microphone access to record audio.</string>
   <key>NSPhotoLibraryUsageDescription</key>
   <string>ShootIQ needs photo library access to upload videos.</string>
   ```

7. **Run the app**

   ```bash
   flutter run
   ```

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── config/
│   ├── theme.dart            # Dark basketball theme
│   └── supabase_config.dart  # Supabase credentials
├── services/
│   └── auth_service.dart     # Auth helpers
├── router/
│   └── app_router.dart       # GoRouter + auth redirects
├── pages/
│   ├── login_page.dart
│   ├── home_page.dart
│   ├── record_video_page.dart
│   ├── upload_page.dart
│   └── results_page.dart
└── widgets/
    ├── main_shell.dart       # Bottom navigation shell
    ├── shootiq_logo.dart
    └── stat_card.dart
```

## Theme

Dark background with basketball orange accents and court green highlights — designed for a modern sports analytics feel.
