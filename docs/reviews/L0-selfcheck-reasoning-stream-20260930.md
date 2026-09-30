# L0 自查 + 六项自审记录：思考流展示与两级超时（2026-09-30）

- 产物：思考流实时展示 + 超时口径重构（LLMClient / SessionCoordinator / CardViews / SelfCheck / 2 文档）
- 背景：用户实机反馈密集页点词只见静态「思考中…」且频繁「模型响应超时」——旧口径「reasoning 不计、20s 无正文即超时」与混合推理模型的长思考（4–20s+）直接冲突；经批准按「展示思考流 + 两级超时」方案实施
- 声明：本自查不构成 review 结论、不承诺清零；L2a/L2b 独立审查义务不因此降低

## ① 自查结论表（代码 diff 场景 CI×结果）

| CI | 结果 | 证据（动作 + 对象 + 数字/命令 + 结论） |
|---|---|---|
| CI-1 同源一致性 | 通过 | 本轮引入的事实点逐一 grep：①「reasoning 不计」旧口径清除——`VisibleIdleGuard` 全仓 0 残留（grep Gloss/ SelfCheck/ docs/tech-design.md）；②product-design:222 单行超时 → 三行（无事件/思考过长/思考中展示）；③tech-design 三处（:154 不渲染内容→尾部预览、:155 三层超时、:370 计数）；④断言计数四处（README/README_EN/website×2/tech-design）统一 88（实测 88/88） |
| CI-2 状态真实性 | 通过 | 全部实跑：SelfCheck 88/88（连跑 3 次稳定）；xcodebuild Debug 0 error；变异测试 1 项（markEvent 同时重置正文时钟 → `reasoningPreventsNoEventButThinkingExpires` 精确 FAIL）后还原复绿 |
| CI-3 引用有效性 | 通过 | `VisibleIdleMonitor`/`waitForTimeout`/`eventIdleSeconds`/`reasoningText`/`reasoningStartedAt` 全部触点 grep 列表核对（消费方恰为 SessionCoordinator+CardViews+SelfCheck，无第三处）；`reasoningActive` 旧触点保留（SkeletonView 分支仍用） |
| CI-4 动作可执行性 | 通过 | 验收计划明确：密集页 ⌥S 全链路 + 截图取证 + 词查询回归 |
| CI-5 新旧结论一致 | 通过 | 旧前提「思考流用户看不见」已随代码注释、product-design 表、tech-design §4.2 三处同步废止并写明废止理由；新口径两级（20s 无任何事件 / 90s 纯思考）在 LLMClient 注释、SessionCoordinator 常量注释、两文档一致 |
| CI-3' 改动边界 | 通过 | 5 文件（LLMClient/SessionCoordinator/CardViews/SelfCheck）+2 文档，无越界；ReaderWindow/精读窗未动（方案明确的范围外） |
| CI-4' 依赖完整性 | 通过 | `VisibleIdleGuard` 删除后其唯一非测试引用（SessionCoordinator:63 常量）已改指 `VisibleIdleMonitor.eventLimit`；SelfCheck 旧 14 条守卫断言整体替换为新 6 条（96→88）；`reasoningActive` 的另一消费方 SkeletonView 分支保留 |
| CI-5' 风格一致 | 通过 | 中文注释「为什么」；`reasoningFlushInterval`/`reasoningTailMaxChars` 常量上移 class 级，对齐 `visibleIdleLimit` 既有布局 |

## ② 修复清单（本轮实施编辑）

| # | 位置 | 改动 |
|---|---|---|
| R1 | LLMClient | `VisibleIdleGuard` 结构体删除；`VisibleIdleMonitor` 重写为两级（eventLimit 20 / thinkingLimit 90 / `markEvent` vs `markVisible` 分野 / `waitForTimeout() -> VisibleIdleTimeout?`）；`AppError.thinkingTimeout`「模型思考时间过长，请重试」 |
| R2 | SessionCoordinator | CardState +`reasoningText`(@Published)/`reasoningStartedAt`；常量 `visibleIdleLimit`/`thinkingLimit`/`reasoningFlushInterval` 0.2s/`reasoningTailMaxChars` 4000；`run` 竞速改枚举原因分发；`consume` reasoning 分支攒批+节流+封顶+markEvent、content 分支先冲尾部批；`retryCurrent` 重置三个思考字段 |
| R3 | CardViews | `SkeletonView` 加两参（默认值保兼容）；新 `ReasoningPreview`（TimelineView 秒表 + 固定高 46pt 尾部滚动 + onChange scrollTo bottom） |
| R4 | SelfCheck | 旧 guard.* 14 条（结构体 9 + 旧 Monitor 5）替换为新 6 条（零事件原因/finish 切片/markVisible 重置/思考推迟原因/limitsSane/错误文案），96→88 |
| R5 | product-design.md / tech-design.md | 超时表三行化；tech-design :154/:155/:370 同步 |

## ③ 关键锚定串（reviewer 可直接复验）

- `swiftc -O -o /tmp/sc_r1 <9 Core 文件> SelfCheck/main.swift && /tmp/sc_r1` → `PASS=88 FAIL=0` + `SELFCHECK ALL PASS`（3 次稳定）
- `xcodebuild -quiet -project Gloss.xcodeproj -scheme Gloss -configuration Debug -destination 'platform=macOS' build` → error 0
- `grep -rn "VisibleIdleGuard" Gloss SelfCheck docs/tech-design.md` → 0
- 变异测试：markEvent 重置 lastContentAt → `FAIL guard.monitor.reasoningPreventsNoEventButThinkingExpires`（实测 Optional(.noEvent)），还原后复绿

## 六项自审声明（证据口径）

1. **通读全量**：本轮 diff 全部 hunk 逐处通读（LLMClient :27-140 重写段、SessionCoordinator 5 处、CardViews 2 处、SelfCheck 整段替换、2 文档）；关键前置锚点（run/consume/retry/CardState/SkeletonView 现状）实施前 Read 核对。
2. **整体审视三问**：①达成度——用户两个诉求（看到进展/减少误杀）分别由 ReasoningPreview 与两级超时直接达成，无方案外功能；②实现方式——节流攒批选「consume 内局部 buffer + 时间戳」而非 Timer 发布器，避免引入第三并发实体；ReasoningPreview 固定高避免逐 delta resize；③自洽——「思考即进展」在四个触点口径一致（markEvent 注释、consume 分支、product-design 表、tech-design §4.2）。
3. **断言逐条验证**：见 ①CI-2；关键行为断言（zeroEvent 原因/reasoning 推迟原因/finish 切片）均为异步实测而非常量比对。
4. **实证**：SelfCheck 88/88 ×3、build 0 error、变异 1 项精确 FAIL 后还原。
5. **场景推演（跨组件状态组合，12 项）**：①长思考（用户图 1 场景）——①计时被 markEvent 持续重置不触发，②计时从创建累计 90s 兜底，预览实时滚动；②正文到达——pendingReasoning 先冲（尾部完整）→ phase=.streaming 预览随骨架屏消失；③零事件流——20s `.noEvent`→「模型响应超时」（昨修语义保留）；④快速失败——consume throw→defer finish→0.25s 内感知→nil→rethrow 原错误（切片语义保留）；⑤超时撞 done——catch 的 `phase == .done` 守卫保留；⑥retry——三思考字段重置、计时从零；⑦缓存命中——useCache 分支提前 return 不进竞速；⑧历史回放——done 直达无思考区；⑨无思考模型（deepseek）——无 reasoningDelta 走「正在查询…」旧行为，向后兼容；⑩面板高度——预览固定高 + reasoningText 不 bump revision → 思考期间零 resize 抖动；⑪首帧计时起点——reasoningStartedAt 赋值先于 reasoningActive 触发重渲，同 MainActor 同步块内顺序一致；⑫40KB 级长思考——4000 封顶 suffix 裁尾，Text 渲染成本受控。
   **未覆盖（如实声明）**：真机网络级超时路径（拔线/断流）无法在本环境稳定构造，由断言层覆盖；思考死循环 90s 实测不可行（耗时），由断言以 0.6s 缩比口径覆盖。
6. **修复处定向复核**：编译错误两处即时修复（初版 `guard try await timedOut else` 改 if-let switch；`fix.timeoutIsTimeout` 重复断言移除）；修复后复跑 88/88×3 + build 0 error；未做全量二轮自我辩论。

---

## L1 修复轮（L2a 独立审后，2026-09-30）

L2a 报告：`docs/reviews/L2a-glm-review-reasoning-stream-20260930.md`（0 P0 / 2 P1 / 3 P2；核心竞速五时序判定与昨日 Bool 版语义等价、攒批尾部完整、口径与代码一致）。全部处置：

| # | 位置 | 改动 | 来源 |
|---|---|---|---|
| S1 | `SessionCoordinator.consume` reasoning 分支 | 首条思考 delta 补 `revision += 1`（首帧增高一次，尾部滚动区不再落在面板折叠线下；思考期间仍不逐 delta bump，防抖设计保留） | L2a P1-1 |
| S2 | `SessionCoordinator` | 新增 `appendReasoningTail(card:_:)` 私有函数，两条冲批路径（节流 flush + 正文前冲批）共用，contentDelta 冲批路径也做 4000 封顶 | L2a P2-2 |
| S3 | `SelfCheck` m3 | 补总耗时下界 `>0.30s`（重置生效≈0.37s 到期 vs 被杀 0.25s 提前到期）；变异复测确认现在 FAIL（实测总 0.267s 被捕） | L2a P1-2 |
| S4 | `website/index.html:1109` | hero 统计卡 68→88（L0 漏检的第三处） | L2a P2-1 |
| S5 | `CardViews.swift:344` | onChange 单参旧 API → 双参（macOS 14 目标） | L2a P2-3 |
| — | L0 自查两处失实声明 | ①CI-1「website×2 统一 88」实为漏了 hero 第三处；②变异只测了 m4 单方向（m3 变异存活假绿）——已在报告原文保留并在本节更正 | L2a 反噬 |

修复后：SelfCheck **88/88 ×5 稳定**、xcodebuild 0 error、m3 变异实测 FAIL。

---

## L2 终审修复轮（K3 异构终审后，2026-09-30）

K3 报告：`docs/reviews/L2b-k3-review-reasoning-stream-20260930.md`（0 P0 / 0 P1 / 3 P2；裁决可定稿进实机验收）。全部处置：

| # | 位置 | 改动 | 来源 |
|---|---|---|---|
| K1 | `SessionCoordinator.run` Task 闭包 | 开头 `guard let self else { return }` 显式升级 + `self.consume(...)` 显式调用——`async let` 派生的隐式 self 绕过 `[weak self]` 实为强捕获（K3 /tmp 同构实证）且 Swift 6 硬错误；闭包内两处 `self?.revision` 随 guard 升级改 `revision` | K3 P2-1 |
| K2 | 同处 :390 | `let timedOut = await timeout` 去掉死代码 `try`（waitForTimeout 非 throwing） | K3 P2-2 |
| K3 | `SelfCheck` m3 | 参数拉大（eventLimit/thinkingLimit 0.25→0.4、markVisible 0.12s→0.15s、下界 0.30→0.47s）：调度容差从 0.13s 翻倍到 0.25s，消除「重负载下 markVisible 睡眠超调误 FAIL 正确实现」的反向 flake 窗口 | K3 P2-3 |
| K4 | `docs/tech-design.md:150` | `done(usage: Usage?)` → `case done`（与代码一致，HEAD 既有漏网） | K3 尾行 |
| K5 | `README.md`/`README_EN.md` | 88 项类别枚举补「流式超时守卫」 | K3 尾行 |

修复后：SelfCheck **88/88 ×8 稳定**（含新 m3 参数）、xcodebuild 0 error、SessionCoordinator 相关编译警告清零。K3 三向变异闭合确认（S3 断言在丢①重置/丢②重置/markEvent 染②三方向均 FAIL）。
