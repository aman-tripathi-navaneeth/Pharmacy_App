# Pharmacy App — Flutter Frontend

Mobile-first Flutter application for the 12-module Pharmacy Store Application.

## Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.24+ (Dart 3.5+)
- Chrome browser (for quick web testing in mobile frame), Windows desktop, or an Android emulator / physical device.

### Install dependencies
```bash
flutter pub get
```

### Run the App

#### Option 1: Chrome (Mobile Frame View)
Runs the app in Google Chrome inside a centered mobile phone viewport:
```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

#### Option 2: Windows Desktop
```bash
flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

#### Option 3: Mobile (Android / iOS)
Connect your device or start an emulator, then:
```bash
flutter run --dart-define=API_BASE_URL=http://<backend-host>:8000
```

Set `API_BASE_URL` to the backend's reachable address. For an Android emulator,
use `http://10.0.2.2:8000`; for a physical device, use the computer's LAN IP.
The default remains `http://127.0.0.1:8000` for local desktop/web development.

### Run Tests
```bash
flutter test
```

## Integration Expectations
- Call the backend under `/api/v1` using a configurable API base URL.
- Never include `POSTGRES_URL` or any database secret in frontend/mobile environment files.
- Handle slow/failed networks, retries, loading/empty/error states, and duplicate submit prevention.
- Support Telugu and English labels and mobile-sized screens.
- Keep API types/contracts aligned with `docs/api-conventions.md`.
