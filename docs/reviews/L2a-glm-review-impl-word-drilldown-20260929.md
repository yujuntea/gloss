# L2a 独立第一审：截图单词下钻 实施代码（2026-09-29）

- 审查对象：工作区未提交 diff（10 个改动文件）+ 2 个未跟踪新文件（`Gloss/Core/ImageGeometry.swift`、`Gloss/UI/ImageZoomWindow.swift`）
- 验收基准：`docs/proposal-2026-09-29-word-drilldown.md`（已定稿）
- 透明素材：`docs/reviews/L0-selfcheck-impl-word-drilldown-20260929.md`（其声明均已独立复核，见 §断言清单）
- 方式：全 hunk 通读 + 四项指定抽查（a/b/c/d）+ 定向实跑（SelfCheck、xcodebuild、website 命令复现）

## 0. 结论表

| 级别 | 计数 | 一句话 |
|---|---|---|
| P0 | **0** | 核心机制（A chips / B2 图片窗 / C 降级 / 缓存版本与 context 入键 / D-e / D-f）实现与规格语义等价，未发现会致错/假绿的缺陷 |
| P1 | **2** | website 自检命令缺 `ImageGeometry.swift` 复制即编译失败（已实测复现）；断言计数四处失实（65/86/89 并存）且 L0 自查两个声明与仓库现状不符 |
| P2 | **5** | 文档残留已删常量名 / 帮助文案与分流口径不一 / 一条弱断言 / 根卡流式中点 chip 后返回只见「已取消」/ 准星坐标 resize 后漂移 |

**总体判断**：代码主体可放行（0 P0）；两条 P1 均为「同源一致性/可验证性」类（不碰运行时逻辑），修复成本低。产物量级判定：中量级（12 文件、+457/−103，方案级实现），本审按任务书为第一道独立审；两处 P1 修复后无需升级 K3 异构终审——但若发布前要走 `scripts/release.sh`，website 属发布资产，P1-1 必须先修。

---

## 1. 分级问题清单

### P1-1 website 自检命令复制即编译失败 + 计数错误（公共发布资产）

- **位置**：`website/index.html:1167`（`核心逻辑自检 · 65 项断言`）、`website/index.html:1170-1175`（swiftc 命令块）、`website/index.html:1261`
- **问题**：命令块的文件清单缺 `Gloss/Core/ImageGeometry.swift`。本 diff 的 `SelfCheck/main.swift:287-289` 新增了 `ImageGeometry` 引用，按网页命令编译直接失败。**实测复现**（照抄网页文件清单编译）：
  ```
  SelfCheck/main.swift:287:19: error: cannot find 'ImageGeometry' in scope
  SelfCheck/main.swift:288:22: error: cannot find 'ImageGeometry' in scope
  ```
  同时该网页计数被本 diff 从「68 项」**改错为「65 项」**（:1167、:1261 两处）——68 是旧树的真实值，65 从未正确过，新树实际为 89。
- **依据**：上为实跑输出；对照 `docs/tech-design.md:362-366`（已补 ImageGeometry 的正确命令，本人照抄实跑 PASS=89）。
- **建议修法**：网页命令块与 tech-design §8 同步（补 `ImageGeometry.swift`），两处计数改 89。`website/index.html` 本身在 diff 内被改动过（hero/⌥S 段落），不存在「范围外」辩护。

### P1-2 断言计数同源失实 + L0 自查两个声明与仓库现状不符

- **位置**：`README.md:91`（86 项）、`docs/tech-design.md:369`（86 项）、`website/index.html:1167/1261`（65 项）、`README_EN.md:91`（65 assertions）；实际 `PASS=89`（本人复跑）
- **问题**：同一工作区内四个不同数字并存（86/86/65/65），真值 89。且：
  - L0 自查 **A4** 声称「`SelfCheck/main.swift` 断言总数 86→89」——`main.swift` 内不存在任何总数声明（grep `断言|86|89` 零命中），该步为无落点的空操作声明；
  - L0 自查 **CI-1/③** 声称「`grep -rn "65 项" README* docs/*.md` → 0 命中」——grep 范围漏了 `website/`（两处「65 项」）且中文模式匹配不到 README_EN 的英文「65 assertions」。声明字面为真、实质为假。
- **依据**：上为 grep/复跑实证；计数演进链（65→86 是 A3，86→89 是 A2/A4，文档停在 86）可从 L0 报告 ②/A3/A4 自身推出。
- **建议修法**：四处统一为 89；后续同类核查的 grep 模式须覆盖 `website/` 与英文数字措辞（建议 `grep -rn "项断言\|assertions\|项 全绿" README* docs website`）。

### P2-1 tech-design 引用已删除的常量名 + 固定阈值措辞滞后于 A1 修复

- **位置**：`docs/tech-design.md:292`（§4.12「`ImageTapView.inCardWidth = 376`」）、`docs/tech-design.md:114`（§3.3「`≤ 376pt`（面板 400 − 2×12 padding）」）
- **问题**：L0 自查 A1 已把硬编码 376 改为实测 `geo.size.width`（`CardViews.swift:209`），常量 `inCardWidth` 不存在；§4.12 仍以它为口径描述，§3.3 仍是固定值措辞。代码方向更正确（面板 `.resizable` 可拉宽），但文档指向不存在的符号会误导后续维护。
- **建议修法**：两处改为「按 `ImageGeometry.needsZoomWindow(imageWidth:cardWidth:)` 以点击时实测卡宽判定（默认面板宽 400−2×12=376）」。

### P2-2 `tapHelpText` 与实际分流口径不一致（纯文案）

- **位置**：`Gloss/UI/CardViews.swift:204`（固定 `cardWidth: 376`）vs `:209`（`viewSize.width`）
- **问题**：帮助提示用固定 376 判定，实际点击用实测宽。用户拉宽面板到 600 后，一张 400pt 宽的图：提示说「点击放大查看」，实际点击走就地点词。行为正确、文案说反。
- **建议修法**：`.help()` 移入 GeometryReader 内按 `geo.size.width` 判定，或干脆统一为中性文案（如「点击查询图中单词」）。

### P2-3 `cachekey.screenshotVersionBumped` 为弱断言，断言名超出其实际证明力

- **位置**：`SelfCheck/main.swift:179-184`
- **问题**：断言名为「整图键与点词键均随版本变化」（规格 §8 原意），实际只证明 ①kind 不同键不同 ②`version(for:)` 返回 "m2"——并未把「makeKey 拼入了该版本串」钉死。若 makeKey 误用固定字符串，word 侧被 `cachekey.wordContextDiffers` 的字节级锚定（`glossSHA256("operation|word|m|m1")`）兜住，screenshot 侧无对应锚定、此断言不报警。非假绿（所述两点皆真），但守护面有缺口。
- **建议修法**：补一条字节级锚定，如 `shotKey == glossSHA256("imgsha|screenshotExplain|m|m2")`。

### P2-4 根卡流式中点 chip → 返回后根卡只见「已取消」，部分内容不可见

- **位置**：`SessionCoordinator.swift:260-262`（`cancelCurrent` 对栈内所有 streaming/loading 卡置 `.notice("已取消")`，不豁免 stack[0]）× `CardViews.swift:22-24`（`.notice` 相位只渲染 NoticeView，不渲染 content）
- **问题**：chips 在根卡 streaming 期间即可点（`ScreenshotCardBody` 对 `.streaming/.done` 都渲染）。根卡未完时点 chip，`pushWordQuery → cancelCurrent` 把根卡打成 notice，查询被取消；「返回整图」后只看到「已取消」，已流入的部分内容被 notice 遮蔽（content 仍在内存，重试可重跑）。**句/段卡既有同款行为，非本 diff 引入**；本 diff 把该模式新接入截图卡，可触达面扩大（截图 chips 正是本功能主路径）。
- **建议修法**（可与本 diff 解耦）：`cancelCurrent` 豁免 `stack.first`，或 `.notice` 相位下若 `content` 非空仍渲染 content + 顶部小字提示。

### P2-5 准星 viewPoint 在窗口 resize 后漂移

- **位置**：`Gloss/UI/ImageZoomWindow.swift:11-14, 39-50`
- **问题**：`Crosshair.viewPoint` 是显示区坐标快照；窗口拉大/缩小后 fit 区域变化，旧准星按旧坐标绘制会偏离用户点过的图上位置（`normalized` 读数与发往模型的坐标仍正确，仅叠加显示漂移，下一次点击即纠正）。
- **建议修法**：存 normalized、绘制时按当前 bounds 反解 viewPoint；或 resize 时清除 crosshair。

---

## 2. 必查抽查记录

### a.【D-e】`pushWordAtQuery` 栈顶替换（`SessionCoordinator.swift:172-198`）

**时序推演**（关键事实：全部动作同在 MainActor 一次同步调用内完成，@Published 中间态对 SwiftUI 不可见）：

1. **图片窗连续点 3 个词**（面板可见）：click1 → guard(root==screenshotExplain ✓) → cancelCurrent（root 为 .done，无副作用）→ count=1 不 removeLast → append w1 → [root,w1]，面板可见不走 show → 原地换卡（`revision+=1` → `ResultPanelView.swift:17` onChange → resizeToContent，高度自适配）。click2/3 → cancelCurrent 取消 w(n) 的 Task 并置其 notice（随即被 removeLast 移除，中间态不可见）→ append → 恒为 [root,w(n)]。**不丢卡**（root 永不被该路径移除）、**深度恒 ≤2**（append 前必有 count≤1）。
2. **第 2 词 streaming 中点第 3 词**：旧 Task 经 `currentTask?.cancel()`；因 Task 与本调用同为 MainActor 串行，旧 Task 只能在下一 suspension 处收到 CancellationError → `catch is CancellationError { return }`（:407），无缓存写入、无孤儿流。`cancelCurrent` 先置 notice 再 removeLast 的顺序无中间态泄漏。
3. **ESC 藏面板后再点**：ESC → Carbon 热键（`PanelController.show` 注册）→ hide() → `panelDidHide → cancelCurrent`（w1 置 notice、停 TTS，w1 留栈但面板已隐藏）→ monitors/escape 热键拆除。再点图内：local monitor 已拆不拦 → mouseDown → pushWordAtQuery → removeLast 丢弃旧 w1 → append w2 → **面板不可见 → `show(near: clickRect)` 复活并就近定位**（`PanelController.swift:49-75`：restoredOrigin 用户拖放位优先属规格明示的现状，`orderFrontRegardless` 不抢焦点 ✓）。
4. **monitor 与 tap 的次序**：local monitor 先于 mouseDown 派发；图内事件被 `isImageWindow(ev.window)` 短路（`PanelController.swift:200`），无闪隐/无 ESC 拆装 churn ✓。global monitor 只收他 app 事件，图窗属本 app 不会命中 ✓（规格 §4.3 判断正确）。

**结论：三种时序下不丢卡、不泄漏、无孤儿流。`if stack.count >= 2` 用 `>=` 而非 `==` 是对「栈深意外 >2」的防御，合理。**

### b.【D-f】`setRoot` 收口与 `windowWillClose` 互踩

- `grep -rn "stack = \[" --include="*.swift"` → **仅 `SessionCoordinator.swift:312`（setRoot 内）一处** ✓（:65 的 `= []` 为声明初始化）。
- 四条换根路径全走 setRoot：⌥D `beginHotkeyQuery→show(:105)`、⌥S `beginScreenshotFlow→show(:154)`、`replay(:432)`、`requery(:214)`；⌥S 的关窗发生在采集成功后的 `show`（取消截图则栈未变、窗保留，语义正确）。另一条非换根路径（≥400 词 → `showReader`）不动栈，图窗与旧栈根仍绑定一致，无静默死路。
- `closeImageWindow`（orderOut+置空）与 `windowWillClose` imageWindow 分支（置空）**不互踩**：orderOut 不触发 windowWillClose；关窗按钮走 performClose→close()→windowWillClose 置空一次；ESC 走 closeImageWindow 置空一次。重复置空幂等。delegate 为系统弱引用、WindowManager 是单例，无 dangling delegate。窗关闭后 `imageWindow=nil` → 再点缩略图 `makeWindow` 新建（isReleasedWhenClosed=false 无重复释放问题）。
- 规格「可选加固」`stack.first?.originalImage === image` 身份校验未实现——规格标注「可选」，换根即关窗已封死两条失效路径，不构成缺陷。

### c.【坐标契约】`ImageZoomWindow.swift:118-128`

- **`isFlipped=true` 自洽性**：`draw(:100-109)` 与 `ImageGeometry.normalizedPoint`（`ImageGeometry.swift:9-19`）同用视图局部 y 向下坐标 + 同一套 fit 公式，绘制与换算同源 ✓；`NSImage.draw(in:)` 在 flipped 视图中自动翻正，不需手动变换。SwiftUI 侧准星 overlay 直接叠在同一组 y 向下坐标上（overlay 与 representable 同 frame、无 padding 插层，`ImageZoomWindow.swift:21-33`）✓。
- **`convert(from: nil)` 与 `convert(to: nil)` 不是等价而是互逆**：前者把 `event.locationInWindow`（window base 坐标）翻到视图局部系（供 normalizedPoint 与准星），后者把同一局部点翻回 window 系（供 convertToScreen）。写 `from: nil` 的意图 = 先取局部点，一举供换算/准星/回翻三用，正确且必要。
- **零尺寸 CGRect**：`win.convertToScreen(NSRect(origin:winPoint, size:.zero)).origin` 取点合法。下游 `positionBySelection`（`PanelController.swift:136-153`）只用 minX/minY/maxY：零高 rect 的 maxY==minY → 先试「点击点下方 12pt」（`minY-12-height`），贴屏底时翻上方（`maxY+12`）再钳制——纯点语义，无退化、无 NaN。
- **多屏**：convertToScreen 按所在屏 frame 换算（系统保证）；`positionBySelection` 用 `NSEvent.mouseLocation` 选屏，而调用发生在 mouseDown 同步栈内，鼠标即点击点 → 同屏 ✓。未手搓单屏翻转公式 ✓（规格红线遵守）。

### d.【prompt 契约】`.screenshotExplain` 难词表 × `SectionExtractor`

- Swift 源里 `` `\\|` ``（`PromptLibrary.swift:79`）实际输出为 `\|`（两字符）；SelfCheck `shotPrompt.contains("\\|")`（源码里同为 `\|`）断言成立 ✓。护栏指令「例句含竖线以 `/` 替代」与规格 §3.1 逐字一致（其与「逐字一致」的语义张力属规格自身取舍，非实现偏差）。
- **`tableRows` 实际按裸 `|` 切分**（`SectionExtractor.swift` tableRows：`components(separatedBy: "|")`），不识别 `\|` 转义——所以护栏是「让模型别产出竖线」而非「解析端转义」，与规格括注「按朴素 `\|` 切分」描述相符，防错位机制成立。
- **节名变体**：`isSectionHeader` 识别 `**难词表**`、`**难词表**：…`（trim `：: `）；`### 难词表` **不识别** → 优雅降级：chips 为空 + `removingSection` no-op → 表格留在正文由 MarkdownView 渲染——与段落卡既有契约完全一致，非回归。
- **节序边界**：`removingSection` 逐行状态机与节序无关（要点前后均正确）；`|---|` 分隔行 trim 后 ≠ `---`，不触发 allSections 的分节 flush；`**难词表**` 为模板末节，其后无内容也正确取到。唯一极端：模型若在节名与表格之间插入裸 `---`，节体为空 → chips 空 + 表格被 removingSection 吞掉（极不可能，见 §4 边界）。

---

## 3. 核对过的断言清单（独立复核，非转述）

| 声明 | 结果 |
|---|---|
| SelfCheck 89/89 全绿 | ✓ 复跑：PASS=89 / FAIL=0 / SELFCHECK ALL PASS（tech-design §8 命令照抄编译运行） |
| xcodebuild Debug 0 error | ✓ 复跑：`error:` 计数 0 |
| `stack = [card]` 全仓恰 1 处（setRoot） | ✓ |
| makeKey 5 调用点、仅 runText 传 context | ✓（SessionCoordinator:195/244/330/337 + ReaderWindow:182） |
| pushWordAtQuery 3 调用方（缩略图窗内/就地点/demo） | ✓（CardViews:211/216 + SessionCoordinator:295） |
| 静态 `PromptLibrary.version` 已删、无残留引用 | ✓（grep 仅 `version(for:)`） |
| 新文件自动入 target（pbxproj 不需改） | ✓（编译产物含 ImageZoomWindow；`PBXFileSystemSynchronizedRootGroup`） |
| website 自检命令可用 | ✗ **证伪**：缺 ImageGeometry.swift，编译失败（P1-1） |
| L0 A4「断言总数 86→89」 | ✗ 无落点：main.swift 无总数声明，文档仍 86（P1-2） |
| L0 CI-1「65 项全仓 0 命中」 | ✗ 字面真实质假：website/ 与英文措辞未入 grep 范围（P1-2） |

**规格对照结论**：§3（chips+removingSection+row[3]）、§4.2-4.5（B2 窗口/分流/共享换算）、§5.1（version(for:) 分 kind+删常量+makeKey 接线）、§6.1（context 归一入键限 word）、§6.2（例句空串不覆盖）、§7（多候选不编造）、§8（8 类断言全落地并实跑）、§10（7 步骤全落点，验收 9 由本人复验）——实现与规格**语义等价**；A1（实测卡宽替代常量 376）是规格精神下的合理增强，仅文档/文案未跟上（P2-1/P2-2）。

---

## 4. 查过未报的边界

- **图片窗最小化后复用路径**：`showImage` 复用已存在窗口时仅 `makeKeyAndOrderFront`，对已最小化窗口是否反最小化未实机验证（AppKit 文档对 orderFront 系有「不自动 deminiaturize」口径）；若不恢复，用户最小化后再点缩略图可能看似无响应。建议实机验收第 5 条顺带覆盖，必要时补 `if w.isMiniaturized { w.deminiaturize(nil) }`。
- **ESC 在 `keyDown` 内同步释放窗口**（`closeImageWindow` 置 nil → 窗与 contentView 可能在自身事件派发栈内释放）：方法体其后不再触碰 self/super，理论安全，未观察到实际问题；如求稳可改为 `orderOut` + 延迟置空。
- **图片窗保持打开期间用户点面板内「重新截图」等按钮**：面板内点击不被 monitor 排除逻辑误伤（命中 panel frame → 不 hide）✓ 推演通过。
- **历史回放截图卡**：thumbnail ≤200px 恒走就地点词、不弹窗 ✓（与 §4.5 注记一致）；demo 通道 `-demo-wordat` 签名兼容（默认参数）✓。
- **`screenshotWordAt` 空语境**：`runText` 仅文本类走；点词卡 `context: nil`、prompt 不拼语境 ✓ 与规格一致。
- **规格 §11 三个次级项**：阈值口径已定（实测宽）、窗尺寸不记忆（每次新建回 1000×700 居中）、标题「Gloss 图片」——均按「拟定」落地，未做记忆属明示的开放项。
- **变异测试声明**（removingSection no-op → 2 FAIL 等）：由 impl-worker 执行，本轮未重跑变异；守护对象与断言的对应关系已经代码层核对（无假绿）。
- **版本号未 bump**：工作区不 bump 与仓库发布流程（release 时改 MARKETING_VERSION）一致，非缺陷。
