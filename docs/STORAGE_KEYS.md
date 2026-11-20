# 存储 key 清单（P1 交付物）

> **这份清单是 App 侧读 localStorage 的唯一依据。**
> 所有 key 都是**实测**出来的 —— 方法是直接扫 `h5_tools` 仓库的**构建产物**（产物即线上真实运行的东西），
> 不是照着源码猜的。
>
> ⚠️ 命名规范现存问题（见 §4）：喝水无版本号；驼峰/蛇形/点号/短横四种风格混用；全部无命名空间。
> 因为 App 与网页版**同源**，key 是共享的 → **改名 = 数据迁移**，需要双端同步发版 + 迁移脚本。
> **当前版本一律不改名**，App 侧硬编码读取。

---

## §1 总表

| 工具 | id | localStorage key | 结构 | 摘要算法 |
|---|---|---|---|---|
| 每日喝水 | `water` | `waterIntakeRecords`<br>`waterIntakeGoal` | `[{id, timestamp, …}]`<br>字符串数字 | `countToday` |
| 打卡助手 | `checkin` | `checkin_records` | `{"YYYY-MM-DD": [{t, time}]}`（**按日期分组的对象**） | `countDateMap` |
| 药品管家 | `medicine` | `medicine_tracker_v1` | `{meds:[], warnDays, sortBy}` | `count`（path=`meds`） |
| 宝盒是怎样月光的 | `whereismoney` | `baobox.v1` | `{salary, minExpense, installments:[]}` | `count`（path=`installments`） |
| 任务管理 | `list` | `todo-h5:v1` | `{tasks:[], tags:[]}` | `count`（path=`tasks`） |
| 脑力慢养 | `mindx` | `bf_settings`<br>`bf_progress`<br>`bf_daily`<br>`bf_level_pool`<br>`bf_flags` | 见 §3 | `lastGame` |
| 通往AGI之路 | `feishu` | — | `grep -c localStorage` = 0，纯静态无存储 | 无 |
| 井条条 | `jingtt` | — | 外部 App，App 不接管 | 无 |

> ⚠️ **localStorage 的值一律是字符串。**
> `snapshot["checkin_records"]` 拿到的是 JSON **字符串**，不是 Map —— 必须先 `jsonDecode` 再取值。
> 这条坑真实咬过（续接卡一直显示「还没开始」，见 DESIGN.md BUG #7）。

---

## §2 逐项证据

### 2.1 每日喝水（`water`）

```js
// 产物：h5_tools/assets/index-*.js
localStorage.setItem("waterIntakeRecords", JSON.stringify(records))
localStorage.setItem("waterIntakeGoal", String(goal))
```

- `records` 是数组，每项含 `timestamp`（毫秒时间戳）→ 配 `countToday` + `dateField: "timestamp"`
- `goal` 是纯数字字符串 → 摘要里显示「今天 3 杯 / 目标 8 杯」

### 2.2 打卡助手（`checkin`）

```js
// 产物：h5_tools/checkIn.html（单文件内联）
// 实测取值：
// {"2026-11-19":[{"t":"in","time":"08:38:21"},{"t":"in","time":"08:40:19"}]}
```

- **不是数组，是按日期分组的对象**；每条记录有 `t`（`in`/`out`）与 `time`（`HH:MM:SS`）
- ⇒ 配 `countDateMap`：取今天的 `YYYY-MM-DD` 键 → 数它那组的条目数
- 今天没记录但历史有 → 显示「今天还没打卡 · 累计 N 次」

### 2.3 药品管家（`medicine`）

```js
// 产物：h5_tools/medicine/index.html
localStorage.setItem("medicine_tracker_v1", JSON.stringify({
  meds: [{name, perUse, unit, period, freq, total, buySize, startDate}],
  warnDays, sortBy
}))
```

- `path: "meds"` → 数 `meds` 数组长度

### 2.4 宝盒是怎样月光的（`whereismoney`）

```js
// 产物：h5_tools/whereismoney/app.js
localStorage.setItem("baobox.v1", JSON.stringify({
  salary, minExpense, installments: []
}))
```

- `path: "installments"` → 数分期条数

### 2.5 任务管理（`list`）

```js
// 产物：h5_tools/list/assets/index-*.js
localStorage.setItem("todo-h5:v1", JSON.stringify({tasks: [], tags: []}))
```

- `path: "tasks"` → 数任务条数

### 2.6 通往AGI之路（`feishu`）

- 产物里 `localStorage` 出现 **0 次** —— 纯静态内容页，没有任何存储
- ⇒ `resume.enabled = false`，最近页不显示它的续接卡

---

## §3 脑力慢养（`mindx`）—— 唯一用 IndexedDB 的工具

### 3.1 五个 localStorage key

产物 `h5_tools/mindx/assets/index-D1Hn55KO.js`（302KB）里的 key 表：

```js
const pe = {
  settings:  "bf_settings",
  progress:  "bf_progress",
  daily:     "bf_daily",
  levelPool: "bf_level_pool",
  flags:     "bf_flags"
};
```

IndexedDB：`brainfit-db`，object store `session_log`。

### 3.2 `bf_progress` = 「今天还没打完的那一局」

H5 的 `Br()` 会读 `bf_progress`，如果 `startedAt` 不是今天、或超过 24 小时，就把它 `removeItem`。
⇒ **只要这个 key 还在，就一定是今天的那一局** —— 这是 App 侧不用维护时间戳也能取到「上一局」的原因。

实测值：

```json
{"gameId":"B","level":2,"qIndex":0,"score":0,"usedSeqs":["342"],"startedAt":1795141226115}
```

### 3.3 五个游戏的字段不一样

| gameId | 游戏 | 字段 |
|---|---|---|
| A | 找一找 | `level` `qIndex` `score` `lastCenter` `usedSeqKey` |
| B | 数口令 | `level` `qIndex` `score` `usedSeqs` |
| C | 配一对 | `level` `moves` `cardState:{deck,matchedIdx}` `firstFlipHintDone` ← **没有 score** |
| D | 赶集 | `level` `qIndex` `score` `plan` |
| E | 数字找家 | `level` `qIndex` `score` `usedTargets` |

### 3.4 游戏代码 → 中文名放在配置里

产物里的映射表：

```js
const nl = {A:"找一找", B:"数口令", C:"配一对", D:"赶集", E:"数字找家"};
```

⇒ 这份知识**放在 `config/app.config.json` 的 `resume.extract.names`** 里，App 不硬编码 H5 的内部知识。
（对应设计决策 D5「H5 管业务，App 管外壳」。）

### 3.5 摘要算法 `lastGame` 的三级降级

| 情况 | 走哪条模板 | 例 |
|---|---|---|
| 有 `score` | `template` | 上一局·数口令·82 分 |
| 只有 `moves`（配对一对） | `templateMoves` | 上一局·配一对·24 步 |
| 两者都没有 | `templateFallback` | 上一局·找一找 |

`detail`（续接卡副标题）优先级：「游戏名 · 第 N 关」>「游戏名 · N 分」>「游戏名」。

---

## §4 续接卡摘要算法（六种）

| kind | 用在哪 | 说明 |
|---|---|---|
| `countToday` | 每日喝水 | 按 `dateField` 数今天的记录；`goalKey` 取目标值 |
| `count` | 药品 / 月光 / 任务 | 数数组长度；`path` 是 **`key` 那个值内部**的路径（不是从快照根取） |
| `countDateMap` | 打卡助手 | 按日期分组的对象 → 取今天的组 → 数条目 |
| `lastGame` | 脑力慢养 | 三级降级（分数 / 步数 / 只有游戏名） |
| `field` | 预留 | 取某个字段的值直接显示 |
| `none` | feishu / jingtt | 不做摘要 |

### 占位符

| 占位符 | 含义 |
|---|---|
| `{n}` | 数量 |
| `{v}` | 字段值 |
| `{goal}` | 目标值 |
| `{unit}` | 单位 |
| `{game}` | 游戏中文名（由 `extract.names` 映射） |
| `{level}` | 关卡号 |

`text` 是卡片主标题，`detail` 是副标题。两者职责分开 —— 主标题给结论，副标题给细节。

---

## §5 命名规范整改建议（暂不执行）

现状：驼峰（`waterIntakeRecords`）、蛇形（`checkin_records`）、点号（`baobox.v1`）、短横（`todo-h5:v1`）四种风格混用，全部无命名空间。

**建议**（需要 h5_tools 与网页版同步发版 + 迁移脚本，暂不做）：

1. 统一 `kmlab.<tool>.<name>`（如 `kmlab.water.records`）
2. 全部带版本号（`kmlab.water.records.v1`）
3. 一次性迁移脚本：读旧 key → 写新 key → 删旧 key
4. App 侧**同时**支持新旧 key（读新、找不到再读旧），迁移期零风险

---

## §6 与离线副本的联动（⚠️ 关键）

因为 App 与网页版**同源**，key 是共享的 ⇒ 换 origin = 数据分家。

- ❌ **绝不能**把 H5 副本打进 APK 用 `file://` 或 `appassets.androidplatform.net` 加载
  → 那会变成另一个 origin，`localStorage` 里**看不到网页版的老数据**
- ✅ 离线必须用 **Service Worker**（同 origin 接管请求）→ 见 DESIGN.md §5.8
- 降级路径（内置副本）只在**用户明确接受「数据独立」**时才可用，并且要提示 + 给导入/导出

这条是 D1「换 origin = 丢数据」铁律的技术细节，也是 R1 风险的全部来源。
