# kmlab Toolbox · App 设计文档

> **版本** v0.4 · 2026-11-23
> **状态** 设计已定稿 · 无待拍板项 · 可直接排期开发
> **目标平台** 🟡 **当前只做 Android** —— 暂不开通 Apple 开发者账号，iOS / macOS 的代码保留但**不发布、不投入**（见 D15）
> **品牌一致性**：图标、分类、工具名、线稿全部复用 kmlab_site；App 正式名 `kmlab Toolbox`（唯一一处刻意不照抄，见 §4.5）

---

## §1 目标与范围

### 1.1 一句话

**一个「配置驱动主界面 + WebView 承载业务」的极简 App 壳**：壳只做四件事 —— 渲染配置 / 打开 H5 / 管理导航 / 兜底异常；业务逻辑全在 H5 里。

### 1.2 目标

| # | 目标 | 验收标准 |
|---|---|---|
| G1 | 站内 7 个 H5 + 1 个外部入口全部可用 | 小工具页 8 张卡片全部能打开并正常渲染 |
| G2 | 与网页版数据打通 | 同 origin 加载，网页版攒的数据在 App 里直接可见，零迁移 |
| G3 | 不改 H5 一行代码 | h5_tools 仓库只做「旁挂」（sw.js / key 清单），不编辑既有产物 |
| G4 | 配置不发版即可改 | 改 `kmlab_site/public/data/app.json` → 重新部署 → App 下次冷启动生效 |
| G5 | 断网照常能用 | Service Worker 缓存 + 内置快照双层兜底，首屏永远有内容 |

### 1.3 不做什么（首版明确排除）

- ❌ 账号体系 / 跨设备云同步 —— 用「导出 `.json` → 系统分享 → 导入」完成换机搬运
- ❌ 后端服务 —— App 不连任何自建接口
- ❌ 改写任何 H5 的业务逻辑
- ❌ 工具内部的增删改查 UI —— 那是 H5 的事
- ❌ **iOS / macOS 的发版与维护** —— 暂不开通 Apple 开发者账号（$99/年），代码与工程保留（已跑通、已出包），但**不做签名分发、不上架、不投入**（见 D15）

### 1.4 现状快照（2026-11-23）

| 项 | 状态 |
|---|---|
| 设计 | ✅ 定稿，13 条决策 + 15 条拍板 + 11 条风险 |
| 配置 Schema | ✅ 落地（`config/app.config.json` 602 行 / 8 工具） |
| Flutter 工程 | ✅ 17 个 dart 文件，`flutter analyze` 0 issues，`flutter test` 26 passed |
| Android 实跑 | ✅ 模拟器 emulator-5554 全功能验证通过 |
| iOS 实跑 | ✅ 模拟器 D2D6D351（iPhone 16 / iOS 18.2）验证通过 —— 但**已停止投入**（D15） |
| **目标平台** | 🟡 **只做 Android**；iOS / macOS 代码保留、不发布 |
| 端上 UI 冒烟测试 | ✅ `flutter drive` 4 用例，iOS + Android 双端可跑 |
| 实跑中修掉的真 BUG | 27 个（见 §8.0） |

---

## §2 范围与边界

### 2.1 收录的 8 个入口

| # | 工具名（= `html_files.json` 的 title） | id | 加载方式 | 分类 |
|---|---|---|---|---|
| 1 | 每日喝水 | `water` | WebView 远端 | 生活习惯 |
| 2 | 打卡助手 | `checkin` | WebView 远端 | 生活习惯 |
| 3 | 药品管家 | `medicine` | WebView 远端 | 生活习惯 |
| 4 | 宝盒是怎样月光的 | `whereismoney` | WebView 远端 | 效率清单 |
| 5 | 任务管理 | `list` | WebView 远端 | 效率清单 |
| 6 | 脑力慢养 | `mindx` | WebView 远端（immersive） | 其他 |
| 7 | 通往AGI之路 - 文章分类索引 | `feishu` | WebView 远端（auto） | 知识索引 |
| 8 | 井条条 | `jingtt` | 外部 App（无 chrome） | 效率清单 |

### 2.2 不收录

| 项 | 原因 |
|---|---|
| 网页自动登录插件 | Chrome 扩展，移动端无法承载 |

`html_files.json` 共 9 条 → App 收录 8 条。

### 2.3 App 与 H5 的职责边界

| 谁 | 负责什么 |
|---|---|
| **App** | 外壳导航、配置渲染、WebView 生命周期、下载/外链/权限拦截、离线、数据备份、主题、原生 Toast |
| **H5** | 业务逻辑、业务 UI、数据读写（localStorage / IndexedDB）、业务级导出 |
| **共享契约** | storage key 命名规范 + Bridge API + 配置字段语义 |

---

## §3 术语表

| 词 | 含义 |
|---|---|
| **壳 / App** | 本工程（`webview_app`，Flutter，包名 `tech.kmlab.kmlabToolbox`） |
| **H5 / 工具** | `kmlab_site` 托管的静态页面，本质是 `h5_tools` 的构建产物 |
| **配置 / app.json** | `config/app.config.json` —— 唯一真相源，驱动整个主界面 |
| **chrome** | WebView 容器外面那层 App 自己的界面（顶栏 / 底条） |
| **origin** | 协议 + 域名 + 端口，决定 localStorage 的隔离边界 |
| **Bridge** | App 注入到页面的 `window.KM` 对象，纯增强非依赖 |
| **续接卡** | 最近页顶部的「接着干」卡片，显示上次干到哪儿 |
| **快照** | App 从 WebView 沙箱里取回的 localStorage 副本（存在 App 自己的 SharedPreferences） |
| **D1~D14** | 设计决策（§6） |
| **R1~R11** | 开发风险（§10） |

---

## §4 架构与配置

### 4.1 分层：配置 → 模型 → 渲染器，三层单向依赖

渲染层永远不直接读文件。

```
┌─────────────────────────────────────────────────────┐
│ 配置源                                                │
│  · 内置快照  assets/app.config.json                   │
│  · 远端配置  https://kmlab.tech/data/app.json         │
│  · 上次可用  last-good（SharedPreferences）            │
└───────────────────────┬─────────────────────────────┘
                        │ ① ConfigLoader
                        │   拉取 → 解析 → Schema 校验 → 字段兜底
                        │   版本闸门：schemaVersion 不兼容则拒绝
                        │   原子替换：失败保留旧配置，绝不半更新
                        │   内容嗅探：首字符必须是 {（防 SPA 兜底）
                        │   新鲜度闸门：generatedAt 不得早于本地（见 §4.4.1）
                        ▼
┌─────────────────────────────────────────────────────┐
│ AppConfig（不可变模型）                               │
└───────────────────────┬─────────────────────────────┘
                        │ ②
        ┌───────────────┼───────────────┬──────────────┐
        ▼               ▼               ▼              ▼
  HomeRenderer   ToolResolver   SettingsRenderer   WebView 容器
  首页/搜索/筛选  URL/副本/打开   设置项与开关        远端/离线/兜底
```

### 4.2 配置顶层结构

```
config/app.config.json
├─ schemaVersion   int      必填   当前恒为 1；不认识的更高版本直接拒绝
├─ generatedAt     string   必填   本份配置的生成时间（ISO-8601），用于新鲜度保护（见 §4.4.1）
├─ app
│  ├─ id / name / appName / brandSub / pageTitle / icon / brand / tagline
│  ├─ theme / allowThemeOverride
│  ├─ brandSource   object   逐项写明来自 kmlab_site 的哪个文件（溯源）
│  ├─ icons         object   doodle 白名单 + 默认图标
│  ├─ tabs[]        array    筛选页签（**唯一真相源**，复用 kmlab_site 四大分类）
│  ├─ bottomNav[]   array    最近 / 小工具 / 我的
│  ├─ recent        object   最近页内容开关与时间线分组
│  ├─ home          object   小工具页布局（列数 / 搜索 / 角标）
│  └─ storageManifest string 指向 docs/STORAGE_KEYS.md
├─ remote          object   远端配置开关 / 地址 / 超时 / 签名要求
├─ tools[]         array    8 个工具（id / 标题 / 图标 / 分类 / URL / open / resume）
├─ webview         object   容器行为（UA / 权限 / 缓存 / chrome / 溢出菜单 / 数据传输）
├─ bridge          object   window.KM 的白名单与超时
└─ about           object   版本 / 仓库 / 站点
```

> ⚠️ 顶层**没有** `tabs[]` —— 分类的唯一真相源是 `app.tabs[]`。历史版本残留过一个顶层 `tabs[]`（id 是 `all/life/work/learn/family`），与工具引用的 `tab` 值（`life/productivity/knowledge/misc`）对不上，已删除。

### 4.3 字段全表

#### app

| 字段 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `app.id` | string | `kmlab-toolbox` | 逻辑 id |
| `app.name` | string | `kmlab` | **品牌 token**，App 内品牌区大字（与站点 `site.name` 同源） |
| `app.appName` | string | `kmlab Toolbox` | **App 正式名**：桌面图标标签 / 任务标题 / 关于页。纯英文，不与站点混排 |
| `app.brandSub` | string | `handmade workspace` | 品牌副标（站点 `header.brandSub`） |
| `app.pageTitle` | string | `kmlab · 工具` | 站点 `<title>`，**仅作溯源**，不用于 App 名 |
| `app.icon` | string | `assets/icon.svg` | App 图标（= 站点 favicon） |
| `app.brand` | string | `kmlab` | 品牌标识 |
| `app.tagline` | string | `打开就能干活` | 一句话说明 |
| `app.theme` | string | `paper` | 主题 token |
| `app.allowThemeOverride` | bool | `true` | 允许用户在「我的」里切深色 |
| `app.tabs[]` | array | — | 筛选页签：`all/life/productivity/knowledge/misc` |
| `app.bottomNav[]` | array | — | 底部三项导航 |
| `app.recent.*` | object | — | 最近页开关，见 §5.1 |
| `app.home.*` | object | — | 小工具页布局 |
| `app.brandSource.*` | object | — | 7 项溯源声明 |
| `app.icons.names[]` | array | 9 个 | doodle 白名单，越界回退 `box` |
| `app.storageManifest` | string | — | 存储 key 清单文件路径 |

#### tools[]

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | string | 唯一标识，Bridge `KM.openTool` 用它跳转 |
| `title` / `subtitle` | string | 卡片上的两行字（title = 站点 `html_files.json` 原名） |
| `icon` | string | doodle 名（9 个之一） |
| `color` | string | 兜底色；**实际按分类取色**（`app.tabs[].color`） |
| `tab` | string | 所属分类 id |
| `url` | string | H5 地址 |
| `offline` | object | 离线副本开关 / 路径 / 大小 |
| `open.titleBar` | bool | 是否显示标题 |
| `open.pullToRefresh` | bool | 是否支持下拉刷新 |
| `open.chrome` | string | `full` / `auto` / `minimal` / `immersive` / `none` |
| `open.routeBackEnabled` | bool | 默认 `false`（不接管页面内路由） |
| `open.backFallback` | string | `home`（回最近页）/ `exit`（退出 App） |
| `open.overflowItems[]` | array | ⋯ 菜单项，**既是白名单也是顺序** |
| `resume.enabled` | bool | 是否参与续接卡 |
| `resume.mode` | string | `storage` / `bridge` / `none` |
| `resume.storageKeys[]` | array | 需要读取的 localStorage key |
| `resume.extract` | object | 摘要算法（见 `docs/STORAGE_KEYS.md`） |
| `resume.idb` | object | IndexedDB 引用（`name` / `store`） |
| `featured` | bool | 是否进「推荐」位 |
| `sort` | int | 排序权重，越小越靠前 |
| `enabled` | bool | 是否上架 |

#### webview

| 字段 | 默认 | 说明 |
|---|---|---|
| `userAgentSuffix` | `" KMApp/1.0"` | 追加到 UA 尾部 |
| `openExternalLinksInBrowser` | true | 站外链接跳系统浏览器 |
| `interceptDownloads` | true | 接管下载 |
| `downloadExtensions[]` | 31 项 | 命中即按「下载」处理，不当页面导航 |
| `handleHardwareBack` | true | 硬件返回键由 App 处理（false → 不接管，交给系统） |
| `routeBackEnabledDefault` | false | 逐工具默认值 |
| `backFallbackDefault` | `home` | 逐工具默认值 |
| `errorRetryInWebview` | true | 出错时允许页内重试（false → 只留「用浏览器打开」） |
| `chrome.default` | `minimal` | 全局默认档位 |
| `chrome.options[]` | 4 档 | 可选档位 |
| `chrome.immersiveRevealGesture` | `edge-swipe-down` | 沉浸式唤出方式 |
| `chrome.immersiveTopHotZonePx` | 28 | 顶部热区高度（px） |
| `chrome.immersiveFallbackButton` | true | 是否留兜底按钮 |
| `chrome.hideSystemBars` | false | 是否连系统状态栏一起藏 |
| `chrome.keepProgressBarInImmersive` | false | 沉浸式下是否保留进度条 |
| `overflow.sheetStyle` | `grouped` | Action Sheet 分组样式 |
| `overflow.confirmDanger` | true | 危险项二次确认 |
| `overflow.defaultItems[]` | 11 项 | 全局默认菜单项 |
| `dataTransfer.exportFormat` | `json` | 导出格式 |
| `dataTransfer.exportFileName` | `km-{toolId}-backup-{yyyyMMdd}.json` | 文件名模板 |
| `dataTransfer.exportDelivery` | `share` | 交付方式（系统分享面板） |
| `dataTransfer.clipboardFallback` | true | 分享失败时退剪贴板 |
| `dataTransfer.importEnabled` | true | 是否允许导入 |
| `dataTransfer.importMaxSizeMb` | 10 | 导入大小上限 |
| `dataTransfer.importConflictPolicy` | `confirm` | 同名 key 冲突策略 |
| `dataTransfer.importMergeStrategy` | `mergeByKey` | 合并策略 |

#### bridge / remote / about

| 字段 | 默认 | 说明 |
|---|---|---|
| `bridge.enabled` | true | 是否注入 `window.KM` |
| `bridge.namespace` | `KM` | 全局命名空间 |
| `bridge.timeoutMs` | 1500 | 调用超时 |
| `bridge.permissions[]` | 7 项 | 能力白名单，未声明的能力**根本不暴露** |
| `remote.enabled` | true | 是否拉远端 |
| `remote.configUrl` | `https://kmlab.tech/data/app.json` | 远端地址 |
| `remote.timeoutMs` | 8000 | 超时 |
| `remote.refreshOnLaunch` | true | 冷启动拉一次 |
| `remote.hotReload` | false | 运行中热重载（未启用） |
| `remote.requireSignature` | false | HMAC 校验（预留） |
| `about.version` | `0.1.0` | 版本号 |
| `about.repo` / `about.site` / `about.note` | — | 仓库 / 站点 / 备注 |

### 4.3.1 刻意不提供的 WebView 能力（配置里为什么没有这些开关）

「配置即契约」这条规矩在这套工程里踩过 4 次同样的坑（BUG #13 `pullToRefresh`、#18 空壳按钮、#19 `interceptDownloads`、#22 `auto` 档）——
**配置里写了一个开关，代码里却从来没读过它**，于是「改配置就能改行为」是假的。

所以做了两件事：

**① 逐字段审计**：把 `config/app.config.json` 的全部叶子路径（332 条）跟 `app/lib/**/*.dart` 里的 `json['…']` 读取点做比对，
找出「声明了但代码里找不到」的字段。首轮结果只有 4 个：3 个是 `app.brandSource.*`（溯源声明表，UI 只展示了 1 项），
1 个是 `webview.allowUniversalAccessFromFileUrls`。

**② 该删的删、该做的做**：

| 被删的开关 | 为什么删 |
|---|---|
| `javascriptEnabled` / `domStorageEnabled` | 恒为 true，且平台默认就是开的（Android 端 `AndroidWebViewController` 内部固定 `setDomStorageEnabled(true)`；iOS 非 ephemeral data store 默认开）。**关不掉** ⇒ 开关是假的 |
| `databaseEnabled` | WebStorage 配额，`webview_flutter` 没有暴露对应 API |
| `allowFileAccess` / `allowContentAccess` | 同上，平台 API 未暴露；而且 App 从不加载 `file://` / `content://`，永远用不上 |
| `allowUniversalAccessFromFileUrls` | 同上，而且是**危险开关**（允许 `file://` 页面跨域读资源）—— 配置里留一个永远不生效的危险开关，最容易误导人 |
| `mediaPlaybackRequiresUserGesture` | 平台 API 未暴露 |
| `cacheMode` | 平台 API 未暴露（`webview_flutter` 只提供 `clearCache()`，不是缓存策略） |

**留下的两个开关都真做了**：

| 开关 | 行为 |
|---|---|
| `handleHardwareBack` | `true`（默认）→ `PopScope(canPop: false)`，返回键由 App 处理，走 `backFallback`（§5.5）。`false` → `canPop: true`，**不接管**，交给系统默认行为（弹掉当前路由，退回上一页） |
| `errorRetryInWebview` | `true`（默认）→ 出错兜底页给「重试」+「用浏览器打开」两个出口。`false` → 只留「用浏览器打开」（页面本身已失效时，重试多少次都没用） |

> 结论：**配置里只放真正能改行为的开关。** 想加新开关，先确认代码里已经有对应的执行点，
> 否则就别写进配置 —— 假开关比没有开关更糟。

### 4.4 校验规则

远端配置进来时按顺序过这几道闸门，任何一道不过就**整份拒绝、沿用本地**：

| 闸门 | 规则 | 不过时的行为 |
|---|---|---|
| 状态码 | 必须 200 | 静默降级 |
| **内容嗅探** | body 首字符必须是 `{` | 静默降级（记日志，不报错） |
| schemaVersion | 必须 ≤ 当前支持的版本 | 拒绝 |
| 结构 | 根节点必须是对象；`tools` 不能为空数组 | 拒绝 |
| **签名** | `requireSignature` 时校验 HMAC-SHA256 | **拒绝**（已实现，见 §4.4.2） |
| **新鲜度** | `generatedAt` 不得早于本地 | 拒绝（见 §4.4.1） |

> ⚠️ **内容嗅探为什么必须有**：kmlab.tech 是静态托管的 Vue SPA，访问任何不存在的路径都返回 **HTTP 200 + `index.html`**。只看状态码 → 远端配置永远不会失败也永远不会生效，日志还会刷一片 `FormatException: Unexpected character (at character 1) <!doctype html>`。这是实跑踩出来的第一课。

### 4.4.1 配置新鲜度保护（`generatedAt`）

**问题**：站上 `dist/` 是构建产物，发布滞后很常见。一旦线上跑的是旧配置，会把 App 刚修好的功能**打回去**。

> 实测：站上 `dist/data/app.json` 还是旧的 `kind:"count"`，而 App 内置的已经是 `kind:"countDateMap"` → App 拉远端一覆盖，续接卡立刻又变回「还没开始」。

**做法**：每份配置顶层带 `generatedAt`（ISO-8601）。`ConfigStore.refresh()` 在替换前比时间戳：

| 情况 | 处理 |
|---|---|
| 本地还没有配置（首启） | 放行 |
| 远端缺 `generatedAt`（旧版或手工改动） | **拒绝** —— 「远端配置缺少 generatedAt，已沿用本地配置」 |
| 远端 `generatedAt` 早于本地 | **拒绝** —— 「远端配置比本地配置旧，已沿用本地配置」 |
| 远端 `generatedAt` 不早于本地 | 放行，原子替换 + 写 last-good |

被拒时记 `lastError` 并打日志，**不覆盖** `_config`。

**发布侧配套**：`scripts/publish-config.sh` 在检测到「配置内容真的变了」时才盖新时间戳，且时间戳取 **`max(当前 UTC 时间, 上一版 + 1 秒)`** —— 保证单调递增，即使机器时钟不准、或上一版被人手写成了未来时间，也不会出现「新配置比线上还旧 → 被拒绝」的坑。

### 4.4.2 远端配置签名（HMAC-SHA256）

**问题**：`remote.requireSignature` 这个开关之前是**纯装饰** —— 模型读了、UI 显示了、「我的」页里还有个能拨的开关，但**没有任何一行代码校验过签名**。按下开关什么也不会发生。

> 这跟 BUG #23 那一族（8 个假开关）是同一个病：**配置里声明了能力，代码里没实现**。假开关比没有开关更糟 —— 运营会以为改它有用。

**做法**：远端配置的顶层带一个 `signature` 字段 = `HMAC-SHA256(密钥, 规范化JSON)`。

| 环节 | 规则 |
|---|---|
| 规范化 | 键按字典序排序、无多余空白、中文不转义、排除 `signature` 字段本身 |
| 密钥 | `kmlab-h5-config-2026-v1`，编译进 App（可用环境变量 `KMLAB_CONFIG_SECRET` 覆盖签发侧） |
| 比对 | **定长比较**（`_constantTimeEquals`），避免通过比较耗时侧信道泄漏 |
| 签名开关的来源 | **必须取自本地配置**，不能取自远端自己 —— 否则远端把开关关掉就等于免检 |
| 只能加严 | 配置强制为 `true` 时，用户在「我的」页**关不掉**这个开关；本机可以额外加严，但不能放松 |

**发布侧**：`scripts/sign-config.sh` 用 python 侧的 `canonical()`（与 Dart 侧逐字节一致）算签名，`scripts/publish-config.sh` 在盖完 `generatedAt` 之后、复制副本之前自动签。

**跨语言一致性怎么保证**：`app/test/config_signature_test.dart` 有一组「真实配置文件」用例 —— 用 **Dart 侧**的验签去校验 **python 侧**签出来的 `config/app.config.json`。两边规范化规则差一个字节，这条测试就红。

**威胁模型（诚实版）**：

| ✅ 防 | ❌ 不防 |
|---|---|
| CDN / 静态托管被误改、被劫持 | 定向逆向（密钥编译进 App 包，能被提取） |
| 运营手滑发布了没签名的文件 | 能改 App 的人（他本来就能改行为） |
| 中间人替换响应体（HTTPS 证书被绕过时） | —— |

> 真要做到「防定向逆向」，得用**非对称签名**（服务端私钥签、App 内置公钥验）。那是 M4 之后的事。

### 4.4.3 配置 diff：让热更「可审」

**问题**：远端配置可以在 App 不发版的情况下被运营改掉。方便，但**「改了什么看不见」** —— 用户遇到行为变化只会觉得「App 是不是坏了」，运营也复现不了「线上到底是哪一版」。

**做法**：`ConfigDiff.between(旧配置, 新配置)` 算出一份人类可读的差异清单。

| 环节 | 规则 |
|---|---|
| 差异算在哪层 | **模型的 `toJson()`** —— 只列「人关心的字段」，模型不认识的字段天然看不见 |
| 列表怎么对齐 | 按 `id` 对齐（`tools` / `tabs` / `bottomNav` 都有 `id`）—— 调换顺序不算变化，改标题只算一条 |
| 展示在哪 | ① 「我的 → 配置」里可展开的差异面板（最多 20 条）② 手动刷新配置后弹对话框列出差异 |
| 算法 | `ConfigDiff.diffMaps` 是纯 JSON 树差异的算法本体，可单独测试 |

> ⚠️ 原先一键刷新只弹「配置已更新」四个字 —— 对用户零信息量。现在改成直接列出改了什么。

### 4.5 品牌与命名一致性（复用 kmlab_site）

**原则**：App 不是「另一个品牌」，而是 kmlab_site 的**移动端形态**。所有可复用的东西都从 kmlab_site 直接搬，不另起一套。

#### 与 kmlab_site 的对应关系

| App 里 | kmlab_site 的来源 | 具体取值 |
|---|---|---|
| `app.name` | `site.content.json → site.name` | `kmlab` |
| `app.brandSub` | `site.content.json → header.brandSub` | `handmade workspace` |
| `app.pageTitle` | `index.html → <title>` | `kmlab · 工具`（仅溯源） |
| `app.appName` | **App 自有（无站点来源）** | `kmlab Toolbox` ← 唯一刻意不照抄 |
| `app.icon` | `public/favicon.svg` | 牛皮纸方块 + 红挂件 + 蓝三横线 |
| `app.tabs[].id/title/color` | `site.content.json → categories[]` | 生活习惯(绿) / 效率清单(蓝) / 知识索引(红) / 其他(紫) |
| `app.icons.names` | `DoodleIcon.vue` 的分支名 + `doodleDefault` | checkin / water / money / pill / key / note / rocket / brain + 默认 box |
| `tools[].icon` | 同上，按标题关键词匹配 | 喝水→water · 打卡→checkin · 月光→money · 药品→pill · 任务→note · AGI→rocket · 脑力→brain · 记账→money |
| `tools[].title` | `public/data/html_files.json → title` | 8 个工具原名照搬 |
| `tools[].tab` | 站点的分类关键词规则 | 同上 4 个分类 |
| 底部导航第二项 | `site.content.json → projects.navLabel` | `小工具` |
| 未纳入 App | `html_files.json` 的「网页自动登录插件」 | Chrome 扩展，移动端无法承载 → 不进 App |

#### 八个工具的完整对照

| id | title | subtitle | icon | 分类 | 色 | chrome |
|---|---|---|---|---|---|---|
| `water` | 每日喝水 | 饮水记录与提醒 | water | life | 绿 | minimal |
| `checkin` | 打卡助手 | 每日益处 · 健康打卡 | checkin | life | 绿 | minimal |
| `medicine` | 药品管家 | 还能用几天 · 何时该买 | pill | life | 绿 | minimal |
| `whereismoney` | 宝盒是怎样月光的 | 语音记账 · 飞书备份 | money | productivity | 蓝 | minimal |
| `list` | 任务管理 | 待办任务清单 | note | productivity | 蓝 | minimal |
| `mindx` | 脑力慢养 | 找一找 · 数口令 | brain | misc | 紫 | **immersive** |
| `feishu` | 通往AGI之路 - 文章分类索引 | 文章分类索引 | rocket | knowledge | 红 | **auto** |
| `jingtt` | 井条条 | 外部 App | money | productivity | 蓝 | **none** |

#### 三条硬规矩

1. **颜色按分类取，不按工具取** —— 同一分类的卡片同色，一眼能看出「这是一类」
2. **图标必须是线稿 SVG，不能用 emoji** —— 且路径逐字复用 `DoodleIcon.vue`
3. **卡片旋转角必须各不相同** —— 用 `seededBetween` 稳定伪随机（Flutter 侧对应 `seededTilt(seed)`）

#### 关于 App 正式名

站点的 `<title>` 是「**kmlab · 工具**」—— 中英混排。放到桌面图标标签上（宽度只有几个字）既别扭又不统一。

所以 App 侧**刻意**改成纯英文 **`kmlab Toolbox`**：

- 保留 `kmlab` 品牌 token —— 图标、分类色、工具名、线稿全都跟站点一一对应，改成「工具箱」会让 App 看起来像另一个产品
- 纯英文 —— 解决中英混排的问题
- 作为产品名比连写的 `kmlabtoolbox` 更正式

这是 D14 里**唯一一处不照抄**的地方。`app.brandSource.pageTitle` 仍然记录站点原值，便于以后对齐。

---

## §5 容器与页面


#### App 里的品牌图标（`app.icon`）

| 位置 | 展示 |
|---|---|
| 小工具页顶栏 | favicon 32px + 「kmlab」+「handmade workspace」 |
| 我的 → 关于 | 品牌卡：favicon 44px + App 名 + 副标 + 版本角标 |
| 分享长图底部 | favicon 22px + 「kmlab Toolbox · handmade workspace」+ kmlab.tech |

路径全部取自配置的 `app.icon`（默认 `assets/icon.svg`）—— **配置即契约**，换图标只改配置、不改代码。

⚠️ 三处必须同时到位，缺一不可：
1. `assets/icon.svg`（仓库根）= 唯一真相源（= `kmlab_site/public/favicon.svg`）；
2. `app/assets/icon.svg` = 上面那份的副本（由 `scripts/generate-icons.sh` 同步）—— **必须进 pubspec 的 assets**，否则 `SvgPicture.asset` 读不到；
3. Android 桌面图标另有三条链路（传统 mipmap / 自适应 anydpi / 单色），见 BUG #28。

### 5.1 底部导航与首屏

底部三项：**最近 | 小工具 | 我的**（「小工具」取自站点 `projects.navLabel`）。

| ① | 最近 | 首屏（`app.recent.isDefaultTab=true`） |
|---|---|---|
| | | 续接卡 + 常用置顶 + 时间线 |
| ② | 小工具 | 搜索 + 分类页签 + 网格卡片 |
| ③ | 我的 | 外观 / 配置 / 容器 / 离线与数据 / 关于 |

#### ① 最近页（首屏）

| 区块 | 开关 | 内容 |
|---|---|---|
| 问候语 | `showGreeting` | 早上好 / 中午好 / 下午好 / 晚上好 / 夜深了 + `app.brandSub` |
| 今日统计 | `showTodayCount` | 今天打开过 N 个工具 · 已连续使用 N 天 |
| 续接卡 | `showResumeCard` | 「接着干」—— 上次用的工具 + 一句状态摘要 |
| 常用 | `showPinned` | 手动置顶的工具（⋯ 菜单 →「固定到常用」） |
| 时间线 | `showTimeline` | 分组：今天 / 昨天 / 本周 / 更早，`maxTimelineItems=30` |

**首屏为什么是「最近」**：打开 App 的动作 = 「我要接着干活」，不是「我要逛工具目录」。首屏给目录 = 每次都多一次点击。

**代价与解法**：「最近」要撑得起首屏，就必须升级成一级页面（三块内容），否则内容太薄；首次安装空白 → 空状态直接给推荐工具 + 「去小工具逛逛 ›」的出口。

#### 续接卡的摘要怎么来

App 的 Dart 侧**读不到 WebView 沙箱里的 localStorage**。所以实现是：

1. 打开工具时 → `runJavaScriptReturningResult('JSON.stringify(localStorage)')` 把快照**取回 Dart 侧**并缓存
2. 最近页用缓存 + `resume.extract.kind` 算摘要

> ⚠️ 副作用：**未访问过的工具没有摘要**（显示「还没开始」）。工具被访问至少一次后摘要才出现。

六种摘要算法（`countToday` / `count` / `countDateMap` / `lastGame` / `field` / `none`）详见 `docs/STORAGE_KEYS.md`。

#### 顶栏右侧只留一个图标：网格 ⇄ 列表

「最近」页和「小工具」页的顶栏右侧**各只有一个按钮**，作用是**切换这两页数据的显示格式**（卡片 / 列表）。

| 之前 | 现在 |
|---|---|
| 最近页：齿轮 → 跳「我的」 | 最近页：网格/列表图标 → 切显示格式 |
| 小工具页：↻ 刷新配置 + 齿轮 → 跳「我的」 | 小工具页：网格/列表图标 → 切显示格式 |

- **为什么去掉齿轮**：底部导航本来就有「我的」，顶栏再放一个跳页按钮 = 功能重复 + 语义混乱（一个图标一会儿跳页一会儿刷新）。
- **「刷新远端配置」去哪了**：下沉到「我的」页（配置区块里本来就有刷新按钮）。配置本来也是启动时静默刷新的，手动刷新是低频操作。
- **两页共用同一个开关**（`ViewPrefs`）—— 同一份数据、同一套排版偏好，不给用户「两处设置」的机会。
- 详见 §5.15。

#### ② 小工具页卡片规则

- 布局默认值 `app.home.layout=grid`，列数 `app.home.columns=2`
- 卡片：42×42 圆角图标盒（doodle 24px，底色 = 分类色 16% alpha）+ 标题（2 行内）+ 副标题
- 角标优先级：`tool.badge` > `featured`→推荐 > `offline`→离线
- 搜索：匹配 title / subtitle / id
- 分类页签：`app.tabs[]` 全量渲染，「全部」= 不过滤
- 长按 → 底部抽屉：加载方式 / 离线副本 / 数据存储 / 备份数据 / 加入常用

### 5.2 chrome 四档

目标：header 与 footer 都不显示，把竖向空间 100% 让给 H5。但不能「真的什么都没有」—— 否则用户在 iOS 上（没有硬件返回键）会困死在里面。

| 档位 | 长相 | 适用 |
|---|---|---|
| `minimal`（默认） | 顶部 36px 极简栏 = `←` + `⋯`，无底部条 | 绝大多数工具 |
| `auto` | 滚动时整条栏淡出，停止 1.5s 淡回 | 长文型工具（通往 AGI 之路） |
| `immersive` | 真全屏，无 header 无 footer | 脑力慢养（游戏） |
| `full` | 完整顶栏 + 完整底条 | 需要展示 URL / 显式分享时 |
| `none` | 完全没有 chrome | 外部 App（井条条） |

**逃生通道（三条，缺一不可）**：

1. **顶部热区下滑**（iOS 必需 —— 没有硬件返回键）
2. **硬件返回键**（Android）
3. **双指下滑**（系统级）

**代价**：chrome 隐藏后加载进度条也看不见 → immersive 下用骨架屏/首屏闪屏代替；**失败兜底页在任何档位都必须保留**。

#### 三条只声明没实现的配置项（已补齐）

`webview.chrome` 里有三项以前只被解析、没有任何代码读它们：

| 配置项 | 之前的状况 | 现在的行为 |
|---|---|---|
| `auto` 档 | 早期版本会在停手后自动收起顶栏 | **已改为常驻**（D17）：很多工具的内容不满一屏，顶栏凭空消失会让人以为页面坏了 |
| `keepProgressBarInImmersive`（false） | 从未使用 —— 沉浸式下顶部仍有一条 2.5px 进度条 | 沉浸式（以及用户手动切到全屏时）默认**不显示**进度条，改由骨架屏承担加载反馈 |
| `immersiveRevealGesture`（`edge-swipe-down`） | 只解析不支持其它值 | 目前只有边缘下滑这一种，已实现（见 §5.3 ②） |

#### `auto` 档的判定必须用「当前工具」的档位

```dart
// ✅ 对：按工具自己的档位
if (widget.tool.open.isAutoChrome) { /* 注入滚动监听 */ }

// ❌ 错：用全局默认档位
if (widget.config.webview.chrome.defaultMode == ChromeMode.auto) { ... }
```

`webview.chrome.default` 恒为 `minimal`，所以上面那种写法**永远为假** → `auto` 档永远拿不到滚动脚本 → 顶栏永远不淡出（BUG #22）。判断入口统一放在 `OpenConfig.isAutoChrome` 上，并有单元测试守住。

### 5.3 实现要点（Android 实跑踩出来的）

#### ① immersive 层必须盖在 WebView 之上，不能塞进 Column

```dart
// ❌ 错误写法：Stack 全是 Positioned 子节点 → constraints.biggest 高度无界
Column(children: [
  _ImmersiveLayer(...),   // Stack(children: [Positioned(...), Positioned(...)])
  Expanded(child: WebViewHost(...)),
])

// ✅ 正确写法：immersive 层作为覆盖层浮在 WebView 之上
Expanded(
  child: Stack(children: [
    Positioned.fill(child: WebViewHost(...)),
    if (chrome == ChromeMode.immersive)
      Positioned.fill(child: _ImmersiveLayer(...)),
  ]),
)
```

**为什么会炸**（Flutter 源码）：

```dart
// RenderStack._computeSize
if (hasNonPositionedChildren) { size = Size(width, height); }
else { size = constraints.biggest; }   // ← 全 Positioned 时走这里

// RenderFlex._constraintsForNonFlexChild：Column 的非 flex 子节点只约束宽度
// → constraints = BoxConstraints(0<=w<=320, 0<=h<=Infinity)
// → constraints.biggest = Size(320, Infinity)
// → assert "A Stack requires bounded constraints from its parent" 触发
// → 整棵 Column 布局中断 → WebView 拿到 0×0
```

WebView 拿到 0×0 → `window.innerWidth = 0` → 页面内容全部不可见 → 只剩 Scaffold 的纸色。**看起来像「页面加载失败」，其实是布局炸了**。

#### ② 边缘下滑手势必须由页面自己监听

Android 上 WebView 是 **PlatformView**，在原生视图层级里比 Flutter 树更靠上 → **Flutter 叠在上面的手势层收不到落在 WebView 区域的触摸**。

所以：

```js
// 注入到页面里的脚本（KmBridge.edgeSwipeScript(zone)）
// touchstart 记录起点 → touchmove 判断 clientY <= zone 且下滑 > 36px
// → window.KmHost.postMessage(JSON.stringify({action:'edgeSwipe'}))
```

幂等标记 `window.__kmEdgeBound`。

> 实测：**Flutter 覆盖层上的按钮仍然可点**（点 `←` 能回最近页）。所以「覆盖层按钮不可点」这个猜测是错的，错的只是「落在 WebView 区域的手势」。

#### ③ 调试手段（值得记住）

**Dart VM service**（不用改代码就能看布局）：

```bash
# logcat 里找端口
adb logcat -d | grep "Dart VM service is listening"
adb forward tcp:45533 tcp:45533
TOKEN=$(curl -s "http://127.0.0.1:45533/…/getVM" | jq -r '.result.isolates[0].id')
curl "http://127.0.0.1:45533/…/ext.flutter.debugDumpRenderTree?isolateId=isolates/$TOKEN&objectGroup=dump"
```

渲染树里 `size: MISSING` + `NEEDS-LAYOUT` = 布局根本没跑完。

> ⚠️ 结果在 `result.data`（不是 `valueAsString`）；query 里 `isolateId` 的 `/` **不要** URL 编码。

**WebView DevTools 协议（CDP）** —— 直接在真机 WebView 里跑 JS：

```bash
adb shell cat /proc/net/unix | grep devtools_remote   # → webview_devtools_remote_<pid>
adb forward tcp:9333 localabstract:webview_devtools_remote_<pid>
curl http://127.0.0.1:9333/json/list                     # → webSocketDebuggerUrl
```

用 node 的全局 `WebSocket` 连上后发 `Runtime.evaluate`（`returnByValue:true`），结果在 `result.result.value`。

#### ④ SnackBar 会被 WebView 盖住

同源问题：Flutter 树里画的 SnackBar 在原生层级上被 PlatformView 遮住 → **完全看不见**。

解法：走原生 Toast 通道（§5.9）。

### 5.4 状态设计

| 状态 | 触发 | 表现 |
|---|---|---|
| 加载中 | `onProgress` 0~100 | 顶部 2.5px 琥珀色进度条（immersive 下用骨架屏） |
| 首次加载 | 尚未 `onPageFinished` | 牛皮纸骨架 + CircularProgressIndicator +「正在打开…」 |
| 加载失败 | `onWebResourceError` 且 `isForMainFrame` | 兜底页：图标「这一页没打开」+ URL + 「重试」/「用浏览器打开」 |
| 空（最近页） | 从未打开过任何工具 | 虚线圆角方块 + 工具盒 doodle +「还没有使用记录」+ 推荐位 +「去小工具逛逛 ›」 |
| 离线 | 网络不可达 | 「离线」角标 + 提示已缓存副本 |
| 深色 | 用户切换 | 全套纸片 token 换 dark 版 |

### 5.5 返回键行为（默认不接管页面内路由，可按工具开启）

**实测结论**：喝水 / 打卡 / 药品 / 月光 / 任务 / AGI 之路 —— 源码 **0 处 `pushState`、0 处 hash 路由**，确实是单页。

App 一旦接管 `goBack()`，就会和 H5 自己的路由形成**两套历史栈**，行为不可预测。「退出工具」比「退一步」更符合直觉 —— 工具在 App 里是独立页面，不是网站。

| `routeBackEnabled` | `backFallback` | 行为 |
|---|---|---|
| `false`（默认） | `home` | **回 App 根页面（最近页）** —— 顺带切底部导航到「最近」 |
| `false` | `exit` | 退出 App |
| `true` | `home` | 先 `goBack()` 退一步；无历史栈时回最近页 |
| `true` | `exit` | 先 `goBack()`；无历史栈时退出 App |

**全局默认**：`webview.routeBackEnabledDefault=false` / `webview.backFallbackDefault=home`。

**脑力慢养也不开** —— 它虽是 hash 路由 SPA（`#/game/A`~`E`、`#/records`…），但页内本就有「回到首页」按钮，不需要 App 帮它退；保持 8 个工具行为一致比给一个特例更值。

**代价**：任何多路由的 H5 都无法用系统返回键回退 —— 但这正是「默认关闭」想控制的复杂度；真需要时配置里开一个字段即可。

### 5.6 ⋯ 溢出菜单（顶栏右侧三个点）

12 个低频动作全收进**分组 Action Sheet**（底部弹出），顶栏只留一个 `⋯`。

| 组 | 动作 | 行为 |
|---|---|---|
| **页面** | `reload` | 刷新页面 |
| | `copyLink` | 复制链接 |
| | `openInBrowser` | 在浏览器中打开 |
| | `share` | 分享 |
| **显示** | `fullscreen` | 全屏浏览 ↔ 退出全屏（只改当前会话，不写回配置） |
| | `pin` | 固定到常用 ↔ 取消固定 |
| **数据** | `exportData` | 导出这个工具的数据 |
| | `importData` | 导入数据 |
| | `clearData` | 清除这个工具的数据（**危险**） |
| **独立** | `about` | 关于这个工具 |
| | `feedback` | 反馈问题（GitHub Issue） |

**逐工具裁剪**（`open.overflowItems` 既是白名单也是顺序）：

| 工具 | 项数 | 差异 |
|---|---|---|
| water / checkin / medicine / whereismoney / list / feishu | 10 | 去 `importData` |
| mindx | 9 | 去 `reload`/`pin`，加 `importData` |
| jingtt（外部） | 4 | `copyLink` / `openInBrowser` / `share` / `about` |

**规则**：

- `clearData` 必须二次确认 + 写明「只清这个工具，不影响其它工具」+ 提示先备份
- `exportData` 导出**该工具自己的**存储；App 级「导出全部数据」在「我的」页，两者不重复
- immersive 档位下**没有 ⋯ 按钮**（完全无 chrome），要靠顶部热区唤出工具栏才够得着

### 5.7 数据导入导出落地（`.json` 文件 + 系统分享面板）

**导出**：选「导出这个工具的数据」→ 生成 `.json` → 交给系统分享面板（Android `ACTION_SEND` / iOS `UIActivityViewController`）。

**为什么是文件不是剪贴板**：剪贴板只适合小段文本；工具数据动辄几十 KB，塞剪贴板既不稳又不安全（会被别的 App 读）。

**一条路走通**：发微信 / 飞书 / 邮件、存「文件」再上传网盘、AirDrop 到电脑 —— 都是系统分享面板的原生能力，不用自己造。

**换机闭环**：导出 → 传到新机 → 「导入数据」选回这个文件 → 覆盖恢复。

**文件名可配**：`webview.dataTransfer.exportFileName = "km-{toolId}-backup-{yyyyMMdd}.json"`，带工具名和时间，落到「文件」里一眼认得出。

**剪贴板只作兜底**（`clipboardFallback:true`）：分享面板被禁或用户想快速粘贴时用，容量小则提示改用文件。

**导入侧**：`importEnabled` / `importMaxSizeMb`（默认 10MB）/ `importConflictPolicy:"confirm"`（同名 key 问用户覆盖还是合并），**不静默覆盖**。

**导出内容结构**：

```json
{
  "toolId": "checkin",
  "version": "0.1.0",
  "exportedAt": "2026-11-19T08:00:00Z",
  "storage": { "checkin_records": "…" },
  "idb": { "brainfit-db": { "session_log": "…" } }
}
```

**「清除数据」的最终形态**（D13）：放在 ⋯ 的「数据」组，但用最高规格防护 —— 二次确认 + 明确写「只清这个工具，不影响其它工具」+ 弹窗里给「先导出备份」按钮 + 危险色 + 独立取消按钮。

> 🔴 实现铁律：**绝不用 `localStorage.clear()`** —— 8 个工具共用同一个 origin（`kmlab.tech`），清一次全没了。只能按 `resume.storageKeys` 逐个 `removeItem`。

### 5.8 离线双层：下拉刷新 + Service Worker

#### 两层方案对比

| | L1 · Service Worker | L2 · 内置副本打进 APK |
|---|---|---|
| origin | **不变**（仍在 `kmlab.tech`） | 变（`appassets.androidplatform.net` / `file://`） |
| 本地数据 | ✅ 与网页版共享 | ❌ **分家**，用户看不到老数据 |
| 断网可用 | ✅ | ✅ |
| 结论 | **首选** | 仅作降级，且必须显式提示「离线副本数据独立」 |

> 选 L1 的根本原因：**换 origin = 丢数据**（D1 铁律）。把副本塞进 APK 换 origin 那条路被否决。

#### SW 的设计约束

- **接管范围必须收窄**：只接管同源 GET 且 `pathname` 以 `/h5_tools/` 开头；站内 Vue SPA 本体与 `/data/*.json` 一律放行
- **缓存策略**：cache-first（命中先返回，断网秒开）+ 后台刷新缓存
- **安装容错**：`Promise.allSettled`，单个 404 不让整个安装失败
- **生命周期**：`skipWaiting()` + `clients.claim()`；激活时清掉旧版本 cache
- **注册时机**：页面加载完成后注入脚本调 `navigator.serviceWorker.register('/sw.js', {scope:'/'})`，失败静默；成功后回传 `{action:'swReady'}` → 「关于这个工具」里显示「断网可用：已缓存到本机」

> ⚠️ `list/` 与 `mindx/` 是上游构建产物不可改 —— SW 由**发布侧旁挂**（`kmlab_site/public/sw.js`），不侵入上游代码。

#### 下拉刷新（`open.pullToRefresh`）

之前只是配置里声明，实现是空的（BUG #13）。现在：

- 页面内监听「已在顶部（`scrollY<=0`）继续下拉」
- `touchmove` 里 `preventDefault()`（需 `{passive:false}`）拦掉原生回弹
- 画牛皮纸风格指示器（「下拉刷新」/「松手刷新」，inline style 用纸色 `#fbf7ec` + 墨线 `#2f2a24` + 投影）
- 超过阈值 68px 松手 → `postMessage({action:'pullToRefresh'})` → App 侧 `reload()` + 原生 Toast「正在刷新…」

#### 实跑验证结果（2026-11-20，Android 模拟器）

部署 `kmlab_site/public/sw.js` 后，逐条实测：

| 验证项 | 结果 |
|---|---|
| 线上文件 | `https://kmlab.tech/sw.js` → 200 / `application/javascript` / 3305 bytes（此前是 SPA 兜底的 `text/html`） |
| SW 注册 | CDP 的 target 列表里出现 `Service Worker https://kmlab.tech/sw.js`；`getRegistration().active.state = activated` |
| 页面被接管 | `navigator.serviceWorker.controller` 非 null；`registration.scope = https://kmlab.tech/` |
| 预缓存命中 | `caches` 里 7 个工具入口全部在（`index` / `checkIn` / `medicine` / `whereismoney` / `list` / `mindx` / `feishu`），另加 `icons/checkin.png` |
| **断网秒开** | `adb shell svc wifi disable && svc data disable` 后重新打开打卡助手 → H5 **完整渲染**（上班打卡 / 下班打卡 / 近 7 天记录全在），不是兜底页 |
| 断网取未访问过的工具 | `fetch('/h5_tools/{index,mindx/index,feishu,list/index}.html')` 在 `cache:'no-store'` 下仍全部 200（排除 HTTP cache，证明走的是 SW） |
| App 内提示 | 「⋯ → 关于这个工具」显示「**断网可用：已缓存到本机**」 |

> 结论：**L1 离线层跑通，且 origin 不变** —— 断网能用，数据依旧与网页版共享，D1 铁律不破。

### 5.9 iOS / macOS 侧适配要点

> ⏸ **本章暂缓** —— 暂不开通 Apple 开发者账号，iOS / macOS 不发布也不投入（D15）。
> 本章保留是为了**将来账号条件齐了可以直接照着做**，以及**别再踩一遍已知的坑**（尤其 BUG #27：`WKAppBoundDomains` 会打死整个 JS Bridge）。
> Android 侧不受影响 —— 本工程是 Flutter，Dart 层三端共用，Android 的功能与修复全部照常。

#### 工具链（踩过的坑，按顺序）

| # | 问题 | 现象 | 解法 |
|---|---|---|---|
| 1 | `xcode-select` 指向 CommandLineTools | `xcrun --sdk iphonesimulator` 报 `SDK "iphonesimulator" cannot be located`；Flutter 的 native-assets hook 抛 `Bad state: No element` → `Target build_hooks failed` | `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| 2 | CommandLineTools 里**只有 macOS SDK，没有 iOS 模拟器 SDK** | —— | 必须切到完整版 Xcode |
| 3 | `DEVELOPER_DIR` 环境变量 | **治标不治本** —— Xcode 内部 build script 以 `xcode-select` 为准，往 xcconfig 里加无效 | 只作命令行辅助 |
| 4 | CocoaPods | 系统 Ruby 2.6 太老，`nap` 要 Ruby ≥ 3.3 | **不需要** —— Flutter 3.47 默认走 Swift Package Manager |
| 5 | SPM 拉依赖 | `github.com` 主站不通 | **`codeload.github.com` 通** ✅ |
| 6 | 模拟器出包 | `flutter build ios --release --simulator` | **不支持** —— 模拟器只出 debug 包 |
| 7 | `simctl install` 间歇性挂死 | 一直不返回 | 重试循环（5 次，每次最长等 60s） |

#### 平台差异对照表

| 项 | Android | iOS | macOS | Dart 层处理 |
|---|---|---|---|---|
| `setUserAgent` | ✅ 可用 | ❌ 抛 `UnsupportedError` | ❌ 抛 `UnsupportedError` | 用 `defaultTargetPlatform == TargetPlatform.android` 守卫 |
| 原生 Toast | ✅ `Toast.makeText` | ❌ 无系统 Toast | ❌ 无系统 Toast | iOS 侧自绘 UILabel 浮层、macOS 侧自绘 NSTextField 浮层；统一走 `NativeToast.show()` |
| SnackBar 被 WebView 盖住 | ❌ 被盖 | ❌ 被盖（WKWebView 同为 PlatformView） | ❌ 被盖（同上） | 都走原生通道，不靠 SnackBar |
| `clearCache` | 有 | 有 | 有 | 均可 |
| `runJavaScriptReturningResult` | **双重 JSON 编码** | 单层 | 单层 | 统一按「字符串→字符串→Map」多解两层 |
| DOM Storage | 内部固定开 | 默认非 ephemeral data store 即开 | 同 iOS | **无需平台特定调用** |
| `evaluateJavaScript`（JS 注入） | ✅ | ✅（**前提：Info.plist 不声明 `WKAppBoundDomains`**） | ✅（macOS 也没声明） | 无需特殊处理；详见下方「App-Bound Domains」 |
| Service Worker（离线） | ✅ 可用 | ❌ `navigator.serviceWorker` 是 **undefined** | ✅ **实测可用**（`object|function`，注册成功 `scope=https://kmlab.tech/`） | 探测 SW API 存不存在：iOS 报「不支持」、注册失败报「首次访问后自动缓存」、成功报「已缓存到本机」 |
| 上架沙箱 | 无 | 无 | ⚠️ **必须开 App Sandbox** | 与业务无关，但决定能不能上 Mac App Store |

> **结论**：Dart 层 **100% 三端共用**，平台差异只有三处（`setUserAgent` 的可用性、Toast 的呈现方式、macOS 的沙箱 entitlement）。

#### macOS 平台要点

| 项 | 值 / 说明 |
|---|---|
| 平台目录 | `flutter create --platforms=macos .` 生成（`lib/` 与 `pubspec.yaml` 不受影响） |
| Bundle ID | `tech.kmlab.kmlabToolbox`（与 iOS 同一个） |
| App 名 | `PRODUCT_NAME = kmlab Toolbox`（`AppInfo.xcconfig`）+ `CFBundleDisplayName` |
| **必须有**的 entitlement | `com.apple.security.app-sandbox`（不上架就没有沙箱，App Store 拒收） |
| **必须有**的 entitlement | `com.apple.security.network.client`（**不然 WebView 加载不了 kmlab.tech**） |
| **必须有**的 entitlement | `com.apple.security.files.user-selected.read-write`（「导入数据」要读用户选的文件） |
| 原生 Toast | `MainFlutterWindow.swift` 里注册 `km/toast`，自绘 NSTextField 浮层（与 iOS 同款视觉） |
| 调试 | `flutter run -d macos`（Impeller/Metal 后端）；VM service 在 127.0.0.1:<port> |
| 出包 | `flutter build macos --release` → `build/macos/Build/Products/Release/kmlab Toolbox.app` |
| 上传 | **不能**用 `flutter build` 的包直传 —— 必须走 Xcode 的 Product → Archive → Distribute App |

> ⚠️ macOS 上架必须开 App Sandbox，但沙箱里 `network.client` 和 `files.user-selected.read-write` 是**按需单独申请**的 —— 漏一个，App 能启动但 WebView 白屏 / 导入按钮没反应。

#### 🔴 App-Bound Domains：iOS 的隐形杀手（把整个 Bridge 打死的元凶）

这是 iOS 侧**最贵的一个坑**，坑了整整两轮才挖出来（见 §8.0 的 BUG #26 / #27）。

**Apple 的规则**（WebKit 官方博客 <https://webkit.org/blog/10882/app-bound-domains>）：

> Once the `WKAppBoundDomains` key is added to the Info.plist, **all WKWebView instances in the
> application default to a mode where JavaScript injection, custom style sheets, cookie manipulation,
> and message handler use is denied.**
> To gain back access to these APIs, a WKWebView can set the `limitsNavigationsToAppBoundDomains`
> flag in their WKWebView configuration.

也就是说：**只要在 Info.plist 里写了 `WKAppBoundDomains`，WKWebView 就进入「严格模式」** ——
App 往页面里注入的 JS（`evaluateJavaScript`）、`WKUserScript`、message handler 全部被拒，
除非该 frame 的域名**已被 Apple 验证**为 app-bound domain。

而「验证」需要一整套账号侧的东西：

| 步骤 | 需要什么 | 我们有吗 |
|---|---|---|
| 1. 域名进 `WKAppBoundDomains` | Info.plist 一行 | ✅ |
| 2. Associated Domains 权限 `applinks:kmlab.tech` | **付费 Apple Developer 账号 + 真机签名** | ❌ 本机 `security find-identity` = 0 个证书 |
| 3. 站点根目录 `/.well-known/apple-app-site-association` 写上本 App 的 `appID` | 能改 kmlab.tech（✅） | ✅ 文件能写，但没人验证它 |
| 4. Apple 把该域名授予本 App | 账号 | ❌ |

**⇒ 没有账号 = 声明了 `WKAppBoundDomains` 也只是「把严格模式打开，但一个域名都拿不到」。**

实测症状（iOS 模拟器日志里 WebKit 自己说的）：

```
com.apple.WebKit.WebContent  [com.apple.WebKit:Process]
  WebPage::runJavaScriptInFrameInScriptWorld: Request to run JavaScript failed with error
  Unable to execute JavaScript in a frame that is not in an app-bound domain
```

对应到我们的代码，表现是：

| 能力 | 表现 |
|---|---|
| `window.KM` 注入 | ❌ 注不进去 → 整个 Bridge 哑火 |
| `localStorage` 快照 | ❌ 读不回来 → **续接卡永远「还没开始」** |
| JS channel（`window.KmHost`） | ❌ 页面里是 `undefined` → `swReady` / `toast` 全收不到 |
| 下拉刷新 / 下载拦截 / 边缘下滑 | ❌ 全部失效 |
| **Service Worker（离线）** | ❌ **照样用不了** —— 因为域名根本没被验证（iOS 侧；macOS 未声明该键，不受影响） |

**最后一格是最讽刺的**：加 `WKAppBoundDomains` 的**初衷**就是修 iOS 离线（BUG #26），
结果**离线没修好，反而把原本好使的 Bridge 全打死了**。

**⇒ 决策：把 `WKAppBoundDomains` 从 Info.plist 里删掉。**

| 方案 | Bridge / 快照 / 下拉刷新 | iOS 离线 |
|---|---|---|
| A. 声明 `WKAppBoundDomains`（当前踩坑版） | ❌ 全废 | ❌ 也不行（域名没验证） |
| **B. 不声明（现行版）** | ✅ **全好** | ❌ 用不了（SW API 是 undefined） |
| C. 有 Apple 账号 + 完成域名验证 | ✅ 全好 | ✅ 可用 |

**选 B**：Bridge 是 App 的命脉（续接卡、Toast、分享、下拉刷新全靠它），离线是增强项。
而且 B 里的 ❌ 是**平台硬限制**，不是我们能修的；C 要等账号，不该让它挡住主线。

**将来拿到账号后怎么开 C**（写在 `Info.plist` 注释里，也写进 `scripts/setup-testflight.sh`）：

1. Xcode → Runner → Signing & Capabilities → 加 **Associated Domains** → `applinks:kmlab.tech`
2. 站点根目录放 `/.well-known/apple-app-site-association`（内容含 `appID` = `<TeamID>.tech.kmlab.kmlabToolbox`）
3. `Info.plist` 去掉注释、加回 `WKAppBoundDomains = [kmlab.tech]`
4. 真机（**不是模拟器** —— 模拟器不走域名验证）跑一次，「关于这个工具」应显示「已缓存到本机」

> ⚠️ **同一条规则也适用于 macOS**（macOS 14+ 同样有 App-Bound Domains）。
> 本项目的 `macos/Runner/Info.plist` **本来就没写这个键**，所以 macOS 侧不受影响；
> 但别手贱加 —— 加之前先读完这一节。
>
> **实测差异（很反直觉，值得记住）**：
> - **iOS**：`navigator.serviceWorker` = `undefined` ⇒ **没有离线**（平台硬限制，要开 app-bound 域名验证才有）
> - **macOS**：同样是 WKWebView、同样没声明 `WKAppBoundDomains`，但 `navigator.serviceWorker` = `object|function`，
>   `register('/sw.js')` **注册成功**（`scope=https://kmlab.tech/`）⇒ **macOS 有离线能力**
> - **Android**：SW 就绪，断网秒开（最早实测通过）
>
> ⇒ 三端的离线能力矩阵是 **Android ✅ / macOS ✅ / iOS ❌**，代码里用「启动时探测 SW API」而不是写死平台判断。

#### iOS 原生 Toast 浮层

`AppDelegate.swift` 里注册 MethodChannel `km/toast`，收到消息后：

- UILabel 墨色底 `#2F2A24`（alpha .94）+ 牛皮纸字 `#F6F1E4`
- 圆角 12
- 底部安全区上方 72pt
- 淡入 0.18s / 2 秒后淡出 0.25s 移除

#### 模拟器与真机

- 模拟器免签名；上真机需要 Development Team
- `xcrun simctl io <udid> screenshot <path>` 截图
- `xcrun simctl spawn <udid> log show --last 8m --predicate '…' --style compact` 看日志

### 5.10 端上 UI 冒烟测试通道

`flutter drive` + `integration_test` —— 一套用例，Android / iOS 双端可跑，当永久回归测试。

#### 通道怎么建的（踩了个大坑）

```bash
flutter pub add --dev integration_test     # ❌ 直接失败
```

```
Because kmlab_toolbox depends on integration_test any which doesn't support null safety,
version solving failed.
The lower bound of "sdk: '>=2.7.0 <3.0.0'" must be 2.12.0 or higher to enable null safety.
```

**根因**：Flutter 已把 `flutter_driver` / `integration_test` **搬进 SDK、不再往 pub.dev 发布**；pub.dev 上残留的 `flutter_driver` 最新版是**废弃的 0.0.1**（null-unsafe），`integration_test` 依赖它 → 求解失败。

**修法**：`pubspec.yaml` 的 dev_dependencies 必须**显式写 `sdk: flutter`**：

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
```

#### 六个用例

| # | 用例 | 断言 |
|---|---|---|
| ① | 首屏最近页能渲染 | 问候语 + 空状态文案存在 |
| ② | 小工具页能渲染出工具卡片 | 卡片数量 > 0 |
| ③ | 点开工具 → WebView 加载到远程 H5 | 兜底页文案「这一页没打开」**不出现** |
| ④ | 顶栏返回 → 回到根页面 | 回到根路由 |
| ⑤ | 离线能力被如实探测并显示 | **Android / macOS** 显示「已缓存到本机」；**iOS** 显示「此平台不支持（需域名验证）」—— **三端各自的结果都要是确定结论**，不能停在「首次访问后自动缓存」 |
| ⑥ | JS Bridge 注入成功 | 「关于这个工具」里能读到真实 URL（说明页面活着、JS 通道没被拦） |

#### 关键技术点

- `IntegrationTestWidgetsFlutterBinding` 继承 `LiveTestWidgetsFlutterBinding` → **真实异步**，测试里可直接 `await Future.delayed(...)` 等网络
- `find.text(...)` 默认 skipOffstage —— push 了新路由后旧页 Text 找不到了；诊断用 `dumpTexts(tester, tag)` 打印当前所有 Text
- 定位 SVG 图标按钮要用语义标签：`_CircleButton` 加 `Semantics(button: true, label: ...)`（back→返回 / more→更多 / close→关闭 / home→回最近页），测试里用 `find.bySemanticsLabel('返回')`
- ⚠️ **小屏上 ⋯ 溢出菜单放不下 → `find.text` 根本找不到**：Android 模拟器只有 320×640，11 个条目 + 4 个分组标题超过一屏，菜单要滚动，而 `ListView` 是懒建的 → 折叠线以下的「关于这个工具」**压根不在树里**（`Bad state: No element`）。iPhone 16（393×852）一屏放得下 → iOS 上不滚动也能找到。⇒ **同一套用例「Android 挂、iOS 过」**。解法：测试里写 `tapOverflowItem()`，找不到就先把 `ListView` 往上拖几屏再找
- ⚠️ **Android 上不能用 `flutter drive`**（BUG #17）—— 没有 driver 消费者时 `binding.takeScreenshot()` 永不完成；Android 用 `flutter test integration_test/... -d <device-id>`

#### 跑法

```bash
# iOS / macOS
flutter drive --driver=test_driver/integration_test.dart \
              --target=integration_test/app_smoke_test.dart -d <device-id>

# Android（不要用 flutter drive，会卡死 —— BUG #17）
flutter test integration_test/app_smoke_test.dart -d emulator-5554
```

> 截至 2026-11-21：**Android 6/6 通过、iOS 6/6 通过**（iOS drive 报 +7 是把 `tearDownAll` 也算进去了）。

---

### 5.11 App 级数据管理（导出全部 / 导入 / 清除全部）

「我的」页的「离线与数据」区块提供**整机级**的三件事，与单工具的 ⋯ 菜单形成两级：

| 动作 | 落地 | 说明 |
|---|---|---|
| **导出全部** | 生成 `km-all-backup-{yyyyMMdd}.json` → 系统分享面板 | 含**全部工具的 localStorage 快照** + 使用记录 + 置顶 |
| **导入** | FilePicker 选 `.json` → 校验 → 冲突确认 → mergeByKey | 单工具备份也能整个导进来（自动转换结构） |
| **清除全部** | 二次确认 + 「先导出备份」按钮 + 危险色 | 只清**这台设备**，不影响网页版 |

**导出结构**：

```json
{
  "kind": "app-wide",
  "app": "kmlab",
  "appName": "kmlab Toolbox",
  "version": "0.1.0",
  "exportedAt": "2026-11-20T08:00:00Z",
  "tools": { "checkin": { "checkin_records": "…" } },
  "usage": { "history": [ … ], "pinned": ["water"] }
}
```

**导入的两种策略**（弹窗让用户选，不静默覆盖）：

| 策略 | 行为 |
|---|---|
| **合并**（`mergeByKey`） | 导入的 key 覆盖同名，**本地独有的保留** —— 日常搬运数据用这个 |
| **完全覆盖** | 先清掉本地全部快照再写导入的 —— 换机还原用这个 |

> 为什么导入的是**快照**而不是直接写 WebView 的 localStorage：App 的 Dart 层读不到 WebView 沙箱里的 localStorage（只能靠 `runJavaScriptReturningResult` 取回快照）。所以导入后要**重新打开该工具**，WebView 才会把快照写回它的 localStorage。

**代码位置**：`lib/data/data_transfer.dart`（导出/导入/清除三个入口）+ `UsageStore.exportPayload()` / `importPayload()` / `clearAllData()`。

### 5.12 拦截层（下载 / 外链）

#### 先说清楚一个事实：拦截点不需要另造

调研 `webview_flutter_android 4.14.1` 与 `webview_flutter_wkwebview 3.27.2` 的源码后确认，**两端的目标_blank 与下载请求都会经过 `onNavigationRequest`**：

| 平台 | 机制 | 结果 |
|---|---|---|
| Android | `AndroidWebViewController` 默认就装了 `DownloadListener`，实现里调 `_handleNavigation(url, isForMainFrame: true)` | 下载请求**被当成主框架导航** → 走 `onNavigationRequest` |
| Android | `WebChromeClientProxyApi.onCreateWindow` 建临时 WebView → `shouldOverrideUrlLoading` → 转发给**主 WebViewClient** | `target="_blank"` → 走 `onNavigationRequest` |
| iOS / macOS | `onCreateWebView` 里 `isForMainFrame == false` 时 `PlatformWebView...load(request)` | `target="_blank"` **在当前 WebView 内加载** → 走 `onNavigationRequest` |

⇒ 所以不需要自研 PlatformView 拦截层（那会把复杂度放大一个量级）。真正缺的是三件事：

| 缺什么 | 后果 | 本节怎么做 |
|---|---|---|
| **下载识别** | 同源下载会把 WebView 导航到一段二进制 → 白屏坏页 | 按扩展名识别（`webview.downloadExtensions`），识别到就**不导航**，改走下载流程 |
| **`blob:` / `data:` 处理** | 之前一律 `prevent` 然后什么也不做 → 用户点了没反应 | `blob:` 让页面自己转成 `data:` 回传；`data:` 直接解码落盘 |
| **用户可见反馈** | 外链交给浏览器后 App 里「毫无反应」→ 看起来像卡死 | 每次交接都给一条原生 Toast（「已用浏览器打开 xxx」） |

#### 判定顺序（`onNavigationRequest`）

| 顺序 | 条件 | 动作 |
|---|---|---|
| ① | `blob:` / `data:` | `prevent` + 当作下载处理 |
| ② | 非 http(s)（`mailto:` / `tel:` / `sms:` / `intent:` …） | `prevent` + 交给系统（`launchUrl`）+ Toast |
| ③ | 站外 http(s)（`openExternalLinksInBrowser`） | `prevent` + 交给系统浏览器 + Toast |
| ④ | 同源但扩展名命中 `downloadExtensions` | `prevent` + 下载 |
| ⑤ | 其余 | `navigate` |

#### 三种下载来源

| 来源 | 怎么拿到字节 | 落盘 |
|---|---|---|
| 普通 http(s) | Dart 侧 `http.get` 直接下（绕开 WebView 的二进制导航） | 临时目录 → 系统分享面板 |
| `data:` URL | Dart 侧 `base64Decode` | 同上 |
| `blob:` URL | **只有页面自己读得到** → 注入 `KmBridge.blobToDataUrlScript()` 让页面转成 `data:` 再回传 | 同上 |

#### 配置项

| 字段 | 默认 | 说明 |
|---|---|---|
| `webview.interceptDownloads` | `true` | 总开关（**之前只被解析、从未被使用**） |
| `webview.downloadExtensions` | 29 个扩展名 | 刻意**不含** `html` / `json` —— 那两类多半是页面导航而不是文件 |

**代码位置**：`lib/data/downloader.dart`（下载 + 文件名消毒）+ `lib/webview/webview_host.dart`（`onNavigationRequest` 判定）+ `lib/ui/tool_detail_page.dart`（`_handleExternalLink` / `_startDownload` / `_handleBlobData`）。

### 5.13 灰度发布（两份 URL + 设备稳定分桶）

**要解决的问题**：运营改了配置想先给 10% 用户试，出问题一键回滚 —— 但**不能用「同一份配置里的一个百分比字段」来做**。

**为什么不能用一份配置**：`rolloutPercent` 写在**哪一份**配置里，决定了「我拉哪个地址」的又是那份配置本身。
写在灰度版里 ⇒ 不在灰度组的设备永远看不到这个字段 ⇒ 永远升不到 100%。递归问题。

**⇒ 必须两份 URL**：

| 字段 | 写在哪 | 含义 |
|---|---|---|
| `remote.configUrl` | **稳定版**配置 | 稳定版配置地址（绝大多数设备拉这个） |
| `remote.canaryUrl` | **稳定版**配置 | 灰度版配置地址（可选，空 = 没开灰度） |
| `remote.rolloutPercent` | **稳定版**配置 | 0~100，进灰度的设备比例 |

**设备分桶**（`lib/data/device_bucket.dart`）：
1. 首次启动生成随机 UUID → 存 SharedPreferences（`km.device.id`）→ 之后一直是同一个
2. `bucket = FNV-1a(uuid)` → **murmur3 `fmix32` 终混合** → 乘高位映射到 0~99
3. `bucket < rolloutPercent` → 走灰度地址

**踩过的三个坑**：
- `String.hashCode` 不能用 —— Dart 只保证「同一版本内一致」，跨版本可能变；灰度要求「同一设备永远同一个桶」
- FNV-1a 直接 `% 100` 分布很差（200 个 ID 只覆盖 76 个桶）—— 取模只用低位，而 FNV 的雪崩集中在低位
- 只改「乘高位映射」仍不够（覆盖降到 47 个桶）—— 最后靠 `fmix32` 终混合解决

**运营流程**：
```
publish（stable 不动） → 只发 canary → stable 配置里填 canaryUrl + rolloutPercent
   → 观察 → 全量：stable 也更新 + canaryUrl 清空（或 rolloutPercent 提到 100）
```

### 5.14 分享长图

**做什么**：把「我用了哪些工具、用了多久」做成一张牛皮纸海报（长图），一键分享到微信/小红书等。

**两个入口**：
- 工具容器 ⋯ 菜单 → **生成分享长图**（该工具的摘要）
- 我的页 → 离线与数据 → **生成分享长图**（整体使用报告）

**实现**：`RepaintBoundary` → `toImage(pixelRatio: 3)` → PNG → 临时文件 → `SharePlus` 系统分享面板。
先弹**预览弹窗**（看得见再分享），卡片固定 340 逻辑宽、视口窄时横向滚动。

**⚠️ 已知限制**：WebView 是 PlatformView，系统截图**抓不到 H5 内容** ⇒ 长图画的是 App 自己知道的数据（使用统计 + 工具摘要），不是网页截图。

---

### 5.15 视图偏好（网格 ⇄ 列表）

「最近」和「小工具」两页共享一个显示格式开关，存在 `ViewPrefs`（`app/lib/data/view_prefs.dart`）。

| 层 | 来源 | 作用 |
|---|---|---|
| 默认值 | 配置 `app.home.layout` | 用户没手动切过时跟随配置 |
| 用户选择 | 本机 `SharedPreferences`（`km.view.mode`） | 手动切过一次后以用户为准，配置再变也不覆盖 |

两页各自的表现：

| 页面 | 卡片（grid） | 列表（list） |
|---|---|---|
| 小工具 | 2 列卡片（`app.home.columns`） | 每行一个：图标 + 标题 + 副标题 + 角标 |
| 最近 | 时间线按组排 2 列卡片（图标 / 标题 / 摘要 / 时间） | 时间线按组排紧凑行（图标 + 标题 + 摘要 + 右侧时间） |

「最近」页的**续接卡**和**常用**两种排版下都一样 —— 它们本来就只有一张卡和一行小图，没有「列表 vs 卡片」之分。

#### 实现要点

- `ViewPrefs extends ChangeNotifier`，`RootShell` 用 `Listenable.merge([configStore, viewPrefs])` 一起听（两个开关都要能触发重建）。
- 配置到达时用 `setConfigDefault()` 喂默认值 —— ⚠️ **不能直接在 `build` 里调**（它会 `notifyListeners`，在 build 期间通知 = 「setState during build」）。要用 `addPostFrameCallback` 丢到下一帧。
- `setMode()` 跟**当前生效值**比而不是跟用户上次选择比 —— 没手动选过时生效值 = 配置默认值，此时 `setMode(默认值)` 应该是空操作。
- 单元测试：`app/test/view_prefs_test.dart`（8 个用例）。

---

## §6 设计决策

### D1 🔴 换 origin = 丢数据

所有工具数据在 `https://kmlab.tech` 这一个 origin 的 localStorage 里。App 若用内置副本加载（`appassets.androidplatform.net` / `file://`）就是另一个 origin → 用户网页版数据全不可见。

**决策**：默认走远端 origin；离线用「缓存副本 + 显式导入导出」补齐，不在存储层面偷换 origin。
**代价**：首次打开需一次网络。

### D2 🟢 同源共享反而是优点

老数据零迁移可见；各工具 key 本就不冲突（`baobox.v1` / `medicine_tracker_v1` / `water*`）。

### D3 🟡 配置双轨 = 与 kmlab_site 同构

内置快照 → 运行时静默拉取 → 失败降级。**实测补充**：SPA 对不存在的路径返回 200 + index.html，所以要做内容嗅探；再加 `generatedAt` 新鲜度保护（§4.4.1）。

### D4 🟣 Bridge 增强而非依赖

H5 在普通浏览器里必须原样可用。必须：`openTool`/`setTitle`/`toast`/`share`/`exportData`；可选：`vibrate`/`theme`/`track`；**禁止**让 H5 依赖 Bridge 才能跑。

### D5 🔵 职责边界

App 管外壳/配置/WebView/拦截/离线/备份/主题；H5 管业务/数据（§2.3）。

### D7 🟡 首屏 = 最近

「打开 App」=「我要接着干活」。代价：「最近」必须升级为一级页面（§5.1）。

### D8 🟡 chrome 四档

full / auto / minimal / immersive / none。immersive 必须配顶部热区下滑（iOS 无硬件返回键）。**实跑补充**：PlatformView 遮挡 → 边缘手势必须由页面 JS 监听回传（§5.3 ②）。

### D9 ✅ 技术栈 = Flutter

| 方案 | 配置渲染 | WebView 控制力 | 跨平台 | 结论 |
|---|---|---|---|---|
| Android 原生 Compose | 中等 | 最强 | 仅 Android | 只发安卓时的最优解 |
| **Flutter** | **低成本** | 中（PlatformView 桥接） | **Android + iOS** | ✅ 已定：复用 brainfit 适老设计系统 |
| Capacitor | 最自然 | 弱 | 全平台 | WebView 定制能力不够 |

理由：① 跨平台一次开发 ② 配置→Widget 映射成本最低 ③ 已有 Flutter 设计系统可直接复用 ④ 上架链路成熟。

### D10 🟡 返回键默认不接管页面内路由

`routeBackEnabled:false` → 直接回 App 根页面（最近页）；8 个工具**全部**不开（含脑力慢养）。理由与矩阵见 §5.5。

### D11 🟡 顶栏只留一个 ⋯

11~12 个低频动作收进分组 Action Sheet，逐工具裁剪（§5.6）。

### D12 🟢 导出 = `.json` 文件 + 系统分享面板

理由、文件名模板、导入策略见 §5.7。

### D13 🟢「清除数据」放在 ⋯ 菜单里

二次确认 + 写明只清本工具 + 给「先导出备份」按钮 + 危险色（§5.7）。

### D14 🟢 品牌与命名复用 kmlab_site

名称 / 图标 / 分类 / 工具名 / 线稿全部照搬；**唯一例外**是 App 正式名 `kmlab Toolbox`（站点标题中英混排）。对齐表见 §4.5。

### D15 🟡 当前只做 Android，iOS / macOS 暂缓

**结论**：迭代范围收窄到 **Android**；iOS / macOS 的代码与工程**保留**（已跑通、已出包），但**不签名分发、不上架、不投入**。

**理由**：
1. **没有 Apple 开发者账号** —— TestFlight / App Store 都要求付费的 Apple Developer Program（$99/年）。账号侧条件不齐，iOS 的一切发布动作都推不动。
2. **iOS 的离线能力本来就被账号卡住** —— WKWebView 只在「已验证的 app-bound domain」里暴露 `navigator.serviceWorker`，而域名验证（Associated Domains + 站点 AASA + 真机签名）同样需要付费账号（§5.9 / R12）。**账号是同一个卡点**。
3. **Android 侧该有的能力都已经有了** —— Service Worker 离线（实测断网秒开）、原生 Toast、下载拦截、外链交接、分享面板、灰度、签名校验、配置 diff，全都在 Android 上实跑验证过。继续投入 Android 的边际收益远高于继续修 iOS。
4. **Dart 层三端共用** —— 以后一旦账号齐了，iOS/macOS 的代码仍在、坑也已记录（§5.9），随时能捡起来，**沉没成本几乎为零**。

**代价（明说）**：
- 没有 App Store / TestFlight 分发渠道 —— Android 侧靠 **release APK 侧载**（`app-release.apk`）。
- macOS 桌面版也一并搁置（它本来也不走 TestFlight，上架要走 Mac App Store）。

**因此本仓库的约定**：
- 出包 / 验证 / 冒烟测试的**主链路只有 Android**（`./scripts/build-android.sh`、`flutter test integration_test/... -d emulator-5554`）。
- iOS / macOS 相关的脚本（`setup-ios.sh` / `setup-testflight.sh` / `run-ios-device.sh`）与文档（`docs/TESTFLIGHT.md`）**保留但标注暂缓** —— 不删，是为了将来能直接用。

---
### D17 🟢 工具顶栏**常驻**，不自动隐藏

**决定**：`auto` 档不再自动收起顶栏。顶栏一旦显示就一直在 —— 滚动不隐藏、停手不收起。

**理由**：
1. 很多工具（药品、宝盒、任务清单…）的内容**不满一屏**，顶栏凭空消失会让人以为页面坏了、以为 App 卡了。
2. 「省 44px」的收益远小于「用户以为出问题了」的代价。
3. 真需要沉浸就明说 —— 用 `immersive` 档（真全屏、顶部热区唤出工具栏），那是有明确手势的另一种模式，不是「意外消失」。

**连带清理**（不留死代码）：`webview.chrome.autoHideDelayMs`（配置 + 模型）、`OpenConfig.isAutoChrome`、`KmBridge.scrollScript`、`WebViewHost.onScrollDirection` 全部删除。

### D18 🟢 点工具卡片**不做特例**：一律进配置的 url

**决定**：删掉 `open.mode` 字段和 `external` / `browser` 两种打开方式。所有工具 —— 包括「井条条」这种本身是外部项目的 —— 点卡片都在 App 内的 WebView 里打开配置里的 url。

**理由**：
1. 同一个列表里「有的进 App、有的跳出去」= 行为不一致，用户每次都要重新判断。
2. 外部跳转还多一个中间弹窗（`_ExternalToolSheet`），多一次点击。
3. WebView 里打开外部页面一样能用，而且「在浏览器中打开」本来就留在 ⋯ 菜单里，想跳出去随时能跳。

**代价**：外部页面在 App 内打开时没有原生 App 的体验（登录态、推送等）。可接受 —— 这些页面本来就是「看一眼 / 点个链接」。

### D16 🟡 顶栏右侧只留一个图标：网格 ⇄ 列表

**决定**：最近页和小工具页的顶栏右侧**各只保留一个**按钮 = 切换显示格式（卡片 / 列表），两页共用同一个开关。移除原来的齿轮（跳「我的」）和小工具页的刷新按钮。

**理由**：
1. 底部导航本来就有「我的」—— 顶栏再放一个跳页按钮是重复入口。
2. 一堆图标里混着「跳页」和「刷新」两种语义，用户点之前得先猜 —— 这就是「功能混乱」的来源。
3. 显示格式是**排版偏好**，天然属于「同一份数据、同一套偏好」，不该分成两处设置。
4. 「刷新远端配置」下沉到「我的」页（那里本来就有），不丢功能。

**代价**：想刷新配置要多点一次（去「我的」）。可接受 —— 配置启动时本来就静默刷新，手动刷新是低频动作。

## §7 视觉规范

### 7.1 设计 token（纸片风）

| token | 浅色 | 深色 | 用途 |
|---|---|---|---|
| `--paper` | `#f6f1e4` | `#1b140e` | 页面底色（牛皮纸） |
| `--paper-deep` | `#ece4d0` | `#2a211a` | 凹槽 / 分割 |
| `--paper-card` | `#fbf7ec` | `#302619` | 卡片底 |
| `--ink` | `#2f2a24` | `#f2e8da` | 主文字 / 描边 |
| `--ink-soft` | `#6b6256` | `#b8a892` | 次要文字 |
| `--crayon-red` | `#d9534f` | 提亮 | 危险 / 知识索引 |
| `--crayon-blue` | `#3d6b8a` | 提亮 | 效率清单 |
| `--crayon-green` | `#6f9264` | 提亮 | 生活习惯 |
| `--crayon-amber` | `#d9a441` | 提亮 | 进度 / 提示 |
| `--crayon-purple` | `#8a6fa3` | 提亮 | 其他 |

线宽 `2.5px`；投影 `3px 4px 0 rgba(47,42,36,.16)`（hover `6px 10px 0 rgba(47,42,36,.14)`）。

### 7.2 五条禁忌

1. **禁 emoji 图标** —— 只用内联 SVG 线稿（且线稿直接复用 `DoodleIcon.vue` 的路径）
2. **禁彩色渐变铺底**、禁玻璃拟态 / 霓虹发光
3. **卡片旋转角必须各不相同**（`seededTilt(seed)` 稳定伪随机）
4. **手绘抖动滤镜**只用于装饰 SVG，不用于文字
5. **颜色按分类取，不按工具取**

### 7.3 字体

- 中文：`PingFang SC` → `Hiragino Sans GB` → `Heiti SC` → `Microsoft YaHei` → `Noto Sans CJK SC` → `sans-serif`
- 站点侧：中文 `ZCOOL KuaiLe`（手写）+ 英文 `Caveat` + 数字 `Kalam`，CN 环境走 `fonts.googleapis.cn`
- 数字用 `FontFeature.tabularFigures()`，避免跳动

### 7.4 响应式

| 断点 | 变化 |
|---|---|
| ≤900px | 3 列 → 2 列 |
| ≤640px | 单列 + Header 横向滚动 |

Flutter 侧：小工具页列数 `app.home.columns`（默认 2，clamp 1~3）。

---

## §8 迭代路线

### 8.0 当前进度（2026-11-23）

| 里程碑 | 状态 | 已完成 | 待做 |
|---|---|---|---|
| **M1 骨架** | ✅ | Flutter 工程 + 配置加载器 + 最近页（首屏）+ 小工具页 + 我的页 + WebView 容器（minimal/full/auto）+ 返回键 + 品牌资产（图标/分类/工具名/doodle）+ **App 正式名 `kmlab Toolbox`** + 单元测试（**146 个用例**） | ⏸ iOS / macOS 正式签名出包 —— **暂缓**（D15，当前只做 Android） |
| **M2 体验** | ✅ | **视图偏好（网格 ⇄ 列表）✅（最近页 + 小工具页顶栏右侧各只留一个图标，共用一个开关，见 D16 / §5.15）** + chrome 四档 ✅（**minimal / auto / immersive / full 全部实跑验证**；含 immersive 顶部热区边缘下滑；**auto 档已改为常驻、不再自动隐藏 —— D17**） + 续接卡摘要 ✅ + ⋯ 溢出菜单（12 动作分组）✅ + 下拉刷新 ✅ + 加载进度 ✅ + 失败兜底页 ✅ + 导出分享面板 ✅ + **App 级数据管理（导出全部/导入/清除全部）✅** + 原生 Toast 通道 ✅ + 端上 UI 冒烟测试通道 ✅ + **离线 L1 Service Worker ✅（Android 已部署并实测断网秒开；macOS 实测 SW 也可用 ✅；**iOS 需「已验证的 app-bound domain」，无 Apple 账号时如实显示「此平台不支持」**，见 §5.9 与 BUG #27）** + **拦截层（下载 / 外链）✅** + **分享长图 ✅** | 长按抽屉 · 搜索 UI 打磨 |
| **M3 生态** | 🔄 | `resume.mode: storage` 已跑通 ✅ + **脑力慢养续接卡 ✅（`lastGame` 算法，实测 `bf_progress`）** | Bridge 落地（title/toast/share/export/openTool 已写，待 H5 侧接入）· Bridge 上报通道（跨仓库，需 h5_tools 侧配合）· 常用置顶持久化 ✅（本地） |
| **M4 运营** | 🔄 | 远端配置链路 ✅ + 内容嗅探 ✅ + 新鲜度保护 ✅ + **签名校验 ✅（HMAC-SHA256，真做）** + **配置 diff 提示 ✅（热更可审）** + **灰度发布 ✅（两份 URL + 设备稳定分桶，见 §5.13）** + 三份副本同步脚本 ✅ + 远端自查脚本 ✅ | 工具上下架与推荐位 |
| **M5 扩展** | 🔄 | 深色模式 ✅ + **macOS 平台接入 ✅（出包 + 跑通 + 沙箱 entitlement）** + **分享长图 ✅（纸片风海报，见 §5.14）** | **仅剩**：TestFlight 上传 —— ⏸ **暂缓**（不开通 Apple 账号，D15；步骤已写好在 `docs/TESTFLIGHT.md`，将来账号齐了直接照做）<br>~~多语言 / 桌面 Widget / 平板手表适配~~ —— 用户明确「只要兼容手机」 |

#### 实跑中修掉的 31 个真 BUG

| # | 现象 | 根因 | 修法 |
|---|---|---|---|
| 1 | 远端配置永远不生效，日志刷 `FormatException: <!doctype html>` | 静态托管 SPA 对不存在路径返回 **200 + index.html** | `ConfigLoader.loadRemote` 加内容嗅探 `looksLikeJson(body)`（首字符 `{`），非 JSON 静默降级 |
| 2 | ⋯ 溢出菜单被截断，只显示到「显示」组标题 | `showModalBottomSheet` 没开 `isScrollControlled` | 加 `isScrollControlled:true` + `constraints: maxHeight = 0.86 * screenHeight` |
| 3 | 卡片倾斜 21° 几乎斜躺，盖住「接着干」标签 | `Transform.rotate` 的 angle 是**弧度**，`seededTilt` 返回**度** | 新增 `tiltToRadians(deg)`，PaperCard / PaperButton 两处改用 |
| 4 | localStorage 快照取不回来 | Android 的 `runJavaScriptReturningResult` 会把 JS 字符串**再 JSON 编码一层** | 按「字符串→字符串→Map」多解两层 |
| 5 | 返回键没回最近页（停在工具网格页） | `_goHome()` 只 `popUntil(isFirst)` 没切底部导航 tab | `_goHome()` 加 `setState(() => _index = _indexOf(nav, recentId))`；新增 `_exitApp()` |
| 6 | 续接卡永远「还没开始」（快照 = `{}`） | 只在 `onPageFinished`（用户还没操作）采一次快照 | `WebViewHostState` 公开化 + GlobalKey；新增 `refreshSnapshot()`；退出工具前与切后台（`didChangeAppLifecycleState` → paused/inactive）各采一次 |
| 7 | 打卡助手续接卡永远「还没开始」 | 打卡助手的 localStorage 是**按日期分组的对象** `{"YYYY-MM-DD":[{t,time}]}`，且值是**字符串**；`count` 算法假定是数组 | 新增 `ExtractKind.countDateMap` + `maybeDecode()`；`_countSummary` 的 path 语义修正为「key 那个值内部的路径」 |
| 8 | 快照存了但冷启动读不回来 | `UsageStore.load()` 根本没调用 `loadSnapshots()` | `load()` 末尾补 `await loadSnapshots();` + 剥掉 `flutter.` 前缀 |
| 9 | 远端旧配置覆盖内置新配置 | 站上 `dist` 没更新 → 拉回旧配置直接覆盖 | 顶层加 `generatedAt`；`ConfigStore.staleReason()` 在替换前比时间戳（§4.4.1） |
| 10 | immersive 档整页白屏 | 全 `Positioned` 的 Stack 塞进 Column → `constraints.biggest` 高度无界 → assert → 布局中断 → WebView 0×0 → `innerWidth=0` | immersive 层改成盖在 WebView 之上的覆盖层（§5.3 ①） |
| 11 | immersive 顶部热区唤不出工具栏 | PlatformView 在原生层级盖住 Flutter 手势层 | 边缘手势改由页面 JS 监听回传（`KmBridge.edgeSwipeScript`）（§5.3 ②） |
| 12 | Flutter 的 SnackBar 被 WebView 整个盖住 | 同上，PlatformView 在原生层级更靠上 | 新增 `util/native_toast.dart` → MethodChannel `km/toast` → Android `Toast` / iOS 自绘浮层 |
| 13 | `open.pullToRefresh` 声明了但没实现 | 只写进了配置，代码里没有 | 新增 `KmBridge.pullToRefreshScript()`（页面内监听 + 纸片风格指示器 + 阈值回传） |
| 14 | 一进小工具页就崩（iOS 断言） | `OutlineInputBorder` **硬性只支持圆角**，而主题给了椭圆角（`paperBorderRadius`） | 三个 `OutlineInputBorder` 改 `BorderRadius.circular(14)` + 补 `errorBorder` / `focusedErrorBorder`；搜索框显式给全套 `InputBorder.none` |
| 15 | iOS 桌面图标一直是 Flutter 默认 logo | `generate-icons.sh` 生成的文件名（`Icon-1024.png` / `Icon-20@2x.png`）与 `Contents.json` 引用的（`Icon-App-1024x1024@1x.png` / `Icon-App-20x20@2x.png`）**对不上** → Xcode 压根不用你生成的图 | 改成**直接读 `Contents.json`，按它列的 filename 逐个生成**（尺寸 = size × scale），共 19 个尺寸 |
| 16 | SW 缓存名变成 `kmlab-h5-kmlab-h5-v1`（前缀重复） | `VERSION = 'kmlab-h5-v1'` 又被 `CACHE = 'kmlab-h5-' + VERSION` 拼了一次 | `VERSION` 改成短串 `'v1'`（完整名由 `CACHE` 拼出），`PREFIX` 不变（仍用于清理旧版本） |
| 17 | Android 上 `flutter drive` 整个卡死（`request_data message is taking a long time`） | **没有 driver 消费者时 `binding.takeScreenshot()` 永远不会完成** —— `flutter test integration_test` 没有 driver 进程，`flutter drive` 下 Android 也要等 driver 来取数据 | `shot()` 统一加 5 秒 `timeout` + try/catch，截图彻底变成「尽力而为」；Android 改用 `flutter test integration_test` 作主 runner |
| 18 | 「我的」页的**导出全部 / 导入 / 清除全部**三个按钮点了没反应 | `RootShell` **根本没传**这三个回调，`SettingsPage` 里是 `onExportAll?.call()` —— 空调用静默失败 | 新增 `lib/data/data_transfer.dart`（导出/导入/清除三个入口）+ `UsageStore.exportPayload()` / `importPayload()` / `clearAllData()`；`RootShell` 接上回调 |
| 19 | `webview.interceptDownloads` 声明了但**从未被任何代码读取**；同源下载会把 WebView 导航到二进制 → 坏页；站外链接交出去后 App 里毫无反馈 | 下载被 Android 的 DownloadListener 当成主框架导航；`blob:` / `data:` 一律 prevent 后无下文；外链交接没有提示 | 新增 `lib/data/downloader.dart`（下载 + 文件名消毒）+ `onNavigationRequest` 五级判定（§5.12）+ `webview.downloadExtensions` 配置项 + `blob:` 走页面回传 + 每次交接给原生 Toast |
| 20 | ⋯「刷新页面」点了没反应；**「清除这个工具的数据」只清了 App 侧快照，WebView 里的 localStorage 纹丝不动**（用户重开工具数据还在）；导入数据也同步不回 WebView | `ToolDetailPage` 里声明了 `WebViewController? _controller` 但**从未被赋值** —— 控制器归 `WebViewHost` 所有，而 `WebViewHost` 收到的 `controller: _controller` 是 null，于是自己 new 了一个；`_controller` 永远是 null，所有 `_controller?.xxx()` 全是静默 no-op | 删掉 `_controller` 字段，改用 `_hostKey.currentState?.xxx()`；`WebViewHostState` 补 `runScript / canGoBack / goBack`，`reload()` 改成 `Future<void>` |
| 21 | 下载下来的文件名里的中文全变成 `_`（「月度报告.txt」→「月度报告_.txt」） | Dart 的 `\w` **只认 ASCII 词字符**，`RegExp(r'[^\w.\- ]')` 把非 ASCII 全判成非法字符 | `sanitizeFileName` 改成按 code point 遍历：`rune > 0x7f`（非 ASCII）一律保留，其余按 `^[A-Za-z0-9._\- ]$` 判断；长度截断改按 runes 列表取最后 96 个 |
| 22 | `auto`（自动隐藏顶栏）档**完全失效** —— 通往 AGI 之路的顶栏永远压着内容，从不淡出 | `webview_host.dart` 注入滚动监听时判断的是 `config.webview.chrome.defaultMode == ChromeMode.auto`，而 `webview.chrome.default` 恒为 `minimal` → 条件永远为假 → `KmBridge.scrollScript` 从未被注入 → 页面不上报滚动方向 → 顶栏不淡出 | 改用当前工具的档位判断 + `app/test/chrome_test.dart` 守住（当时修好了）。⚠️ **后来这个能力被整体删除** —— 用户反馈「很多页面不满一屏，顶栏凭空消失会让人以为页面坏了」，auto 档改为**常驻**（D17），`autoHideDelayMs` / `isAutoChrome` / `scrollScript` 一并从代码与配置里移除 |
| 23 | 配置里有一整族「声明了但代码里从没读过」的**假开关** —— 运营改了以为生效，实际毫无反应 | `webview` 块里的 `javascriptEnabled` / `domStorageEnabled` / `databaseEnabled` / `allowFileAccess` / `allowContentAccess` / `mediaPlaybackRequiresUserGesture` / `cacheMode` 在 `webview_flutter` 里**没有对应平台 API**（或恒为 true）；`allowUniversalAccessFromFileUrls` 连模型里都没有 | 逐项审计（配置叶子路径 → 扫 `app/lib` 里的 `json['…']` 读取点）→ **8 个假开关从配置与模型里同时删除**；两个真开关 `handleHardwareBack` / `errorRetryInWebview` 真做实；新增 `app/test/config_contract_test.dart` 做「配置即契约」守卫，以后再出现孤儿字段就红 |
| 24 | 脑力慢养的续接卡永远是「上一局还没打完」 | 配置写的是 `resume.mode: "bridge"`，但**没有任何 Bridge 上报通道** —— H5 侧没接，App 侧也就永远收不到 | 实测线上 bundle 摸清 `bf_progress` 的真实结构（今天没打完的那一局，H5 自己会清理过期）→ 新增 `ExtractKind.lastGame` 算法（三级降级：分数 → 步数 → 只有游戏名），`resume.mode` 改回 `storage`；游戏代码→中文名映射放进**配置**（App 不硬编码 H5 的知识） |
| 25 | 「我的 → 签名校验」开关**点了没反应**（纯装饰）；`remote.requireSignature` 在 loader 里只有一行 `TODO(M4)`，**签名从来就没被校验过** | 与 BUG #23 同一族：配置声明了能力、代码没实现。签名开关连 `onChanged` 都没有，`_Switch(on: ...)` 只是个显示 | 新增 `lib/config/config_signature.dart`（纯 Dart HMAC-SHA256，零依赖）+ `lib/config/config_diff.dart`；`parseAndValidate` 改成同时拿到原始 Map 并在 `requireSignature` 时验签，不通过 → 拒绝沿用本地；签名开关改成真开关且**只能加严不能放松**；新增 `scripts/sign-config.sh` 与 `app/test/config_signature_test.dart`（用 Dart 验 python 签的文件，锁死跨语言一致性）；顺带补上「配置 diff 提示」，让热更可审（§4.4.2 / §4.4.3） |
| 26 | **iOS 上离线（Service Worker）一直没生效** —— Android 断网秒开，iOS 断网打不开 | WKWebView 的 Service Worker **默认关闭**，iOS 14+ 需要「已验证的 app-bound domain」才暴露 `navigator.serviceWorker`。当时没配 → `register()` 静默失败 | 当时的解法（在 Info.plist 加 `WKAppBoundDomains`）**被 BUG #28 推翻**：域名没经过 Apple 验证，加了等于把整个 Bridge 打死。**现行解法**：iOS 侧如实显示「此平台不支持（需域名验证）」，离线等账号侧条件齐了再开（§5.9）；**macOS 实测 SW 可用，不受影响**；原计划的「L2 内置副本兜底」**取消**（它会换 origin，让 localStorage 与网页版分家，违反 D1 铁律） |
| 27 | 🔴 **iOS 上整个 JS Bridge 全废** —— `window.KM` 注不进去、`localStorage` 快照读不回来（续接卡永远「还没开始」）、下拉刷新 / 下载拦截 / 边缘下滑全失效、JS channel 是 `undefined` | **BUG #26 的修法引入了新问题**：在 `Info.plist` 里声明 `WKAppBoundDomains` 会让**所有** WKWebView 进入严格模式（Apple 的 App-Bound Domains 规则），拒绝 JS 注入 / 用户脚本 / message handler —— 除非域名**已被 Apple 验证**。kmlab.tech 没走 Associated Domains + `apple-app-site-association` 验证（需要付费 Apple 账号与真机签名，本机 `security find-identity` = 0 个证书）⇒ WebKit 报 `Unable to execute JavaScript in a frame that is not in an app-bound domain` | **删掉 `WKAppBoundDomains`**（Info.plist 里留注释说明为什么、以及将来怎么开）；`_injectBridge()` 的 try/catch 不再静默吞异常（改成逐步 `debugPrint` + 每段独立 try/catch + 超时）；新增 `decodeJsValue()` 修 Android 的双重 JSON 编码（否则 `state.startsWith('ready')` 永远 false）；新增 `swSupportScript` 探测 `navigator.serviceWorker` 到底存不存在，把「不支持」与「注册失败」分开；UI 如实显示「此平台不支持（需域名验证）」；**实测：Android / iOS / macOS 三端冒烟测试各 6 个用例全过**（Android 2:00 / iOS 1:28 / macOS 1:32） |

> ⚠️ 其余 `paperBorderRadius` 调用点（Container / BoxDecoration / RoundedRectangleBorder）**都支持椭圆角**，不用改 —— 只有 `OutlineInputBorder` 是雷。

| 28 | **Android 桌面图标一直是 Flutter 默认的蓝色 logo**（不是 kmlab 的 favicon） | `scripts/generate-icons.sh` 写好了但**从没在 Android 侧成功跑过** —— `res/` 里只剩 `flutter create` 生成的模板 PNG（`eb05e57` 初始提交带进来的），`mipmap-anydpi-v26/ic_launcher.xml` / `ic_launcher_foreground.png` / `ic_launcher_monochrome.png` / `values/colors.xml` **一个都没有**。而且 API 26+ 用的是自适应图标（`mipmap-anydpi-v26/ic_launcher.xml`），**只改 `mipmap-*/ic_launcher.png` 也没用** | 跑 `scripts/generate-icons.sh` 生成三层资源（传统 / 自适应前景 / Android 13 单色）+ `mipmap-anydpi-v26/ic_launcher.xml` + `values/colors.xml`；**单色层不能用 `icon.svg` 抠 alpha**（牛皮纸底不透明 → 抠出来是一整块黑方块），单独画 `assets/icon-monochrome.svg`（纯黑描边）；实机确认桌面已是「牛皮纸底 + 红 b + 蓝三线」 |

| 29 | **App 里根本没有品牌图标** —— 小工具页顶栏只有「kmlab / handmade workspace」两行字；「我的 → 关于」写着「名称 / 图标 / 分类复用 kmlab_site」，但**一个图标都没显示** | 两个真缺口：① `assets/icon.svg` **压根没进 pubspec 的 assets** → Dart 侧根本拿不到这张图；② 配置里的 `app.icon`（`"assets/icon.svg"`）**从没被任何 UI 读过** —— 模型 `fromJson` 读了所以「配置即契约」守卫查不出来，但 UI 根本没用它（死字段） | `pubspec.yaml` 加 `assets/icon.svg`；新增 `ui/widgets/app_logo.dart`（`SvgPicture.asset` + 读不到时退回工具盒 doodle，不崩）；小工具页顶栏 / 我的页「关于」品牌卡 / 分享长图品牌行三处用起来，路径全部取自 `config.app.icon`；`generate-icons.sh` 增加「把 favicon 同步进 `app/assets/`」步骤（根 `assets/` 是唯一真相源）；`config_contract_test.dart` 加两个用例 —— **资产真实存在且已进 pubspec** + **在 UI 层有使用点**（防再退化成死字段） |

| 30 | **通往 AGI 之路的顶栏几秒后凭空消失**，向上滚动才又出现 | `auto` 档的「停手 1.5s 自动收起」逻辑 —— 但**很多工具的内容不满一屏**，顶栏自己藏起来会让人以为页面坏了 | `auto` 档改为**常驻**（D17）：去掉 `AnimatedContainer` 的高度动画、去掉滚动方向监听与自动收起定时器；`autoHideDelayMs` / `isAutoChrome` / `KmBridge.scrollScript` / `WebViewHost.onScrollDirection` 一并删除（不留死代码）；实跑验证：加载完 18 秒顶栏仍在，滚动两屏后仍在 |
| 31 | 点「井条条」卡片弹「这是另一个 App，会用系统方式打开」 —— **同一个列表里有的进 App、有的跳出去，行为不一致** | 配置里 `open.mode` 有三种取值，`jingtt` 配的是 `external` → `RootShell` 里有个专门的分支弹 `_ExternalToolSheet` | 用户要求「app 类型的工具也直接进配置的 url，不做特例」⇒ **`open.mode` 整个字段删除**（配置 + 模型 + `OpenMode` 枚举 + 分支 + `_ExternalToolSheet`）；所有工具一律在 App 内 WebView 打开配置里的 url；`jingtt` 的 chrome 由 `none` 改 `minimal`；`config_contract_test.dart` 加一条钉死「配置里不许再有 `open.mode`」 |

### 8.1 跨仓库配合任务（与 h5_tools / kmlab_site）

| # | 任务 | 内容 | 状态 |
|---|---|---|---|
| P1 | 存储 key 清单 | 8 个工具各自的 localStorage / IndexedDB key 与结构 | ✅ 已交付 `docs/STORAGE_KEYS.md` |
| P2 | Service Worker 旁挂 | `list/` 与 `mindx/` 是上游产物不可改 → SW 由发布侧旁挂 | ✅ 已部署并实测：断网秒开 + origin 不变 |
| P3 | Bridge 上报接口 | `window.KM.setResumeState()` 约定 | ⏳ 未阻塞（走 storage 模式） |
| P4 | 外链白名单 | 哪些链接应跳外部浏览器 | ⏳ |
| P5 | 远端配置托管 | `kmlab_site/public/data/app.json` 纳入站内发布流程，运营改配置不发 App 版本 | ✅ 已提交 + 已部署验证 |

### 8.2 Flutter 工程结构（实际）

```
app/
├─ pubspec.yaml                 webview_flutter 4.14.1 / webview_flutter_android 4.14.1 /
│                               webview_flutter_wkwebview 3.27.2 / flutter_svg 2.2.0 /
│                               http 1.5.0 / shared_preferences 2.5.3 / path_provider 2.1.5 /
│                               share_plus 12.0.1 / file_picker 10.3.3 / url_launcher 6.3.2 /
│                               flutter_localizations  +  integration_test (sdk: flutter)
├─ assets/app.config.json       内置配置快照（= config/app.config.json）
├─ lib/
│  ├─ main.dart                 MaterialApp + ListenableBuilder 注入 + bootstrap
│  ├─ model/app_config.dart     全量不可变模型（20 个类 + 6 个枚举 + fromJson/toJson）
│  ├─ config/
│  │  ├─ config_loader.dart     内置 / 远端 / 解析校验 / 内容嗅探 / 签名校验闸门
│  │  ├─ config_store.dart      bootstrap / refresh / staleReason / last-good 持久化 / lastDiff
│  │  ├─ config_diff.dart       配置差异算法（列表按 id 对齐）
│  │  └─ config_signature.dart  纯 Dart HMAC-SHA256（零依赖）+ 规范化 JSON
│  ├─ data/
│  │  ├─ usage_store.dart       使用记录 / 置顶 / 快照缓存（SharedPreferences）
│  │  │                          + exportPayload / importPayload / clearAllData
│  │  ├─ resume_reader.dart     六种摘要算法 + maybeDecode
│  │  ├─ data_transfer.dart     App 级导出全部 / 导入 / 清除全部
│  │  ├─ downloader.dart        下载抓取 + 文件名消毒（保留中文）
│  │  ├─ device_bucket.dart     灰度分桶（FNV-1a + murmur3 终混合，稳定不漂）
│  │  └─ share_image.dart       长图抓取（RepaintBoundary → PNG）+ 系统分享
│  ├─ theme/paper_theme.dart    PaperTokens(ThemeExtension) + 纸片主题 + seededTilt
│  ├─ icons/doodle_icons.dart   9 个 kmlab doodle（内联 SVG）+ ~25 个 UI 图标
│  ├─ util/native_toast.dart    原生 Toast 通道（Android / iOS / macOS）
│  ├─ ui/
│  │  ├─ root_shell.dart        底部导航外壳（自绘 PaperNavBar）+ IndexedStack
│  │  ├─ recent_page.dart       最近页（首屏）
│  │  ├─ tools_page.dart        小工具页
│  │  ├─ tool_detail_page.dart  工具容器（chrome 四档 + ⋯ 菜单 + 导入导出）
│  │  ├─ settings_page.dart     我的页
│  │  ├─ share_preview_dialog.dart 长图预览弹窗（先看后分享）
│  │  └─ widgets/
│  │     ├─ paper_widgets.dart   PaperCard / PaperButton / PaperBadge / TapeStrip …
│  │     └─ share_card.dart      纸片风长图卡片（工具报告 / 使用报告）
│  └─ webview/
│     ├─ km_bridge.dart          window.KM 注入 + ready/scroll/edgeSwipe/pullToRefresh/snapshot 脚本
│     └─ webview_host.dart       WebView 容器 + 兜底页 + 骨架屏 + ImmersiveHotZone
├─ test/
│  ├─ resume_reader_test.dart            摘要算法单元测试（21 个用例）
│  ├─ data_transfer_test.dart            App 级数据管理单元测试（7 个用例）
│  ├─ downloader_test.dart               下载解析 / 文件名消毒单元测试（16 个用例）
│  ├─ chrome_test.dart                   chrome 档位单元测试（10 个用例）
│  ├─ lastgame_test.dart                 脑力慢养 lastGame 算法单元测试（15 个用例）
│  ├─ config_contract_test.dart          「配置即契约」守卫（5 个用例：孤儿字段 / 假开关 / 品牌溯源）
│  ├─ config_signature_test.dart         HMAC-SHA256 向量 + 跨语言验签（23 个用例）
│  ├─ config_diff_test.dart              配置差异算法（19 个用例）
│  └─ canary_test.dart                   灰度分桶与判定（17 个用例）
├─ integration_test/app_smoke_test.dart  端上 UI 冒烟测试（4 个用例）
├─ test_driver/integration_test.dart      flutter drive 入口
├─ android/app/src/main/
│  ├─ AndroidManifest.xml        INTERNET 权限 + label="@string/app_name"
│  ├─ kotlin/.../MainActivity.kt  原生 Toast 通道
│  └─ res/values/strings.xml     由 publish-config.sh 从配置生成
├─ ios/Runner/
│  ├─ Info.plist                 CFBundleDisplayName = kmlab Toolbox
│  └─ AppDelegate.swift          MethodChannel km/toast + iOS 原生 Toast 浮层
└─ macos/
   ├─ Runner/
   │  ├─ Info.plist              CFBundleDisplayName = kmlab Toolbox
   │  ├─ MainFlutterWindow.swift MethodChannel km/toast + macOS 原生 Toast 浮层
   │  ├─ DebugProfile.entitlements  沙箱 + network.client + files.user-selected
   │  ├─ Release.entitlements       同上（App Store 上架必需）
   │  └─ Configs/AppInfo.xcconfig   PRODUCT_NAME / PRODUCT_BUNDLE_IDENTIFIER
   └─ Runner.xcworkspace            Xcode 工作区（上传 App Store 用这个）
```

---

## §9 拍板结果（19 条全部已定）

> 无待拍板项 · 可直接排期开发

| # | 问题 | 结论 | 影响 |
|---|---|---|---|
| 1 | 原生壳技术栈？ | ✅ **Flutter** —— 跨平台一次开发；复用 brainfit 的适老设计系统；webview_flutter + 自研 PlatformView 拦截层 | 工程结构 / 出包链路 |
| 2 | 首版必须离线可用？ | ✅ **是** —— 双层：Service Worker 保同源离线（首选）＋ 内置副本兜底（降级） | h5_tools 需配合加 sw.js |
| 3 | 数据与网页版打通？ | ✅ **要** —— 同源天然打通，零迁移成本 | 决定加载策略（远端优先） |
| 4 | 配置远程即时生效？ | ✅ **允许热更** + 保留「回滚到上次可用」 | ConfigLoader 需原子替换 |
| 5 | 账号 / 跨设备同步？ | ✅ **首版不做** —— 用「导出 `.json` → 分享 → 导入」完成换机搬运 | 零后端依赖 |
| 6 | App 名称与图标？ | ✅ 复用 kmlab_site —— 图标 / 分类 / 工具名 / doodle 全部照搬；**App 正式名 `kmlab Toolbox`**（纯英文） | 见 D14 / §4.5 |
| 7 | 首屏落哪？ | ✅ **最近** —— 升级为一级页面（续接卡 + 常用 + 时间线） | 导航结构 |
| 8 | 容器要不要全屏？ | ✅ **四档 chrome**，逐工具指定 `open.chrome` | 容器层 |
| 9 | 全屏时连系统状态栏一起藏？ | ✅ **默认不藏**（`hideSystemBars:false`），做成用户开关 | immersive 档位 |
| 10 | immersive 怎么唤出工具栏？ | ✅ **顶部热区下滑**（iOS 无硬件返回键，必需） | 手势层 |
| 11 | `resume.storageKeys` 由谁提供？ | ✅ 与 h5_tools 对齐一份 key 清单，App 侧硬编码兜底 + 配置可覆盖 | h5_tools 子任务（P1 ✅） |
| 12 | 返回键处理页面内路由？ | ✅ **默认不接管**，逐工具开关 `routeBackEnabled`（默认 false） | 容器层 |
| 13 | 脑力慢养保留一步后退？ | ✅ **不开** —— 页内已有「回到首页」，8 个工具行为一致 | — |
| 14 | ⋯ 菜单放「清除数据」？ | ✅ **放** —— 二次确认 + 提示先导出 + 给「先导出备份」按钮 | ⋯ 菜单 |
| 15 | 导出数据落地形式？ | ✅ **`.json` 文件 + 系统分享面板**，剪贴板仅兜底 | 导出/导入模块 |
| 16 | iOS / macOS 要不要一起发？ | ⏸ **暂缓，当前只做 Android** —— 暂不开通 Apple 开发者账号（$99/年）；iOS / macOS 代码保留但不发布、不投入（D15） | 迭代范围 |
| 17 | 顶栏右侧那个图标该干什么？ | ✅ **切显示格式（网格 ⇄ 列表）** —— 最近页与小工具页共用一个开关；原来的齿轮（跳「我的」）和小工具页的刷新按钮都撤掉（D16） | 顶栏语义 |
| 18 | 工具顶栏要自动隐藏吗？ | ✅ **不要隐藏，常驻** —— 很多工具内容不满一屏，顶栏凭空消失会让人以为页面坏了；要沉浸就明说用 immersive 档（D17） | chrome 档位 |
| 19 | 「井条条」这种外部项目的卡片点了怎么办？ | ✅ **照样进配置的 url** —— 删掉 `open.mode` 与 external / browser 特例，所有工具一律在 App 内 WebView 打开（D18） | 打开方式 |

---

## §10 开发风险清单

> 每条都有缓解措施，没有「无法开工」的阻塞项

| # | 风险 | 影响 | 缓解措施 |
|---|---|---|---|
| R1 | 离线副本换 origin → 工具数据不可见 | 高 | 首选 Service Worker 保持同源；副本仅作降级，并显式提示「离线副本数据独立」+ 给导入/导出 |
| R2 | iOS WKWebView 对 Service Worker 支持有历史限制 | 中 | 启动时探测 `serviceWorker` 可用性；不可用则降级到内置副本路径并提示用户 |
| R3 | WebView 无法拦截页面内的 `window.open` / 下载 | 中 | 用 PlatformView 接管 WebChromeClient / 下载回调；`webview.*` 里逐项开关 |
| R4 | h5_tools 的 `list/` 与 `mindx/` 是上游构建产物，不能直接改 | 中 | 不编辑产物；离线包与 SW 由发布侧旁挂 `sw.js` 实现，不侵入上游代码 |
| R5 | 续接卡摘要依赖各 H5 的 localStorage 结构，尚未统一 | 中 | 先做「无摘要降级」（只显示工具名与打开时间），key 清单对齐后再开摘要（✅ 已交付 `docs/STORAGE_KEYS.md`） |
| R6 | 远端配置被篡改 | 低 | 可选 HMAC 签名校验（`remote.requireSignature`），预留未启用 |
| R7 | App 图标需各平台多尺寸位图 | 低 | ✅ **已消除** —— `scripts/generate-icons.sh` 用 ImageMagick 从 SVG 自动生成（Android 传统/自适应/单色 + iOS 全尺寸） |
| R8 | 8 个工具的 localStorage 结构各不相同，导出 JSON 难统一 | 低 | 统一包一层 `{toolId, version, exportedAt, storage:{}, idb:{}}`；导入按 toolId 分发 |
| R9 | `html_files.json` 与 `app.config.json` 两份清单可能不同步 | 低 | `app.config.json` 是 App 的唯一真相源；站内清单只作参考 |
| R10 | 远端配置发布滞后，会把 App 打回旧行为 | 中 | 配置带 `generatedAt`；远端比本地旧（或缺这个字段）一律拒绝并沿用本地（§4.4.1） |
| R11 | WebView 是 PlatformView，Flutter 盖在上面的手势层收不到落在 WebView 区域的触摸 | 中 | 需要页面内手势时由页面 JS 监听后回传，不靠 Flutter 的 `GestureDetector`；Flutter 覆盖层上的按钮仍可点（§5.3 ②） |
| R12 | **iOS 上没有离线能力** —— iOS 的 WKWebView 只在「已验证的 app-bound domain」里暴露 `navigator.serviceWorker`；没有 Apple 开发者账号就拿不到验证（**macOS 实测 SW 可用，不受影响**） | 低（**已搁置**，D15） | 如实显示「此平台不支持（需域名验证）」而不是假装能离线；Android 侧 SW 离线已实测可用；**拿到 Apple 账号后按 §5.9 的四步开 app-bound domain**（改 `Info.plist` + Associated Domains + 站点 AASA + 真机验证） |
| R13 | **Android 侧没有正式分发渠道** —— 没有 Google Play 开发者账号，release APK 只能靠侧载（传文件 / 网盘 / 微信）；且当前 `build.gradle` 里 release 用的仍是 **debug key**（`signingConfigs.getByName("debug")`） | 中 | 侧载够用，`./scripts/build-android.sh --install` 一条命令出包并装机（覆盖安装保留数据）；要上 Play 需自建 keystore（`key.properties` 放本地、不入库）；版本号用 `pubspec.yaml` 的 `version: x.y.z+build` |

---

## §11 目录结构

```
webview_app/
├─ README.md                       快速开始 / 核心思路 12 条 / 三份副本说明 / 进度表
├─ config/app.config.json          ★ 唯一真相源（唯一真相源）
├─ docs/
│  ├─ DESIGN.md                    本文件
│  ├─ STORAGE_KEYS.md              8 工具 key 清单 + 六种摘要算法 + 字符串层说明
│  └─ TESTFLIGHT.md                iOS 上架逐步骤手册（路线 A 免费自用 / 路线 B TestFlight）
├─ prototype/index.html            设计示意图（4 页签 / 4 组 / 8 手机屏，单文件无构建）
├─ assets/
│  ├─ icon.svg                     App 图标（= kmlab_site/public/favicon.svg）
│  └─ icon-foreground.svg          自适应前景层（红 b + 蓝三线）
├─ scripts/
│  ├─ build-android.sh             Android 一键出包（analyze + 单测 + APK + 可选装机）
│  ├─ publish-config.sh            三份副本同步 + 自动盖 generatedAt + 生成 strings.xml
│  ├─ verify-remote-config.sh      线上配置自查
│  ├─ generate-icons.sh            ImageMagick 生成各平台图标
│  ├─ sign-config.sh               配置签名（HMAC-SHA256，python 侧）
│  ├─ setup-ios.sh                 iOS 工具链体检 + 修复引导        ⏸ 暂缓
│  ├─ setup-testflight.sh          TestFlight 发布链路体检 + 引导   ⏸ 暂缓
│  └─ run-ios-device.sh            路线 A：免费签到自己的 iPhone    ⏸ 暂缓
│                                    （iOS / macOS 暂缓发布，见 D15；脚本保留不删）
└─ app/                            Flutter 工程 kmlab_toolbox（详见 §8.2）
```

### ⚠️ 三份配置副本必须同步

| 副本 | 作用 | 谁改 |
|---|---|---|
| `config/app.config.json` | **唯一真相源** | 开发改这个 |
| `app/assets/app.config.json` | 随 App 打包的内置快照 | `publish-config.sh` 生成 |
| `kmlab_site/public/data/app.json` | 远端配置 | `publish-config.sh` 生成，运营改这个 |

跑 `./scripts/publish-config.sh` 同步 → 提交 kmlab_site → 部署 → `./scripts/verify-remote-config.sh` 自查。

### ⚠️ `generatedAt` 必须单调递增

每份配置顶层带 `generatedAt`。**比 App 内置的旧 → 直接拒绝**。`publish-config.sh` 会在内容变化时自动盖上 `max(现在, 上一版+1秒)`，别手写。
