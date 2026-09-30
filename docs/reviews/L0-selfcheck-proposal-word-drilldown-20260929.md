# L0 自查 + 六项自审记录：proposal-2026-09-29-word-drilldown.md 二轮修订

- 产物：`docs/proposal-2026-09-29-word-drilldown.md`（2026-09-29 二轮复审修订版，共 17 处编辑）
- 修订来源：同日第一轮主会话评审（1×P0 + 3×P1 + 7×P2，全部落进文档）
- 自查口径：`~/three-stage-review-design.md` §3.2 文档场景五项 CI + v1.7 六项自审方法论
- 声明：本自查不构成 review 结论、不承诺清零；L2a/L2b 独立审查义务不因此降低

## ① 自查结论表（CI × 结果）

| CI | 结果 | 证据（动作 + 对象 + 数字/命令 + 结论） |
|---|---|---|
| CI-1 同源一致性 | 通过 | 对本轮引入的 9 组事实（D-d/D-e、fit 满窗前提、ESC 两级、monitor 排除、clickRect、静态 version 删除、row[3] 判空、§4.3 章节号修正）逐一 grep 比对：`双击适应`/`约 1 行`/`已在 §4.5 补充`/`## 难词表` 均 0 命中；`不随之变`/`轻微下移`/`prompt 不变`/`保持 m1` 的命中全部位于新表述或明确标废引用内（见 ③ 锚定串） |
| CI-2 状态真实性 | 通过（1 项标注） | 本轮新增的 6 组代码断言全部实核：`SessionCoordinator.swift:172`（guard 行）、`PanelController.swift:179-206`（installMonitors）、`PanelController.swift:56-59`（saved-origin 分支）、`SelfCheck/main.swift:102`（prompt.version 断言）、`PromptLibrary.version` 全仓 2 处引用（grep：CacheStore.swift:27 + SelfCheck:102）、ResultPanelView 仅渲染 `currentCard`（ResultPanelView.swift:68-69）。标注：§1.2 的 log 实测数据为原文既存内容，未重跑 `log show` 验证，旁证=LLMClient.swift:35 注释「图上点词实测 4–14s」（同日） |
| CI-3 引用有效性 | 通过 | 文档内 §X 引用逐个核对：§4.3→§4.4 前提、§4.3/§8→「验收标准第 5 条」（第 5 条确含 D-e+monitor 两要素）、§7→「§5.1 决策 D-d」、§0 连带影响→§4.3（规格实际所在）；文件行号引用全部在本会话 Read 核对（见 CI-2）；DESIGN.md D5/D9、product-design.md P1 在一轮已核 |
| CI-4 动作可执行性 | 通过 | §10 六步骤均有执行主体（实施者）、可执行动作与验证手段（SelfCheck 断言/手工验收项）；§8 表格每行对应可写断言；无「愿望陈述」型缓解 |
| CI-5 新旧结论一致 | 通过 | 本轮推翻的 2 组旧结论均带标废指针：§5.1「原文『prompt 不变故保持 m1』与 §7 矛盾…故一并升 m2」（D-d）；§4.3「原文『图片窗轻微下移让位』删除」；旧表述残留 grep 均只命中标废引用本身 |

## ② 修复清单（17 处编辑，来源=一轮评审发现）

| # | 位置 | 改动 | 来源 |
|---|---|---|---|
| 1 | 文档头状态块 | 补「二轮复审修订」说明与 D-d/D-e 指针 | 流程 |
| 2 | §0 决策表 | +D-d（wordAt 升 m2）、+D-e（栈顶替换）两行；连带影响改指 §4.3（原文误写 §4.5） | P1-1、P2 |
| 3 | §3.1① | `## 难词表` 笔误 → `**难词表**`（SectionExtractor 按独立粗体行识别） | P2 |
| 4 | §4.2 对比表 B2「交互新词汇」 | 「系统原生缩放、滚动、双击适应」→「拉大窗口即放大，图片恒 fit 满窗」 | P1-3 |
| 5 | §4.3 窗口 | 更正「自动获得滚动条」（滚动条来自内容视图 ScrollView 非窗口样式）；补 activate+makeKeyAndOrderFront 打开方式 | P1-3、P2 |
| 6 | §4.3 内容 | +fit 满窗前提条目；+历史回放卡（无原图）不开放大窗 | P1-3 |
| 7 | §4.3 点词 | +clickRect 入参；+D-e 栈顶替换规格（含原守卫行号与失效时序）；声明 chips 路径不动及理由 | **P0**、P2 |
| 8 | §4.3 结果卡片去向 | +restoredOrigin 记忆位置优先的准确表述；删「图片窗轻微下移让位」；+外点 monitor 排除（local monitor 判 ev.window，global 不涉） | P1-2、P2 |
| 9 | §4.3 关闭 | +ESC 两级优先级（先藏面板后关图片窗） | P2 |
| 10 | §4.4 | +fit 满窗/无滚动无缩放前提（公式成立条件） | P1-3 |
| 11 | §4.5 改动清单 | SessionCoordinator 行改真实范围（守卫+参数+置前）；+PanelController 行（monitor 排除）；ImageZoomWindow 内容补 ESC/fit | P0/P1-2 配套 |
| 12 | §5.1 | version(for:) 改双 kind 升 m2；+静态 version 删除与 SelfCheck:102 断言改写；代价/评审确认按 D-d 重写（含标废说明） | P1-1 |
| 13 | §6.1 | +makeKey 需增 context 参数的接线说明（现签名无 context） | P2 |
| 14 | §6.2 | row[3] 补判空（空串不得覆盖有效 context） | P2 |
| 15 | §7 | +版本耦合注记（指向 §5.1 D-d） | P1-1 |
| 16 | §8 | versionPerKind 改双 m2；+versionLegacyRemoved；wordContextDiffers/screenshotVersionBumped 断言随 D-d 更新；+AppKit 层不进 SelfCheck 的覆盖说明 | P1-1 配套 |
| 17 | §9.1/§10/§11 | +2 风险行；步骤 6 与验收 5/8 更新（连续点词、ESC 两级）；决策状态表 +D-d/D-e | P0/P1-2 配套 |

## ③ 关键锚定串（reviewer 可直接复验）

- `双击适应`、`约 1 行`、`已在 §4.5 补充`、`## 难词表` → 应 0 命中（旧表述清除）
- `prompt 不变`、`保持 m1`、`轻微下移` → 各仅 1–2 命中且全部在标废引用/决策说明内
- `栈顶替换`、`version(for:` → 全文命中语义一致（栈顶替换=「count==2 且栈首为截图卡时 pop+push」；version(for:=screenshotExplain/screenshotWordAt→m2、其余→m1）。计数口径修正（L2a P2-6）：自查时按章节枚举漏计 §4.5/§8 等处，L2a 复核为 7 处 / 8 行，L1 修复轮后增至 11 处 / 8 行——以语义一致性为判定标准，计数仅作参考
- 代码锚点：`grep -n "PromptLibrary.version" Gloss SelfCheck scripts` → 恰 2 处（CacheStore.swift:27、SelfCheck/main.swift:102）；`grep -c '^check(' SelfCheck/main.swift` → 68（=65 基线 + 9 VisibleIdleGuard）

## 六项自审声明（证据口径）

1. **通读全量**：修订前全文 Read 一遍（512 行原版），17 处编辑逐处定位落笔；修订后按章节结构 grep 复核（13 个 § 级标题完整）+ 残留清扫（见 ③）。
2. **整体审视三问**：①达成度——一轮 12 项发现全部落档，无方案外新增功能（纯规格修订）；②实现方式——D-e 取「仅截图根卡放宽栈顶替换」最小改法，保住「深 ≤2」既有不变量与返回按钮语义；monitor 排除取 local-monitor 判 window（global monitor 天然不涉本 app 事件）；③自洽——D-d 在 §0/§5.1/§7/§8/§11 五处同源一致，fit 满窗前提在 §4.2/§4.3/§4.4 三处闭环，ESC 两级与 registerEscape 装拆周期（show 注册/hide 注销）不冲突。
3. **断言逐条验证**：本轮新增 6 组代码断言全部本会话实核（见 CI-2）；一轮已核的行号引用未再变动。
4. **实证**：产物为设计文档，「能跑的」= 行号/计数/结构核验（③ 中的 grep 均实跑）；SelfCheck 现值 68 断言已 grep 确认，与 §8「65+9+N」口径吻合。
5. **场景推演（文档分支：读者视角逐节追问）+ 元检查（规范性语句触发）**：D-e 与 SessionCoordinator 既有注释「子查询入栈，深 ≤2」不矛盾（替换不超深）；与 popCard/返回标签（backLabel 按 stack.first）不矛盾；monitor 排除与 pinned 正交；clickRect 与 show(near:) 的 positionOverride/restoredOrigin 优先级已在 §4.3 写明；静态 version 删除后全仓无第三处引用（grep 实证）。未覆盖场景（如实声明）：ImageZoomWindow 的 SwiftUI 具体实现（十字准星/坐标读数/keyDown）为实施期细节，文档只钉交互契约——其行为正确性由验收 5/8 手工覆盖。
6. **修复处定向复核**：17 处编辑后对编辑区域跑了残留 grep（③）与章节结构核验，未发现引入新问题；未做全量二轮自我辩论（一轮即止纪律）。

---

## L1 修复轮（L2a 独立审后，2026-09-29）

L2a 报告：`docs/reviews/L2a-glm-review-proposal-word-drilldown-20260929.md`（0 P0 / 2 P1 / 6 P2，24 组代码断言独立核对无一错位，D-e/D-d 复验成立）。本轮修复全部 2 P1 + P2-1~5（P2-6 为本文件计数修正，见 ③）：

| # | 位置 | 改动 | 来源 |
|---|---|---|---|
| 18 | 文档头/§0/§11 | +D-f 决策（图片窗生命周期绑定栈根，换根即关窗） | L2a P1-1 |
| 19 | §4.3 点词 | +D-f 规格：`show(card:)`/`replay` 换根前 `closeImageWindow()`；写明两条失效路径（静默死路/跨会话混栈）与可选图像身份校验加固 | L2a P1-1 |
| 20 | §4.2/§4.3/§9.1/§10 步骤 7/验收 11/§11 | P1 零打断收口：例外条款封闭单例外→扩写「例外 2」入 product-design.md；activate 与全屏 Space 切换定为已接受同级打断（与精读窗 `showReader` 同模式，WindowManager.swift:46-47/72-80） | L2a P1-2 |
| 21 | §3.1③ | 措辞对齐 §6.2 机制：截图卡 context 传 nil，例句由 WordChipsRow 内部取 row[3] | L2a P2-1 |
| 22 | §3.1① 模板 | 难词表例句护栏：须与「识别内容」转写逐字一致，不新造不改写 | L2a P2-2 |
| 23 | §4.5 CardViews 行 | 「开窗」改「按宽度分流」与注记同口径 | L2a P2-3 |
| 24 | §6.1 | +sentence 类不并入 context 键的取舍说明 | L2a P2-4 |
| 25 | §4.3 关闭/§4.5 | windowWillClose imageWindow 分支体写明（置空引用）+ closeImageWindow() | L2a P2-5 |
| 26 | §8 注/§9.1/§10 | 验收 5/10 覆盖声明、+2 风险行、步骤 6 补换根关窗 | 配套 |
| 27 | 本文件 ③ | 计数口径修正（见上） | L2a P2-6 |

修复处定向复核（L1 后）：grep `栈顶替换`（11）/`version(for:`（8）/`D-f`（12）/`例外 2`（7）全文语义一致；旧表述无新增残留。

---

## L2b 终审轮（K3 异构终审 + 终修，2026-09-29）

K3 报告：`docs/reviews/L2b-k3-review-proposal-word-drilldown-20260929.md`（0 P0 / 2 P1 / 7 P2；裁决「修完 P1-1/P1-2 后可定稿进入实施」；抽查 L2a 四项结论中三项成立、一项（clickRect 可默认 nil 的兼容预设）被反驳升级进 P1-1）。本轮修复全部 2 P1 + 7 P2：

| # | 位置 | 改动 | 来源 |
|---|---|---|---|
| 28 | §4.3 结果卡片去向 | 无条件 `show(near:)` → **条件式置前**（`if !isVisible`），写明两条调用路径（图片窗/就地点词）的行为矩阵与理由；`clickRect` 钉为 `CGRect? = nil` 可选（就地/demo 通道传 nil） | K3 P1-1 |
| 29 | §4.4 | +**屏幕坐标换算第二段契约**（SwiftUI 视图局部 y 向下 → Cocoa 全局 y 向上多屏；钉死 NSView.convert + convertToScreen 路径，禁手搓单屏 y 翻转公式） | K3 P1-2 |
| 30 | §4.3 窗口/monitor 排除 | `imageWindow` 保 private + 新增 `isImageWindow(_:)` 访问器（消跨类型引用矛盾），monitor 排除改用访问器 | K3 P2-1 |
| 31 | §4.3 D-f | 置根点枚举补第三处 `requery`（:205，注明当前守卫不可达）+ 收口建议（三处栈根赋值点或 setRoot 入口） | K3 P2-2 |
| 32 | §10 步骤 5 | 依赖「—」→「1」（prompt 变更须随版本升，与步骤 3 同理，D-d 口径一致） | K3 P2-3 |
| 33 | §3.1① 模板 | +例句竖线护栏（含 `\|` 以 `/` 替代，防 tableRows 朴素切分错位污染 context） | K3 P2-4 |
| 34 | §8 | 断言 `versionLegacyRemoved` 改名 `versionForWordUnchanged`，注明静态常量删除由编译期保证 | K3 P2-5 |
| 35 | §6.1 | ctx 入键改 `glossSHA256(QueryRouter.cacheNormalized(c))`（空白变体同键） | K3 P2-6 |
| 36 | 文档头/§4.5/验收 5/6 | 状态行改「已定稿（三道审修完毕）」并附审修记录指针；§4.5 SessionCoordinator 行同步条件式置前与三处置根；验收 5/6 按条件式置前更新 | K3 P2-7 + 配套 |

修复处定向复核（L2b 后）：`clickRectInScreenCoords`/`versionLegacyRemoved`/`已评审通过`/`（无依赖）`/`show(near:) 置前` 均 0 命中；`条件式置前` 5 处、`isImageWindow` 2 处、`convertToScreen` 1 处语义一致；文档 581 行，章节结构完整。终版锚定计数（口径同 ③ 注：计数随编辑漂移，语义一致性为判定标准）：`栈顶替换` 11 处、`version(for:` 9 处/8 行、`D-f` 12 处、`例外 2` 7 处。

**终态**：K3 裁决的 P1-1/P1-2 与全部 P2 已修复完毕，方案文档定稿（状态行「已定稿…待实施」）。
