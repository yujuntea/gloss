# 精读窗生命周期修复记录（2026-09-27）

> 缺陷：同一进程内**第二次及以后**打开「精读」窗，四个 tab（翻译/生词/术语/解读）全空，不发任何 API 请求。
> 涉及文件：`Gloss/UI/WindowManager.swift`、`Gloss/UI/ReaderWindow.swift`、`Gloss/App/AppDelegate.swift`。
> 版本：仍在 v0.1.5（build 6）上修复，**未 bump 版本**（是否随 appcast 发布待定）。

## 一、根因

`WindowManager.showReader` 复用同一个 `NSHostingView`、靠 `hv.rootView = view` 换内容。
SwiftUI 对**同类型根视图的热替换不触发 onAppear/onDisappear**，而 `ReaderView` 的任务启动只写在 `.onAppear { vm.start() }`。
于是同会话第二次起 `ReaderViewModel.start()` 从不被调用：`batches` 空、`aggregatePhase` 永远 `.pending`、零请求——用户看到的就是一扇"能开但不动"的窗。

连带症状：`@State tab` 跨内容热替换残留（SwiftUI 保留状态、只换视图值），用户被停在上一次的「解读」页，
而该页本应显示 `.pending` 占位文字，视觉上就成了一整片空白，比停在「翻译」页更难判断"是没反应还是坏了"。

## 二、证据

| 证据 | 内容 |
|---|---|
| 最小复现（仓库外 `/tmp/Repro.app`） | 往已有 hosting view 赋 `rootView` → 无 APPEAR；换新 `NSHostingView` → DISAPPEAR + APPEAR；再赋 `rootView` → 又无 APPEAR |
| 修复前统一日志 | 22:12:42 `reader opened chars=509` → 22:13:04 `reader aggregate done`；22:14:48、22:16:18 两次 `reader opened chars=1319` 之后**无任何日志** |
| 数据侧 | `default.store` 中 `ZQUERYRECORD` 的 article 记录只有 22:13:04 一条（输入 509 字符）；22:14/22:16 两次 1319 字符精读**无 article 记录、无 article 缓存条目**。注意同源链：22:12:27 `paragraph/509` → 22:13:04 `article/509`（首开成功）；22:14:45 `paragraph/1319` → 22:14:48 精读打开 → 之后无 article/1319（段落查询本身成功，精读却从未启动） |
| 进程状态 | `sample` 主线程停在 `_nextEventMatchingEventMask`（正常事件循环）——不是卡死，是任务压根没启动 |
| AX 树 | 右栏 `AXScrollArea` 无子元素；切到「解读」页才有 `（等待各批次完成后汇总）`——即状态永远 `.pending` |
| 像素级 | 用户截图中右侧区域**零个深色像素**（占位文字未被绘制），佐证热替换的渲染残留 |

> 坑：`log` 是 zsh 内建命令，直接敲 `log show …` 会静默失败；查统一日志必须用 `/usr/bin/log`。
> 坑：`log show --last 3h` 需同时加 `--info --debug`，否则只拿到 default 级。

## 三、修复

1. **`WindowManager.showReader`**：删掉 `readerHosting` 缓存属性，每次都 `w.contentView = NSHostingView(rootView:)` 装全新视图树；`makeKeyAndOrderFront` 之后**显式** `vm.start()`——任务归 WindowManager 所有，不再依赖视图生命周期回调。
2. **`ReaderView`**：删掉 `.onAppear { vm.start() }`；`init` 改为 `init(vm: ReaderViewModel)` 必传（去掉 `externalVM` 默认兜底，避免造出永不启动的空窗口）。
3. **`AppDelegate`**：新增 `-demo-reader-twice` 启动钩子（3 秒后连续再开一次），仿照既有 `-demo-image-twice`，用于回归验证。

### 审后追加（glm-reviewer-hs P1-1 / P2-1）

- **P1-1 关窗不取消跑批**：`WindowManager` 改为 `NSObject, NSWindowDelegate`，`windowWillClose` 里按窗口身份匹配后 `currentReaderVM?.cancel()`。
  该问题**早于本次修复存在**——代码注释（原 K3-P1-2「关窗/替换内容都取消跑批」）声称的安全属性为假：实测关窗/最小化**不触发 onDisappear**，
  任务会在关窗后继续发请求并写缓存，而唯一的取消入口（stop 按钮）随窗口消失。注释已改真。
- **P2-1**：`ReaderView.init` 去掉 `externalVM` 默认值（见上）。

## 四、回归验证

- 编译：Release BUILD 成功（仅存量 warning）；`codesign -v` 通过，版本仍 0.1.5 (6)。
- 逻辑自检：按 tech-design §10 显式文件清单联合编译 → `SELFCHECK ALL PASS`。
- **双开回归**（`-demo-reader-twice`，冷缓存）：22:25:00.510 `reader opened chars=2619` → 22:25:03.607 `reader opened chars=2652` → 22:25:28.301 `reader aggregate done`；
  AX 树右栏含「第 1/1 批/译文/难词表/难词行…」，「解读」页含「文章主线/论证结构/关键转折/背景补充」，截图肉眼确认。
- **关窗取消回归**：唯一文本 698 字符跑批中关窗 → 无 `reader aggregate done`、无 article 记录；
  对照组（689 字符同流程不关窗）→ 22:40:37.831 opened → 22:41:04.976 `reader aggregate done` → 22:41:05 article 记录落库（排除"查询本身失败"的可能）。
- **替换内容取消回归**：`-demo-reader-twice` 首开 2619 字符的任务在 3 秒后被第二次 `showReader` 显式取消 → DB 至今**无 2619 的 article 记录**，只有 2652 落库。
- **真实入口 E2E**：`-demo-paragraph`（392 词）→ 浮窗段落卡（译文 + 难词 chips）→ 按「展开精读」→ `reader opened chars=2560` → 22:43:46 `reader aggregate done`，右栏 76 个文本元素、「第 1/1 批」在位。

## 五、独立审（glm-reviewer-hs，轻量级终审）结论

0 P0 / 2 P1 / 3 P2。P1-1、P2-1 已修（见上）。其余登记：

- **P1-2 证据留存方式**：修复前的 `log show` 行在事后已无法从 log store 复现，原因未定（形态上不像"轮转修剪"——更早的条目全没了却保留了更晚的，更接近 Info 级当时根本未持久化）；DB 侧也只能证明"22:13 有产物、22:14/22:16 无产物"。
  后续留存前后对照证据应改用 `log stream` 实时落文件或从终端启动取 stdout（`GlossLog` 双写）。
- **P2-2 版本未 bump**：若随 appcast 分发需 bump 0.1.6 (7) + release notes；仅本地验证无碍。
- **P2-3 本文件**：`-demo-reader-twice` 回归钩子与复现证据已登记于此。

## 六、遗留

- 「解读」页 `.pending` 占位文字在修复前的热替换场景下未被绘制（用户截图为零深色像素）。修复后同一管线渲染正常，
  未单独隔离该现象的独立成因；如需闭环，可在修复版上不触发查询直接切到「解读」页确认占位可见。
