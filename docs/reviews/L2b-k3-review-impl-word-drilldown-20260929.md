# L2b 异构终审（K3）：截图单词下钻 实施代码（终版候选，2026-09-29）

- 审查对象：工作区未提交 diff（13 文件）+ 2 个未跟踪新文件（`Gloss/Core/ImageGeometry.swift`、`Gloss/UI/ImageZoomWindow.swift`）
- 验收基准：`docs/proposal-2026-09-29-word-drilldown.md` §10（11 条）
- 前轮材料：L2a 报告、L0 自查 + L1 修复记录（B1–B8）——均已独立复核，未采信
- 方式：全 hunk 通读 + 相关文件全量 Read + 定向实跑（SelfCheck 复跑、B5 变异 ×2、website 命令实跑、xcodebuild clean 构建、isFlipped 离屏渲染实证 ×4 轮、grep 终检）

## 0. 结论表

| 级别 | 计数 | 一句话 |
|---|---|---|
| P0 | **0** | 未发现会致错/数据损坏/假绿的缺陷 |
| P1 | **0** | 未发现合流前必须处理的质量/风险项 |
| P2 | **6** | 「面板可拉宽」前提被 `.frame(width: 400)` 证伪（A1/B4/L2a P2-2 共同前提）/ PROMPT_VERSION 概念残留 ×5 + §4.9 键公式缺 ctx 段 / §4.2 超时旧语义未随 VisibleIdleGuard 修订 / B5 一恒真死条款 / fit 公式三处拷贝 / 见 §1 |

**总体判断**：核心机制（A chips / B2 图片窗 / C 降级 / 分 kind 版本 + context 入键 / D-e 栈顶替换 / D-f 换根关窗 / 条件式置前 / monitor 排除 / VisibleIdleGuard）实现与规格**语义等价**；L1 的 8 项修复全部落实到位且未引入新矛盾（B5 经两种变异实证能捕获回归，B6/B7 经反例检验成立）。主 Agent 的 SelfCheck 91/91、xcodebuild 0 error 经本人独立复跑证实。**裁决：可定稿进实机验收**（§3 给出实机清单；6 个 P2 可在实机验收并行修，不阻塞）。

---

## 1. 分级问题清单（P2 ×6，无 P0/P1）

### P2-1 「用户可拉宽面板」前提失实——内容宽被钉死 400，`geo.size.width` 恒为 376

- **位置**：`Gloss/UI/ResultPanelView.swift:15`（`.frame(width: 400)`）× `docs/tech-design.md:114`（「面板 styleMask 含 `.resizable`，用户可手动拉宽，写死 376 会让拉宽后本可看清的图仍被无谓弹窗打断」）× `docs/tech-design.md:292`（§4.12 同口径）× `SelfCheck/main.swift:303` 注释（「拉宽面板后 300 宽图不该再弹窗」）
- **问题**：面板 contentView 的根 SwiftUI 视图是 `.frame(width: 400)` 的**固定宽**（非 maxWidth），窗口虽 `.resizable`，用户拖宽窗口只会得到居中的 400 宽内容列，`ImageTapView` 内 GeometryReader 的 `geo.size.width` 在任何可达 UI 状态下恒为 376（400−2×12）。即 A1「实测卡宽替代常量 376」在当前布局下与常量产行为**完全等价**，其文档化动机（拉宽后不再误弹窗）描述的是一个**不可达状态**。同源反噬：L2a P2-2 报的「用户拉宽到 600 后 help 与行为相反」原本也不可达——该「bug」在当前 UI 不会显现（B4 的修复作为单一数据源卫生仍然正确，保留）。L0 发明了该理由、L2a 在同一前提上立项，两轮均未核宽度钉点——本项为两轮共同盲区的实证。
- **依据**：`ResultPanelView.swift:15` 直接读取；`ImageTapView` 唯一消费者为 `CardRouterView`（`ResultPanelView.swift:69`，历史窗只渲染 44×33 小图，见 `HistoryWindow.swift:55-59`）；`PanelController` 全文件无任何宽度改写（`resizeToContent` 只动 height，`PanelController.swift:85-98`）。
- **建议修法**：代码不动（实测宽写法对未来可宽布局是正确防御）；把 tech-design :114/:292 的动机改为「阈值取实测卡宽以为未来可宽面板留口；当前内容宽固定 400（`ResultPanelView.swift:15`），实测恒 376」；SelfCheck :303 注释删「拉宽面板后」场景措辞（断言本身作为纯函数边界仍然有效，保留）。

### P2-2 `PROMPT_VERSION` 概念残留 5 处 + §4.9 键公式缺 ctx 段

- **位置**：`docs/tech-design.md:64`（树注释「5 套模板 + PROMPT_VERSION」）、`:160`（§4.3 标题「PROMPT_VERSION = "m1"」——分 kind 后截图两类实为 m2，标题字面失实）、`:270`（§4.9「缓存键 = `sha256(normalizedInput | kind | kindParams | model | PROMPT_VERSION)`」——既未体现按 kind 分版本，也缺本 diff 新增的 `|ctx:` 段）；`Gloss/Core/PromptLibrary.swift:4`（头注释「PROMPT_VERSION 参与缓存键」）、`Gloss/Core/CacheStore.swift:4`（同类注释）
- **问题**：静态常量已删（L2a 已核符号级无残留），但**概念名**在文档与代码注释中存活，且 §4.9 的键契约是后续维护者推导键格式的权威来源——按其公式推不出 `ctx` 段与 m2。L2a 的「无残留引用」核查只 grep 了 Swift 符号 `PromptLibrary.version`，未覆盖散文/注释中的概念名；L0 CI-1 同源扫描同样漏此类。
- **依据**：上行 grep 实证（`grep -rn "PROMPT_VERSION" docs Gloss`）。
- **建议修法**：§4.3 标题改「`version(for:)` 按 kind 分版本（截图两类 m2，其余 m1）」；§4.9 公式改为实现口径 `sha256(normalizedInput | kind | model | version(for:kind) [| pt:..] [| pg:..] [| ctx:8 位摘要，仅 word 且 context 非空])`；两处代码注释把 `PROMPT_VERSION` 改为 `PromptLibrary.version(for:)`；:64 树注释同步。

### P2-3 tech-design §4.2 超时条目仍是「任何 delta」旧语义，未随 VisibleIdleGuard 修订

- **位置**：`docs/tech-design.md:155`（「超时：流式空闲（20s 无**任何 delta**）取消并抛 `timeout`」）
- **问题**：本 diff 引入 `VisibleIdleGuard` 后，用户可感超时语义是「20s 无 **content** delta（reasoning 不计）」——纯 reasoning 流 20s 即被杀，恰与该条字面相反（按其说法，reasoning 在流的请求不会超时）。product-design.md:222 已改为新口径（「reasoning delta 不计」），tech-design 未同步，同仓两文档口径互相矛盾；且 §4.2 完全未提及 VisibleIdleGuard 与 URLSession 20s 的双层分工（网络层管字节空闲、守卫管可见内容空闲）。
- **依据**：`Gloss/Core/LLMClient.swift:34-52`（守卫语义注释）、`SessionCoordinator.swift:372-390`（仅在 contentDelta 时 `markVisible`）、`LLMClient.swift:149`（`timeoutIntervalForRequest = 20`）。
- **建议修法**：§4.2 超时条目改写为双层口径：「URLSession 20s 管字节级空闲（连接死）；`VisibleIdleGuard` 20s 管可见内容空闲（reasoning 不刷新）——后者是 2026-09-29 长思考流卡死实测的修复」。

### P2-4 B5 锚定断言中一条恒真死条款

- **位置**：`SelfCheck/main.swift:190-193`（`cachekey.screenshotKeyDiffersFromM1` 的第 2 个合取项 `glossSHA256("imgsha|screenshotWordAt|m|m1|pt:30,50") != wordAtKeyIfStillM1`）
- **问题**：该子句比较两个**字面量字符串**的 sha（一个带 `|pt:30,50` 一个不带），不经过 `makeKey` 的任何输出，在任何实现下恒真——是死条款。守护面无实际损失：同断言的第 1 项（`shotKey != shotKeyIfStillM1`）与第 3 项（`wordAtKey == glossSHA256("imgsha|screenshotWordAt|m|m2|pt:30,50")`）才是真锚，本人用两种变异实证（见 §2-B5）。
- **依据**：变异 1（`version(for:)` 全回 m1）→ 该断言 FAIL（由第 1/3 项触发）；变异 2（`makeKey` 硬编 `"m1"` 字面量）→ 该断言独立 FAIL——两种变异下第 2 项均始终为真，未贡献判别力。
- **建议修法**：删第 2 项，或把它改成有判别力的形式（如 `wordAtKey != glossSHA256("imgsha|screenshotWordAt|m|m2")` 以钉「pt 段确实入键」——当前该性质由 :163 `cache.point.changesKey` 间接覆盖）。

### P2-5 fit 公式三处拷贝，漂移风险结构性存在

- **位置**：`Gloss/Core/ImageGeometry.swift:12-14`（normalizedPoint）、`Gloss/UI/ImageZoomWindow.swift:110-113`（`ZoomImageNSView.draw`）、`Gloss/UI/ImageZoomWindow.swift:39-42`（`ImageZoomView.marks` 准星反解）
- **问题**：规格 §4.4 要求「抽成共享函数供缩略图与图片窗两处使用」——换算侧已收口进 `ImageGeometry`，但**绘制侧**（draw 的 fit rect）与**准星反解侧**（B7 新增）仍各自内联同一公式。三处当前逐字符等价（本人已核，且绘制方向经离屏实证自洽，见 §2-抽②），但任一处未来加 padding/缩放，另两处不会编译期报错，静默漂移即坐标错位。
- **依据**：三处源码并列比对。
- **建议修法**：`ImageGeometry` 增加 `static func fitRect(viewSize: CGSize, imagePixelSize: CGSize) -> CGRect`（返回 ox/oy/dw/dh），三处全部改调它；normalizedPoint 基于 fitRect 实现，marks 与 draw 共用。

### P2-6 §4.12 交叉引用措辞别扭（WindowManager 在 §4 无专节）

- **位置**：`docs/tech-design.md:292`（「复用 §4.5 之外的 `makeWindow(title:size:)` 工厂」）
- **问题**：§4.5 是 PanelController，makeWindow 属 WindowManager（§4 无其专节），「§4.5 之外的」读来像指错位置；意思是「PanelController 之外的 WindowManager 工厂」。
- **建议修法**：改「复用 `WindowManager.makeWindow(title:size:)` 工厂（与精读窗同一套模式）」。

---

## 2. 指定任务回执

### 任务 2：L1 修复 B1–B8 逐项复核

| # | 结论 | 证据 |
|---|---|---|
| B1 | ✅ 落实且**实跑通过** | 照抄 website/index.html:1170-1175 命令块（zsh 花括号展开）编译运行：`SELFCHECK ALL PASS`、PASS=91；:1167/:1261 两处 91 ✓ |
| B2 | ✅ 落实 | README.md:91 / README_EN.md:91 / tech-design.md:369 均为 91，与实际 PASS=91 一致（本人复跑）；全仓 `[6-8][0-9] 项/assertions` 残留 0（仅历史评审文档内引用，不计） |
| B3 | ✅ 落实但有残留 | :114/:292 已改实测卡宽口径、`inCardWidth` 引用清零——但同源残留新增两类未扫到：PROMPT_VERSION 概念（P2-2）与 §4.2 超时旧语义（P2-3）；且 :114 新措辞的「可拉宽」前提本身失实（P2-1） |
| B4 | ✅ 落实，命中区域不变 | `.help` 移到 GeometryReader 内但挂在 `Image` 上，而 `Image` 被 `.frame(width: geo.size.width, height: geo.size.height)` 撑满整个 geo（`CardViews.swift:198`）——help 命中区域与原外层 `.help` 相同（含 letterbox）；help 与 `tap()` 共用 `needsZoomWindow(imageWidth:cardWidth:)` 同一调用，口径一致 ✓。前提失实问题见 P2-1 |
| B5 | ✅ 落实且**经两种变异实证有效** | 变异 1：`version(for:)` 截图两类改回 `"m1"` → 3 FAIL（`prompt.versionPerKind`、`cachekey.screenshotVersionBumped`、`cachekey.screenshotKeyDiffersFromM1`）；变异 2：`makeKey` 改用硬编 `"m1"` 字面量（L2a P2-3 设想的漏网形态）→ 恰由新锚 `cachekey.screenshotKeyDiffersFromM1` 独立 FAIL（旧弱断言 `screenshotVersionBumped` 照常绿——证明 L2a 诊断准确且修复闭环）。缺陷：一条死条款（P2-4） |
| B6 | ✅ 落实，渲染安全 | `.notice` 相位 `content.isEmpty` 分支保持原样；非空时并渲染 `kindBody`——逐 kind 核：`.screenshotExplain`→ScreenshotCardBody（chips 取自部分 content，半表由 SectionExtractor 容忍；ImageTapView 仍可用，属预期改善）；`.word`/`.screenshotWordAt`→WordCardBody（`displayQuery` 正则对部分 content 安全，`stripFirstHeading` 容错）；`.sentence`/`.paragraph`→同构 chips 体。`content` 仅空白串时按非空渲染，无害。`MarkdownView` 成本 = 每次相位一次渲染，与 streaming 相同，无二次渲染问题。对 L2a P2-4 的反例检验：根卡流式中点 chip→返回的场景对**句/段根卡同样成立**（`pushWordQuery` guard `count<2` + `cancelCurrent` 不豁免 root + `popCard` 返回），B6 在相位层修复对三类根卡同时生效；未选「cancelCurrent 豁免 stack.first」是正确取舍——`run()` 单 `currentTask` 槽（`SessionCoordinator.swift:366`）不支持双流并发，状态机层修复代价远大于显示层。不掩盖状态机问题（根卡请求确被取消是既已接受的语义） |
| B7 | ✅ 落实，公式真同源 | `marks()`（ImageZoomWindow.swift:39-43）与 `ZoomImageNSView.draw`（:110-113）与 `ImageGeometry.normalizedPoint` 三处公式逐字符等价；归一化→显示区是换算的精确逆（`ox + nx*dw` ↔ `(clickX - ox)/dw`）；resize 后准星随 bounds 重解，漂移消除 ✓。`onTap` 签名去 viewPoint 后三处调用方（ImageZoomView 内部、WindowManager.showImage、ImageTapView.tap）一致 ✓。结构风险见 P2-5 |
| B8 | ✅ 落实 | L0 工件 CI-1/CI-2 两处失实声明已更正并留痕（A4 空操作、grep 范围漏 website/ 与英文措辞）✓ |

### 任务 1：GLM 同源盲区专项（新发现汇总）

- **P2-1（本轮最有价值的盲区实证）**：A1 的「面板可拉宽」动机、tech-design 两处措辞、SelfCheck 注释、乃至 L2a P2-2 的立项前提，全部建立在「用户能改变内容宽」上——被 `ResultPanelView.swift:15` 的 `.frame(width: 400)` 证伪。L0 发明理由、L2a 在理由上立项，**同源模型均未去核宽度钉点**。
- **P2-2/P2-3**：修复轮的同源扫描两次都只扫「被点名的锚串」（`inCardWidth`、计数），未扫「被删概念的其他化身」（PROMPT_VERSION 散文残留、超时旧语义条目）——与本次复审在 [[test-platform-assemble]] 记录的「锚点漂移只修对照表」同族。
- **B6 反例检验**（L2a「既有行为」论断复核）：成立，见 B6 行；句/段卡同场景 B6 同样覆盖，无掩盖。
- **L2a P2-5 反例检验**：B7 后归一化读数/发模型坐标/准星显示三者同源，resize 场景复核无反例。
- **未覆盖运行时语义**：isFlipped 绘制方向经离屏实证自洽（下）；`viewDidMoveToWindow` 抢 first responder 发生在窗未上屏时（`showImage` 先装 contentView 后 `makeKeyAndOrderFront`），若失败则首次 ESC 不到 `keyDown`——静态无法判死，列入实机清单（§3 第 8 条附带项）；`activate()` 抢焦点与 NSHostingView 生命周期：每次 showImage 装全新 hosting view，旧 view 随旧 responder chain 释放，无悬挂。

### 任务 3：L2a 结论抽查（独立复验 4 项）

1. **抽① pbxproj 自动入 target**——`xcodebuild clean` 后全量构建：`error:` 计数 0，`ImageGeometry.swift` 与 `ImageZoomWindow.swift` 各出现 4 次编译行 → 同步根目录自动入 target **实证成立**（L2a 判断正确，且本人用的是 clean 构建，比增量更硬）。
2. **抽② 坐标契约 + isFlipped 绘制方向**——离屏实证（`/tmp` 下 4 轮 harness，未触仓库）：同一 NSImage 经 (A) SwiftUI `Image(nsImage:)`（缩略图同款路径）与 (B) `isFlipped=true` NSView + `draw(in:)` + 同一 fit 公式（放大窗同款）各渲染一次，两次均用视图局部绿色顶条锚定位图行序——两路径「图区靠上/靠下」像素**完全一致** → `draw(in:)` 在 flipped 视图中翻正，`normalizedPoint` 的 y 向下口径与实际显示自洽，**无翻转 bug**（过程中本人曾用未锚定的位图行序得出过一次假阳性「画反」，经绿色锚点排除——说明该处确实容易误判，L2a 的 c 项结论正确且值得实证背书）。`convert(from: nil)`/`convert(to: nil)` 互逆判断：独立重推成立（window base→view local→window base 往返恒等，flippedness 由 convert 机制处理，教科书行为）；零尺寸 rect 取 origin 合法，下游 `positionBySelection` 纯点语义无退化（`PanelController.swift:143-150`）✓。
3. **抽③ D-e 三时序**——独立重推 L2a a 项：连续 3 词 / 第 2 词流式中点第 3 词 / ESC 藏面板后再点，三时序下不丢卡（root 永不被 removeLast——`pushWordAtQuery` 只在 `count>=2` 时弹子卡）、深度恒 ≤2、旧 Task 经 MainActor 串行 + `catch is CancellationError { return }`（`SessionCoordinator.swift:407`）无孤儿流、无缓存脏写 ✓。补一条 L2a 未写的交织：⌥S 采集进行中点击图片窗——`cancelCurrent` 会取消 `pendingCapture`，但系统 screencapture 交互 UI 独占鼠标，图内点击不可达，实际不可交织 ✓（不立项）。
4. **抽④ L2a §3 断言清单中的计数链**——PASS=91 复跑一致；`stack = [` 全仓恰 1 处（setRoot，`SessionCoordinator.swift:312`）✓；`makeKey` 5 调用点仅 `runText` 传 context ✓；静态 `version` 符号级无残留 ✓（概念级残留见 P2-2）。

---

## 3. 规格 §10 验收 11 条三分类

| # | 分类 | 说明 |
|---|---|---|
| 1 密集截图出 chips、点 chip 得词卡 | **需实机** | 代码侧契约（节名/表格解析/chips 渲染/row[3] 语境）已被 SelfCheck 4 条断言锁定；模型是否发 `**难词表**` 只能实机 |
| 2 升级后不命中 v0.1.7 旧缓存 | **代码可证** ✅ | `version(for:)` 双 m2 + B5 字节级锚定（本人两种变异实证） |
| 3 同词两截图各自语境 | **代码可证**（质量需实机） | context 入键断言 + `row[3]` 接线已核；语境义质量依赖模型 |
| 4 句/段 chips 无回归 | **代码可证 + 实机抽验** | 句/段路径仅 row[3] 增强与 B6 相位扩展，SectionExtractor 未动 |
| 5 放大窗点词/面板浮出/连续第 2 词/monitor 排除 | **需实机** | AppKit 层不进 SelfCheck（规格明示）；静态三时序推演 + 坐标口径已离屏实证 |
| 6 S6 小图就地、不被弹窗/重定位 | **代码可证逻辑 + 实机确认** | `needsZoomWindow` false 分支 + 条件式置前（`SessionCoordinator.swift:187-189`） |
| 7 多候选不编造 | **prompt 契约代码可证**（遵从需实机） | `prompt.screenshotWordAtCandidates` 断言锁定文案 |
| 8 windowWillClose 清理 + ESC 两级 | **需实机** | 附带核查项：①图片窗最小化后再点缩略图是否反最小化（L2a 已挂账，`makeKeyAndOrderFront` 对 miniaturized 窗行为以实机为准，必要时补 `deminiaturize`）；②`viewDidMoveToWindow` 在窗未上屏时抢 first responder 若失败，首次 ESC 是否可达 `keyDown`（mouseDown 会补抢，风险仅限「未点先按」） |
| 9 SelfCheck 全绿 + 三道发布闸 | **本环境已验前半** ✅（91/91）；发布闸属发布时动作（当前工作区未提交，干净闸本就该拒，属预期） |
| 10 换根关窗（D-f） | **代码可证 + 实机抽验** | `setRoot` 唯一收口（grep 恰 1 处 `stack = [`），四条换根路径全走它；≥400 词→showReader 不换根故窗与旧根仍绑定，无死路（与 L2a 推演一致） |
| 11 P1 例外 2 文档同步 | **代码可证** ✅ | product-design.md:12 双例外 + tech-design §4.12 已落（本人亲核原文） |

## 4. 本人复跑记录（命令与结果摘要）

| 验证 | 结果 |
|---|---|
| tech-design §8 命令编译运行 SelfCheck | `PASS=91 FAIL=0 SELFCHECK ALL PASS` ✅ |
| 变异 1：`version(for:)` 截图两类→m1（/tmp 副本，未触仓库） | 3 FAIL：`prompt.versionPerKind` / `cachekey.screenshotVersionBumped` / `cachekey.screenshotKeyDiffersFromM1` ✅ 符合预期 |
| 变异 2：`makeKey` 硬编 `"m1"`（/tmp 副本） | 恰 1 FAIL：`cachekey.screenshotKeyDiffersFromM1` ✅ B5 闭环 L2a P2-3 设想的漏网形态 |
| website/index.html:1170-1175 命令照抄 | 编译通过，`SELFCHECK ALL PASS`、PASS=91 ✅（B1 实证） |
| `xcodebuild` clean + Debug 全量构建 | exit 0、`error:`=0、两新文件各 4 条编译行 ✅ |
| isFlipped 离屏渲染（双路径绿锚对比，/tmp） | SwiftUI 与 flipped NSView 两路径像素一致 → 无翻转 ✅ |
| grep 终检 | `stack = [` 恰 1 处；makeKey 5 点仅 runText 传 context；`[6-8][0-9] 项/assertions` 业务文档 0 残留；`PromptLibrary.version` 符号 0 残留；`PROMPT_VERSION` 概念 5 残留（P2-2） |

## 5. 查过未报的边界

- **ESC `keyDown` 内同步释放窗口**（L2a 已挂账）：补一条安全性证据——`performClose`+`isReleasedWhenClosed=true` 是 Apple 支持的在事件派发中同步释放窗口的范式，说明 AppKit 事件派发对窗对象有存活保护；且 `keyDown` 置空后不再触碰 self。维持不立项；求稳可 `DispatchQueue.main.async` 延迟置空。
- **`.notice` 卡无重试入口**：footer 的「重新查询」仅 `usedCache` 时显示（`ResultPanelView.swift:159-164`），被取消根卡（非缓存）用户只能重触发查询——既有行为，非本 diff 引入，B6 未加剧。
- **窄长图分流盲区**：分流判据只看自然宽（规格 §4.5 钦定）——350×2000 之类窄长截图宽 ≤376 走就地，缩略图仍不可读；§11 次级项 1 本就开放该判据，实机若遇到再评估，不立项。
- **`ZoomImageView.updateNSView` 每次 state 变更重设 image 触发 `needsDisplay`**：每次点击多一次静态图重绘，可忽略。
- **`.zcodeignore`（未跟踪）**：ZCode 工具文件，非本 diff 功能件；是否入库请作者决定。
- **实机清单已并入 §3 第 5/8/10 条**，不再单列。

## 6. 基础一致性瑕疵（确认无影响，合并一行）

L0 修复记录 B1 称「删**不存在的** ProviderPresets」——`Gloss/Core/ProviderPresets.swift` 实际存在且自包含可编译，删它的正确理由是「自检不引用其符号」，措辞失实但动作与结果正确（website 命令实跑通过）；另 §4.12「复用 §4.5 之外的 makeWindow」措辞别扭已单列为 P2-6。
