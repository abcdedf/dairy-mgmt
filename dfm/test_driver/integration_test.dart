// test_driver/integration_test.dart
//
// Required boilerplate for running integration tests on web via flutter drive.
// Usage:
//   chromedriver --port=4444 &
//   flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/ff_milk_purchase_test.dart \
//     -d chrome

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
