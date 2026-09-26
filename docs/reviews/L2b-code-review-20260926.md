# Gloss M1 代码 L2b 异构终审报告（2026-09-26）

> 审查人：K3（三段式 L2b 异构终审，与产出方及 L2a 均异构）。
> 对象：`Gloss/` 全部 26 个 Swift 源文件、`Gloss/GlossApp.swift`、`Info.plist`、`Gloss.xcodeproj/project.pbxproj`、`SelfCheck/main.swift`、`scripts/mock_llm.py`。
> 对照基准：docs/DESIGN.md、docs/product-design.md、docs/tech-design.md（§3/§4/§10/§12）；L0 声明 docs/reviews/L0-selfcheck-code-20260926.md（V1–V6）；L2a 报告 docs/reviews/L2a-code-review-20260926.md（P0×0/P1×9/P2×15）；修复清单 docs/reviews/code-fixes-20260926.md（P1 9/9 已修）。
> 方法：全源 26 文件逐字通读 + 三项必查专项 + L2a 修复处枚举式可达性推演 + SelfCheck 独立复跑。重点：修复引入的新缺陷、并发/生命周期残余、三存储（缓存/历史/Keychain）边界交互。
> 不重复 L2a 已报内容（除非修法有错）；L2a 已登记的 5 项 P2 与微小项不重复罗列。

## 0. 定向验证记录

- **SelfCheck 独立复跑**：swiftc 联合编译（main.swift + 8 个核心文件）→ `SELFCHECK ALL PASS`，62 项全绿声明属实。但发现其中 1 项为恒真空断言（P2-4），1 项通过 ≠ 端到端修复成立（P1-2）。
- **三处指定 grep**：①`AppError.network(e.localizedDescription)` 全库零命中 ✓（stream 路径 timedOut 不再被吞；testConnection 路径残留见 P2-1）；②`displayQuery` 三消费点落实（ResultPanelView.swift:142/143/144 + CardViews.swift:82 展示位 + SessionCoordinator.swift:45 定义）✓；③`OpenURLAction { _ in .discarded }` 在 InlineText（MarkdownView.swift:101）✓。
- **修复处可达性枚举**：对 `SessionCoordinator.run()` 的全部 8 个调用点逐一核对 `currentCard === card` 是否成立（结果支撑 P0-1 与 P1-4）；对 `beginScreenshotFlow` 守卫的全部栈状态取值做真值表推演（支撑 P0-1）。
- **assumeIsolated 全 7 处调用点线程核验**（GlossApp:7 / PanelController:59,135,148 / ServicesBridge:9,12 / AppDelegate:81,85）：均在主线程成立（DispatchQueue.main.async 内、Carbon 主事件循环回调、NSEvent monitor 主线程投递、NSServices 主线程派发），无伪造隔离。

---

## 1. 必查项结论（主 Agent 指定）

### 必查 1-①：P1-2 修复复核（通道开关三处联动）—— 闭环成立，但新增 1 个 P1（误报冲突）

- ServicesBridge 入口检查 `channelServiceEnabled`（ServicesBridge.swift:9-10）✓，且 `MainActor.assumeIsolated` 在 Services 主线程派发语义下成立。
- `beginScreenshotFlow` 入口检查 `screenshotEnabled`（SessionCoordinator.swift:137）✓。
- `installHotkeys` 拆分 ⌥D↔hotkeyEnabled / ⌥S↔screenshotEnabled（AppDelegate.swift:72-75）✓；三开关 didSet → `.glossChannelsChanged` → `channelsChanged()` → 重装热键，运行时闭环 ✓。
- **任务书点名的时序疑点不成立**：`loadIfNeeded()`（:10）的 didSet 通知确实先于 `addObserver`（:20-21）发出而丢失，但启动时 `installHotkeys()`（:19）直接读取当前值安装，通知仅服务运行时变更（彼时 observer 已就位）——无功能缺口。
- **但发现新缺陷**：`hotkeyConflict = !(okD && okS)`（:76）把"用户主动关闭通道"误判为冲突 → **P1-6**（见 §3）。

### 必查 1-②：P1-6 修复复核（ReaderViewModel 生命周期）—— 替换路径闭环，关窗路径未闭环（P1-3）

- `Task { [weak self] ... }` + WindowManager `currentReaderVM` 锚点、替换前 cancel ✓；StateObject→ObservedObject 迁移方向正确（StateObject 绑定视图结构身份，`hv.rootView =` 替换时会保留旧 storage 不重建 VM——该坑属实，迁对；VM 所有权在 WindowManager，@ObservedObject 无新坑）✓。
- 备注：`[weak self]` 在 runAll 执行期间并不真正放行 deinit（`await self?.runAll()` 一旦进入即强持 self 至结束），真正生效的是 WindowManager 的 cancel 锚点——**而关窗（红按钮 orderOut）不经过该锚点** → P1-3。
- 新引入小问题：`retryBatch/retryAggregate` 覆盖 `task` 引用不脱旧 → P2-2。

### 必查 1-③：P1-7 修复复核（截图采集纳管）—— 纳管成立，但 guard 引入 P0 回归，旧卡 notice 为死代码

- 采集 Task 存入 `pendingCapture` ✓；与 `beginHotkeyQuery` 复用同一槽位无冲突（各入口先 `cancelCurrent` 统一取消，槽位仅一份）✓；`retryCurrent` 不经过 pendingCapture，无交互 ✓。
- **stack.top guard（:147）判据错误 → P0-1**（见 §2，本报告唯一 P0）。
- **旧卡 notice（run() :334-336）为死代码 → P1-4**：对 run() 全部 8 个调用点枚举，7 处 `currentCard === card`（show/append/赋值栈顶后才 run），唯一例外（beginScreenshotFlow 先 start 后 show）又被 :147 守卫先行拦截——该分支无任何可达路径。其想解决的"被取消旧卡冻结 .streaming"在 push 流程依然真实存在（P1-4 残留部分）。

---

## 2. P0（阻塞级，共 1 项）

**P0-1 ⌥S 截图通道二次使用必静默丢弃：beginScreenshotFlow 的"接管守卫"读的是残留旧栈**
- 位置：Gloss/Core/SessionCoordinator.swift:147-150。
- 问题：P1-7 修复把 `show(card:)` 推迟到采集完成之后，并新增守卫 `guard self.stack.isEmpty || self.currentCard?.phase == .capturing else { return }`。但 **`stack` 从创建起终生不被清空**（全库无 `removeAll`；`panelDidHide` 只 cancel 不清栈；popCard 保底留 1 张）——采集完成时栈里存的是**上一次查询的旧卡**（通常 `.done`/`.failed`/`.noKey`/`.notice`），守卫据此判定"已有新查询接管"而 `return`：截图结果无声丢弃，面板不弹、无任何反馈。真值表：仅①App 启动后从未查询（stack 空）或②上一张卡恰为被 ⌥S 取消的 ⌥D 冻结卡（.capturing）时守卫放行——即**每个会话只有第一次 ⌥S 能用**，连续两次截图、文本查询后再截图、截图失败再重试，全部静默失败。
- 该守卫的目标场景其实不可达：任何新查询入口都先 `cancelCurrent()` 取消 pendingCapture（:145 的 `Task.isCancelled` 已拦截），且采集完成到 `show()` 之间无 `await`，MainActor 上不存在交错窗口——守卫防的是不可能事件，伤的是必然路径。
- 影响：T4 截图主通道在修复后的真实使用中基本不可用。回归缺口佐证：修复清单 P1-7 行回归证据仅"编译 ✓"，修复后实机只重跑了单词卡场景；demo 通道 `beginScreenshotWithImage` 先 show 后 run 不经此守卫，故 `-demo-image` 也无法暴露。
- 修法：直接删除 :147-150 守卫（取消语义已完备）；如需双保险，在入口记 `let rev = revision`、完成时 `guard self.revision == rev`（revision 随每次栈变更递增）。**修复后必须实机重跑真实 ⌥S 场景（连续两次 + 文本查询后一次），不可用 demo 通道替代。**

## 3. P1（应修，共 5 项）

**P1-1 流尾内容仍丢失：LLMClient 先判 done 后 yield，P2-5 的 parser 修复端到端失效，自检构成假绿**
- 位置：Gloss/Core/LLMClient.swift:104-110（消费侧）；Gloss/Core/SSEParser.swift:23-36（修复侧）；SelfCheck/main.swift:165-168（测试侧）。
- 问题：P2-5 修复把"[DONE] 前缓冲 flush"的内容**合并进 done chunk 返回**，但消费侧顺序是 `if chunk.done { break }` 在前、`yield(.reasoningDelta/.contentDelta)` 在后——merged chunk 携带的 content/reasoning 在 break 处被直接丢弃。修复声称解决的"服务器省略 [DONE] 前空行导致末条 data 事件丢失"在生产路径上**原样存在**。
- 假绿链：`fix.doneFlushesBuffer` 自检（:165-168）只测 parser 单元（PASS，本次复跑确认），mock_llm.py 永远发送规范空行（:147,150）无法触发该形态——两层验证都绿而集成行为未修。
- 影响：对省略空行的服务器（非 MiniMax 主流形态，但属自定义 OpenAI 兼容端点的合法 SSE），流尾最后一个事件的内容静默丢失（回答缺尾）。
- 修法：消费侧改为先 yield 后判 done（reasoning→content→`if chunk.done { break }`）；mock 增加"[DONE] 前无空行"形态开关并补一条端到端断言（或把 LLMClient 分行-消费逻辑抽成可测函数）。

**P1-2（编号顺延为报告内 P1 第 2 项）精读窗关闭不取消跑批任务：P1-6 修复只覆盖"替换"未覆盖"关窗"**
- 位置：Gloss/UI/WindowManager.swift:47-66（cancel 仅存在于 showReader 替换前）；:68-76（makeWindow 无 delegate/无关窗通知）；Gloss/UI/ReaderWindow.swift:189-244（ReaderView 无 onDisappear 处理）。
- 问题：L2a P1-6 原文并列两个场景"替换精读内容/**关窗**不取消旧任务"。修复落实了替换路径，但用户点红按钮关窗（isReleasedWhenClosed=false → orderOut 隐藏）时，`currentReaderVM` 持有的任务继续逐批请求直至聚合完成——每批一个完整付费 API 请求，UI 已消失、不可停止。关窗后不再打开精读窗则整轮 N+1 请求全部烧掉。
- 影响：与 L2a P1-6 原始影响相同（计费损失+状态滞留），只是触发面从"替换+关窗"收窄为"关窗"。
- 修法：监听 `NSWindowWillCloseNotification`（或设 window delegate）在关窗时 `currentReaderVM?.cancel()`；或 ReaderView `.onDisappear { vm.cancel() }`（cancel 幂等，替换路径重复调用无害）。

**P1-3 "旧卡置 notice" 是死代码；push 子查询时被取消的旧卡仍冻结在 streaming 且无恢复入口**
- 位置：Gloss/Core/SessionCoordinator.swift:332-336（死代码）；:158-167（pushWordQuery 触发路径）。
- 问题：①`if let old = currentCard, old !== card, old.phase == .streaming || old.phase == .loading`——对 run() 全部 8 个调用点枚举，7 处在 run 前 card 已是栈顶（`old === card` 短路），唯一例外（beginScreenshotFlow 先 startScreenshotExplain 后 show）被 P0-1 的守卫先行 return——**该分支永不可达**，修复清单声称的"run() 取消旧任务时旧卡置 .notice(已取消)"实际未落地。②真实残留场景：句/段卡流式中点击难词 chip → pushWordQuery → cancelCurrent 取消旧卡任务（其 catch 到 cancelled 直接 return，:366/:370-371）→ 旧卡永停 `.streaming` → 用户点"返回"回到旧卡：BlinkingCursor 常亮、无重试按钮（非 .failed）、无 🔄（usedCache=false）——死卡一张，只能 ESC。
- 影响：修复目标未达成且产生虚假安全感；用户可达路径上面板呈现永久假死卡。
- 修法：把终态处理从 run() 内挪到 `cancelCurrent()`——遍历栈内 `.streaming`/`.loading` 卡置 `.notice("已取消")`（或 `.failed` 以带出重试按钮）；同时删除 :333-336 死代码。

**P1-4 回放截图卡点"重新查询"清空已展示内容：retryCurrent 先清 content 才发现无图可重查**
- 位置：Gloss/Core/SessionCoordinator.swift:208-227（:211 清 content，:214-215/:217-218 guard 裸 return）；Gloss/UI/ResultPanelView.swift:159-161（🔄 对 usedCache 卡一律显示）；Gloss/Core/SessionCoordinator.swift:387-398（replay 不带 originalImage）。
- 问题：历史回放的截图卡（screenshotExplain/screenshotWordAt）`usedCache=true` → footer 显示 🔄 → 点击 → retryCurrent 先 `card.content = ""`，再在 `.screenshotExplain/.screenshotWordAt` 分支因 `originalImage == nil` 裸 return——卡片定格为 **phase=.done 的空内容卡**（带缓存徽标）。product §7"历史回放……可『重新查询』"对图类条目不可用且具破坏性。
- 影响：用户一键销毁正在查看的回放内容（历史记录本身还在，可重新点开恢复）。
- 修法：retryCurrent 把清空前移到各分支 guard 通过之后；或对 originalImage==nil 的截图卡不渲染 🔄（footer 加 `card.kind` 与 originalImage 联合判断）。

**P1-5 installHotkeys 把"用户关闭通道"误报为热键冲突**
- 位置：Gloss/App/AppDelegate.swift:72-77；Gloss/UI/SettingsWindow.swift:217-220（红色警告展示位）。
- 问题：`okD = hotkeyEnabled && register(...)` 短路求值——用户关闭 ⌥D（或 ⌥S）通道时 okD=false，`hotkeyConflict = !(okD && okS)` 恒为 true → 设置页显示红色"快捷键注册失败（可能已被占用）"。P1-2 修复让开关生效的同时，让关闭任一开关的用户必定看到一条假警报（且真实冲突信号将被狼来了效应淹没）。
- 影响：设置页虚假错误态，恰落在本次修复新增的可用路径上。
- 修法：把注册结果与开关状态拆开计算——`hotkeyConflict = (hotkeyEnabled && !registeredD) || (screenshotEnabled && !registeredS)`。

## 4. P2（建议，共 11 项）

1. **testConnection 仍把超时报成"网络连不上"**（LLMClient.swift:181-183）：stream 路径已用 mapURLError 区分 timedOut，测试连接路径未同步——设置页/向导的"测试连接"超时文案与 P1-8 修复后的口径不一致。修法：复用 mapURLError。
2. **ReaderViewModel.retryBatch/retryAggregate 覆盖 task 引用不脱旧**（ReaderWindow.swift:61-79）：runAll 进行中某批失败、用户立即点"重试本批"→ `task` 被新任务覆盖，原 runAll 任务脱锚——WindowManager 的 cancel 锚点只能取消最新任务，旧 runAll 继续烧请求并最终跑一次聚合。修法：覆盖前 `task?.cancel()`，或 isRunning 期间禁用批级重试。
3. **精读取消后无恢复路径**（ReaderWindow.swift:39-59）：cancel 后 batches 非空挡住房 `start()` 守卫，剩余 pending 批永驻、无"继续"按钮——停止即死局，只能关窗重来。修法：cancel 后允许 start() 续跑（guard 改为只查 isRunning）。
4. **SelfCheck 恒真空断言**（SelfCheck/main.swift:155）：`check("fix.timeoutMapping", true)` 永真占位，虚增 62 计数 1 项。修法：删除或并入下一行真实断言。
5. **历史回放截图卡丢缩略图**（SessionCoordinator.swift:387-398 + CardViews.swift:158）：QueryRecord.thumbnail 已入库，replay 未传进 CardState，回放卡只显示 Markdown 无图。修法：replay 增 thumbnail 参数还原。
6. **cachePruneToLoaded 只按条数不按 50MB**（DataStore.swift:70-86）：持久层清理口径=2000 条单阈，tech §4.9"2000 条或 50MB"双阈的字节维度未落实（大响应场景盘缓存可超 50MB）。修法：loader 或 prune 增加累计字节截断。
7. **缓存命中路径在锁内做 SwiftData fetch**（CacheStore.swift:35-43 → DataStore.cacheTouch:89-100）：每次命中一次同步 DB 读（60s 节流只节写不节读），且发生在 CacheStore.lock 持有期间——命中即"一秒钟原则"关键路径上的主线程 I/O。修法：内存记录 lastTouch 自行节流，超阈值再落盘。
8. **tech §4.2"连接 10s"未回填**：实现为 20s 合并超时（LLMClient.swift:57），L2a P1-8 给出的"或保留合并但在文档回填"未执行；§13-C4 仅挂账 reasoning 字段与超时预算测量口径，未明确登记该偏差。修法：§4.2 原文改为实际口径或补连接级 10s。
9. **ImagePipeline 双 CGContext 迂回**（ImagePipeline.swift:23-39）：绘制后另建第二个 context 包裹同缓冲直接 makeImage（第二个 context 未绘制）——功能正确（makeImage 快照缓冲）但冗余易误读。修法：直接对第一个 context makeImage。
10. **NSScreen.screens 非主线程访问**（AXTextFetcher.swift:109-113 ← withTimeout 池线程）：NSScreen 属 AppKit 主线程 API，池线程读取为未定义行为（实践中通常可用）。修法：坐标转换所需主屏高度在主线程预取注入，或转换挪回主线程。
11. **mock_llm 无"[DONE] 前无空行"形态**（mock_llm.py:147,150 恒发 `\n\n`）：P1-1 的集成缺口根因之一；另 mock 对 testConnection 的 `stream:false` 请求也回 SSE（仅靠状态码过关，可接受，备注）。修法：加形态开关。

（微小项合并一行：SettingsWindow.swift:186-188 `var cfg/upsert/cfg=` 三行死代码；:287-290 清除缓存重复调 `CacheStore.clear()`（cacheClearAll 已内含）；AppDelegate.swift:109 `let c =` 未用绑定；Info.plist NSPrincipalClass 与 @main 并存冗余（@main 生效）；ReaderWindow.swift:143 精读历史 origin 恒 .service 不随真实通道。）

## 5. 同源盲区专项结论（L2a 未覆盖区）

- **Concurrency 深水区**：①`withTimeout`（TextFetching.swift:11-22）——父任务取消不自动传染 task group 子任务，但 sleep 子任务响应取消立即返回 nil 使 `group.next()` 及时解阻，且两个 op（AX 0.15s BFS 预算 / ⌘C 0.3s 轮询）自带预算，组域收尾等待有界——当前行为正确；注意该封装的安全性依赖"op 有界"，未来接入无预算 op 时超时将形同虚设（备注，不计缺陷）。②onTermination×retry 循环：消费者取消 → onTermination 取消 producer → sleep 抛错被 `try?` 吞 → continue → `session.bytes` 立即抛 cancelled → finish(.cancelled) 正确收尾，无泄漏无野请求（多走一轮请求组装 L2a 已登记）；重试仅在 `!emitted` 时发生 ✓ 防重复内容。③assumeIsolated 7 处全真在主线程（§0 已列）。④新发现 P1-1（done 合并 chunk 消费丢弃）。
- **SwiftData**：①`@Attribute(.unique)` 冲突路径——cachePut fetch-then-upsert 全部主线程串行（经 CacheStore 闭包），无并发冲突面 ✓；QueryRecord UUID 无现实冲突面 ✓。②ModelContext 线程——cachePut/cacheTouch/cacheLoadAll 未标 @MainActor，但调用点全部经主线程到达（现状安全；建议在 DataStore 侧补标注把隐式契约显式化，备注）。③cachePruneToLoaded 事务行为——单 ctx 批量 delete 一次 save ✓；字节维度缺失（P2-6）；命中回写节流只节写（P2-7）。④`try? ctx.save()` 全库吞错（自用可接受，备注）。
- **pbxproj 手写格式**：objectVersion 77 / PBXFileSystemSynchronizedRootGroup 结构合法，ID 引用双向一致，ad-hoc 签名（CODE_SIGN_IDENTITY="-"）与自用自签口径一致，同步组使新增源文件自动入 target ✓ 未发现问题。
- **Info.plist 键完整性**：LSUIElement/LSMinimumSystemVersion 14.0/ATS 本地网络/NSServices 齐备；NSRequiredContext 缺失与 NSSendTypes 差异 L2a P2-15 已登记（修复清单称已回填 tech §13-C3）；NSPrincipalClass 冗余见微小项。

## 6. 结论

L2a 的 9 项 P1 修复中，6 项（P1-1/3/4/5/8/9）复核成立；3 项（P1-2/P1-6/P1-7）各自引入或未闭环新缺陷：**P1-7 的守卫造成 1 个 P0 级回归（⌥S 通道二次使用必静默失败）**，P1-6 关窗路径未闭环，P1-2 误报冲突；另有 P2-5 修复端到端失效并伴生自检假绿。三处指定 grep 与三存储边界交互核查干净，并发深水区除 P1-1 外无新问题，pbxproj/Info.plist 无新问题。当前状态**不宜判可合流**：P0-1 修复后必须实机重跑真实 ⌥S 场景（连续两次+文本后一次），P1-1/P1-3 建议随同批修复并补对应验证。

**统计：P0×1 / P1×5 / P2×11**
