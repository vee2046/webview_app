// ⚠️ 本文件由 `scripts/build-android.sh` **自动生成**，请勿手改。
//
// 每次出包前脚本会：
//   1. 递增 `app/pubspec.yaml` 的 version（`x.y.z+N` → patch 位 +1、build 号 +1）
//      —— Android 的 versionCode / versionName 与 iOS 的 CFBundleVersion /
//         CFBundleShortVersionString 都来自这里，所以**版本号一变，安装包就能覆盖升级**。
//   2. 重新生成本文件。
//
// 为什么要自动递增：之前版本号一直卡在 0.1.0+1，连着出好几个包，
// 装到手机上系统会当成「同一个版本」→ 装不上 / 还是旧包 → 看起来像「改了没效果」。
library;

/// 版本名（用户可见），如 `0.1.1`。
const String kAppVersion = '0.1.13';

/// 构建号（Android versionCode / iOS CFBundleVersion），每次出包 +1。
const int kAppBuild = 14;

/// 完整标签（用户可见），如 `0.1.1 (2)`。
const String kAppVersionLabel = '$kAppVersion ($kAppBuild)';
