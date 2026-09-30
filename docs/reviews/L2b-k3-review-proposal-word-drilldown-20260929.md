# L2b K3 异构终审报告：proposal-2026-09-29-word-drilldown.md（终版候选）

- 审查人：K3（异构模型，与主 Agent / glm-reviewer-hs 不同源）
- 审查对象：`docs/proposal-2026-09-29-word-drilldown.md` + L2a 报告 + L0 自查/L1 修复记录 + 代码基线（v0.1.7 后未发布工作区）
- 方式：全文通读 + 14 个代码/文档文件独立 Read 核对 + 锚定串 grep 复跑 + swiftc 实证 + D-e/D-f 时序独立推演；不采信前轮结论
- 纪律声明：前轮「未发现问题」不构成干净信号；本审对范围外与前轮已验处均独立复核

## 0. 结论表

| 分级 | 计数 | 摘要 |
|---|---|---|
| **P0（阻塞）** | **0** | D-e/D-f 时序推演闭环；缓存版本与 ctx 入键推演成立；未发现致错/数据损坏/假绿缺陷 |
| **P1（建议）** | **2** | ① §4.3 新增的无条件 `show(near:)` 未区分图片窗路径与卡片内就地点词路径，S6 就地点词的面板定位行为被未声明地改变（与「完全保留」承诺相抵）；② 坐标换算规格只钉视图内归一化，未钉 SwiftUI 视图坐标→Cocoa 全局屏幕坐标的另一半（y 翻转/多屏），实施分叉风险 |
| **P2（风格）** | **7** | imageWindow 声明 private 与 monitor 排除跨类型引用矛盾；D-f「任何置新栈根路径」枚举遗漏 requery；§10 步骤 5「无依赖」与 D-d 自身论证口径不一；例句含竖线破表格解析污染 context；versionLegacyRemoved 断言名不副实；ctx 入键未归一化；状态行抢跑+L0 计数残留不准（合并行） |

**总体判断**：L1 修复轮质量高，2 项 P1、5 项 P2 修复全部逐条核验落实，例外 2 文案六处同源一致。两处 P1 均为 B2 新机制的规格缺口（非方向错误，不与 A+B2+C 框架冲突），修复量各一两段文字。**修完 P1-1/P1-2 后可定稿进入实施；P2 随实施一并处理。**

---

## 1. 分级问题清单

### P1-1 `pushWordAtQuery` 新增的无条件 `show(near:)` 未区分两条调用路径，S6 就地点词面板定位被未声明改变（§4.3「结果卡片去向」/§4.5）

**位置**：§4.3 代码片段（:259-262）、§4.3 点词（:234-236）、§4.3 保留（:291）、§4.5 SessionCoordinator 行（:318）

**问题描述**：§4.3 规格在 `pushWordAtQuery` 内 `stack.append` 之后无条件新增一行 `PanelController.shared.show(near: clickRectInScreenCoords)`。但 `pushWordAtQuery` 同时服务两条路径——图片窗路径与卡片内就地点词路径（`ImageTapView` 手势回调，`CardViews.swift:188`；§4.3「保留」明确 S6 就地点击完全保留、§4.5 注记按宽度分流保留就地点词）。无论 clickRect 设计为哪种形态，都存在未声明的行为变更或矛盾：

- **若 clickRect 非可选**（§4.3 签名 `pushWordAtQuery(image:point:clickRect:)` 与片段变量名均按非可选呈现）：就地路径也必须换算屏幕 rect 传入，且每次就地点词面板被重定位到点击处/记忆位——现状是面板原地不动（当前 `pushWordAtQuery` 不含任何 show 调用，`SessionCoordinator.swift:171-189` 实核）。这与 §4.3「卡片内缩略图与就地点击**完全保留**」（:291）及验收 6 的 S6 承诺相抵，且验收 6 只查「不被强制弹窗」，查不到面板移位。
- **若 clickRect 可选而无条件 show**：nil 时 `show(near: nil)` 走 `positionByMouse`（`PanelController.swift:60-66` 实核），面板跳到鼠标位置——同样是未声明的行为变更。
- L2a §4「查过未报」中「demoWordAtQuery 在新签名下的兼容（clickRect 可默认 nil）」一句预设了可选形态，与 §4.3 的非可选呈现冲突——两轮 GLM 审均未发现该歧义；demo 验收通道（`AppDelegate.swift:165` → `demoWordAtQuery`，`SessionCoordinator.swift:284-288`）的兼容故事随之悬空。

**依据**：`CardViews.swift:188`（就地点词与图片窗共用 pushWordAtQuery）；`SessionCoordinator.swift:171-189`（现状无置前）；`PanelController.swift:49-75`（show 三级定位 + 每次必 move）；`PanelController.swift:24`（`isVisible` 现存可用）。

**建议修法**：规格钉死条件式置前——`if !PanelController.shared.isVisible { PanelController.shared.show(near: clickRect) }`（就地路径面板必可见故不重定位，行为真正「完全保留」；图片窗路径面板被 ESC/外点藏掉时可复活），并声明就地路径传 `clickRect: nil`。同步明确 demoWordAtQuery 的默认参数形态。

### P1-2 坐标换算规格缺另一半：SwiftUI 视图局部坐标 → Cocoa 全局屏幕坐标的换算契约未钉（§4.4/§4.5）

**位置**：§4.4（:293-308）、§4.5 ImageZoomWindow 行（:315）、§4.3 点词（:234-236）

**问题描述**：§4.4 把「坐标换算」钉死为视图内归一化公式（view/image 尺寸 + 点击点 → 0…1），但 `show(near:)` 需要的 `clickRect` 是 **Cocoa 全局屏幕坐标**（y 向上、多屏各自 frame）——`PanelController.swift:142` 注释「CaptureResult 侧已完成 AX→Cocoa 转换」与 `positionBySelection` 直接用 `sel.minY/minX` 于可见屏坐标系（:136-153）共同确立了该契约。而 SwiftUI `SpatialTapGesture` 给出的 `v.location` 是视图局部坐标（y 向下）。文档全部提及只有 §4.5 一句「点击回调（含屏幕坐标换算）」。实施者面对多条实现路径（`NSView.convert(_:to:)` + `window.convertToScreen`；或 `window.frame.origin` + 内容区偏移 + 内容区内 y 翻转），其中手搓 `NSScreen.main.frame.height - y` 的经典单屏公式在多屏布局下即错（仅当目标屏位于主屏正上方时偶然成立）。L0 自审与 L2a 均把 ImageZoomWindow 内部实现归为「实施期细节」，但坐标系的**跨层契约**（谁负责翻转、是否多屏安全）不属于实现细节，恰是 §4.4 该钉而未钉的部分。

**依据**：`PanelController.swift:136-153`（positionBySelection 的坐标系契约）、`CardViews.swift:184-188`（SwiftUI tap 输出视图片段坐标的现状）；§4.4 全文仅覆盖归一化。

**建议修法**：§4.4 增补第二段换算契约（推荐经 `NSView.convert(_:to: nil)` + `window.convertToScreen(_:)`，明确禁止手搓单屏 y 翻转公式，多屏安全由 convertToScreen 保证），或把该换算一并收口进 §4.4 的共享函数（签名增 window frame / contentLayoutRect 入参）。

---

### P2 清单

| # | 位置 | 问题 | 依据 | 建议 |
|---|---|---|---|---|
| P2-1 | §4.3 :218 vs :274-275；§4.5 :314 | monitor 排除判 `ev.window === WindowManager.shared.imageWindow`，但同节把 `imageWindow` 声明为 `private var`——private 跨类型不可达，PanelController 引用不了，规格自相矛盾 | 方案文档两处原文；Swift 访问控制语义 | 去掉 private，或加 `func isImageWindow(_ w: NSWindow) -> Bool` 访问器 |
| P2-2 | §4.3 :243-245（D-f） | 「**任何**置新栈根的路径（show(card:)…replay）」枚举遗漏第三个置根点 `requery`（`SessionCoordinator.swift:205` `stack = [card]`，UI 可达 `ResultPanelView.swift:123`）。当前被 requery 守卫（root.inputText 非空，:201）挡住故不可达——潜在缺口而非现患，但全称声明不实，未来改动可静默绕过 | `grep -n "stack = \[card\]"` 实证三处：:205/:301/:417，D-f 只覆盖后两处 | 措辞改为枚举三处并注明 requery 因守卫不可达；或把 closeImageWindow 收口进唯一栈根赋值点 |
| P2-3 | §10 :499 | 步骤 5（方案 C prompt）依赖列标「无依赖」，与 D-d 自身论证矛盾——D-d 存在的理由正是「prompt 变更不升版本=旧缓存复活旧单猜行为」（§5.1 :363-366），步骤 3 恰以同理由标「依赖 1」。同分支同版本发布使实害为零，属依赖标注口径不一 | §10 表 :495/:499 对照；§5.1 D-d 标废段 | 步骤 5 依赖列补「1」 |
| P2-4 | §3.1① :120 | 难词表例句列含 `\|` 时 `tableRows` 朴素切分（`SectionExtractor.swift:71` `components(separatedBy: "|")`）致单元格错位、`row[3]` 取到例句片段——终端/代码截图的例句含管道符（如 `ls \| grep foo`）概率显著高于散文段落（段落卡既有暴露面更低）。§3.1① 已有「逐字一致」护栏但无竖线护栏；后果是 §6.2 流入 word 查询的 context 与 §6.1 缓存键被片段污染 | `SectionExtractor.swift:66-76`；§6.2 :407-408 消费链 | 模板补「例句含竖线时以 / 替代或截断」；或 tableRows 支持 `\|` 转义 |
| P2-5 | §8 :442 | `prompt.versionLegacyRemoved` 断言名不副实——「静态常量已删」是符号缺席，运行时不可断言；该断言实际能钉的只有 `version(for: .word) == "m1"`。删除约束事实上由编译期保证（残留引用即编译错误），断言名会给读者「有运行时闸」的错觉 | §8 表格原文；SelfCheck 纯断言机制（`main.swift:8` check 签名） | 断言改名（如 `prompt.versionForWordUnchanged`）或在 §8 注明删除靠编译期保证 |
| P2-6 | §6.1 :387-389 | ctx 入键对 context 原文直接 `glossSHA256(c)`，未经 `cacheNormalized` 归一（对照输入键的归一，`QueryRouter.swift:39-42`）——同一语境的空白变体产生不同键。仅缓存效率损失，无正确性问题 | §6.1 代码片段；`QueryRouter.swift:40-42` | `glossSHA256(QueryRouter.cacheNormalized(c))` |
| P2-7 | 文档头 :3；L0 文档 ③/L1 复核段 | 基础瑕疵合并行（已评估无 P0/P1 影响）：① 文档头状态行「已评审通过…待实施」先于 L2b 终审，本轮有 P1 需回改；② L0 的 `version(for:` 计数仍不准（称 8 行，实测 9 处/7 行——其余三组计数实证吻合：`栈顶替换`=11、`D-f`=12、`例外 2`=7） | 文档头原文；grep -o 复跑 | 定稿时回改状态行；L0 再版时修正计数口径 |

---

## 2. 三项指定任务记录

### 任务 1：GLM 同源盲区专项

- **坐标换算**：命中 P1-2（屏幕坐标半段未钉）。归一化半段核验无问题：§4.4 公式与现状 `CardViews.swift:174-187` 逐项一致（含 max(dw,1) 守卫）；归一化对点/像素口径天然免疫（比值不变）；NSImage 口径实证——`NSImage(pasteboard:)`（`ScreenshotManager.swift:32`）尊重 Retina 截图的 144dpi，size 为点（§1.1 的 1512 与此一致）；`thumbnailImage` 经 `NSImage(data:)`（`ImagePipeline.swift:43-46`）size=像素值 ≤200，历史回放卡自然走就地点词 ✓。「自然宽度」的口径歧义仅存于 1x 屏/合成图，已由 §11 次级项 1 收口（L2a 称「Retina 2x 口径歧义已列入 §11」为略超原文的表述——§11 项 1 钉的是判据选择，口径未显式列出，但主路径无歧义，未升级为问题）。
- **尺寸协商**：窗内版无固定 frame 时 viewW/viewH 取自窗口内容区的 GeometryReader——`NSHostingView` 填充内容区、geo 测根视图，公式随窗口缩放恒成立（§4.4 前提覆盖）；十字准星/坐标读数被 §4.3「**叠加**」钉为 overlay，不污染 viewH 口径。**查过未报**。
- **prompt 契约**：命中 P2-4（竖线）。其余边界实证：`SectionExtractor.isSectionHeader`（:11-19）覆盖 `**难词表**`/`**难词表**：`/`**难词表**（若有）` 变体；模型若用 `### 难词表` 则静默无 chips——契约类既有行为（句/段卡同暴露面），非本轮新增；`**要点**` 后空行、节乱序、整节省略（§8 noWordTableIsNoop 锁定）均走通。**除 P2-4 外未报**。
- **缓存键**：`ctx:` 8 位 hex 前缀 = 32bit，maxEntries=2000 下生日碰撞概率约 5e-4，碰撞后果仅同词跨语境误命中一次——量级可接受，**未报**；`version(for:)` switch 经 default 穷尽 QueryKind 七 case（`QueryRouter.swift:4-8`），未来新增 kind 静默落 m1 属可接受默认，**未报**；命中 P2-6（ctx 未归一）。
- **§10 可实施性**：步骤 1-7 依赖无循环；每步有验证手段；步骤 6 对 2、4 的软依赖（同文件改动域）合理。命中 P2-3（步骤 5 依赖标注）。验收 1-11 与步骤映射逐条核通（5↔6、8↔6、10↔6、11↔7、2↔1、3↔2）。

### 任务 2：L1 修复处复核（编辑 18-27 逐条）

| 编辑 | 核验 | 结论 |
|---|---|---|
| 18-19 D-f | D-f×D-e 交互推演：换根关窗后窗内点击不可达，D-e 守卫只剩图片窗存活期内的合法点击，无互踩；可选加固的 thumbnail 分支（`originalImage === image \|\| thumbnail === image`）与就地点词传参（`originalImage ?? thumbnail`，`CardViews.swift:158`）两路均核通 | 落实，但引入 P2-2 枚举缺口 |
| 20 例外 2 收口 | 六处同源一致实证：§4.2 理由 3（:195-201）/§4.3（:213-214）/§9.1（:464）/§10 步骤 7（:501）/验收 11（:519-520）/§11（:534）；`product-design.md:12` 封闭单例外原文亲核（「唯一例外：≥400 词长选段直接开精读窗」）；`WindowManager.swift:14-16/72-80` activate+无 collectionBehavior 实核，「同级打断」论证成立 | 落实，无新矛盾 |
| 21 §3.1③ | 现文「截图卡 context 传 nil；例句由 §6.2 在 WordChipsRow 内部按行取 row[3]」与 §6.2 机制闭环 | 落实 |
| 22 例句护栏 | :120「须与识别内容节的转写逐字一致，不新造不改写」在模板内 | 落实 |
| 23 §4.5 口径 | :316「按宽度分流（与下方注记同口径）」与 :321-322 注记一致 | 落实 |
| 24 §6.1 取舍 | :395-397 sentence 不并入的取舍说明在文 | 落实 |
| 25 windowWillClose 分支体 | :282-284「置空 imageWindow 引用即可（无可取消任务，勿照抄 reader 的 VM cancel 逻辑）+ closeImageWindow()（orderOut + 置空）」规格闭环；orderOut 不触发 windowWillClose、两路径各自置空，无死结 | 落实 |
| 26 配套 | 验收 5/10、§9.1 两行、步骤 6 均实证在位 | 落实 |
| 27 L0 计数 | 复跑：`栈顶替换`=11 ✓、`D-f`=12 ✓、`例外 2`=7 ✓、`version(for:`=9 处/7 行（称 8 行，仍不准） | 部分落实（并入 P2-7②） |

### 任务 3：抽查 L2a 结论（实做 4 项，≥2 达标）

1. **HotkeyManager registerEscape 幂等**（L2a 引 :14-15/:57-61）：独立 Read 实证——`register` :15「重复注册先卸旧」幂等注释与逻辑属实；`registerEscape` :59-61 走 id=99；:57 消费式互斥注释属实。L2a 结论**成立**。配套推演：ESC 热键注册于应用事件目标、随面板显隐装拆（`PanelController.swift:69-71/81`），图片窗 keyDown 只在热键缺席（面板已隐藏）时收到 ESC——§4.3 两级语义时序闭环 ✓。
2. **show(near:) 三级定位**（L2a 称 positionOverride→restoredOrigin→就近）：`PanelController.swift:53-67` 独立 Read 实证三分支顺序与回退链属实；`restoredOrigin` 有效性校验（:116 屏幕交集守卫）属实。L2a 结论**成立**。
3. **L2a §4「`payload += "|ctx:" + sha.prefix(8)` 的 String+Substring 拼接可编译」**：swiftc 实证（`"abc" + "defgh".prefix(2)` 编译通过并输出 `abcde`）。L2a 结论**成立**。
4. **L2a §4「demoWordAtQuery 在新签名下的兼容（clickRect 可默认 nil）」**：该「查过未报」项预设 clickRect 可选，与 §4.3 的非可选呈现冲突——并非已结边界，而是未决歧义，且 nil + 无条件 show 会触发 positionByMouse 重定位。**L2a 此条判断不成立**，已升级为 P1-1 的组成部分。

---

## 3. 查过未报的边界（P0=0 的旁证义务）

- 图片窗尺寸协商：NSHostingView 填内容区 + 根 GeometryReader 测窗内容区，fit 公式随窗口缩放恒成立；读数/准星被「叠加」钉为 overlay
- `ctx:` 8 位前缀 32bit 在 2000 条上限下碰撞概率 ~5e-4，后果上限为同词跨语境单次误命中，可接受
- `version(for:)` 经 default 穷尽七 case；未来 kind 静默落 m1 可接受
- windowWillClose 置空 imageWindow 与 reader 分支不置空 readerWindow（`WindowManager.swift:66-70`）的模式差异各自自洽；与 §11 次级项 2（记忆尺寸）的交互在定该项时需先存 frame 再置空——属次级项落地时的已知约束
- 模型输出 `### 难词表`（标题而非粗体）则静默无 chips——契约类既有暴露面，句/段卡相同，非本轮新增
- D-e 实现中 removeLast 与 cancelCurrent 的两种顺序均无害（被弹流式卡的标记与否不影响终态）；W1 done 后历史已落库（`SessionCoordinator.swift:382-383`），栈顶替换无历史丢失
- ⌥D 捕获失败路径：show(card:) 在捕获完成前已换根（:105），D-f 于 ⌥D 按下即关窗，与「换根即关窗」语义一致
- 全局/局部 monitor 分工：图片窗属本 app，global monitor 天然不涉，排除只需 local 侧——AppKit 语义正确
- pinned 面板 + 图片窗点击：monitor handler pinned 早退（`PanelController.swift:184/:197`），排除逻辑正交
- 面板被他 app 外点藏掉后回图片窗点击：monitors 已拆无干扰，push→show(near:) 复活面板，链路闭环
- §1.1 算术复算（0.163/246pt/2.1px）✓；「面板内宽 376pt」与 `PanelController.swift:27`（400）+ `CardViews.swift:32`（padding 12）一致 ✓
- `scripts/release.sh` 三道发布闸（闸 0 架构/闸 1 工作区/闸 2 build 递增）实证存在，验收 9 可执行

## 4. 行动项清单（每项可独立执行）

1. 【P1-1】§4.3 把无条件 `show(near:)` 改为条件式（`if !isVisible`），声明就地路径 clickRect 传 nil 不重定位，并钉死 clickRect 可选性与 demoWordAtQuery 兼容形态
2. 【P1-2】§4.4 增补「视图局部坐标→Cocoa 全局屏幕坐标」换算契约（推荐 NSView.convert + window.convertToScreen，禁手搓单屏 y 翻转），或收口进共享函数
3. 【P2-1】imageWindow 去 private 或加 isImageWindow 访问器，对齐 monitor 排除的跨类型引用
4. 【P2-2】D-f 措辞补 requery 第三置根点（注明守卫挡住不可达）或收口赋值点
5. 【P2-3】§10 步骤 5 依赖列补「1」
6. 【P2-4】§3.1① 模板补例句竖线护栏（或 tableRows 支持 `\|` 转义）
7. 【P2-5】§8 versionLegacyRemoved 断言改名或注明删除靠编译期保证
8. 【P2-6】ctx 入键改 `glossSHA256(cacheNormalized(c))`
9. 【P2-7】定稿时回改文档头状态行；L0 再版修正 version(for: 计数口径
