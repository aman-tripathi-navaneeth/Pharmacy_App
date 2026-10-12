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
flutter run -d chrome
```

#### Option 2: Windows Desktop
```bash
flutter run -d windows
```

#### Option 3: Mobile (Android / iOS)
Connect your device or start an emulator, then:
```bash
flutter run
```

### Run Tests
```bash
flutter test
```

## Integration Expectations
- Call the backend under `/api/v1` using a configurable API base URL.
- Never include `MONGODB_URL` or any Atlas secret in frontend/mobile environment files.
- Handle slow/failed networks, retries, loading/empty/error states, and duplicate submit prevention.
- Support Telugu and English labels and mobile-sized screens.
- Keep API types/contracts aligned with `docs/api-conventions.md`.
