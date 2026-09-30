# L2a 独立第一审报告：proposal-2026-09-29-word-drilldown.md（二轮修订版）

- 审查人：glm-reviewer-hs（独立冷启动，不采信 L0 自查与主 Agent 结论）
- 审查对象：`docs/proposal-2026-09-29-word-drilldown.md`（2026-09-29 二轮复审修订版）+ L0 自查工件（仅作透明素材）
- 方式：全文通读 + 11 个代码文件独立 Read 核对 + 锚定串 grep 复跑 + D-e/D-b 事件时序独立推演
- 代码基线：v0.1.7 后未发布工作区（含 VisibleIdleGuard 等未提交改动，与任务书声明一致）

## 0. 结论表

| 分级 | 计数 | 摘要 |
|---|---|---|
| **P0（阻塞）** | **0** | D-e 栈顶替换规格在指定必查场景下推演闭环；D-d 缓存版本推演成立；未发现会致错/数据损坏/假绿的缺陷 |
| **P1（建议）** | **2** | ① 图片窗与会话生命周期解耦：栈首换成非截图卡后点击成静默死路、换成新截图卡后跨会话混栈（§4.3/§4.5 规格缺口）；② B2 与 product-design.md P1 零打断的字面冲突未收口——例外条款是封闭单例外，且 §10/验收无 P1 修订步骤，含全屏 Space 切换风险（§4.2） |
| **P2（风格）** | **6** | §3.1③ 措辞与 §6.2 机制错位；截图难词表 prompt 缺"例句不新造"护栏；§4.5 表格行与注记口径不一；§6.1 sentence 类同类问题未处理且无取舍说明；windowWillClose imageWindow 分支清理内容未指明；L0 ③ 两处锚定串计数口径不准 |

**总体判断**：二轮修订版质量高——文档中全部 24 组代码事实断言（file:line）逐一独立核对无一错位；D-e（P0 修复）与 D-d（P1 修复）的核心推演均独立复验成立；两处 P1 均为修订版视野之外的规格缺口，不推翻 A+B2+C 决策框架。修复后可进实施。

---

## 1. 分级问题清单

### P1-1 图片窗与会话生命周期解耦：栈首变更后的两条未定义路径（§4.3「点词」/§4.5 改动清单）

**位置**：§4.3 栈顶替换规格（:229-234）、§4.5 SessionCoordinator 行（:298）、§9.1 风险表（:436-437 未列此项）

**问题描述**：D-e 放宽条件是 `stack.first?.kind == .screenshotExplain`（按 kind 判，不按会话/图像身份判）。但图片窗的存活与栈根的生命周期完全无关——任何新查询入口都会整体替换栈（`show(card:)` 置 `stack = [card]`，SessionCoordinator.swift:300-304；`replay` 同，:409-420），而图片窗不会被这些路径关闭。由此产生两条可复现的未定义路径：

- **路径 A（静默死路）**：图片窗开着，用户对别处文本 ⌥D / Services 划词 → 栈根换成 word/sentence 卡。此后图片窗内点击：`pushWordAtQuery` 的 `stack.first?.kind == .screenshotExplain` 守卫（SessionCoordinator.swift:172）静默 `return`——无查询、无面板浮出、无任何反馈；又因 §4.3 的 monitor 排除（`ev.window === imageWindow` 直接跳过），连"点击藏面板"的副反馈都没有。方案宣称的核心卖点「图片窗保持打开、便于连续查多个词」（:228）在此路径下失效，唯一恢复手段是用户自己想到关窗。
- **路径 B（跨会话混栈）**：图片窗开着（来自截图 E1），用户再 ⌥S 截一张新图 → 栈根换成 E2。此后图片窗内点击：kind 守卫**通过**（E2 也是 screenshotExplain）→ E1 的图像 wordAt 卡被压在 E2 的根上，栈为 `[E2, W(E1图)]`。「返回整图」按钮（backLabel 按 `stack.first`，CardViews.swift:39-46）返回的是 **E2**——用户看着 E1 的放大窗查词，返回却落到另一张图。结果内容本身对 E1 无误（查询用的是窗内图像），但导航语义错乱。

**依据**：SessionCoordinator.swift:172（仅按 kind 的守卫）、:300-304（`show(card:)` 无条件换栈、不触及任何窗口）、:143-156/:76-97（⌥S/⌥D/Services 均经 `show(card:)`）；PanelController.swift:179-206（monitor 排除后图片窗点击不再有任何面板反馈通道）。

**建议修法**（择一或叠加）：
1. **主修**：`SessionCoordinator.show(card:)`（及 `replay`）在置新根时关闭图片窗（`WindowManager.shared.closeImageWindow()`）——窗口生命周期绑定"它所放大的那次截图会话"，两条路径同时消灭。
2. **加固**（可选）：`pushWordAtQuery` 增加图像身份校验 `stack.first?.originalImage === image || stack.first?.thumbnail === image`（thumbnail 分支保历史回放卡就地点词路径不被误杀），身份不符时同样关闭或提示。
3. §9.1 风险表补一行对应条目。

### P1-2 B2 与 product-design.md P1 零打断的字面冲突未收口（§4.2/§4.3/§10）

**位置**：§4.2 对比表 B2 行「是否违反 P1 零打断：⚠️ 是（属既有例外类别）」（:179）、选定理由 3（:193-194）、§10 无对应步骤

**问题描述**：product-design.md:12 的 P1 是封闭单例外——「**唯一例外**：≥400 词长选段直接开精读窗，属预期的显式深读动作」，且三条原则明示「所有交互争议以此裁决」。B2 的「属既有例外类别」是类比引申而非条款覆盖；B2 实际造成的打断比精读窗路径更重，方案未逐项评估：

1. `showImage` 照 `showReader` 模式走 `NSApp.activate(ignoringOtherApps: true)`（WindowManager.swift:14-16）。面板是 nonactivating（PanelController.swift:33 `becomesKeyOnlyIfNeeded`），用户点击面板缩略图时**活动 app 仍是原阅读 app**；开窗瞬间活动 app 被抢成 Gloss，菜单栏随之外观切换——直接命中 P1 禁语「不切窗口」。
2. `makeWindow`（WindowManager.swift:72-80）不设 `collectionBehavior`，默认不含 `canJoinAllSpaces`。用户身处其他 app 的**全屏 Space**（S4 视频字幕恰是高频全屏场景，截图面板能悬浮其上正因它特意设了 `[.canJoinAllSpaces, .fullScreenAuxiliary]`，PanelController.swift:32）时，`makeKeyAndOrderFront` 会把整个系统切离全屏 Space——这不是"开一个窗"而是"离开当前阅读上下文"的字面实现。§9.1 风险表无此项。

方案头部虽有「实施完成后本文相应条目合并进 product-design.md / tech-design.md」（:9），但 §10 六步骤与 9 条验收标准均无 P1 例外条款修订项——按现状实施完成即出现裁决文档与已发布行为的自相矛盾。

**建议修法**：
1. 现在钉死修订后的 P1 例外文案（例：「例外 2：点击截图卡缩略图打开图片放大窗，属预期的显式细看动作」），作为 §10 新增步骤（如步骤 7）与验收项；
2. §9.1 补「全屏 Space 下开窗导致 Space 切换」风险行，并在此风险与例外 2 文案中明确取舍（接受切换，或评估给图片窗临时加 `canJoinAllSpaces` 的代价）。

---

### P2 清单

| # | 位置 | 问题 | 建议 |
|---|---|---|---|
| P2-1 | §3.1③（:144-146） | 「改为传**该行的原文例句**」在调用侧不可实现——例句是 per-row 数据，只在 `WordChipsRow` 的 ForEach 内可见；实际机制是 §6.2 在 `WordChipsRow` 内部按行取 `row[3]`、调用侧仍传 `card.inputText`（=nil）。两句表述错位，实施者可能照 §3.1③ 在 `ScreenshotCardBody` 侧硬造传值 | §3.1③ 改写为「截图卡 context 传 nil；例句由 §6.2 在 WordChipsRow 内部按行取 row[3]」 |
| P2-2 | §3.1① 模板（:111-119） | 截图难词表列 `图中原文例句` 无「不新造」护栏——段落模板有先例「原文例句取自输入原文，不新造」（PromptLibrary.swift:56），截图模板未要求例句与「识别内容」节转写一致，模型可能改写例句，污染 §6.2 传入 word 查询的 context | 模板补「例句须与**识别内容**节的转写逐字一致，不新造不改写」 |
| P2-3 | §4.5 表格（:296） | 表格行「截图卡点击改为『开窗』而非直接点词」是无条件表述，与紧随注记「若原图自然宽度 ≤ 卡片内宽则直接点词，否则开放大窗」（:301-302）口径不一，表格读作 S6 也强制开窗 | 表格行补「（按宽度分流）」对齐注记 |
| P2-4 | §6.1（:363-367） | context 入键限定 `kind == .word`；但 sentence prompt 同样拼 `语境：`（PromptLibrary.swift:46）——同句不同 surrounding context 命中旧缓存的同类问题在 sentence 类未处理，文档未说明取舍理由 | 补一句取舍说明（如「句/段输入自身即主导语境，context 边际影响小，故不并入」）或将范围决策记入 §0 |
| P2-5 | §4.3 关闭（:262-264） | 「`windowWillClose` 需扩展以识别 `imageWindow`」未指明分支体做什么——图片窗无可取消的 VM，实际清理仅 `imageWindow = nil`（释引用）；规格留白可能被实施成空分支或误抄 reader 的 cancel 逻辑 | 补一句「分支体 = 置空 `imageWindow` 引用（无可取消任务）」 |
| P2-6 | L0 文档 ③（:44-45，非方案文档缺陷） | 锚定串计数口径不准：`栈顶替换` 称「共 5 处（§0/§4.3/§9.1/§10/§11）」，实为 7 处（另见 §4.5:298、§8:422）；`version(for:` 称 3 处，实为 8 行（另见 §9.1:438、§10:456/467）。**语义一致性结论均成立**（全部映射 screenshotExplain/screenshotWordAt→m2、word→m1，无矛盾表述） | L0 若再版改计数口径；无需改方案文档 |

---

## 2. 抽查记录

### a.【P0 修复核心】D-e 栈顶替换事件时序独立推演（对照 SessionCoordinator.swift:171-189 / PanelController.swift:179-206）

前置状态：⌥S → 栈 `[E]`（E=screenshotExplain，done），面板可见（monitors 已装、ESC 已注册）；点击面板缩略图（此点击在面板内，local monitor 判位置在面板 frame 内 → 不藏）→ 图片窗打开，持 E 的原图。

**第一次点词（mouseDown→local monitor→tap→push→show）**：
1. mouseDown 落图片窗 → local monitor：面板可见、未 pinned、鼠标位置在面板外 → 无修复本应 `hide()`；**修复后** `ev.window === imageWindow` 跳过 → 面板不动，无闪隐/churn ✓
2. mouseUp → SpatialTapGesture.onEnded → 归一化坐标 + clickRect → `pushWordAtQuery`
3. 守卫：count=1<2 ✓、first.kind==screenshotExplain ✓；`cancelCurrent()`（E 已 done 不受影响，:246-256）；append → `[E, W1]`；revision+=1
4. 新增 `PanelController.shared.show(near: clickRect)`：positionOverride→restoredOrigin→就近三级定位（:53-67）；`installMonitors` 幂等（:180 `guard monitors.isEmpty`）；`registerEscape` 幂等（HotkeyManager.swift:15 重复注册先卸旧，无泄漏）✓
5. 面板显示 W1（loading→streaming→done），backLabel="返回整图"（first 为 screenshotExplain，CardViews.swift:44）✓ **闭环**

**第二次点词（连续查两词）**：mouseDown 同上被排除；`pushWordAtQuery`：count==2 → D-e：first 仍为 E → `removeLast()` 弃 W1 → push W2 → `[E, W2]`；`show(near: clickRect2)` 面板换卡。W1 若在流式中被 `cancelCurrent` 标「已取消」后即被弹出，无论 pop/cancel 先后序均无害 ✓ **原 P0 主场景修复成立**

**第三次点词（面板先被 ESC 藏掉）**：ESC → Carbon 消费式热键（HotkeyManager.swift:57-61 已核实「消费式」与面板互斥注释）→ `hide()`（orderOut + removeMonitors + unregisterEscape + `panelDidHide→cancelCurrent`，:77-83），栈保持 `[E, W2]`。此后图片窗点击：monitors 已拆无干扰；tap → D-e pop W2 push W3 → `show(near:)` 面板**重新浮出**（panel 复用 + orderFrontRegardless，:50-72）✓ **原 P0 的「无恢复路径」半边由 D-e + show(near:) 联合闭环**

**pinned 状态**：monitor handler 在 pinned 时早退（:184/:197），本就不藏；每次 `show(near:)` 重定位面板——与 ⌥D 每次新查询重定位 pinned 面板的现状语义一致（beginHotkeyQuery → show(near:)），非新缺陷（未报）。

**栈首非截图卡**：**不闭环**——静默死路 + 跨会话混栈两条路径，见 P1-1。此为 D-e 规格（仅按 kind 判）与图片窗不随栈根关闭共同留下的缺口，任务书指定的该项必查点在此处命中真实缺陷。

**chips 路径不动的声明核验**：chips 仅渲染于栈顶卡身（word 卡无 chips），`pushWordQuery` 从 UI 不可达 count==2，声明成立 ✓。

### b.【D-d】§5.1 缓存版本推演（对照 CacheStore.swift:26-34 / PromptLibrary.swift:6）

- `makeKey` payload 含 `PromptLibrary.version`（:27）+ `kind.rawValue` + 1% 量化的 `pt:x,y`（wordAt 专属，:28-31）→ `version(for:)` 分 kind 后：word/sentence/paragraph/article/pdfPage 键**逐字节不变**（老缓存全保留）✓；两类截图键各整体失效一次 ✓
- 「老缓存复活旧单猜」矛盾为真：wordAt 若保持 m1，同图同点（1% 网格内）命中 v0.1.7 旧条目，返回旧 prompt 的单猜答案，且除「重新查询」（ResultPanelView.swift:159-164 唯一 useCache:false 入口）外无刷新路径——恰是 C 要消灭的行为从缓存复活。升 m2 后旧键永不再命中，LRU 自然淘汰 ✓ **D-d 修复成立**
- 「整图与点词互不误命中」：kind 字串不同（"screenshotExplain" vs "screenshotWordAt"），pt 后缀仅点词键有 ✓
- 静态 `version` 删除的引用面：grep 实证全仓恰 2 处（CacheStore.swift:27、SelfCheck/main.swift:102），与方案声明一致；SelfCheck:121 LRU 测试硬编码 `"k\(i)|word|m|m1"` 只是任意唯一键串，不受删除影响 ✓
- `version(for:)` 的 switch（screenshotExplain/screenshotWordAt→m2，default→m1）对 QueryKind 七个 case（QueryRouter.swift:4-8）经 default 穷尽 ✓

### c.【自审声明抽查】L0 ③ 锚定串复跑（4 组全跑）

| 锚定串 | L0 声明 | 实测 | 判定 |
|---|---|---|---|
| `grep -rn "PromptLibrary\.version" Gloss SelfCheck scripts` | 恰 2 处 | CacheStore.swift:27 + SelfCheck/main.swift:102，恰 2 | **真实** |
| `grep -c '^check(' SelfCheck/main.swift` | 68（=65+9） | 68 | **真实** |
| `双击适应`/`约 1 行`/`已在 §4.5 补充`/`## 难词表`（方案内） | 0 命中 | 0 命中 | **真实** |
| `prompt 不变`/`保持 m1`/`轻微下移` | 各 1-2 命中且全在标废引用 | :20、:251、:343，均为标废/修订说明上下文 | **真实** |
| `栈顶替换` 5 处 / `version(for:` 3 处 | 语义一致 | 7 处 / 8 行，语义全一致 | 结论真实，**计数口径不准**（P2-6） |

L0 CI-2 抽查的 6 组代码断言（:172/:179-206/:56-59/SelfCheck:102/version 2 处引用/ResultPanelView:68-69）本审全部独立复核为真；§1.2 log 数据 L0 声明未重跑，旁证 LLMClient.swift:35「图上点词实测 4–14s」注释实核存在。

### d.【场景推演】S1–S6 端到端 + P1 判定

- **S1 密集文本**：⌥S → 整图卡含 chips（A）→ 点 chip → 词卡（context=row[3] 例句，键含 ctx）✓；走 B2 指点 → C 多候选兜底 ✓
- **S2/S3/S4**：chips 取自模型「识别内容」转写，命中即正确 ✓（S4 全屏场景的 Space 切换问题归入 P1-2）
- **S5 转写错**：chips 带错拼写，A 覆盖不到 → B2 像素级指点是唯一覆盖，方案自知（:98）✓
- **S6 小图**：宽度 ≤376pt 走卡片内就地点击原路径；Retina 2x 小图的宽度口径歧义已被 §11 列为实施期待定项 ✓
- **P1 零打断**：B2 违反 P1 **字面**（切窗口 + activate 抢活动 app + 全屏 Space 强切），例外条款不覆盖——判定与修法见 P1-2。「例外类比」本身可辩护（同为用户显式触发的一次性深看动作），缺的是条款收口而非方向错误。

---

## 3. 核对过的断言清单（全部独立 Read/grep，无一错位）

**代码锚点（24 组全对）**：CardViews.swift :153-164（ScreenshotCardBody 无 chips）、:191（height 160）、:179（scaledToFit）、:117/:146（句/段卡 chips 先例）、:184-188（坐标换算算法）、:206-211（row[3] 丢弃）、:39-46（backLabel 按 stack.first）；SessionCoordinator.swift :171-189（pushWordAtQuery 守卫与无置前）、:172（guard 行号精确）、:246-256（cancelCurrent 标已取消）、:300-304（show 换栈）、:312（原图保存）、:320-326（runText 键无 context）、:401-406（历史缩略图 ≤200）；PanelController.swift :26-33（nonactivating/floating/canJoinAllSpaces/fullScreenAuxiliary）、:49-75（show 三级定位 + orderFrontRegardless:72）、:56-59（restoredOrigin 分支）、:77-83（hide 拆装）、:179-206（monitors）；WindowManager.swift :11/:46-62/:56-59 注释/:66-70/:72-80（含 makeWindow 无 collectionBehavior）；HotkeyManager.swift :14-15/:57-61（消费式+幂等）；CacheStore.swift :26-34；PromptLibrary.swift :6/:46/:56/:60-77；QueryRouter.swift :4-14；ResultPanelView.swift :68-69/:159-164；SelfCheck/main.swift :102、68 checks、VisibleIdleGuard 9 checks；LLMClient.swift :27-53/:35。

**文档锚点**：DESIGN.md D5（不用本地 OCR）/D9 ✓；product-design.md :12 P1 唯一例外原文 ✓；§1.1 算术（0.163/246pt/2.1px）复算 ✓；§0-§11 章节引用（§4.3→§4.4、§7→§5.1、验收 5 含 D-e+monitor 两要素）逐个走通 ✓。

## 4. 查过未报的边界（P0=0 的旁证义务）

- pinned 面板 + 图片窗连续点词（重定位语义与 ⌥D 现状一致）
- ESC 两级时序（Carbon 消费式拦截在前、keyDown 在后，架构成立）
- monitor 排除的 global/local 分工声明（global monitor 只收他 app 事件，AppKit 语义正确）
- 面板已隐藏后第三次点击恢复路径（D-e + show(near:) 闭环，见 2a）
- 图片窗 letterbox 空白区点击（0…1 guard 拒绝，与现状一致）
- 图片窗拉大/zoom 后换算公式（fit 满窗前提下恒成立，§4.4 前提钉死正确）
- 历史回放卡 ≤200px 自然走就地点词（不误开窗）
- makeKey context 默认参数的调用面（runText 唯一需接线处，方案已写明）
- demoWordAtQuery 在新签名下的兼容（clickRect 可默认 nil）
- §10 步骤 6 依赖 2、4 的软依赖合理性（同文件改动域）
- `payload += "|ctx:" + sha.prefix(8)` 的 String+Substring 拼接可编译性（String 的 Sequence 重载覆盖）

## 5. 行动项清单（每项可独立执行）

1. 【P1-1】`show(card:)`/`replay` 置新根时关闭图片窗（或 pushWordAtQuery 加图像身份校验），§9.1 补风险行
2. 【P1-2】钉死修订后的 P1 例外 2 文案并入 §10 步骤 + 验收；§9.1 补全屏 Space 切换风险
3. 【P2-1】§3.1③ 措辞对齐 §6.2 机制
4. 【P2-2】截图难词表模板补「例句与识别内容一致、不新造」
5. 【P2-3】§4.5 表格行补「按宽度分流」
6. 【P2-4】§6.1 补 sentence 类不并入的取舍说明
7. 【P2-5】§4.3 windowWillClose imageWindow 分支体写明（置空引用）
8. 【P2-6】L0 再版时修正两处计数口径（方案文档无需动）
