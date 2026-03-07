# Dairy Farm Management — Flutter App

Flutter web + mobile frontend for the Dairy Farm Management System.

## Setup

1. Copy `lib/core/app_config.dart` and set your WordPress backend URL:
   ```bash
   flutter run -d chrome --dart-define=DFM_WP_BASE=https://your-domain.com
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run on Chrome:
   ```bash
   flutter run -d chrome --dart-define=DFM_WP_BASE=https://your-domain.com
   ```

4. Build for web deployment:
   ```bash
   flutter build web --release --base-href /dairyapp/ --dart-define=DFM_WP_BASE=https://your-domain.com
   ```

## Testing

```bash
flutter test          # Run all 52 unit/integration tests
flutter analyze       # Static analysis (should show 0 issues)
```

For E2E integration tests:
```bash
chromedriver --port=4444 &
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/ff_milk_purchase_test.dart -d chrome \
  --dart-define=DFM_WP_BASE=https://your-domain.com \
  --dart-define=DFM_TEST_USER=<username> \
  --dart-define=DFM_TEST_PASS=<password>
```

## Architecture

See [CLAUDE.md](../dfm-backend/CLAUDE.md) for full project documentation including database schema, API contracts, and coding conventions.
