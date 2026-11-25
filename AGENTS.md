# AGENTS.md

> kmlab Toolbox（Android 壳应用）的**协作规约与 SOP**。
> 面向任何在本仓库里改代码的 Agent / 人 —— 读完这一份就知道该怎么动、怎么验、怎么发。
> 架构与决策全文见 [`docs/DESIGN.md`](docs/DESIGN.md)（13 章 / 15 决策 / 17 拍板 / 13 风险 / 28 个实跑真 BUG）。

---

## 1. 这个项目是什么

**kmlab Toolbox** = kmlab_site 的**移动端形态**。一个「配置驱动主界面 + WebView 承载 H5」的极简壳：

- 壳只做四件事：**渲染配置 / 打开 H5 / 管理导航 / 兜底异常**
- 业务逻辑全在 H5 里（`kmlab.tech/h5_tools/**`），通过「一份 JSON 配置」解耦
- 品牌完全复用 kmlab_site：名称、图标、分类、工具名、doodle 线稿

**目标平台：只做 Android**（D15）。iOS / macOS 的代码保留、已跑通、已出包，但**不签名分发、不上架、不投入** —— 暂不开通 Apple 开发者账号。

---

## 2. 目录结构

```
webview_app/
├─ config/app.config.json     ★ 唯一真相源（工具 / 分类 / 远端配置 / 品牌溯源）
├─ docs/
│  ├─ DESIGN.md                架构、字段全表、决策、风险、BUG 史
│  └─ STORAGE_KEYS.md          各工具的 localStorage key 与摘要算法
├─ prototype/index.html        设计示意图（4 页签，纯静态，可直接开）
├─ scripts/                    运维脚本（见 §4）
├─ assets/                     图标源（icon.svg / icon-foreground.svg / icon-monochrome.svg）
└─ app/                        Flutter 工程 kmlab_toolbox
   ├─ lib/
   │  ├─ model/app_config.dart      配置模型（唯一解析入口）
   │  ├─ config/                    加载 + 校验 + 签名 + diff
   │  ├─ data/                      用量 / 续接卡 / 导入导出 / 更新检查
   │  ├─ theme/paper_theme.dart      纸片风 ThemeExtension
   │  ├─ icons/doodle_icons.dart     kmlab doodle + UI 图标
   │  ├─ webview/                   WebView 容器 + JS Bridge
   │  ├─ ui/                        三个页签 + 工具容器 + 我的
   │  └─ version.dart                ★ 自动生成：真实包版本
   ├─ test/                        单元测试
   └─ integration_test/             真机 UI 冒烟
```

---

## 3. 环境

| | |
|---|---|
| Flutter / Dart | **3.47.9 / 3.13.7** → 可以放心用 `??` / `?.` / sealed / records |
| Xcode | 16.2（`xcode-select` 必须指向 `/Applications/Xcode.app/Contents/Developer`） |
| 模拟器 | Android `emulator-5554`（**320×640**，很窄）；iOS `D2D6D351-…`（iPhone 16 / iOS 18.2） |
| 状态管理 | **不新增依赖** —— `ListenableBuilder` + `ChangeNotifier` |

---

## 4. 常用命令

### 出包（主链路）
```bash
./scripts/build-android.sh              # analyze + 单测 + release APK（自动递增版本号）
./scripts/build-android.sh --install    # 顺便装机并启动
./scripts/build-android.sh --debug      # debug 包
```
产物**同时**在两个地方：
- `app/build/app/outputs/flutter-apk/app-release.apk`
- **项目根目录** `kmlab-toolbox-v<版本>.apk` ← 手机直接装这个（旧的会自动删掉）

### 测试
```bash
cd app
flutter analyze                        # 必须 0 issues（项目标准）
flutter test                           # 单元测试（当前 160 个）
flutter test integration_test/app_smoke_test.dart -d emulator-5554   # Android 冒烟
# iOS / macOS 用 flutter drive（Android 用 flutter drive 会卡死，见 §8）
```

### 配置与发布
```bash
./scripts/sync-categories.py           # 把站点的分类/图标同步进 App 配置（改站点的分类后必跑）
./scripts/publish-config.sh             # 签名 + 同步三份副本 + 生成 Android strings.xml
./scripts/verify-remote-config.sh      # 核对线上 app.json 与本地三份副本是否一致
./scripts/publish-update.sh             # 生成自动更新清单 kmlab_site/public/data/update.json
./scripts/publish-release.sh            # 出包 → 发 GitHub Release → 更新清单
./scripts/init-github.sh --release      # 推 main + 打 tag → Actions 自动出包发版
```

---

## 5. 配置即契约（最容易踩的地方）

### 三份副本，必须一致
| 文件 | 作用 |
|---|---|
| `config/app.config.json` | **唯一真相源**（人改这份） |
| `app/assets/app.config.json` | 随包发布的内置快照（`publish-config.sh` 生成） |
| `kmlab_site/public/data/app.json` | 线上远端配置（运营改这份，App 启动时拉） |

`./scripts/publish-config.sh` 负责签名 + 同步这三份，并生成 `android/.../values/strings.xml`。

### 四道闸门（`config_store.dart` / `config_loader.dart`）
1. **状态码**必须是 200
2. **内容嗅探**：body 首字符必须是 `{` —— 静态托管的 SPA 对不存在的路径返回 **200 + index.html**，只看状态码会永远以为成功
3. **schemaVersion** 不得高于本地
4. **签名**（HMAC-SHA256）：`remote.requireSignature` 打开时必须验签
5. **新鲜度**：远端 `generatedAt` 不得比本地旧 —— 远端旧了**沿用本地**，不报错

### 铁律
- **改了配置必须跑 `publish-config.sh`**，否则 App 内置快照和线上会不一致
- **改了配置还要部署 kmlab_site**，否则线上还是旧的（App 会因新鲜度保护拒绝它）
- 配置里**不许出现没人读的字段**（假开关比没有开关更糟）→ `app/test/config_contract_test.dart` 做守卫
- `generatedAt` 由脚本自动维护，**内容真变了才盖**，且保证单调递增

---

## 6. 分类与图标：不要手工抄

站点的分类和手绘图标是**关键词规则**驱动的（`kmlab_site/src/lib/project.ts` → `categoryOf()` / `doodleOf()`）：

```
text = title + ' ' + description
命中任一 keywords → 归入该分类；兜底 = 最后一条（misc）
```

⇒ App 侧**不手工填** `app.tabs[]` / `tools[].tab` / `tools[].color` / `tools[].icon`，而是跑：

```bash
python3 scripts/sync-categories.py
```

它复刻站点那套规则并写回 App 配置，同时提示「站点有、App 没有的条目」。

> 站点的分类顺序很重要：**兜底分类（misc）必须排最后**，因为 `fallbackCategory = categories[最后一条]`。
> 页签图标是 App 自己的（`scripts/sync-categories.py` 里的 `TAB_ICONS`）。

---

## 7. 自动更新（APK 直链）

```
App 启动 → 静默查 data/update.json → 有新版就主动弹窗
        → 用户确认 → App 内流式下载 APK → 拉起系统安装界面
```

- 清单：`https://kmlab.tech/data/update.json`（`scripts/publish-update.sh` 生成）
- 版本比较：远端 `versionCode` > 本机 `kAppBuild`（`app/lib/version.dart`，**出包脚本自动生成**，跟安装包里的一致）
- 拉取失败**一律静默**（离线 / 404 / 返回 HTML 都不打扰用户）
- 安装必须走原生：MethodChannel `km/install` → `ACTION_VIEW` + `content://` URI（`FileProvider` 授权 + `FLAG_GRANT_READ_URI_PERMISSION`，`url_launcher` 给不了这个授权）
- APK 托管在 **GitHub Releases**，资产名固定 `kmlab-toolbox.apk`：
  `https://github.com/vee2046/webview_app/releases/latest/download/kmlab-toolbox.apk`（稳定直链，清单不用改）
- 发版：`./scripts/init-github.sh --release` → push main + 打 tag → Actions 自动出包 + 发 Release

---

## 8. 环境坑（真踩过的，别再踩）

| 坑 | 结论 |
|---|---|
| `Transform.rotate` 的 angle 是**弧度** | `seededTilt` 返回的是「度」→ 必须过 `tiltToRadians()` |
| Android `runJavaScriptReturningResult` 会把 JS 字符串**再 JSON 编码一层** | 解码要按「字符串→字符串→Map」多解两层 |
| `OutlineInputBorder` **硬性只支持圆角** | 主题给了椭圆角会直接断言崩（iOS 断言） |
| `io.open(p,'w')` 是**先截断再写** | 内容要先算好再写，否则格式化抛错会把文件清成 0 字节 |
| WebView 是 **PlatformView**，在原生层级里盖住 Flutter | Flutter 手势层收不到落在 WebView 上的触摸；SnackBar 会被盖住 → 用原生 Toast；边缘手势要靠页面 JS 监听回传 |
| `DoodleIcon`/`UiIcon` 的 name 是**位置参数** | `DoodleIcon(tool.icon, size: 24)` |
| **位置参数不能带默认值** | `f(String v = 'x')` 是语法错误 → 写 `f([String v = 'x'])` 或 `f({String v = 'x'})` |
| Dart 不允许类内声明 enum | 一律顶层 `enum` |
| Android 上 `flutter drive` 会卡死 | 没有 driver 消费者时 `takeScreenshot()` 永不完成 → Android 用 `flutter test integration_test/...` |
| `http.Response` 默认按 **latin-1** 解码 | 单测里带中文要加 `headers: {'content-type': 'application/json; charset=utf-8'}` |
| 图标表里没有的名字会**静默 fallback** | 之前 `refresh` 缺失 → 刷新按钮被画成网格图标。补图标时同步检查 fallback |
| 模拟器 320×640 很小 | 顶部热区在 y=24..52；小工具页第 1 行卡片图标 y≈222 |
| 拿不准坐标就用 `uiautomator dump` | 比截图量像素准得多（分类页签那种横向列表尤其准） |
| 本机 `github.com/.../releases/download/...` 返回 500 | 是本地 Fastly CDN 的问题（走 `gh-proxy.com` 正常），**不是 Release 的问题** |

---

## 9. 视觉与交互约定

- **纸片风**：牛皮纸 `#f6f1e4` + 墨线 `#2f2a24` + 不规则圆角 + 轻微倾斜角（纸片手作感）
- **分类色**按分类取，不按工具取：绿=生活习惯 / 蓝=效率清单 / 红=知识索引 / 琥珀=娱乐 / 蓝=资讯 / 紫=其他
- **图标必须是线稿 SVG**，禁 emoji；doodle 路径逐字复用 `kmlab_site/src/components/DoodleIcon.vue`
- 顶栏右侧**只留一个**图标：网格 ⇄ 列表（两页共用 `ViewPrefs`）
- 左边缘右滑 = 返回；最近页要「再划一次退出」
- 顶栏**不自动隐藏**（auto 档已改常驻）
- 工具容器 chrome 四档：`full` / `auto`（常驻精简） / `minimal`（默认） / `immersive`（真全屏 + 顶部热区）

---

## 10. 收敛原则（当前阶段最重要的一条）

> **功能已经稳定，开发过程中只做修复与收敛，不顺手开发新功能 / 新配置项 / 新开关。**

新增能力必须有明确需求，不在修 bug 的路上夹带。详见 `docs/DESIGN.md` §1.3 / D20。

「我的」页已经收敛过一次：只读展示项、假开关、纯开发信息全部去掉，留下能真操作的。

---

## 11. 提交前检查清单

```bash
cd app && flutter analyze && flutter test          # 0 issues + 全过
cd .. && ./scripts/build-android.sh               # 出包（自动升版本号）
python3 scripts/sync-categories.py                # 改了站点分类/图标才需要
./scripts/publish-config.sh && ./scripts/verify-remote-config.sh
git status --short                                # 只应有预期的改动
```

- 文档同步：`docs/DESIGN.md`（字段全表 / 决策 / 风险 / BUG 表）、`docs/STORAGE_KEYS.md`（新增工具的存储 key）、`README.md`
- 数字要对齐：章节数、决策条数、拍板条数、风险条数、BUG 条数、单测用例数
- 改了两个仓库时：`kmlab_site` 只 `git add` 具体文件（**别 `git add -A`**，那会带上你自己的私货文件）
