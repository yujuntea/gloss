# L0 自查 + 六项自审记录：截图单词下钻 实施代码（v0.1.8 工作区）

- 产物：阶段一 + 阶段二实施代码（10 文件：CacheStore/PromptLibrary/SessionCoordinator/CardViews/WindowManager/PanelController/ImageGeometry(新)/ImageZoomWindow(新)/SelfCheck + 3 文档）
- 规格：`docs/proposal-2026-09-29-word-drilldown.md`（已定稿，经 L0/L2a/L2b 三道审修）
- 声明：本自查不构成 review 结论、不承诺清零；L2a/L2b 独立审查义务不因此降低

## ① 自查结论表（代码 diff 场景 CI×结果）

| CI | 结果 | 证据（动作 + 对象 + 数字/命令 + 结论） |
|---|---|---|
| CI-1 同源一致性 | **发现 3 项，已修；复审发现我自查本身有 2 处失实，已更正** | ①`docs/tech-design.md:362` SelfCheck 编译命令缺 `Gloss/Core/ImageGeometry.swift` → 照抄命令编译失败（已加）；②同文件 :368 与 `README.md:91` 仍写「65 项断言」，实为 86（已改，并补 ImageGeometry/VisibleIdleGuard 覆盖项与 AppKit 层未覆盖声明）；③**L2a 复审补正**：我当时的 grep 范围只含 `README* docs/*.md`，**漏了 `website/index.html`（发布资产，同源但不在我 grep 范围）**，导致 P1-1「web 仍写 65 且命令缺文件」漏检。**CI-1 教训**：仓库里有非 `docs/` 目录的文档副本（website 发布页），同源扫描必须含它。另：`README_EN.md` 英文措辞（「65 assertions」）也被我的中文 grep 模式漏掉。 |
| CI-2 状态真实性 | 通过（自查两处声明经 L2a 证伪并更正） | 全部验证实跑：`swiftc` 联合编译 → `PASS=91 FAIL=0`（基线 68 → 阶段一 80 → 阶段二 86 → 阈值重构 89 → 键字节级锚定 91，逐轮实测非照抄）；`xcodebuild` Debug → `error数=0`。**自查失实处如实更正**：①A4 行「断言总数 86→89」是**无落点的空操作声明**（改 89 的动作实际发生在 A2 之后、A4 只是重复计数——L2a 指出该行声称的变更无对应编辑）；②CI-1「`grep -rn "65 项" README* docs/*.md` → 0」**字面为真但质假**（范围漏 website/ 与英文措辞），已按 CI-1 教训更正扫描范围与结论。 |
| CI-3 引用有效性 | 通过 | 方案 §X 引用逐个走通；代码行号引用本会话全部 Read 核对（`SessionCoordinator.swift:172/310-312`、`WindowManager.swift:65-102`、`PanelController.swift:200`、`ImageGeometry.swift` 全文、`ImageZoomWindow.swift` 全文）；`product-design.md:12` P1 双例外原文亲核；`tech-design.md:294-295` 新增 §4.12 坐标两段契约亲核 |
| CI-4 动作可执行性 | 通过 | §10 七步骤全部落地且各带验证手段；7 步→11 条验收映射经 K3 上一轮核通，本轮实现后逐条对照实机验收清单 |
| CI-5 新旧结论一致 | 通过 | D-a~D-f 六项决策在代码中均有对应落点（D-a `showImage`；D-b `makeKey(context:)`；D-c 同版本；D-d `version(for:)` 双 m2；D-e `pushWordAtQuery` 栈顶替换；D-f `setRoot` 收口）；P1 例外 2 落入 product-design.md:12 |
| CI-3' 改动边界 | 通过 | `git status` 确认无越界文件；pbxproj **未改**（实证同步根目录 `PBXFileSystemSynchronizedRootGroup` objectVersion=77，`ImagePipeline` 在 pbxproj 出现 0 次，新文件自动入 target，build 日志可见 `ImageZoomWindow.swift`） |
| CI-4' 依赖完整性 | 通过 | `setRoot` 收口实证：全仓 `stack = [card]` 仅剩 `SessionCoordinator.swift:312` 一处（:214/:317/:432 三处调用点均改走它）；`makeKey` 5 处调用点：仅 `runText`(:337) 传 context，其余 4 处为截图/长文类 context 恒 nil 走默认值（编译通过）；`pushWordAtQuery` 3 处调用方（缩略图 :213 传 nil、窗内 :208 传 rect、demo :295 走默认） |
| CI-5' 风格一致 | 通过 | 中文注释解释「为什么」、无空行堆砌、跟随周边命名（`closeImageWindow`/`isImageWindow` 对齐既有 `showSettings`/`showReader` 风格） |

## ② 修复清单（主会话自查阶段发现并已修）

| # | 位置 | 改动 | 来源 |
|---|---|---|---|
| A1 | `CardViews.swift` `ImageTapView` | 分流阈值由硬编码 `inCardWidth = 376` 静态常量 → `ImageGeometry.needsZoomWindow(imageWidth:cardWidth:)`，卡宽传**实测 `geo.size.width`** | CI-3'：面板 styleMask 含 `.resizable`（`PanelController.swift:28`），用户可拖宽面板；写死 376 会让「拉宽后本可看清」的图仍被无谓弹窗打断 |
| A2 | `ImageGeometry.swift` + `SelfCheck` | 新增 `needsZoomWindow` 纯函数 + 3 条断言（denseScreenshot / smallImage+拉宽场景 / exactFit 边界） | A1 的可测化（AppKit 层不进 SelfCheck，纯函数才可断言） |
| A3 | `docs/tech-design.md:362,368`、`README.md:91` | SelfCheck 编译命令补 `ImageGeometry.swift`；断言数 65→86（后随 A2 变 89）；补覆盖项与「AppKit 层未覆盖」声明 | CI-1 同源不一致 |
| A4 | `SelfCheck/main.swift` | 断言总数 86→89 | A2 配套 |

## ③ 关键锚定串（reviewer 可直接复验）

- `swiftc -O -o /tmp/sc3 <9 个 Core 文件> SelfCheck/main.swift && /tmp/sc3` → `PASS=89 FAIL=0` + `SELFCHECK ALL PASS`
- `xcodebuild -quiet -project Gloss.xcodeproj -scheme Gloss -configuration Debug -destination 'platform=macOS' build` → `error数=0`
- `grep -n "stack = \[card\]" Gloss/Core/SessionCoordinator.swift` → 恰 1 处（:312，setRoot 内）
- `grep -rn "65 项" README* docs/*.md` → 0 命中
- `grep -c ImageGeometry Gloss.xcodeproj/project.pbxproj` → 0（同步根目录，无需登记）
- `grep -n "65 项" / 阈值常量` → `inCardWidth` 已 0 命中

## 六项自审声明（证据口径）

1. **通读全量**：本次实施 diff 全量逐 hunk 通读（`git diff` + 5 个改动文件全文 Read：`ImageGeometry.swift` 20 行、`ImageZoomWindow.swift` 139 行、`SessionCoordinator`/`CardViews`/`WindowManager`/`PanelController` 改动段）。未抽样跳读。
2. **整体审视三问**：①达成度——方案 §10 七步骤全部落地，无方案外功能（唯一偏离=impl-worker 报告的 pbxproj 前提不成立，经我实证确认其判断正确，不改 pbxproj 反而是达标）；②实现方式——A1 把阈值从常量改为实测卡宽是比原规格更正确的实现（规格只说「卡片内宽」，未说是否随面板缩放变化），已抽成纯函数可测；③自洽——D-e 栈顶替换与 D-f 换根关窗不互踩（换根即关窗，窗内点击只在窗存活期可达）；条件式置前与 monitor 排除正交（前者管面板定位、后者管藏面板，pinned 判断在前不受影响）。
3. **断言逐条验证**：本轮全部代码断言实核（见 CI-2/③）。方案 §8 的 7 类断言均在 SelfCheck 中落地并实跑。
4. **实证**：SelfCheck 89/89（实跑四轮，逐轮递增核对）、xcodebuild 0 error、新二进制时间戳核实。变异测试由 impl-worker 执行（removingSection no-op → 2 FAIL；删 prompt 契约 → 2 FAIL），我复核了变异逻辑与断言守护对象一致。
5. **场景推演（代码分支：边界条件 + 失败模式 + 用户旅程）**：
   - **边界**：面板拉宽/缩窄下的分流（A1 修）；letterbox 点击返回 nil；`stack.count == 2` 时 replaceLast；`context` 为空串/空白归一（断言覆盖）；历史回放 200px 缩略图不弹窗（断言覆盖）。
   - **失败模式**：`ImagePipeline.normalize` 返回 nil → `pushWordAtQuery` 已 append 后设 `.failed("图像处理失败")`（既有行为，面板可见，用户可重试）；模型漏发难词表 → chips 为空不渲染（`if !rows.isEmpty`）；老缓存无难词表 → `removingSection` no-op（断言 `section.noWordTableIsNoop` 锁定）。
   - **用户旅程**（跨组件状态组合）：S1 密集文本 ⌥S → chips 出现 → 点 chip 得带例句语境的词卡；S6 小图 ⌥S → 缩略图直接点词；S5 密集图 ⌥S → 点缩略图开窗 → 窗内点词 → 面板浮出 → **再点第二个词**（面板可见，条件式不重定位，栈顶替换出新卡）→ ESC 藏面板 → 再点第三词（面板不可见，复活并就近定位）→ ⌥D 划词（setRoot 关图片窗）。**未实测项如实声明**：该旅程的 AppKit 行为全部依赖实机验收（本轮只做静态与自检层验证）。
6. **修复处定向复核**：A1–A4 修完后重跑 SelfCheck（89/89）与 xcodebuild（0 error）；A1 首次改写时把 `tapHelpText` 误写为 `tap(view:)` 形式的计算属性导致 `expected '(' in argument list` 编译错误，已改名为 `tapHelpText` 并重验通过——**如实记录**：此处自审引入过一个编译错误，靠实跑拦下，未凭直觉放过。

---

## L1 修复轮（L2a 独立审后，2026-09-29）

L2a 报告：`docs/reviews/L2a-glm-review-impl-word-drilldown-20260929.md`（0 P0 / 2 P1 / 5 P2；四项指定抽查——栈顶替换三时序 / setRoot 收口与 windowWillClose 互踩 / 两段坐标换算 / 竖线护栏×SectionExtractor——全部通过；主 Agent 的 SelfCheck 89/89 与 xcodebuild 0 error 经其复跑证实）。本轮修复 2 P1 + 5 P2：

| # | 位置 | 改动 | 来源 |
|---|---|---|---|
| B1 | `website/index.html:1167-1173` | 自检命令块：补 `ImageGeometry`、删不存在的 `ProviderPresets`；计数 65→91；`:1261` 同步 | L2a P1-1 |
| B2 | `README.md:91`/`README_EN.md:91`/`docs/tech-design.md:369` | 断言计数统一 91（含英文措辞） | L2a P1-2 |
| B3 | `docs/tech-design.md:114,292` | 阈值措辞改实测卡宽口径，删已不存在的 `ImageTapView.inCardWidth = 376` 引用 | L2a P2-1 |
| B4 | `CardViews.swift` `ImageTapView` | help 文案从固定 376 改为与分流同一实测 `geo.size.width` 判定（拉宽面板后文案不再与行为相反） | L2a P2-2 |
| B5 | `SelfCheck/main.swift` | 新增 2 条字节级锚定断言：`cachekey.screenshotKeyDiffersFromM1`（整图/点词键确从 m1 payload 迁到 m2）+ `cachekey.wordKeyUnchangedByVersionSplit`（词类键与旧版逐字节一致） | L2a P2-3 |
| B6 | `CardViews.swift` `CardRouterView` | `.notice` 相位在 `content` 非空时并渲染 `kindBody`——取消提示不再吞掉根卡已生成内容（点 chips 切子卡后返回可见部分结果） | L2a P2-4 |
| B7 | `ImageZoomWindow.swift` | 准星改存**归一化**点、按当前 bounds 反解显示区坐标（resize 后不再漂移）；`onTap` 去掉已无用的 viewPoint 参数 | L2a P2-5 |
| B8 | 本文件 ①CI-1/CI-2 | 更正两处失实声明（A4 空操作声明、CI-1 grep 范围漏 website/ 与英文措辞） | L2a P1-2 反噬 |

修复处定向复核（L1 后）：`swiftc` 联合编译 → `PASS=91 FAIL=0`（89 + B5 的 2 条）；`xcodebuild` Debug → `error数=0`；全仓计数终检 `grep -rn "[6-8][0-9] 项断言|[6-8][0-9] assertions" README* docs/*.md website/index.html` → 0 命中。
