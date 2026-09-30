# L2 异构终审：实机验收 3+1 缺陷修复（2026-09-29）

- 审查范围：工作区全部改动中与 4 项验收修复相关的部分（LLMClient/SessionCoordinator 竞速、CardViews chips 前移、PanelController applyHeight、WindowManager 图片窗定位），外加验收报告结论抽查
- 审查人：异构终审（与前两轮 GLM-5.x 不同源）
- 独立验证：xcodebuild Debug `BUILD SUCCEEDED`（0 error）；SelfCheck 复跑 94 PASS / 0 FAIL ×3；并发竞速结构在 /tmp 搭建同构 harness 实证（5 场景 + 600 次边界注入）
- **裁决：需再修**（0 P0 / 2 P1 / 3 P2）。两个 P1 修复面都很小，修完即可定稿

---

## P1（质量/风险，定稿前必修）

### P1-1 截图卡 chips 被渲染两次——「移到正文之前」实为「复制到正文之前」

- 位置：`Gloss/UI/CardViews.swift:183` 与 `Gloss/UI/CardViews.swift:186`
- 问题：`ScreenshotCardBody.body` 中 `WordChipsRow(rows: chips, context: card.inputText)` 出现**两次**——`MarkdownView` 之前（修复新增）与之后（原行残留，连同其注释"截图卡 inputText 恒为 nil…"一起没删）。凡模型输出 `**难词表**` 的截图卡（本功能主路径），chips 双份渲染。
- 依据：
  - 修复意图是"移"：验收报告缺陷 2 原文「修复：`ScreenshotCardBody` 中 chips 移到 `MarkdownView` **之前**（缩略图 → chips → 正文）」（`docs/reviews/acceptance-word-drilldown-20260929.md:33`）。
  - 设计文档互证：tech-design §3.3 第 5 条「该表同时从卡片正文中移除，**不重复渲染**」。
  - 验收为何漏网：`acceptance-chips.png` 只能看到首屏（缩略图 → 4 条 chips → 识别内容/翻译与解释/要点），第二份 chips 在滚动区底部，截图结构上注定照不到——证据与缺陷并存不矛盾。
- 影响：用户滚到卡片底部会看到第二份相同的难词条（含重复的「难词」标题）；白损 ~30–230pt 垂直空间——恰是缺陷 2 想省下的资源；另每次流式 delta 多跑一次 `SectionExtractor` 全量解析（`chips` 计算属性被求值两次）。
- 修法：删除 `:186` 的残留行及其上方注释（`:185`）。顺带消除第三次解析。

### P1-2 竞速结构吞掉快速失败的及时性：流错误最长延迟 20s 才上卡（回归）

- 位置：`Gloss/Core/SessionCoordinator.swift:377-384` + `Gloss/Core/LLMClient.swift:92-102`
- 问题：父协程 `guard try await timedOut` **先等计时器**；而 `waitForTimeout` 的 `finish()` 只置标志位、**不打断进行中的 `Task.sleep`**——首趟睡眠时长≈完整 limit（20s）。于是任何在超时前失败的流（断网 URLError、401、重试尽后的 429/5xx、baseURL 非法 parse 错），`consume` 早已抛出并在 `defer` 里 `finish()`，父协程却要睡到计时器自然醒才 `try await consumed` 拿到错误。卡片在错误已确定后继续空转骨架屏，最长 20s。
- 实证（/tmp 同构 harness，limit=2s，流在 t=0.5s 抛错）：父级 catch 在 **t=2.02s** 才触发——延迟恰好等于 limit 余量。修复前旧代码 `for try await` 内联，错误即时上卡，故属本次修复引入的回归。
- 影响面：断网/错 Key 用户每次查询先看最长 20s「正在查询…」才看到真实错误；成功路径不受影响（`consume` 自己已把 `phase` 置为 `.done`，UI 不等父协程，实测 t=0.6s 内容完成、卡片即时 done）。
- 修法（任一即可）：
  1. `waitForTimeout` 的睡眠切片化：`try? await Task.sleep(nanoseconds: UInt64(min(remaining, 0.5) * 1e9))`——finish 后 ≤0.5s 内解除，计时精度无损；
  2. 用 continuation/通知让 `finish()` 主动唤醒等待方；
  3. 改 `withThrowingTaskGroup` 真竞速（`group.next()` 取先完成者后 `cancelAll`），结构上消掉「先等谁」的顺序依赖。

---

## P2（建议修，不阻塞）

### P2-1 超时边界 done 可被覆盖成「超时失败」

- 位置：`Gloss/Core/SessionCoordinator.swift:379-389`
- 问题：done 落在 limit 内侧 ~1ms 窗口时，`consume` 已写完缓存/历史并置 `.done`，但 `waitForTimeout` 同刻先醒返回 true → 父协程抛 `timeout` → catch 无条件把卡片盖成 `.failed("模型响应超时")`。实证：done=limit−[0,0.8]ms 注入 300 次，298 次终态 failed（缓存与历史已正确落盘，无双写——只有 `consume` 写；重试即缓存命中自愈）。
- 修法：catch 中 `case .timeout` 时先判 `card.phase == .done`（或 `!card.content.isEmpty`）则不再覆盖。一行守卫即可，窗口本身极小，可顺手。

### P2-2 锚点/计数漂移合集

- `docs/tech-design.md:369`「当前 **91 项断言全绿**」、README.md:91、README_EN.md:91「91」——实测 **94**（本人复跑 94/0 FAIL，验收报告的 94/94 成立，三处文档停在修复前计数）。
- 代码注释章节号指错：图片放大窗规格在 tech-design **§4.12**，但 `Gloss/UI/ImageZoomWindow.swift:4`（§4.3=PromptLibrary）、`:7` 与 `:69`（§4.4=TTSEngine）、`Gloss/Core/ImageGeometry.swift:6`（§4.4）、`Gloss/Core/ImageGeometry.swift:29` 与 `Gloss/UI/CardViews.swift:192`（§4.5=PanelController）全部指空。
- `docs/tech-design.md:158`（§4.2 超时条）把运行时守卫写作 `VisibleIdleGuard`，实际运行时是 `VisibleIdleMonitor`（Guard 只剩测试用纯逻辑 struct + defaultLimit 常量）。
- 验收报告表格第 1 条标准仍写「卡片**底部**出现可点难词条」，修复后实际在顶部（且见 P1-1）。
- 修法：四处计数 91→94；章节号统一改 §4.12（分流另可引 §3.3-4）；§4.2 改述为 Guard/Monitor 双层；报告措辞改「缩略图下方」。

### P2-3 `showImage` 定位只认主屏且无退化兜底

- 位置：`Gloss/UI/WindowManager.swift:79-83`
- 问题：①按 `NSScreen.main.visibleFrame` 居中修好了本机 y=-988，但若另一台机器上 `NSScreen.main` 恰是 visibleFrame 退化（高 0）的那块屏，居中公式会把窗放到 `midY−350`，仍可能出屏——缺 `visibleFrame.height > 0` 的屏选兜底；②用户在副屏工作时图片窗开去主屏，与 `PanelController.positionByMouse`「跟鼠标屏」的既有惯例不一致。
- 修法：`NSScreen.screens.first(where: { $0.visibleFrame.height > 0 })` 兜底，或直接取鼠标所在屏（与面板同口径）。`setFrameOrigin` 后无需 `setFrame(display:)`（窗未上屏/纯移动，已核，不报）。

---

## 查过未报（边界声明）

**缺陷 1 竞速（除 P1-2/P2-1 外其余核查点均干净）**：
- 超时路径**无 Task 泄漏**：`async let` 作用域退出隐式取消并 await `consumed`；流 `onTermination` 级联取消 URLSession 生产任务。harness 实证：超时后流 terminated、父任务正常完结。
- 外部取消（`cancelCurrent`）展开 **0.000s**：`AsyncThrowingStream.next()` 响应取消返回 nil → `consume` 退循环 → `guard !Task.isCancelled` 拦截 → 不写缓存/历史 → `defer finish()` → 计时器即醒返回 false。**不存在 busy-spin**（finish 在毫秒级到达）。
- **无双写**：缓存/历史只有 `consume` 一个写点；父协程 catch 路径不写。
- `VisibleIdleMonitor` 锁用法：睡眠在锁外，markVisible/finish/idleSeconds 无死锁；`cancelled` 标志优先级高于到期判断，正常完成不误杀。
- 成功路径父任务残留至当趟睡眠自然醒（≤20s）——无害（UI 态由 consume 直驱；currentTask 槽位被下次查询 cancelCurrent 覆盖），不列项。

**缺陷 3 重入安全（全部干净）**：
- `applyHeight` 两次调用各自相对当前 frame 计算 dy，`anchoredTop` 位移不累加错误（y0−(h2−h0)，顶边恒定）；`abs(h−old)>1` 守卫防抖收敛。
- `isProgrammaticMove` 同步置位/复位包住 `setFrame`（display:false），`windowDidMove` 同步派发被正确屏蔽；代码注释对 animate 路径的警告与实现一致。
- 两次测量之间用户拖动：applyHeight 不动 origin.x，顶锚仅保顶边——用户位置不被覆盖；拖动期间 windowDidMove 正常存档。
- 隐藏后面板、过期 async 回调均有 `isVisible` 守卫。

**缺陷 2 回归面（除 P1-1 外干净）**：`SentenceCardBody`/`ParagraphCardBody` 未动（chips 仍在文末，与各自文档描述一致）；`removingSection` 仍保证表格不二次渲染（SelfCheck `section.screenshotRemoved` 锁定）；老缓存无难词表时 chips=[]、两个 `WordChipsRow` 均不渲染（`if !rows.isEmpty` + `section.noWordTableIsNoop` 锁定）；`.notice` 带内容分支逐 kind 核过安全。

**缺陷 4 多屏（除 P2-3 外干净）**：坐标两段契约（`convert(_:to:nil)` → `convertToScreen`）与截图像素级自洽（见下）；图片窗点击只命中本进程 local monitor（global monitor 只收他进程事件），`:210` 排除充分；ESC 两级语义与 Carbon 热键消费顺序一致；`windowWillClose` 图片窗分支只置空引用与注释所述一致；换根关图（D-f）在 `setRoot` 唯一入口收口，已核 `show/replay/requery` 全部走它。

**实机结论抽查（4 张截图全核）**：
- `acceptance-chips.png`：确为 4 条 chips（idempotent/quorum/consensus/linearizability），各带音标+图中义+朗读钮，位于缩略图与正文之间——与报告结论相符（同时证实 P1-1 的第二份在滚动区外、截图注定漏检）。
- `acceptance-zoomwin.png`：像素实测竖线 960/2000=48%、横线 (763−420)/667≈51%，与读数「x 48% y 51%」自洽；letterbox 上下灰边与 fit-by-width 计算吻合。
- `acceptance-wordat.png`：返回整图链 + 截图取词/quorum 卡、语境义扣图——与 5b/3 结论相符（「图片窗保持打开」为裁剪截图，不可独立证伪，列为中立）。
- `acceptance-wordcard.png`：与 1b 结论相符。
- SelfCheck 94/94 与 xcodebuild 0 error 均已独立复跑成立。

**基础一致性瑕疵（无影响，合并一行）**：验收报告 §三「value("-demo-image") 会吞紧随 flag」等描述与代码相符；未发现其他错字/残留。
