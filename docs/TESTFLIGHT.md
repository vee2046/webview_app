# iOS 上架 TestFlight · 逐步骤操作手册

> 这份文档是给**第一次做 iOS 上架**的人写的。
> 每一节都分成「你做什么」→「你会看到什么」→「做错了会怎样」。
>
> 全程大约 40~60 分钟（其中等 Apple 审核/处理可能要几小时到一两天）。
>
> 想直接看结论：**第 0 节**（两条路选一条）+ **第 7 节**（常见错误速查）。

---

## 第 0 节：先决定走哪条路

| | **路线 A · 自用** | **路线 B · 上架 TestFlight** |
|---|---|---|
| 适合 | 只有你自己（和家人）用 | 想给朋友 / 公开测试 / 将来上架 App Store |
| 钱 | **0 元**（用普通 Apple ID） | **99 美元/年**（Apple Developer Program） |
| 有效期 | **7 天**（过期要重装） | **90 天**（每个 build） |
| 安装方式 | Xcode 直接装到你的 iPhone | TestFlight App（App Store 里下载） |
| 需要开发者账号 | ❌ 不需要 | ✅ 需要付费账号 |
| 步骤量 | 5 步 | 40+ 步 |

**建议**：先用**路线 A** 在自己手机上跑起来（今天就能做到），确认好用之后再决定要不要花钱走路线 B。

---

# 路线 A · 自用（免费，5 步）

## A1. 检查 Xcode 已就绪

```bash
./scripts/setup-ios.sh
```

**你会看到**：6 段体检结果。若 `xcode-select` 指向 `CommandLineTools` 而不是完整版 Xcode，会红字提示 —— 加 `--fix` 让它自动修（会弹密码框）。

## A2. 在 Xcode 里登录你的 Apple ID

1. 打开 Xcode → 右上角齿轮/账号图标 → **Add an Account…**
2. 输入普通 Apple ID（**不需要**付费开发者账号）
3. 登录成功即可

> ⚠️ 普通 Apple ID 签出来的 App **7 天后会失效**，需要重新跑 A4~A5。
> 这是 Apple 的规定，不是 bug。

## A3. 把 Bundle ID 改成你自己的

1. Xcode 打开 `app/ios/Runner.xcworkspace`
2. 左侧文件树点 **`Runner`** 项目图标 → 顶部 **TARGETS → Runner** → **Signing & Capabilities**
3. **Team**：选你刚登录的 Apple ID（可能显示 `Personal Team`）
4. **Bundle Identifier**：把 `tech.kmlab.kmlabToolbox` 改成**全球唯一**的一串，例如 `com.你的名字.kmlabtoolbox`
   - ⚠️ 必须唯一。换一个别人没用过的。
   - ⚠️ 改了就和 TestFlight 路线不一致了 —— 如果你以后要上架，最好**现在就**用 `tech.kmlab.kmlabToolbox`（这也是我们默认的），普通 Apple ID 也能用这个 ID。

## A4. 连上手机并选设备

1. 数据线连 iPhone，手机上点「信任此电脑」
2. Xcode 顶部设备下拉框 → 选你的 iPhone
3. 菜单 **Product → Run**（⌘R）

**你会看到**：App 自动装到手机上并启动。

## A5. 每次要用就重装

7 天后 App 会闪退或打不开。重新 **Product → Run**（⌘R）即可。

---

# 路线 B · 上架 TestFlight

## B1. 你需要准备的东西

- [ ] **Mac**（已有）
- [ ] **Xcode 16+**（已有，16.2）
- [ ] **Apple ID**（普通账号即可）
- [ ] **付费 Apple Developer Program 账号**（99 美元/年）
  - 买的时候注意选 **Apple Developer Program**，不是「免费」那个
  - 学生在 25 美元/年，需学校验证

## B2. 注册为 Apple Developer（30 分钟，含等待审核）

1. 打开 <https://developer.apple.com/account> → 点 **Enroll now**
2. 填个人信息 → 选类型：
   - **Individual**（个人）—— 对外不显示姓名，做 App Store 时需要用 **Apple 公证 App**（Public Website Distribution）才能下载
   - **Organization**（组织）—— 需要营业执照等资质，但对外显示公司名
   - 💡 个人开发者也能上架 TestFlight，只是审核问询时身份更容易被拒
3. 提交后 Apple 会发邮件到你的 Apple ID，**点邮件里的链接完成验证**（这步不做就无法继续）
4. 登录后进入 **Certificates, Identifiers & Profiles**

## B3. 注册 App ID（5 分钟）

1. 左侧 **Identifiers** → 右上 **+** → 选 **App IDs**
2. **Description**：`kmlab Toolbox`
3. **Bundle ID**：选 **Explicit**，填 `tech.kmlab.kmlabToolbox`
4. 一路 Continue → **Register**
5. 勾选 Capability（可选，但建议开）
   - **Associated Domains** —— 我们用不上（`WKAppBoundDomains` 是 Info.plist 键，不是这个）
   - 其它都先不管

> 💡 如果你填的是 `com.你的名字.xxx`，后面 B4~B8 的 Bundle ID 都要改成一样的。

## B4. 在 App Store Connect 创建 App 记录（10 分钟 + 审核等待）

1. 打开 <https://appstoreconnect.apple.com> → 右上 **My Apps** → **+** → **New App**
2. 填表：
   - **Name**：`kmlab Toolbox`
   - **Platform**：选 **iOS**（⚠️ 一次只能选一个平台，macOS 要**单独建一条记录**）
   - **Bundle ID**：选 `tech.kmlab.kmlabToolbox`
   - **SKU**：`kmlabToolbox`（内部用，随便填但别重复）
   - **Primary Language**：简体中文
3. 点 **Create**

**你会看到**：App 详情页（带图标、名称、版本号）。

> ⚠️ **这一步之后必须重新提交 App 审核**（几小时到 1~2 天）。
> Apple 会邮件问你「这个 App 做什么的」，照实回：
> 「一个工具箱 App，内嵌多个单页小工具网页，数据全部存在本机。」

## B5. 在 Xcode 里配置签名（5 分钟）

1. Xcode 打开 `app/ios/Runner.xcworkspace`（**必须是 workspace，不是 project**）
2. 左侧点 **Runner** 项目图标 → 顶部 **Signing & Capabilities**
3. 勾上 **Automatically manage signing**
4. **Team**：选你的付费账号（不是 Personal Team）
5. **Bundle Identifier**：确认是 `tech.kmlab.kmlabToolbox`
   - 如果报「No signing certificate」，点 **Manage Certificates** → **+** → **Apple Distribution** → **Create**
6. 顶部 **PRODUCT BUNDLE IDENTIFIER** 也要一致

## B6. 改版本号并 Archive（10 分钟）

版本号在 `app/pubspec.yaml`：

```yaml
version: 0.1.0+1
#        ↑版本  ↑构建号
```

- **版本号**（0.1.0）：给用户看的，TestFlight 上显示
- **构建号**（+1）：给 Apple 看的，**每次上传必须比上次大**（1 → 2 → 3…）
  - ⚠️ 忘了加就传不上去，App Store Connect 会提示「已经上传过这个构建号」

改完保存，然后：

1. Xcode 菜单 **Product → Archive**
2. 等待（首次可能 5~10 分钟）
3. **Organizer** 自动打开 → 选刚建的 archive → 右上 **Distribute App**
4. 选 **App Store Connect** → **Upload**
5. 等它跑完（会校验签名、Swift 版本、隐私清单等）

> 💡 **比 Xcode 菜单更快的方式**（我们工程已经准备好了）：
> ```bash
> cd app && flutter build ipa
> ```
> 这条命令直接出 `.ipa`（在 `build/ios/ipa/`），但**签名证书仍需 B5 先配好**。

## B7. 开启 TestFlight 测试

1. 打开 <https://appstoreconnect.apple.com> → **My Apps** → **kmlab Toolbox**
2. 左侧 **TestFlight** 标签页
3. **内部测试（Internal Testing）**
   - 选一个 **Tester**：App Store Connect 的用户（团队成员）**不用审核**直接能用
   - 如果要用普通 Apple ID（不在团队里），走 **外部测试（External Testing）**
4. **外部测试**要点：
   - 第一次需要填 **测试信息**（测试什么、怎么测、反馈邮箱）→ 提交 **Beta App Review**
   - Apple 会人工审核，通常 **24~48 小时**
   - 通过后最多可加 **10,000 名** 测试者（但只有**首次**要审，之后每个 build 只要快速审批）
5. 点 **+** 选择刚上传的 build → 勾选 → **Add to group**

## B8. 在手机上安装

1. iPhone 上打开 **App Store** → 搜索 **TestFlight**
2. 安装 TestFlight（苹果官方 App）
3. 用你的 Apple ID 登录 → 接受协议
4. 看到 **kmlab Toolbox** → 点 **安装**
5. 之后每次有新 build，直接在 TestFlight 里点**更新**

---

## 第 7 节：常见错误速查

| 报什么 | 什么意思 | 怎么修 |
|---|---|---|
| `No signing certificate "Apple Development"` | Xcode 没找到证书 | B5 里点 **Manage Certificates** → **+** → **Apple Distribution** → Create |
| `Provisioning profile ... doesn't include signing certificate` | 证书与描述文件不匹配 | B5 勾上 **Automatically manage signing**，Xcode 会自动重建 |
| `Failed to create provisioning profile` | Bundle ID 在开发者后台没注册 | 回 B3 注册 `tech.kmlab.kmlabToolbox` |
| `Unable to find a destination matching ...` | 没选设备 | Xcode 顶部设备下拉框选 iPhone（路线 A）或选 **Any iOS Device**（路线 B 的 Archive） |
| `The bundle identifier ... is not available` | Bundle ID 已被别人占用 | 换一个（比如加一段随机后缀） |
| `Upload ... rejected: Invalid Signature` | 用的是个人（ad-hoc）证书 | 换成付费账号的 **Apple Distribution** 证书 |
| `An upload is already in progress` | 上一次上传没传完 | 等 10 分钟，或 `xcrun altool --list-apps` 看状态 |
| `This bundle is already in use` / build 号重复 | 构建号没加 | 改 `pubspec.yaml` 的 `version: 0.1.0+1` → `+2`，重跑 Archive |
| TestFlight 里看不到 build | 上传后还没处理完 | 等 5~30 分钟；App Store Connect → 活动 → 处理邮件 |
| 外部测试一直「Waiting for Review」 | Beta App Review 没提交 | 检查「测试信息」是否每一项都填了 |
| 手机上打开就闪退（路线 A） | 7 天签名过期 | 重新 ⌘R 装一次 |

---

## 第 8 节：macOS 版为什么不能走 TestFlight

**App Store Connect 一次只能给一个平台建 App 记录**（B4 那一步选的是 iOS）。

macOS 版要走的是 **Mac App Store**，是**另一条记录**、另一套审核、另一个 App ID。要上架需要：

1. 另建一条 App 记录，平台选 **macOS**，Bundle ID 用 `tech.kmlab.kmlabToolbox`（**同一个 ID 也行**，但两条记录之间不能重复上传同一个 build）
2. macOS 版要开 **App Sandbox**（已配），并且**沙箱权限**要向 Apple 申请
3. 审核标准比 iOS 松（没有 TestFlight for macOS 的外部测试通道）

**因此我们的建议**：
- 想在 Mac 上用 → 直接 `flutter build macos` 出本地包，双击即用（**不需要任何账号**）
- 想给别人用 → 走 iOS TestFlight
- 暂时不做 macOS 上架

---

## 第 9 节：一键体检

```bash
./scripts/setup-testflight.sh          # 只看现状
./scripts/setup-testflight.sh --build  # 顺便出一个 macOS 本地包
```

它会检查：Xcode 版本、`xcode-select` 指向、代码签名身份（有没有 Apple Distribution 证书）、
`.p8` API key、Bundle ID 与显示名、三份 entitlements、版本号拆解，最后列出**只能你手动做的步骤**。

---

## 相关文档

- [DESIGN.md §5.9 iOS / macOS 侧适配要点](DESIGN.md#59-ios--macos-侧适配要点)
- [README.md 快速开始](../README.md)
- `scripts/setup-ios.sh` —— iOS 工具链体检与修复
- `scripts/setup-testflight.sh` —— 上架前体检
