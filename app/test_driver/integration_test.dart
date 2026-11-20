/// `flutter drive` 的 driver 端。
///
/// Android 上不用这个（用 `flutter test integration_test/...`）——
/// 没有 driver 消费 `takeScreenshot` 的数据时它会永远卡住（BUG #17）。
/// iOS / macOS 用这个。
library;

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
