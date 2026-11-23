# webview_app · kmlab Toolbox

> 一个**配置驱动主界面 + WebView 承载业务**的极简 App 壳。
> 接入 `kmlab_site` / `h5_tools` 里的 7 个 H5 小工具（+ 1 个外部入口），主界面完全由 JSON 配置渲染。
> **App 不是新产品，而是 kmlab_site 的移动端形态** —— 图标、分类、工具名全部复用站内；正式名 `kmlab Toolbox`（纯英文，见下文核心思路第 2 条）。
>
> 🟡 **当前只做 Android 版本** —— 暂不开通 Apple 开发者账号（$99/年），iOS / macOS 的代码保留但**不发布、不投入**（决策见 [DESIGN.md D15](docs/DESIGN.md)）。Android 侧用 `./scripts/build-android.sh` 一条命令出包。

## 快速开始

```bash
# 1) 看设计示意图（纯静态单文件，无需构建）
open prototype/index.html

# 2) 跑 App（Flutter 3.47+ / Dart 3.13+）
cd app
flutter pub get
flutter test                       # 单元测试（续接卡摘要算法等）
flutter run -d emulator-5554        # 或 flutter build apk --debug

# 2b) 端上 UI 冒烟测试（真机点按钮，Android / iOS 通用）
flutter test integration_test/app_smoke_test.dart -d emulator-5554   # 端上冒烟（推荐）
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/app_smoke_test.dart \
  -d emulator-5554

# 3) 发布配置（改完 config/app.config.json 后）
./scripts/publish-config.sh          # 同步到内置快照 + 远端 app.json（自动盖 generatedAt + 自动签名）

# 4) 验证远端配置是否真的上线了
./scripts/verify-remote-config.sh    # 查 HTTP/content-type/md5/generatedAt/关键字段

# 5) 重新生成 App 图标（改了 assets/icon.svg 之后）
./scripts/generate-icons.sh          # Android mipmap + iOS AppIcon

# 5b) Android 一键出包（静态检查 + 单测 + release APK）
./scripts/build-android.sh            # 分析 + 单测 + 出 release APK
./scripts/build-android.sh --debug    # 出 debug APK
./scripts/build-android.sh --install  # 出包并装到已连接的设备

# ⏸ 以下 iOS / TestFlight 相关脚本已暂缓（不开通 Apple 账号），留着将来直接用
# ./scripts/setup-ios.sh --fix         # iOS 出包前体检（Xcode / SDK / 模拟器）
# ./scripts/setup-testflight.sh        # TestFlight 前体检（证书 / Bundle ID / entitlement）
```

### 出包产物在哪

| 平台 | 命令 | 产物路径 |
|---|---|---|
| Android | `flutter build apk --release` | `app/build/app/outputs/flutter-apk/app-release.apk`（约 55MB，debug key 签名，可直接侧载） |
| Android（调试） | `flutter build apk --debug` | `app/build/app/outputs/flutter-apk/app-debug.apk` |
| iOS ⏸ | `flutter build ios --release --no-codesign` | `app/build/ios/iphoneos/Runner.app`（**没有签名**）—— **暂缓发布**（D15） |
| macOS ⏸ | `flutter build macos --release` | `app/build/macos/Build/Products/Release/kmlab Toolbox.app`（ad-hoc 签名，**只能本机跑**）—— **暂缓发布**（D15） |

> ⏸ **iOS / macOS 已暂缓**（暂不开通 Apple 开发者账号，见 D15）。代码与出包能力都保留着，步骤见 [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md)，将来账号齐了直接照做。
>
> **TestFlight 需要的账号前提**（将来才需要，脚本代劳不了，会逐条列给你）：
> ① 付费的 Apple Developer Program 账号（$99/年，免费账号不能上架）
> ② Xcode → Settings → Accounts 登录该账号 → 自动生成「Apple Distribution」证书
> ③ developer.apple.com 注册 Bundle ID `tech.kmlab.kmlabToolbox`
> ④ App Store Connect → My Apps → + → New App（**一次只能选一个平台**，iOS 与 macOS 是两条独立记录）
> ⑤ Xcode → Product → Archive → Distribute App → App Store Connect → Upload
>
> macOS 额外要开三个 entitlement（已在工程里配好）：`app-sandbox`（上架必需）、
> `network.client`（**不然 WebView 加载不了 kmlab.tech**）、`files.user-selected.read-write`（导入数据要读文件）。

> **iOS 需要一次性的系统设置**：本机 `xcode-select` 默认指向 `/Library/Developer/CommandLineTools`，
> 那里**只有 macOS SDK、没有 iOS 模拟器 SDK**。Xcode 的 Run Script 阶段调
> `xcrun --show-sdk-path --sdk iphonesimulator` 会直接失败，表现为
> `Error (Xcode): SDK "iphonesimulator" cannot be located`。
> 一行命令解决（`scripts/setup-ios.sh --fix` 就是干这个的）：
>
> ```bash
> sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
> ```
>
> 改完 **Xcode 和终端都要重启**才生效。`~/.zshrc` 里我也补了一行
> `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`（对命令行工具有效，
> 但 Xcode 内部 build script 仍以 `xcode-select` 为准，所以上面那条 sudo 才是根治）。
>
> Flutter 3.47 默认走 **Swift Package Manager**，不需要 CocoaPods。
> 模拟器包免签名；真机包需在 `ios/Runner.xcworkspace` 里选一个 Development Team。
>
> 已出包：`app/build/app/outputs/flutter-apk/app-release.apk`（debug key 签名，可直接侧载到手机）、
> `app/build/ios/iphonesimulator/Runner.app`（模拟器，免签名）。

### 配置的三份副本

| 文件 | 作用 |
|---|---|
| `config/app.config.json` | **唯一真相源**，改这里 |
| `app/assets/app.config.json` | 随 App 打包的内置快照（首屏直出，断网也能用） |
| `kmlab_site/public/data/app.json` | 远端配置（运营改这份不用发版；需在 kmlab_site 里重新 build） |

`scripts/publish-config.sh` 负责把三者对齐（同一份 md5）。它只在**配置内容真的变了**时才盖新的 `generatedAt`（时间戳取 `max(当前 UTC 时间, 上一版 + 1 秒)`，保证单调递增，绝不会因为机器时钟不准而把新配置标成「旧的」）。

> ⚠️ **远端配置 URL 必须返回 JSON**。kmlab_site 是静态托管的 Vue SPA，对任何不存在的路径都返回 **200 + index.html**，
> 所以 App 侧加了内容嗅探（body 首字符不是 `{` 就判定为失败，静默降级到内置快照）。

> ⚠️ **远端配置不能比 App 内置的旧**。每份配置顶层带 `generatedAt` 时间戳，
> 远端比本地旧（或缺这个字段）一律**拒绝并沿用本地配置** —— 防止「站上构建产物没更新，
> 把 App 刚修好的功能打回去」。详见 [DESIGN.md §4.4.1](docs/DESIGN.md)。

## 目录

```
config/app.config.json   主配置：工具清单、页签、容器行为、Bridge 权限
app/assets/              随包发布的内置配置快照（首屏直出）
prototype/index.html     设计示意图（4 个页签：界面示意 / 架构与流程 / 配置 Schema / 设计决策）
docs/DESIGN.md           完整设计文档
docs/STORAGE_KEYS.md     存储 key 清单 + 续接卡摘要算法（实测自 h5_tools 产物）
assets/icon.svg          App 图标（= kmlab_site/public/favicon.svg）
assets/icon-foreground.svg  自适应图标前景层（只有墨线笔画，底色交给 background 层）
app/                     Flutter 工程（kmlab_toolbox）
app/integration_test/    端上 UI 冒烟测试（真机跑，见 DESIGN.md §5.10）
app/test/                单元测试
scripts/
├─ publish-config.sh     把 config/app.config.json 同步到内置快照 + 远端 app.json（自动盖 generatedAt + 自动签名）
├─ sign-config.sh        给配置算 HMAC-SHA256 签名（--check 只校验 / --print 只打印）
├─ verify-remote-config.sh  验证远端配置是否真的上线（HTTP / content-type / md5 / generatedAt）
├─ build-android.sh      Android 一键出包（analyze + 单测 + release APK + 可选装机）
├─ generate-icons.sh     从 assets/icon.svg 生成 Android mipmap + iOS AppIcon + macOS AppIcon
├─ setup-ios.sh          iOS 工具链体检 + 修复引导（xcode-select / SDK / 模拟器 / SPM）
└─ setup-testflight.sh   TestFlight 发布链路体检 + 引导（证书 / Bundle ID / entitlement / 版本号）
```

## Flutter 工程结构

```
app/lib/
├─ main.dart                 入口：bootstrap → MaterialApp（浅/深纸主题）
├─ model/app_config.dart     配置全量不可变模型（含枚举与 fromJson/toJson）
├─ config/
│  ├─ config_loader.dart     三层加载 + Schema 校验（拒绝规则）
│  └─ config_store.dart      ChangeNotifier：原子替换 + last-good 持久化
├─ theme/paper_theme.dart    纸片 ThemeExtension + 纸角圆角 + 稳定倾斜角
├─ icons/doodle_icons.dart   9 个 kmlab doodle（路径逐字复用 DoodleIcon.vue）+ 25 个 UI 图标
├─ data/
│  ├─ usage_store.dart       最近记录 / 常用置顶 / localStorage 快照缓存
│  │                          + exportPayload / importPayload / clearAllData
│  ├─ resume_reader.dart     续接卡摘要算法（countToday / count / countDateMap / lastGame / field）
│  ├─ data_transfer.dart     App 级导出全部 / 导入 / 清除全部（JSON + 分享面板）
│  └─ downloader.dart        下载抓取（http / blob / data:）+ 文件名消毒（保留中文）
├─ util/
│  └─ native_toast.dart      系统 Toast（WebView 是 PlatformView，会盖住 Flutter 的 SnackBar）
├─ webview/
│  ├─ km_bridge.dart         window.KM 注入 + JS 通道协议
│  └─ webview_host.dart      WebView 容器 + chrome 四档 + 兜底页 + 沉浸热区
└─ ui/
   ├─ root_shell.dart        底部导航外壳（最近 / 小工具 / 我的）
   ├─ recent_page.dart      最近页（首屏）
   ├─ tools_page.dart        小工具页（配置渲染的卡片网格）
   ├─ tool_detail_page.dart  工具容器 + ⋯ 溢出菜单 + 导入导出
   ├─ settings_page.dart     我的（外观 / 配置 / 离线与数据 / 关于）
   └─ widgets/paper_widgets.dart  通用纸片组件
app/integration_test/app_smoke_test.dart  真机 UI 冒烟（4 个用例）
app/test_driver/integration_test.dart    flutter drive 入口
app/test/
├─ resume_reader_test.dart                摘要算法单元测试（26 个用例）
├─ data_transfer_test.dart                App 级数据管理单元测试（7 个用例）
├─ chrome_test.dart                       chrome 档位单元测试（10 个用例，守住 auto 档判定）
├─ downloader_test.dart                   下载解析 / 文件名消毒单元测试（13 个用例）
├─ lastgame_test.dart                     脑力慢养 lastGame 算法单元测试（14 个用例）
└─ config_contract_test.dart              「配置即契约」守卫（5 个用例：孤儿字段 / 假开关 / 品牌溯源）
```

## 核心思路

1. **主界面 = 配置的渲染结果**。新增工具、改名、换色、调序、下架 —— 全都只改 `config/app.config.json`，不发版。
2. **品牌与命名复用 kmlab_site**。App 正式名 `kmlab Toolbox`（纯英文；站点 `<title>` 是中英混排的「kmlab · 工具」，桌面图标标签用着别扭，故刻意改为纯英文 —— 这是唯一一处不照抄的地方），品牌 token = `kmlab` + `handmade workspace`；图标 = 站内 `favicon.svg`，分类 = 站内四大分类（生活习惯 / 效率清单 / 知识索引 / 其他），工具名 = `html_files.json` 里的原名，线稿图标逐字复用 `DoodleIcon.vue`。`app.brandSource` 把这层对应关系写进配置本身 —— 配置即契约。
3. **首屏落在「最近」**。打开 App 的动作是「我要接着干活」，不是「我要逛目录」。因此「最近」是一级页面：续接卡 + 常用置顶 + 时间线；首次安装走空状态（给推荐工具 + 去小工具页的出口），绝不留白。
4. **容器 chrome 四档**。`full` / `auto` / `minimal`（默认）/ `immersive` —— 逐工具指定。immersive 是真全屏（header 与 footer 都不显示），但**必须留顶部热区下滑作为逃生通道**（iOS 没有硬件返回键）。⚠️ Android 上 WebView 是 PlatformView，会盖住 Flutter 的手势层 —— 所以这个边缘手势**由页面 JS 监听后回传**（`KmBridge.edgeSwipeScript`），不是 Flutter 的 `GestureDetector`。
5. **返回键默认不接管页面内路由**。默认直接回 App 根页面 —— 6 个工具实测确实是单页（0 处 `pushState`）。做成**逐工具开关** `open.routeBackEnabled`（默认 `false`），脑力慢养虽是 hash 路由 SPA 也**不开**（页内已有「回到首页」，保持 8 个工具行为一致）；将来接入多路由 H5，改配置一个字段即可。
6. **顶栏只留一个 ⋯**。刷新、复制链接、浏览器、分享、全屏、固定、导出/导入/清除数据、关于、反馈 —— 12 个动作收进分组 Action Sheet，逐工具可裁剪。
7. **数据导出 = `.json` 文件 + 系统分享面板**。不走剪贴板（几十 KB 不稳且会被别的 App 读）—— 发微信/飞书/邮件、存「文件」再上云盘一条路走通；换机时反手导入即可恢复。「清除数据」放在 ⋯ 里，但必须二次确认 + 提示先导出。
8. **配置三来源、双轨加载**。内置快照首屏直出 → 运行时后台静默拉远端 → 失败沿用上次可用配置。断网、服务器挂了，App 都照常能用。
9. **远端优先，保持同源**。H5 仍从 `https://kmlab.tech/...` 加载，**origin 与网页版一致 → 用户在网页版攒的数据直接可见**（换 origin = 换存储空间 = 丢数据，这是最大的坑）。
10. **离线走 Service Worker，不换 origin**。站内 `/sw.js` 只接管 `/h5_tools/**`（cache-first + 后台刷新）—— 断网能秒开，**origin 不变 → 本地数据依旧共享**。把副本塞进 APK 换 origin 那条路被否决（数据会分家）。**已实测（Android）：断网后工具 H5 完整渲染，origin 与本地数据均未变。**
    - ⚠️ **只有 iOS 暂时没有离线**：iOS 的 WKWebView 只在「已验证的 app-bound domain」里才暴露 `navigator.serviceWorker`，而域名验证需要付费 Apple 开发者账号 + Associated Domains + 站点 AASA。本机没有账号 ⇒ iOS 上 `navigator.serviceWorker` 是 `undefined`。**macOS 实测可用**（同样是 WKWebView、同样没声明 app-bound 域名，但 `register('/sw.js')` 注册成功）⇒ 离线矩阵是 **Android ✅ / macOS ✅ / iOS ❌**。
    - ⚠️ **千万别为了修离线去加 `WKAppBoundDomains`**：Apple 的规则是「一旦声明，所有 WKWebView 进入严格模式，拒绝一切 JS 注入 / message handler」—— 域名没验证的话，Bridge、localStorage 快照、下拉刷新会**全废**，离线还照样用不了。详见 [DESIGN.md §5.9](docs/DESIGN.md)。
11. **JS Bridge 只做增强，不做依赖**。每个 H5 在普通浏览器里必须原样可用；Bridge 挂了 H5 还能用。
12. **H5 零改造**。不重写任何业务逻辑，App 只负责「打开、承载、返回、离线、兜底」。

## 技术选型

**Flutter**（`webview_flutter` + 自研 PlatformView 拦截层），复用 `my_mind`/brainfit 的适老设计系统。
跨平台一次开发，配置 → Widget 映射成本最低。若最终只发安卓且对缓存/拦截要求极高，再考虑切 Kotlin + Compose。

## 设计语言

沿用 `kmlab_site` 的「牛皮纸速写本 + 手绘墨线」：设计 token 一致、只用内联 SVG 线稿（禁 emoji）、卡片旋转角各不相同且稳定、支持深色模式。

## 文档

- [设计文档 docs/DESIGN.md](docs/DESIGN.md) —— 架构、字段全表、品牌对齐表、校验规则、状态设计、14 条设计决策、迭代路线（M1~M5 全部排期 + 5 项跨仓库配合任务）、16 条拍板结果、13 条开发风险、**27 个实跑真 BUG**、iOS / macOS 适配要点（§5.9）、端上 UI 冒烟测试通道（§5.10）、App 级数据管理（§5.11）、拦截层（下载 / 外链，§5.12）、远端配置签名（§4.4.2）、配置 diff 提示（§4.4.3）、灰度发布（§5.13）、分享长图（§5.14）
- [存储 key 清单 docs/STORAGE_KEYS.md](docs/STORAGE_KEYS.md) —— 8 个工具的真实 localStorage / IndexedDB key + 续接卡摘要算法
- [**iOS 上架手册 docs/TESTFLIGHT.md**](docs/TESTFLIGHT.md) —— 逐步骤操作手册（点哪里 / 看到什么 / 错了怎么办）：路线 A 免费自用 + 路线 B 上架 TestFlight + 常见错误速查
- [设计示意图 prototype/index.html](prototype/index.html) —— 可交互原型

## 当前进度

| 阶段 | 状态 |
|---|---|
| 设计（示意图 / 文档 / 配置 Schema） | ✅ 定稿 |
| **目标平台** | 🟡 **只做 Android**（iOS / macOS 代码保留但不发布，见 D15）；Android 一键出包：`./scripts/build-android.sh` |
| P1 存储 key 清单 | ✅ 完成（`docs/STORAGE_KEYS.md`） |
| M1 Flutter 骨架（模型 / 主题 / 图标 / 配置加载 / 数据层 / UI 层 / WebView 容器 / Bridge） | ✅ 代码完成，`flutter analyze` 0 issues |
| 单元测试（摘要算法 / 快照往返 / 配置新鲜度 / App 级数据管理 / 下载解析 / chrome 档位 / lastGame / 配置契约 / HMAC 签名 / 配置差异 / 灰度分桶） | ✅ **138 个用例全过**（9 个测试文件） |
| 模拟器实跑验证 | ✅ 已跑通（最近页 / 小工具页 / 我的页 / WebView 同源加载 / minimal & immersive chrome / ⋯ 溢出菜单 / 导出分享面板 / 返回键回最近页 / 沉浸式边缘下滑唤出工具栏） |
| 续接卡摘要 | ✅ 已修（`maybeDecode` 解字符串层 + `countDateMap` 算法） |
| 配置新鲜度保护（`generatedAt`） | ✅ 已实现（远端旧配置不覆盖内置新配置） |
| 远端配置签名（HMAC-SHA256） | ✅ 已实现（`remote.requireSignature` 从假开关变成真校验；只能加严不能放松；`scripts/sign-config.sh` 签发） |
| 配置 diff 提示（热更可审） | ✅ 已实现（「我的 → 配置」可展开差异清单；手动刷新后弹差异对话框） |
| 远端配置热更链路 | ✅ 已打通并验证（线上 app.json 与本地三份 md5 一致；App 冷启动成功拉取，「上次更新 11-19 11:19」） |
| App 图标（Android mipmap + 自适应 + 单色 + iOS AppIcon） | ✅ 已生成（`scripts/generate-icons.sh`，素材 = kmlab favicon；iOS 端按 `Contents.json` 的文件名生成，避免又变回 Flutter 默认 logo） |
| release APK 出包 | ✅ 已出（`app-release.apk`，debug key 签名，可侧载） |
| 下拉刷新（`open.pullToRefresh`） | ✅ 已实现（页面内 JS 监听 + 牛皮纸指示器，真机验证 reload 生效） |
| 离线 L1：Service Worker | ✅ 已部署并实测（**Android**）：SW 激活 + 页面被接管 + 7 个工具入口全预缓存 + **断网秒开**（`svc wifi disable` 后 H5 完整渲染）；**macOS** 实测 SW 注册成功也有离线；**iOS** 如实显示「此平台不支持（需域名验证）」 |
| 原生 Toast（不被 WebView 遮挡） | ✅ 已实现（`km/toast` MethodChannel） |
| ~~M2 离线 L2 内置副本~~ | 🚫 **取消** —— L2 换 origin 会让 localStorage 与网页版分家（违反 D1 铁律） |
| iOS 出包验证 | ⏸ **暂缓** —— 代码已跑通（Xcode 16.2；`xcode-select` 指错是根因，见 `scripts/setup-ios.sh`），但**不再投入**（D15） |
| 端上 UI 冒烟测试 | ✅ **三端各 6 个用例全过**（Android `flutter test integration_test` 2:00 / iOS `flutter drive` 1:28 / macOS `flutter drive` 1:32）—— 最近页 / 小工具页 / WebView 加载远程 H5 / 返回键 / 离线能力如实探测 / Bridge 注入 |
| App 正式名 | ✅ 改为 `kmlab Toolbox`（纯英文；站点标题「kmlab · 工具」中英混排，桌面标签不适用） |
| **App 级数据管理**（导出全部 / 导入 / 清除全部） | ✅ 已实现（`lib/data/data_transfer.dart`；导出 = `.json` → 系统分享面板；导入支持「合并 / 完全覆盖」；清除有二次确认 + 先导出出口） |
| **macOS 平台** | ✅ 已接入并跑通（`flutter build macos --debug` 出包；渲染树验证 UI 正常；三个 entitlement 配齐；原生 Toast 浮层自绘） |
| **TestFlight 上架** | ⏸ **暂缓** —— 暂不开通 Apple 开发者账号（D15）。手册已写好放在 [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md)，将来账号齐了直接照做 |
| **拦截层（下载 / 外链）** | ✅ 已实现（`onNavigationRequest` 五级判定；`blob:`/`data:` 下载、外链交系统浏览器并 Toast 提示、`.zip/.pdf/.xlsx` 等 29 种扩展名自动识别；`webview.interceptDownloads` 之前只声明没实现，现在真正接上了） |
| **配置即契约**（假开关清理） | ✅ 8 个「声明了但代码从没读过」的假开关已从配置与模型删除；新增 `app/test/config_contract_test.dart` 做守卫 —— 以后配置里再出现孤儿字段，测试直接红 |
| **脑力慢养续接卡** | ✅ 新增 `lastGame` 算法（实测线上 bundle 的 `bf_progress` 真实结构）；游戏代码→中文名映射放在配置里，App 不硬编码 H5 的知识 |
| **灰度发布** | ✅ 两份 URL + 设备稳定分桶（FNV-1a + murmur3 `fmix32` 终混合；同一设备永远同一个桶）；`remote.canaryUrl` + `remote.rolloutPercent`（0~100） |
| **分享长图** | ✅ 纸片风海报（RepaintBoundary → PNG → 系统分享面板）；两个入口：工具 ⋯ 菜单「生成分享长图」+ 我的页「生成分享长图」；先弹预览再分享 |
| **iOS 离线** | 🚧 **暂时做不到**（macOS 反而可以 ✅）—— 且已随 iOS 一起暂缓—— iOS 的 WKWebView 只在「已验证的 app-bound domain」里暴露 SW API；域名验证要付费 Apple 账号 + Associated Domains + 站点 AASA。App 已如实显示「此平台不支持（需域名验证）」，等账号条件齐了按 DESIGN.md §5.9 的四步开 |
| **iOS JS Bridge 修复** | ✅ **删掉 `WKAppBoundDomains`** —— 声明它会让所有 WKWebView 进入严格模式（拒绝 JS 注入 / message handler），域名又没验证 ⇒ 整个 Bridge 全废。删掉后 iOS 上 `window.KM` / 快照 / 下拉刷新 / JS channel **全部恢复** |
| **chrome 四档** | ✅ `minimal` / `auto` / `immersive` / `full` 全部实跑验证：`auto` 档滚动淡出 + 停手 1.5s 自动收起（`autoHideDelayMs`）；`immersive` 档真全屏 + 顶部热区边缘下滑唤出工具栏 + 默认不显示进度条（`keepProgressBarInImmersive`） |
