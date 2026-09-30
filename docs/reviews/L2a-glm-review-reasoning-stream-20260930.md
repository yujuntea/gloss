# L2a 独立第一审：思考流展示 + 两级超时（2026-09-30）

- 审查对象：工作区未提交 diff 中「思考流实时展示 + 超时口径重构」相关 hunk（LLMClient.VisibleIdleMonitor / SessionCoordinator.run+consume / CardViews.SkeletonView+ReasoningPreview / SelfCheck 6 条守卫断言 / product-design §9 表 / tech-design §4.2+§10），交叉引用前批基线 `docs/reviews/L2-review-acceptance-fixes-20260929.md`
- 审查人：L2a 独立第一审（GLM 同源高速档；不采信 L0 自查结论，全部独立复验）
- 独立验证：SelfCheck 照抄 tech-design §10 命令编译运行 **88/88 绿**（本人复跑）；`xcodebuild Debug` exit=0 / 0 error（本人复跑）；**两项变异实验**（详见 P1-2 与 §断言）在 /tmp 独立 harness 完成
- **结论：0 P0 / 2 P1 / 3 P2**。核心机制（两级口径、竞速结构、取消传播、攒批节流、缓存/历史隔离）经五时序推演与实测未发现错误；两个 P1 分别在「UI 呈现层」与「断言有效性」，修复面都小

---

## P1（定稿前建议修）

### P1-1 思考预览出现时面板不增高：46pt 尾部区整块落在 ScrollView 视口之下——本功能主场景被折叠线吃掉

- 位置：
  - `Gloss/Core/SessionCoordinator.swift:424-440`（consume 的 reasoningDelta 分支，无 `revision += 1`）
  - `Gloss/UI/ResultPanelView.swift:17-22`（面板 resize 唯二触发源：`onChange(of: coordinator.revision)` 与 `pinned`）
  - `Gloss/UI/PanelController.swift:85-108`（`resizeToContent`/`applyHeight` 是唯一改面板高度的路径，读 `hostingView.fittingSize`）
  - `Gloss/UI/CardViews.swift:296-303`（loading 分支传入 reasoningText/Since）+ `:341`（`frame(height: 46)`）
- 问题：面板高度是手动 fittingSize 驱动的。查询开始时（`show()` 的 async resize / 换卡时 `revision += 1`）量到的是**无思考骨架**（reasoningActive=false，≈156pt 量级）；首条思考 delta 到达后骨架内容净增 ≈50pt（秒表行 + 46pt 预览区 − 原「正在查询…」行），但 reasoning 三字段的变更**不 bump revision** → `resizeToContent()` 不被调用 → 面板高度不变。CardRouterView 的外层 `ScrollView`（CardViews.swift:8）吞掉增量：增量恰好在 VStack 底部 = ReasoningPreview 整块落在折叠线下，且内层 `scrollTo(bottom)` 把**最新尾部**贴在内层视口底部——正是被外层折叠线切掉的部分。整个思考期间（本功能主场景 4–20s+）用户只看到秒表行与预览盒顶缘，「实时滚动思考尾部」不可见；直到首条 contentDelta（`revision += 1`，SessionCoordinator.swift:451）面板才长高。图上点词路径更明显：换卡先缩到小骨架，预览再被折叠。
- 依据：`applyHeight` 为唯一 `setFrame` 高度入口；consume reasoning 分支（:424-440）通读无 revision 变更；L0 自审场景⑩「reasoningText 不 bump revision → 零 resize 抖动」只对**文本增长**（固定高）成立，漏了「预览区出现」这一次性高度跃变。
- 修法：在首条思考 delta 处（`reasoningStartedAt == nil` 转折点，SessionCoordinator.swift:426）补一次 `revision += 1`（或直接调 `PanelController.shared.resizeToContent()`）。只 bump 这一次，后续 flush 固定高不需要再 bump——「零抖动」设计完整保留；`applyHeight` 的 `abs(h-old)>1` 守卫使重复调用无副作用。

### P1-2 SelfCheck m3（guard.monitor.markVisibleResets）对目标性质无效——变异存活实测 88/88 假绿

- 位置：`SelfCheck/main.swift:299-308`（m3 断言块）；被守护对象 `Gloss/Core/LLMClient.swift:77-81`（markVisible）
- 问题：m3 断言 `m3Timeout == .noEvent && m3Idle < 0.40`。到期时刻的 `eventIdleSeconds()` 在两种情形下**同为 ≈一个 limit**：重置生效时 fire at 0.12+0.25=0.37、idle=0.25；重置被杀时 fire at 0.25、idle=0.25。真正能区分两者的量——总耗时（0.37 vs 0.25）——未被断言。
- 实证（/tmp 独立 harness，本人执行）：把 `markVisible` 的 `lastEventAt = Date()` 删掉（即杀掉①级重置，恰是断言名与文案声称守护的性质），重编译 SelfCheck → **仍 88/88 全绿，`PASS guard.monitor.markVisibleResets`**。对照组：复现 L0 自己的变异（markEvent 重置 lastContentAt）→ `FAIL guard.monitor.reasoningPreventsNoEventButThinkingExpires`（87/1），m4 确实强。即 markVisible 的两级重置目前**无任何断言守护**，CI-2 的「变异 1 项 FAIL」只测了一个方向。
- 修法：m3 补总耗时下界 `m3Elapsed > 0.30`（重置生效 ≈0.37 / 被杀 ≈0.25，markVisible 时刻 0.12 与 limit 0.25 的组距分得开这两个值）；顺带把 m3 最后一片睡眠的 flake 余量（阈值 0.40）保留。

---

## P2（建议修，不阻塞）

### P2-1 website 首屏统计卡仍写「68 项核心逻辑自检断言」——本轮改了同文件另两处，漏第三处

- 位置：`website/index.html:1109`（`<div class="stat-v grad-teal">68</div>`）
- 本轮 diff 已把同文件 :1167、:1261 的 68→88（git diff 可见），hero 统计卡漏改。L0 CI-1「断言计数四处（README/README_EN/website×2/tech-design）统一 88」与事实不符——website 实有 3 处，漏 1。发布页面向用户，与 README/tech-design 的 88 口径不一致。修法：1109 的 68 改 88。

### P2-2 contentDelta 冲批路径缺 4000 封顶

- 位置：`Gloss/Core/SessionCoordinator.swift:442-446`（contentDelta 把 pendingReasoning 直接 append），对照 `:437-439`（reasoning 分支 flush 后封顶裁剪）
- 首条正文前的冲批不做 `suffix(reasoningTailMaxChars)`；此后若再无 reasoning delta，reasoningText 可停留在 >4000（超幅 = 一个攒批窗口的文本），且不再被裁。当前无用户可见影响（预览随骨架屏消失、不入缓存/历史），但封顶语义留缺口。修法：append 后同样封顶，两处抽个小函数。

### P2-3 onChange(of:perform:) 单参数旧 API 在 macOS 14.0 已弃用

- 位置：`Gloss/UI/CardViews.swift:344`；项目 `MACOSX_DEPLOYMENT_TARGET = 14.0`
- 单参 onChange 自 macOS 14.0 deprecated（可用，本人复跑 Debug 构建 0 error）。建议迁两参 `onChange(of: text) { _, _ in ... }`，消除弃用面。

---

## 指定审查任务覆盖情况

**a. 竞速五时序（对昨日 Bool 版逐项等价性推演）**：①零事件 20s：`waitForTimeout` 返 `.noEvent` → throw `AppError.timeout` → async-let 作用域退出隐式取消并 await `consumed` → catch 置 `.failed("模型响应超时")`（m1 断言 + 机制核实）；②快速失败：consume throw → `defer finish()` → 计时器 ≤0.25s 切片内醒 → `try await consumed` rethrow 原错误（m2 锁定机制，前轮 P1-2 修复保留：SessionCoordinator.swift:419 defer + LLMClient.swift:111-112 切片）；③正常完成：consume 同步尾段先置 `.done`/落缓存/历史再 `defer finish()` → timeout 返 nil → consumed 已完结；④超时撞 done：catch 侧 `if card.phase == .done { return }`（:403，前轮 300 次注入基线）防双写；⑤外部取消：currentTask cancel → 子任务级联 → 流 `onTermination` 取消 URLSession 生产任务（LLMClient.swift:305）→ consume 退循环 defer finish → 计时器醒返 nil → `try await consumed` rethrow CancellationError/AppError.cancelled → `catch is CancellationError` 与 `if case .cancelled` 双兜底 return；cancelCurrent 已置 `.notice("已取消")`。**枚举化未引入新的 phase 双写、Task 泄漏或取消传播缺口**；`waitForTimeout` 不抛（Task.sleep 用 try?），`try await timeout` 的 try 为空转无碍。外部取消下计时器的短暂自旋窗口由前轮实证兜底（展开 0.000s，不存在 busy-spin），本轮结构未变。

**b. 节流攒批四问**：①正文到达时 pending 先冲（:442-446），尾部完整 ✓（但该路径缺封顶 = P2-2）；②4000 封顶在 reasoning flush 后裁，count/suffix 均为 Character 语义、保尾正确 ✓；③reasoningStartedAt（plain var）与 reasoningActive（@Published）同同步块赋值（:425-426），MainActor 合并渲染，计时起点正确；`?? Date()` 回退实际不可达（reasoning==true 时 startedAt 必已置），不构成秒表重置；retryCurrent 三字段重置（:243-245）计时从零 ✓；④「思考→done 无正文」：pending 尾丢弃但**不可见**——卡转 `.failed("模型未返回内容")`，骨架屏整体被 FailedView 替换，done 分支无需冲批（若未来失败态展示思考再补）；「思考→正文」pending 已冲 ✓。

**c. UI 层**：TimelineView(.periodic) 秒表按 ctx.date−since 计，单调正确、每秒一刷；`since` 为值传入不被重渲重置（见 b③）；46pt 固定高 + ScrollViewReader scrollTo(bottom)（:344-345）配 `.id` 标准、onChange 在节流 flush 上触发、频率 0.2s 合理；`text.isEmpty` 占位「等待模型输出思考…」（首条 delta 因连接时延必然满足 ≥0.2s 间隔而立即冲批，占位几乎不可见）；onChange 单参 API = P2-3。**但外层面板高度不随预览出现而增高 = P1-1（本审最重要发现）**。

**d. 断言有效性**：6 条逐一核对——m1（零事件原因+上限 2s）、m2（finish 打断，强断言：被杀时 30s 才醒必超 2s 阈值）、m4（强：Task.sleep 不欠睡，markEvent 只会晚到使 noEvent 更迟，thinking 0.60 vs noEvent ≥0.65 分离，阈值 0.55 留 50ms 余量；后台 Task 3×150ms 于 ~0.45s 完成、先于断言的 ~0.60s，无泄漏不影响后续 geo 断言）、limitsSane / errorDesc（常量比对，够用）；**m3 无效 = P1-2（变异存活实测）**。m3 另有重度负载下最后一片睡眠超时 >150ms 的理论 flake（阈 0.40），概率低。

**e. 文档口径**：product-design:222-224 三行表与代码逐项对上（20s 无任何 delta→「模型响应超时」/90s 零正文→「模型思考时间过长，请重试」（LLMClient.swift:138 文案一致）/预览+秒表+正文到达收起）；tech-design:154-156 三层口径（URLSession timeoutIntervalForRequest=20 与 LLMClient.swift:213 一致）、流外计时、切片 ≤0.25s、节流 0.2s、封顶 4000 全部与代码一致；§10:370 计数 88 = 实测 ✓、编译命令含 ImageGeometry ✓（本人照抄编译通过）；README:91 / README_EN:91 = 88 ✓。「思考文本不入缓存不入历史」声明与代码相符：`CacheStore.put(cacheKey, card.content)`（SessionCoordinator.swift:461）、`saveHistory → DataStore.addQuery(response: card.content)`（:471-472）；回放卡全新 CardState，reasoningText 恒空 ✓。

---

## L0 自查声明核对（两处失实）

1. CI-1「断言计数……website×2 统一 88」：website 实有 3 处，:1109 hero 统计卡仍 68（= P2-1）。
2. CI-2「变异测试 1 项 FAIL」：属实但方向不全——只测了 markEvent→lastContentAt 方向；markVisible 丢①级重置的变异存活 88/88（= P1-2）。

---

## 查过未报（边界声明）

- **VisibleIdleGuard 残留**：全仓 18 处命中全部位于历史提案/评审文档（`docs/proposal-2026-09-29-word-drilldown.md:61,579` 与 `docs/reviews/*`），代码与两设计文档/README 为 0——L0 CI-1 的 grep 口径（Gloss/ SelfCheck/ docs/tech-design.md）成立，时点文档不列项。
- **前批基线交叉核实**：L2-review P1-2（切片睡眠）与 P2-1（done 守卫）修复在当前代码确认落地（SessionCoordinator.swift:403/419，LLMClient.swift:111-112）；chips/图片窗/notice+content 分支按基线不重审。
- **重试与超时交互**：LLMClient 内 429/5xx 退避（1s/3s）期间无事件，20s eventLimit 覆盖退避窗口，重试不会被误杀（最坏 ~5s 重启请求）；URLError.timedOut 与 monitor .noEvent 双源同文案「模型响应超时」，事件级时钟先于字节级到期，语义不冲突。
- **`.done` 事件不 markEvent**：合理——流将终止，无需续命；20s 静默后 [DONE] 迟到的极端撞点按口径本就该判超时。
- **reasoningActive 在「纯思考后失败」残留 true**：FailedView 不消费该标志，不可见；retryCurrent 重置 ✓。
- **SSE 注释行/keep-alive 不产生事件**：不重置①，符合「无任何 delta」口径。
- **pre-existing（HEAD 同构，非本轮引入，不列项）**：cancelCurrent 置 `.notice` 与在途 contentDelta 改回 `.streaming` 的微小取消投递窗口，HEAD 旧 run 循环同构存在。
- **量级判定**：本批为轻中量级（机制收敛、5 文件 +2 文档），L2a 终审即可；无需升级 K3。

## 行动项清单（可独立执行）

1. [P1-1] SessionCoordinator.swift:426 附近（reasoningStartedAt nil→set 处）补一次 `revision += 1`，让面板在预览出现时长高一次。
2. [P1-2] SelfCheck m3 补总耗时下界（`m3Elapsed > 0.30`），使 markVisible 丢重置的变异可被捕获。
3. [P2-1] website/index.html:1109 的 68 改 88。
4. [P2-2] contentDelta 冲批后补 4000 封顶（与 reasoning 分支抽公共小函数）。
5. [P2-3] CardViews.swift:344 迁两参 onChange。
