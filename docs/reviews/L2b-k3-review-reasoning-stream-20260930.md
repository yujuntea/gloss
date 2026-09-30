# L2b 异构终审：思考流展示 + 两级超时（2026-09-30）

- 审查范围：工作区未提交 diff 中「思考流实时展示 + 超时口径重构」相关 hunk（LLMClient.VisibleIdleMonitor 两级/AppError.thinkingTimeout、SessionCoordinator.run 竞速分发/consume 攒批节流/appendReasoningTail/retryCurrent 重置、CardViews.SkeletonView 两参/ReasoningPreview、SelfCheck guard 段 6 条、product-design §9 三行表、tech-design §4.2/§10）；前批截图下钻改动以 `docs/reviews/L2-review-acceptance-fixes-20260929.md` 为基线，只审交互面
- 审查人：K3 异构终审（与前两轮 GLM-5.x 不同源；不采信 L0/L2a 结论，全部独立复验）
- 独立验证：SelfCheck 照 tech-design §10 命令编译，**88/88 ×15 连跑全绿**（3+2+10）；`xcodebuild clean build Debug` exit=0 / 0 error（**但有警告**，见 P2-1/P2-2——前轮「0 error」口径未覆盖警告面）；**三向变异实验**在 /tmp 独立完成（L2a/L0 只各测了一个方向，本审补第三方向）
- **裁决：可定稿进实机验收（0 P0 / 0 P1 / 3 P2）**。核心机制（两级口径、竞速结构、S1 首帧 bump、断言有效性）经独立推演与实测未发现错误；3 个 P2 为编译卫生与测试余量，均不阻塞

---

## P2（建议修，不阻塞）

### P2-1 `async let consumed = consume(...)` 隐式 self：编译警告 + 运行时实证强捕获，`[weak self]` 被架空

- 位置：`Gloss/Core/SessionCoordinator.swift:388`
- 问题：`currentTask = Task { [weak self] in ... }` 闭包内以 `consume(...)` 隐式引用实例方法。clean build 实测警告：`SessionCoordinator.swift:388:44: warning: implicit use of 'self' in closure; use 'self.' to make capture semantics explicit; this is an error in the Swift 6 language mode`。
- 依据（本审 /tmp 实证，非推测）：构造同构最小复现（`[weak self]` 闭包 + `async let` 隐式调用实例方法），Swift 5 语言模式编译告警同款；运行时把外部强引用置 nil 后，闭包内方法**照常执行、deinit 推迟到任务完结**——即隐式 self **绕过弱捕获、实为强引用**。该写法在 Swift 6 语言模式直接是错误。
- 影响：SessionCoordinator 是 `static let shared` 单例，永不释放，今日无功能后果；但标注（`[weak self]`）与实际语义（强捕获）相悖，且为将来 Swift 6 迁移埋编译错误。HEAD 版本（内联循环 + `self?.revision`）无此问题，系本批提取 `consume` 方法时引入。
- 修法：闭包首行 `guard let self else { return }` 后显式 `self.consume(...)`，或显式写 `self.consume(...)`（强捕获既成事实，显式化即消警告；反正单例语义不变）。

### P2-2 `let timedOut = try await timeout` 死 `try`——新增编译警告

- 位置：`Gloss/Core/SessionCoordinator.swift:390`
- 问题：`waitForTimeout()` 声明为非 throwing（`async -> VisibleIdleTimeout?`），`try await` 的 `try` 为空转。clean build 实测警告：`:390:32: warning: no calls to throwing functions occur within 'try' expression`。
- 依据：LLMClient.swift:100 `func waitForTimeout() async -> VisibleIdleTimeout?`（无 `throws`）；内部 `try? await Task.sleep` 已吞取消。
- 修法：删 `try`（`let timedOut = await timeout`）。

### P2-3 S3 新增的 `m3Elapsed > 0.30` 下界存在反向 flake 窗口（重负载误 FAIL）

- 位置：`SelfCheck/main.swift:303-308`
- 问题：m3 的区分量依赖「120ms 后台 Task 睡眠」先于「计时器 0.25s 首醒」执行 `markVisible()`。若机器重负载使 120ms 睡眠超调 >~130ms，markVisible 落在计时器 0.25s 唤醒之后 → 计时器按未重置路径 0.25s 提前到期 → `m3Elapsed ≈0.25 < 0.30` → **断言误 FAIL**（把正确实现判成变异）。
- 依据：waitForTimeout 首片睡眠 = `min(0.25, 0.25, 0.25) = 0.25s`（LLMClient.swift:111），与 m3 的 120ms 标记点只隔 130ms 余量；Task.sleep 只超调不欠睡，超调 108% 在并行构建负载下可达。本机 15 连跑未复现（全绿），属低概率。
- 说明：与 L2a 已记录的 m3 另一侧 flake（idle 阈 0.40 侧）属同类已接受风险，本项是 S3 新引入下界的对称面，如实登记。修法（可选，不修可接受）：把 markVisible 提前到 60–80ms（拉开与首片 0.25s 的组距），或断言失败后自动重跑一次再判。

---

## 查过未报（边界声明）

**GLM 同源盲区专项（任务指定方向逐项结论）**：

- **TimelineView(.periodic(from: .now, by: 1))**：SkeletonView 每 0.2s 重渲会重建 schedule（`from: .now` 逐次新值），tick 相位漂移但 `Int(ctx.date − since)` 显示秒数单调不减，秒表无感知缺陷；面板隐藏即 cancelCurrent、骨架屏随卡片离场，无隐藏窗空转计时器。
- **`since: reasoningSince ?? Date()` 回退不可达**：`reasoningActive = true` 与 `reasoningStartedAt = Date()` 在 consume 同一 MainActor 同步块内相继赋值（SessionCoordinator.swift:425-427），@Published 渲染在同步块之后才发生，不存在 reasoningActive=true 且 startedAt=nil 的渲染窗口；retryCurrent（:243-245）同块重置，秒表归零正确。不构成起点漂移。
- **scrollTo 丢帧/错锚**：onChange 触发时 ScrollView 布局可能滞后一拍，scrollTo(bottom) 可能少滚最后一行——下一次 0.2s flush 自愈；首条正文前的末次冲批与 `phase = .streaming` 同块完成（:446-453），骨架屏整块消失，最终截断不可见。装饰级，不报。
- **双参 onChange 兼容**：`onChange(of: text) { _, _ in }`（CardViews.swift:344）为 macOS 14.0 API，项目 `MACOSX_DEPLOYMENT_TARGET = 14.0` 恰满足；clean build 对 CardViews.swift 零警告（S5 落实证明）。
- **MainActor 边界**：consume 为 @MainActor 类方法，`async let` 派生继承隔离；`for try await` 挂起让出主线程期间 @Published 与 TimelineView 刷新均排主线程，无数据竞争；`pendingReasoning`/`lastFlush` 为 consume 帧内局部变量，跨挂起点无共享。
- **两级计时边界组合**：先思考后断流 → ②自创建累计 90s 到期报「思考时间过长」（设计口径）；先正文后断流 → markVisible 双重置后 ① 20s 到期报「响应超时」；**`.thinkingOnly` 与正文撞 90s 边界**：catch 的 `.done` 守卫（:403）不覆盖 `.streaming`，部分正文会被失败态覆盖——核定为正确取舍（90s 纯思考即判死；若保留 .streaming 反而留僵尸卡，流已取消再不会有事件）。
- **节流参数与 Unicode**：0.2s flush / 4000 封顶 / 46pt（≈3 行 caption2）/ 0.12s 滚动动画组合无感知问题；`String.count`/`suffix(4000)` 为 Character（字素簇）语义，emoji/组合字符不会被截碎。
- **S1 × resizeToContent 二次复量**：revision bump → onChange 同步量到的 fittingSize 可能是布局前旧值，`DispatchQueue.main.async` 第二段（PanelController.swift:91-94）布局完成后复量收敛，`abs(h−old)>1` 守卫防抖；图上点词（面板被藏 → show → 首帧 bump）链路推演成立。
- **外部取消**：双 async-let 子任务级联取消 → consume 退循环 defer finish → 计时器 ≤0.25s 切片内醒返 nil → `try await consumed` rethrow CancellationError → 双兜底 return；无 busy-spin（finish 毫秒级到达，前轮 0.000s 展开实证在本轮结构下仍成立）。
- **waitForTimeout 轮询**：睡眠切片 = min（两级剩余， 0.25s)，严格递减收敛，无忙等；isDone 判断先于到期判断，正常完成不误杀。
- **旧 consume 取消后 drain 窗口**（缓冲 event 可能在 retry 重置后投递到同卡）：HEAD 内联循环同构存在，本批未扩大，沿袭前轮「查过未报」口径。
- **`case .done: break` 是 switch-break 非 loop-break**：.done 恒为流终止事件（其后 continuation.finish），循环下一拍自然退出；HEAD 同构，无害。

**L1 修复复核（S1–S5 全部落实，无新矛盾）**：

- S1（首条思考 delta 补 `revision += 1`）：SessionCoordinator.swift:426-432，位于 `reasoningStartedAt == nil` 转折点，每卡每轮（retry 后重新）恰好 bump 一次，防抖设计保留；与 resizeToContent 两段测量收敛兼容。
- S2（appendReasoningTail 共用封顶）：:472-477 提取私有函数，:440（节流 flush）与 :447（正文前冲批）两路径均过 4000 封顶，L2a P2-2 缺口闭合。
- S3（m3 补总耗时下界）：SelfCheck:308。本审**三向变异独立实证**：①markVisible 丢 `lastEventAt` 重置 → FAIL（总 0.264s < 0.30 被捕，复现 L2a/L1 结论）；②markVisible 丢 `lastContentAt` 重置（② 不被正文重置的「误杀回归」方向，前两轮未测）→ FAIL（计时器 0.25s 首醒时 thinkingRemaining 恰 ≤0 返回 .thinkingOnly，与断言的 .noEvent 不符被捕）；③markEvent 染 `lastContentAt` → FAIL（m4 捕获，复现 L0 CI-2）。两级重置语义现有断言全覆盖。
- S4（website hero 68→88）：website/index.html:1109 实测已为 88，同文件 :1167/:1261 三处齐；README:91/README_EN:91 = 88。
- S5（双参 onChange）：CardViews.swift:344 已双参；clean build 该文件零警告。

**L2a 结论抽查（4 项独立复验）**：

1. **「面板高度唯一由 revision/pinned 驱动」**：独立 grep 验证——`resizeToContent` 全部调用点 = ResultPanelView.swift:17/21（onChange revision/pinned）+ PanelController.swift:73（show 后异步）；`applyHeight` 为唯一 setFrame 高度路径。论断成立，S1 的 bump 是 loading 中途唯一的增高通路。
2. **竞速五时序**：独立推演 ①零事件 20s（计时器醒 → throw timeout → 作用域退出隐式取消 consume → onTermination 级联取消 URLSession）②快速失败（consume throw → defer finish → ≤0.25s 醒 → rethrow 原错误）③正常完成（consume 先置 .done/落缓存/历史再 defer finish；父级最迟 0.25s 后收尾但 UI 不等父级）⑤外部取消（见上）全部成立；④超时撞 done 由 :403 守卫（前轮 300 次注入基线）。
3. **SelfCheck 88/88**：本人复跑 15 连跑全绿；计数经运行时 `PASS` 行数核实（非文档转述）。
4. **「不入缓存不入历史」**：CacheStore.put 与 saveHistory 均只用 `card.content`（:464/:483）；回放卡新 CardState 且 phase 直达 .done，reasoningText 恒空不渲染。与代码相符。

**其余查过未报**：

- VisibleIdleGuard 残留：Gloss/ SelfCheck/ docs(tech/product)/README×2/website 全 0。
- URLSession `timeoutIntervalForRequest=20`（LLMClient.swift:213）与监视器 ① 同为 20s：零字节流双源同时到期、同文案「模型响应超时」，无语义冲突；思考/正文字节流动时 URLSession 侧自然不触发。tech-design §4.2「①管连接死」表述偏窄但无后果。
- product-design §9 三行表与代码逐项对上（含 FailedView 恒带「重试」钮、思考文案含「思考」二字被断言锁定）。
- tech-design §10「88 项（2026-09-30 实测）」与实测一致；编译命令含 ImageGeometry.swift 照抄可用。
- 前批交互面：pushWordAtQuery 栈顶替换/条件式置前/setRoot 关窗与思考流无冲突；notice+content 分支不消费思考字段（取消后思考文本随骨架消失）符合预期。
- m1/m2/m4/limitsSane/errorDesc 断言强度独立分析成立（m4 的 markEvent 只可能推迟 .noEvent 使 .thinkingOnly 先行，阈 0.55 余量充分）。

**基础一致性尾行（确认无影响，合并登记）**：tech-design.md:150 `enum StreamEvent` 仍写 `done(usage: Usage?)` 与代码 `case done` 不符——HEAD 既有，本批改了紧邻的 :154/:155 两行而漏它；README.md:91/README_EN.md:91 的 88 项类别枚举（路由/SSE/分节提取/缓存键/坐标换算/图像管线）未含本批新增的「流式超时守卫」类（tech-design §10 已含）。

---

## 行动项清单（可独立执行）

1. [P2-1] SessionCoordinator.swift:388 消隐式 self：`guard let self else { return }` 或显式 `self.consume(...)`。
2. [P2-2] SessionCoordinator.swift:390 删死 `try`：`let timedOut = await timeout`。
3. [P2-3]（可选）SelfCheck m3 把 markVisible 提前至 60–80ms 或失败重试一次，消重负载反向 flake 窗口。
4. [尾行] tech-design.md:150 的 `done(usage: Usage?)` 改 `done`；README×2 的断言类别枚举补「流式超时守卫」。

## 裁决

**可定稿进实机验收**。0 P0 / 0 P1 / 3 P2；P2 均为编译卫生与测试余量，修复面各一行级，不阻塞验收；实机验收重点建议覆盖：密集页点词长思考（预览滚动 + 秒表 + 面板首帧增高）、断网/错 Key 错误即时上卡（≤0.25s 切片语义）、90s 思考死循环兜底（可用缩比参数构造）。
