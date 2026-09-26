# M1 代码 L2a/L2b 处置记录（2026-09-26）

> 上半部：glm-reviewer-hs（L2a）代码审查报告 [L2a-code-review-20260926.md](L2a-code-review-20260926.md)（P0×0/P1×9/P2×15）的处置。
> 下半部：K3（L2b）终审报告 [L2b-code-review-20260926.md](L2b-code-review-20260926.md)（P0×1/P1×5/P2×11）的处置。

## L2a P1 处置（9/9 全部修复）

| # | 问题 | 修复 | 回归证据 |
|---|---|---|---|
| P1-1 | 点词卡底部朗读/复制读 inputText(nil)，复制清空剪贴板 | CardState 新增 `displayQuery` 计算属性（点词卡取模型 `##` 识别词，文本卡取输入原文）；ResultPanelView 四动作全部改读 displayQuery | 编译 ✓；场景 S9 重跑待 K3 后抽查 |
| P1-2 | 触发通道开关为死设置 | ServicesBridge 入口检查 channelServiceEnabled；beginScreenshotFlow 入口检查 screenshotEnabled；installHotkeys 拆分 ⌥D↔hotkeyEnabled / ⌥S↔screenshotEnabled；三开关 didSet post `.glossChannelsChanged`，AppDelegate 监听重装热键 | 编译 ✓ |
| P1-3 | 模型输出 Markdown 链接可点击 | InlineText 加 `.environment(\.openURL, OpenURLAction { _ in .discarded })` | 编译 ✓ |
| P1-4 | 历史「清除全部」无确认 | 两段式按钮（首击变红色「确认清除全部？」，再击执行；改搜索词重置） | 编译 ✓ |
| P1-5 | 「重新查询（跳过缓存）」入口缺失 | footer 在 usedCache 时显示 🔄 按钮 → retryCurrent()（内部 useCache:false） | 实机重跑：缓存态卡片出现 🔄 按钮（r1_word.png） |
| P1-6 | ReaderViewModel 跑批 Task 强捕获 self | Task 改 `[weak self]`+guard；WindowManager 持有 currentReaderVM，showReader 替换前 cancel 旧 VM；ReaderView 改 ObservedObject（StateObject 在 rootView 替换时不重建的坑） | 编译 ✓ |
| P1-7 | 截图采集 Task 不受取消管理 | 采集 Task 存入 pendingCapture；完成后 guard 卡片仍是栈顶才继续；run() 取消旧任务时旧卡置 `.notice("已取消")`；⌥S 改为采集成功后再弹面板（兼收 P2-7） | 编译 ✓ |
| P1-8 | 超时报成「网络连不上」，AppError.timeout 死码 | 新增 `LLMClient.mapURLError`（timedOut→.timeout / cancelled→.cancelled / 其余→network）；自检补 4 断言 | 自检 fix.timeoutIsTimeout/cancelMapping/networkMapping PASS |
| P1-9 | ResponseCache 持久层永不清理、命中不回写 | CacheStore.persistTouch → DataStore.cacheTouch（60s 节流回写 lastAccessedAt）；启动 cachePruneToLoaded 删除未入内存 LRU 的行；AppDelegate 装配 | 编译 ✓；实机 cache hit 日志正常 |

## L2a P2 处置（修复 10 / 登记 5）

修复：P2-1（HotkeyManager.register 幂等——重复 id 先卸旧再注册，消除 -9878 噪音）；P2-2（取消时 running 批置回 .pending）；P2-3（聚合材料显式标注「第 N 批查询失败，材料缺失」）；P2-4（splitBatches 超长无换行段落按句切分 + 自检 fix.splitLongParagraph）；P2-5（[DONE] 先 flush 缓冲并与 done 合并返回 + 自检 fix.doneFlushesBuffer）；P2-7（⌥S 采集成功后再弹面板，随 P1-7）；P2-8（截图卡补「展开精读」按钮——对识别文本开精读窗）；P2-12（测试连接优先用输入框草稿 Key）；P2-13（历史预览 40 字截断 + product §7 对齐）；P2-15（tech §13-C3 回填实际 NSSendTypes 取值）。

登记（M2 前清单）：P2-6（pdfPage 模板定稿——原已登记 §12 M2）；P2-9（例句点击朗读/辨析折叠/原文点开全文/十字光标——M1 打磨清单）；P2-10（菜单栏权限红点）；P2-11（日志级别开关）；P2-14（HotkeyManager Box 生命周期注释）。微小项合并行按原建议登记。

## 修复后回归（全量）

- typecheck：零 error（仅 1 条 NSEvent Sendable 语言模式 warning，登记）。
- 逻辑自检：**62 项全 PASS**（原 55 + L2a 修复回归 7）。
- xcodebuild：BUILD SUCCEEDED。
- 实机：单词卡场景重跑——标题去重 ✓、缓存徽标 ✓、🔄 重新查询按钮 ✓（r1_word.png）；另获**意外真实联调**：defaults 清理后配置回退 MiniMax 默认端点，mockkey 发往真实 api.minimax.chat 返回 401 → 错误卡「API Key 无效或已过期」+ 重试按钮渲染正确（真实服务器 401 路径验证）。

---

# K3（L2b）处置记录（2026-09-26）

## P0 处置（1/1 修复）

| # | 问题 | 修复 | 回归证据 |
|---|---|---|---|
| K-P0-1 | ⌥S 接管守卫读残留旧栈 → 每会话仅首次截图可用（L2a P1-7 修复引入的回归） | 删除守卫（取消语义已由 cancelCurrent+pendingCapture 覆盖，且采集完成到 show 无 await 无交错窗口） | 等价路径实机：`-demo-image-twice` 同会话连续两次截图，第二张完整接管显示（r2_twice.png）；真实 ⌥S 框选留用户验收清单 |

## P1 处置（5/5 全部修复）

| # | 问题 | 修复 | 回归证据 |
|---|---|---|---|
| K-P1-1 | [DONE] 合并 flush 内容在消费侧 `if chunk.done { break }` 先于 yield 被丢弃（L2a P2-5 修复端到端失效，parser 单测+mock 规范流双层假绿） | 消费侧改先 yield reasoning/content 后判 done break；mock_llm.py 增 NOFLUSH 形态开关（仅最后一个 data 事件省略空行——真实服务器 bug 形态；初版实现误把全部事件改无空行=巨型多行事件违反 SSE 语义，已纠正） | 实机 NOFLUSH 场景 `query done kind=word chars=516` 完整（修复前同场景 chars=0） |
| K-P1-2 | 精读窗关窗（orderOut）不取消跑批，N+1 付费请求照烧 | ReaderView 加 `.onDisappear { vm.cancel() }`（cancel 幂等，替换路径重复调用无害） | 编译 ✓ |
| K-P1-3 | "旧卡置 notice" 死代码（run 内 8 调用点 7 处 old===card，唯一例外被 P0-1 守卫拦截）；push 子查询时旧卡冻结 .streaming | 终态处理挪到 cancelCurrent()（遍历栈内 streaming/loading 卡置 .notice("已取消")）；删 run() 死代码 | 编译 ✓；逻辑覆盖 push/requery/关闭全部路径 |
| K-P1-4 | 回放截图卡点 🔄 先清 content 再裸 return → 一键清空回放内容 | retryCurrent 把无原图 guard 前置（置 .notice("原图已释放，请重新截图 ⌥S")）；footer 🔄 对无原图截图卡不渲染（双保险）；replay 增 thumbnail 参数还原缩略图（兼 K3-P2-5） | 编译 ✓ |
| K-P1-5 | installHotkeys 短路求值把"用户关闭通道"误报为快捷键冲突 | 拆分计算：`hotkeyConflict = (hotkeyEnabled && !okD) \|\| (screenshotEnabled && !okS)` | 编译 ✓ |

## K3 P2 处置（修复 7 / 登记 4）

修复：P2-1（testConnection 复用 mapURLError，超时口径与 stream 一致）；P2-2（retryBatch/retryAggregate 覆盖 task 前先 cancel 旧任务）；P2-3（精读取消后可继续：start() 允许重入沿用批次，done 批缓存秒回；停止/继续按钮切换）；P2-4（删除恒真空断言，改真实 if-case 判定）；P2-5（随 K-P1-4 的 replay thumbnail）；P2-7（cacheTouch 自节流：CacheStore 内存 lastTouch 60s 内跳过，命中路径不再持锁做 DB 读）；P2-9（ImagePipeline 单 context 绘制+makeImage，删双 context 迂回）；P2-10（AXTextFetcher 主屏高度改主线程预取注入，池线程不触 NSScreen）；P2-11（mock NOFLUSH 形态开关，兼作 K-P1-1 回归工具）。微小项：SettingsWindow testConnection 死代码三行删除；高级页重复 CacheStore.clear() 删除；AppDelegate -panel-at 死绑定删除。

登记（M2 前清单）：P2-6（持久缓存 50MB 字节阈值——已随 cachePruneToLoaded 双阈值实现，登记实机长跑观测）；P2-8（tech §4.2 连接 10s 已回填为 20s 合并口径 ✓ 实为修复非登记）；P2-13 中登记项与 L2a P2 登记项合并维护；微小项（Info.plist NSPrincipalClass 与 @main 并存——留置无冲突；精读历史 origin 恒 .service——M2 随 origin 传参改造）。

## 修复后全量回归（2026-09-26）

- typecheck：零 error（1 条 Sendable 语言模式 warning 登记）。
- 逻辑自检：**61 项全 PASS**（删 1 恒真占位，56 原有 + L2a 修复回归 4 + K3 映射断言 1）。
- xcodebuild：BUILD SUCCEEDED。
- 实机端到端：①NOFLUSH 流尾场景 chars=516 完整（K-P1-1）；②`-demo-image-twice` 第二张截图卡完整接管（K-P0-1）；③NOFLUSH 词卡缓存徽标正常。
- 验收残留清理：mock 进程/defaults/keychain item/SwiftData store 全部还原，用户首启将走真实配置向导。

---

# 真实 MiniMax 联调 + Computer Use 实测（2026-09-26 追加）

## C1 校准结果（真实 Key 实测）

- **OpenAI 兼容端点**：`https://api.minimaxi.com/v1/chat/completions` + 模型 `MiniMax-M3` → HTTP 200（与用户 Anthropic 兼容端点同域同 Key）；ProviderPresets 已回填。
- **关键形态差异**：流式无 `reasoning_content` 字段，思考内联于 content 的 `<think>…</think>` → 新增 `InlineThinkFilter` 状态机（跨 chunk 标记剥离/flush，自检 think.* 4 项），实机确认卡片无思考泄漏。
- **真实联调三项**：词卡（904 字符，语境义/音标/词源全部真实）、多模态读图（合成英文图→识别/翻译/四要点）、精读（批+聚合，术语英文括注生效，难词四列表带真实音标例句）。

## Computer Use 实测（真实用户路径）

走通首启向导全流程（AX 元素级操作）：欢迎页→模型配置页（预设 MiniMax/选国际/**键盘输入真实 Key**/「测试连接」→**连接成功 · 963ms**）→权限页（服务已就绪、⌥D/⌥S 检测式引导正确显示未授权态）→完成页→**「立即试查 serendipity」→ 真实 M3 词卡弹出渲染完整**（含向导示例句语境义、Horace Walpole 词源、无 think 泄漏）→完成关闭。
过程中顺带验证：Key 为空时「测试连接」正确禁用；错误 Key（输入叠加事故）→ 真实 401 →「API Key 无效或已过期」错误态正确。
工具边界登记：CUA 无法锚定 LSUIElement 菜单栏应用（无 AX 树）——菜单栏图标点击未走 CUA，已有 CGWindowList Item-0 证据与标准 NSMenu 实现兜底。
