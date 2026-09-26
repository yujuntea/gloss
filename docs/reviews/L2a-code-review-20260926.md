# Gloss M1 代码 L2a 独立审查报告（2026-09-26）

> 审查人：glm-reviewer-hs（三段式 L2a 第一道独立审；后续 K3 L2b 异构终审）。
> 对象：`Gloss/` 全部 26 个 Swift 源文件、`Gloss/GlossApp.swift`、`Info.plist`、`Gloss.xcodeproj/project.pbxproj`、`SelfCheck/main.swift`、`scripts/mock_llm.py`。
> 对照基准：docs/DESIGN.md（D1–D7）、docs/product-design.md V1.0、docs/tech-design.md V1.0（§3 数据流/§4 模块/§12 M1 T1–T5）；L0 偏差声明 docs/reviews/L0-selfcheck-code-20260926.md（V1–V6 已声明，本报告不重复报告其存在，仅给可接受性判断）。
> 方法：全源逐文件通读 + 三项必查专项对账 + 定向实测。任务书带全量绿锚（自检 55 项 + xcodebuild 通过 + 实机 11 场景），未重跑全量，仅做定向复验。

## 0. 定向实测记录

- **Carbon 双注册实测**（对应必查 2）：CLI 最小程序两次 `RegisterEventHotKey(0x35, 0, id=99, GetApplicationEventTarget())` → 第一次 `0(noErr)`，第二次 `-9878(hotKeyExistsError)` 且 ref=nil。结论：面板重复 show 时的重复 registerEscape 不会产生句柄泄漏/双触发，但每次产生一条 error 日志（见 P2-1）。
- 全库 grep：apiKey/Keychain 触点、UserDefaults 写点、`AppError.timeout`、`masked(`、触发开关引用、`installHotkeys` 调用点、`useCache: false` 可达性、`重新查询` 字符串——结果分布在正文各条。
- `build/Gloss.app` 构建产物在位，与源码文件清单一致。

---

## 1. 必查项结论（主 Agent 指定）

### 必查 1：缓存键对账 —— 未发现不一致（本轴 0 缺陷）

`CacheStore.makeKey`（CacheStore.swift:24-32）全调用点枚举，共 5 处：

| # | 调用点 | normalizedInput | kind | params | model |
|---|---|---|---|---|---|
| 1 | SessionCoordinator.runText(:287) | `QueryRouter.cacheNormalized(card.inputText ?? "")` | card.kind | nil | activeConfig?.model |
| 2 | SessionCoordinator.startScreenshotExplain(:280) | proc.sha256（JPEG 字节） | .screenshotExplain | nil | 同上 |
| 3 | SessionCoordinator.pushWordAtQuery(:168) | proc.sha256 | .screenshotWordAt | card.kindParams（:156 已量化） | 同上 |
| 4 | SessionCoordinator.retryCurrent(.screenshotWordAt, :205) | proc.sha256 | .screenshotWordAt | card.kindParams（同一存储值） | 同上 |
| 5 | ReaderViewModel.queryOnce(ReaderWindow.swift:166) | cacheNormalized(prompt)（含批次 index/total、聚合材料） | .article | nil | config.model |

- 写入与查询永远走同一 `run(card:cacheKey:)`/`queryOnce` 路径、同一键公式——不存在写 A 查 B。
- 点词坐标：写入侧（pushWordAtQuery:156）先量化到 1% 网格存入 `kindParams`；缓存键（makeKey:28）与 Prompt（PromptLibrary.swift:71-72）两侧都用 `Int((p.x*100).rounded())` 二次取整——三处同值。retryCurrent 复用存储的 kindParams，同键。
- 归一化 `cacheNormalized`（split-whitespace-join）对所有文本路径单点生效，幂等；`PROMPT_VERSION="m1"` 参与键（改版本换键 ✓）。
- 备注（不计缺陷）：makeKey 载荷把 kindParams 排在 PROMPT_VERSION 之后，与 tech §4.9 书面顺序不同——键为不透明哈希，无影响。

### 必查 2：取消与资源配对 —— 发现 1 个 P1（#7）

- `cancelCurrent`（SessionCoordinator.swift:215-221）调用点枚举：beginTextQuery / beginHotkeyQuery / beginScreenshotFlow / pushWordQuery / pushWordAtQuery / popCard / requery / retryCurrent / closeAndCancel / panelDidHide / replay / beginScreenshotWithImage——文本类入口全覆盖；**例外：beginScreenshotFlow 内的截图采集 Task（:132）未存入 currentTask/pendingCapture，不可取消**（P1-7）。
- PanelController 装拆：`installMonitors`（:133）有 `monitors.isEmpty` 幂等守卫 ✓，`hide()` 统一 removeMonitors ✓，严格配对；ESC 热键 register 于每次 `show()`（:58）、unregister 于 `hide()`（:70）——连续查询（面板未关时新查询）会重复 register，实测第二次 -9878 失败、无泄漏无双触发，仅日志噪音（P2-1）。装拆语义实际成立。
- HotkeyManager Box：`Unmanaged.passRetained(Box(self))`（HotkeyManager.swift:17）首次 install 时保留一次、永不 release；Box 强持单例 owner，与 App 同生命周期，属一次性微量常驻，非增长性泄漏（P2-14 建议）。
- TTS：新 speak 先 stop（TTSEngine.swift:23）✓；cancelCurrent → stop ✓；面板关闭（hide→panelDidHide→cancelCurrent）→ stop ✓，三处配对成立。

### 必查 3：Keychain / 日志脱敏 —— 通过（0 缺陷）

- API Key 全部触点：KeychainStore set/get/delete（account=配置 UUID）；`LLMConfig` 结构体**不含任何 key 字段**——存 UserDefaults 的配置 JSON 天然无 key 材料 ✓。
- Bearer 头仅存在于 URLRequest（LLMClient.swift:142,165），无日志输出。
- 全部日志点核对：keychain probe 只打 "hit/miss"（AppDelegate.swift:23）、seed 只打 "readback ok/NIL"（:97）；查询日志只含 kind/键前 12 位/字符数（SessionCoordinator.swift:311,317,344）——key 明文与查询内容均不落日志。QueryRecord 无 key 字段 ✓。
- `KeychainStore.masked` 为未使用代码（预留合规），无风险。

---

## 2. P0（阻塞级）

**未发现 P0。**（无崩溃路径：无用户输入驱动的强解包——`AXValueType(rawValue:)!`/`byID("minimax")!` 均为静态常量；无隐私泄漏；核心链路 11 场景实机可走通。）

## 3. P1（应修，共 9 项）

**P1-1 点词卡底部「朗读/复制」全部无效，复制还会清空用户剪贴板**
- 位置：Gloss/UI/ResultPanelView.swift:141-144（`case .word, .screenshotWordAt:` 动作取 `card.inputText ?? ""`）+ Gloss/Core/SessionCoordinator.swift:157（pushWordAtQuery 创建卡片时 `inputText: nil`）。
- 问题：screenshotWordAt 卡的词条名来自模型输出（WordCardBody.headWord 从 `## ` 标题提取，CardViews.swift:80-86，卡片头部显示正常），但底部动作仍读 `inputText`（nil）。朗读走 `TTSEngine.speak("")` 静默无操作；复制走 `copy("")`——`clearContents + setString("")` 把剪贴板替换为空串。
- 影响：点词场景（product S5-3）四个底部动作按钮全部失效，其中复制按钮产生实际损害（覆盖剪贴板）。
- 修法：动作回调改用与 headWord 相同的取值逻辑（把 headWord 提取下沉为 CardState 计算属性，如 `displayQuery`），或在 pushWordAtQuery 完成后把识别词回填 `card.inputText`。

**P1-2 触发通道开关不生效：服务/截图两开关是死开关，热键开关需重启**
- 位置：Gloss/UI/SettingsWindow.swift:213-215（三个 Toggle 仅绑定持久化）；Gloss/Capture/ServicesBridge.swift:5-14（不检查 channelServiceEnabled）；Gloss/Core/SessionCoordinator.swift:126（beginScreenshotFlow 不检查 screenshotEnabled）；Gloss/App/AppDelegate.swift:17,66-73（installHotkeys 仅启动时调用一次，且 ⌥D/⌥S 共用 hotkeyEnabled 一个条件，screenshotEnabled 从不参与）。
- 问题：设置页呈现 product §6「触发」页的三通道开关，但关闭「右键服务菜单」后 Services 查询照常执行；关闭「截图快捷键」后 ⌥S 照常触发；「划词快捷键」关闭后运行中热键不卸载（仅下次启动生效）。
- 影响：用户显式关闭的通道仍在工作，与 product §6/tech T1 的通道开关语义直接矛盾（隐私预期也会被打破——用户以为关掉了截图通道）。
- 修法：ServicesBridge.doQueryService 与 beginScreenshotFlow 入口检查对应开关；SettingsStore 三个开关 didSet（或 SettingsView.onChange）里调 `AppDelegate.installHotkeys()` 重装热键，installHotkeys 内按 screenshotEnabled 拆分 ⌥S 注册。

**P1-3 模型输出中的 Markdown 链接仍可点击并打开浏览器（tech §4.5 明令禁用）**
- 位置：Gloss/UI/MarkdownView.swift:91-101（`InlineText` 用 `AttributedString(markdown:, .inlineOnlyPreservingWhitespace)` 渲染，未置空 openURL）。
- 问题：AttributedString 的 inline markdown 会解析 `[text](url)`；SwiftUI `Text` 渲染的链接默认可点，走环境默认 OpenURLAction 打开浏览器/Finder。tech §4.5：「Markdown 渲染禁用链接点击（模型输出不可信，OpenURL 置空）」。V1 偏差（内置渲染器替代 swift-markdown-ui）本身可接受，但替代实现丢失了这条安全约束。
- 影响：被污染/幻觉的模型输出可诱导用户点开任意 URL（含 file:// 等 scheme），自用场景下仍是不可信输入直接触发系统行为。
- 修法：InlineText 外层加 `.environment(\.openURL, OpenURLAction { _ in .discarded })`；或解析时剥离 link 保留文字。

**P1-4 历史「清除全部」无二次确认，单击即不可逆清空全部历史**
- 位置：Gloss/UI/HistoryWindow.swift:17-20（Button 直接 `DataStore.deleteAllQueries(); reload()`）。
- 问题：product §7 明确「清除全部（二次确认）」。实现在无任何确认弹窗的情况下物理删除全部 QueryRecord。
- 影响：误点（按钮紧邻搜索框）即永久丢失全部查询历史，数据不可恢复。
- 修法：加 confirmationDialog 或两段式按钮（点一次变「确认清除」再点执行）。

**P1-5 「重新查询（跳过缓存）」入口缺失：缓存态与历史回放两处规格均无落点**
- 位置：Gloss/UI/ResultPanelView.swift:75-94（footer 只有 缓存徽标，无重查动作）；全库 grep「重新查询」零命中；`useCache: false` 仅在 retryCurrent（FailedView 路径，SessionCoordinator.swift:200,207,209）可达。
- 问题：product §4.3 缓存态规格 =「即时渲染 + 缓存徽标 + 『重新查询』链接（跳过缓存）」；§7 历史回放规格 =「浮窗回放该结果（缓存态）并可『重新查询』」。实现在结果成功（缓存命中或流式完成）后没有任何绕过缓存的 UI 路径——顶栏类型切换 `requery(as:)` 也走 `useCache: true` 再吃同一缓存。
- 影响：缓存了错误/过时结果时用户无法强制重查（只能等清缓存），两处产品规格落空；底层机制（run(useCache:false)）已具备但不可达。
- 修法：footer 在 `card.usedCache == true` 时追加「重新查询」按钮 → `retryCurrent()`（其内部已是 useCache:false；需让 retryCurrent 对 .done 态也可用，当前无 phase 门槛，直接可用）。

**P1-6 ReaderViewModel 的跑批 Task 强捕获 self：替换精读内容/关窗不取消旧任务，持续发请求**
- 位置：Gloss/UI/ReaderWindow.swift:49（`task = Task { await runAll() }`，闭包强捕获 VM）、:52-56（cancel 仅由 stop 按钮触发）；Gloss/UI/WindowManager.swift:46-60（showReader 复用窗口、直接替换 rootView）。
- 问题：打开文章 A（分批进行中）后再触发 ≥400 词查询/历史「读」回放打开文章 B → rootView 整体替换，旧 ReaderView/VM 从视图树摘除，但其 Task 强持 VM，runAll 继续逐批调用 LLM（每批一个完整请求）直到聚合完成；关窗（orderOut）同理。用户无感知、不可取消（stop 按钮已随视图消失）。
- 影响：重复计费的真实 API 请求 + 内存中滞留整套批次状态；与 tech §7「长任务在独立 window 的 session 中运行」的可取消语义不符。
- 修法：VM `deinit` 不可达 Task 的替代方案——Task 闭包改 `[weak self]` 并在每批循环开头 `guard let self` 检查；或 WindowManager.showReader 替换 rootView 前持有旧 VM 引用并调 `cancel()`（如把当前 VM 存到 WindowManager）。

**P1-7 截图采集 Task 未纳入取消管理：竞态下可见卡片冻结在 streaming，隐形结果照常写缓存/历史**
- 位置：Gloss/Core/SessionCoordinator.swift:126-138（`Task { [weak self] ... }` 既未存 currentTask 也未存 pendingCapture）。
- 问题：时序：⌥S →（面板显示 capturing 卡）→ 用户立刻 ⌥D → beginHotkeyQuery 的 cancelCurrent 取消不了截图 Task → 词卡开始流式（currentTask=词任务）→ 截图子进程返回 → startScreenshotExplain 对**已出栈的**截图卡调 run() → run 内 `currentTask?.cancel()`（:316）取消正在显示的词卡流 → 词卡 catch 到 `.cancelled` 直接 return（:346-347），phase 停留 `.streaming`——面板显示一张永久转着光标的冻结卡；截图结果流进不可见卡片，完成后照常写缓存与历史（:340-341）。
- 影响：违反 product §4.4「查询进行中再次触发 = 取消旧流式请求，浮窗原地切新内容」；产生用户看不到的缓存/历史脏条目；面板假死需 ESC 恢复。
- 修法：该 Task 存入 `pendingCapture`（与热键采集同待遇），返回后先 `guard` 卡片仍是 `stack.last` 再继续；run() 内取消旧任务后若旧卡仍在栈中，把其 phase 置 `.failed("已取消")` 或从栈移除。

**P1-8 流式空闲超时被归类为「网络连不上」：AppError.timeout 是死码，连接 10s 预算未单独实现**
- 位置：Gloss/Core/LLMClient.swift:57（`timeoutIntervalForRequest = 20`，注释「连接与流空闲超时」合一）、:119-124（`catch let e as URLError` 把 `.timedOut` 一律映射 `AppError.network` → 文案「网络连不上，检查后重试」）；:46 的 `case .timeout: return "模型响应超时"` 全库无抛出点。
- 问题：tech §4.2 规格 =「连接 10s；流式空闲 20s 取消并抛 timeout」；product §8/§9 要求超时出「模型响应超时」错误态且不自动重试。实现 20s 空闲触发 URLError.timedOut 后报成网络错误，用户被误导去「检查网络」；「超时≠限流不重试」的语义幸好仍成立（重试只认 429/5xx），但错误域区分完全丢失。
- 影响：错误态文案与 product §8 文案规范直接不符；诊断口径（network vs timeout）不可区分。
- 修法：URLError 分支加 `if e.code == .timedOut { finish(throwing: AppError.timeout) }`；连接 10s 可用单独的 URLRequest.timeoutInterval（对 bytes 请求为请求级超时）或保留合并但在文档回填。

**P1-9 ResponseCache 持久层永不清理：内存 LRU 淘汰不删盘，SwiftData 缓存表无上限增长**
- 位置：Gloss/Core/CacheStore.swift:43-49（put 只 persistPut upsert）、:67-73（evictIfNeeded 仅清内存 dict）；Gloss/Storage/DataStore.swift:44-57（cachePut 只 upsert，无删除路径）、:59-66（cacheLoadAll 只 fetchLimit 2000 读取）。
- 问题：tech §4.9 容量策略 =「LRU 上限 2000 条或 50MB，**启动时清理**（依赖 lastAccessedAt）」。实现中淘汰只发生在内存 dict；被淘汰键对应的 SwiftData 行永远留存（唯一删除路径是手动「清除缓存」）。每次启动 loadPersisted 取最近 2000 行进内存，旧行在盘上无限累积。且 get() 命中只更新内存 lastAccess（CacheStore.swift:34-41），持久层 lastAccessedAt 永远等于写入时间——跨启动的 LRU 退化为 FIFO（tech §5「命中时更新」未落实）。
- 影响：常驻菜单栏 App 长期运行下缓存库文件无上界增长（精读一篇文章即产生 N 批 + 1 聚合 = N+1 行）；淘汰顺序随重启失真。
- 修法：启动时（loadPersisted 后）按 lastAccessedAt 删除超出 maxEntries/maxBytes 的 ResponseCache 行；get() 命中时异步回写持久层 lastAccessedAt（可节流）。

## 4. P2（建议，共 15 项）

1. **PanelController.show 重复 registerEscape 每次打 error 日志**（PanelController.swift:58 + HotkeyManager.swift:36-38）：连续查询时第二次 RegisterEventHotKey 实测返回 -9878，被当 error 记录——日志噪音且伪装故障。修法：register 入口对已存在的 id 只更新 handler 并返回 true（幂等）。
2. **ReaderViewModel 取消后当前批 phase 停留 .running**（ReaderWindow.swift:95-99：catch 中取消分支直接 return）——批次转圈动画永驻。修法：取消时把 running 批置回 .pending。
3. **存在失败批次时聚合照常执行且材料为空串**（ReaderWindow.swift:121-128：materials 拼入空翻译，无缺失标注）——逻辑解读基于不完整材料静默生成。修法：聚合前检查失败批，材料中显式标注「第 N 批缺失」或阻断并提示先重试。
4. **splitBatches 不切分无换行的超长段落**（PromptLibrary.swift:84-99：按 \n 分段聚合）——单段 ≥600 词的输入只出 1 批，防截断目的落空。修法：段落再按句号/词数二次切分。
5. **SSEParser 收到 `data: [DONE]` 时未先 flush 缓冲**（SSEParser.swift:22-25：直接 removeAll + 返回 done）——服务器若省略 [DONE] 前的空行，最后一条 data 事件丢失。修法：[DONE] 分支先 flush 再返回。
6. **选区定位与规格的三处小偏差**（PanelController.swift:91-128）：①未做「偏右 12pt」（x 直接取 sel.minX）；②缺「下方→上方→左侧」第三档避让；③maxContentHeight 取 `NSScreen.main` 而非鼠标所在屏（:45）。
7. **⌥S 采集期间即弹面板**（SessionCoordinator.swift:128-131：captureInteractive 前就 show，CapturingView 文案为「正在获取选中文本…」）——文案不适用，且浮窗可能遮挡正在框选的区域；product §4.4「唤起系统框选→成功则查询，取消则静默返回」的语义是采集期间不弹。修法：截图流改为采集成功后再 show 面板。
8. **截图卡缺「展开精读」动作**（ResultPanelView.swift:151-154 无此按钮；product §4.2 底部操作条注明「展开精读〔仅段落卡与截图卡〕」）。若产品侧认定截图卡不需要，应回改 product §4.2 而非单边省略。
9. **单词卡两处规格交互未实现**：例句无「点击整句朗读」（product §4.3① 字段注释）、辨析无默认折叠（§4.3①「辨析 ▸ 默认折叠，点开」）；句子卡原文无「点开全文」（§4.3② 两行截断点开）；缩略图无十字光标提示（§4.3④）。
10. **菜单栏图标缺权限缺失红点**（tech §4.10「缺失且对应通道开启时加红点」；实现只有菜单内 summary 行，AppDelegate.swift:54）。
11. **高级页缺「日志级别」开关**（product §6 高级；GlossLog 常开，print 常输出）。
12. **Key 保存交互与「粘贴即存」不符 + 测试连接用已存 Key**（SettingsWindow.swift:126-133 需点「保存 Key」；:185-195 testConnection 用 Keychain 旧值而非 keyInput 草稿——用户贴新 Key 直接点测试会得到旧 Key 的结果）。
13. **历史窗三处小缺口**（HistoryWindow.swift）：⭐ 本地标记无 UI（product §7，QueryRecord.isStarred 全程未用）；列表仅 onAppear 加载（窗口开着时新查询不出现）；输入预览未按 40 字截断（仅 lineLimit(1)）。
14. **HotkeyManager Box 永不 release**（HotkeyManager.swift:17）：单例同生命周期、一次性微量；建议在 unregisterAll/注释中显式声明意图，防未来非单例使用时踩坑。
15. **Info.plist NSServices 与 tech §4.6 模板差异**（Info.plist:34-52）：无 `NSRequiredContext`；NSSendTypes 用 `NSStringPboardType + public.utf8-plain-text` 而非模板的 `NSTextType`。属 §13-C3 实现期校准项，建议实测后回填 tech 文档（服务不出现时的兜底引导已具备）。

（其余微小项，合并一行：OnboardingView.hasKey 每次 body 求值打一次 Keychain:159-161；LLMClient 重试 sleep 用 `try?` 吞取消、取消时多走一轮请求组装:114；isChineseDominant 未计 FF00-FFEF 全角符号段:QueryRouter.swift:51；tech §2 声明的 `TextFetching` protocol 未落地（仅 CaptureResult/withTimeout）；`SettingsStore.resetAll`/`KeychainStore.masked` 为死代码。）

## 5. 方案符合性总评（M1 T1–T5 × 实现路径）

- **T1 骨架与配置** ✓：LSUIElement、状态栏、设置四页签、Keychain（V5 account=UUID 更稳）、预设（V2 类型化合理）、「测试连接」、无 Key 提示条（run:300-304 → .noKey 卡 + 去设置按钮）均落地。缺口=触发开关死设置（P1-2）、日志级别页缺项（P2-11）。
- **T2 服务通道+面板+LLM** ✓：ServicesBridge/NSServices、PanelController（nonactivating+canJoinAllSpaces+fullScreenAuxiliary :26）、SSE 多模态客户端、单词卡齐。缺口=链接禁用（P1-3）、超时文案（P1-8）。
- **T3 热键+句段卡+TTS** ✓：⌥D/⌥S Carbon、AX(150ms 内建预算)+⌘C(300ms) 双通道（withTimeout 外包 0.25/0.45 合理）、PermissionCenter（CGPreflightScreenCaptureAccess 优于设计的 CGDisplayStream 试探，认可）、句/段卡含 chips 统一手势（K-P1-1 落实）、TTSEngine 倍率钳制 ✓。
- **T4 截图通道** ✓：双条件取消判定（退出码+changeCount）、「立即恢复」原剪贴板（0.5s 延迟可接受）、ImagePipeline 纯 CG（F3 核实）、点词 1% 网格量化入键（必查 1 通过）。缺口=采集 Task 不受取消管理（P1-7）、点词卡底部动作失效（P1-1）。
- **T5 精读+打磨** ✓：分批+聚合（聚合入参含逐批全文翻译材料，优于"禁只喂要点"字面 ✓）、页内缓存经 CacheStore（重开经缓存秒显 ✓）、历史窗、向导、SMAppService、错误态。缺口=跑批任务生命周期（P1-6）、无换行不分批（P2-4）。
- **三原则**：零打断（nonactivating 面板+ESC 消费式热键实测口径成立）✓；一秒钟（缓存命中路径直接回显 :306-312）✓；所见即可问 ✓。
- **V1–V6 可接受性判断**：全部可接受。其中 V1（内置 MarkdownView）引入了 P1-3 的安全缺口——偏差本身可接受，但替代实现必须继承被替代物的安全约束；V3（SelfCheck 替代 GlossTests）恰是 P1-8 溜过的缝隙（tech §10 原要求的 LLMClient 超时/429 URLProtocol 用例没有对应 SelfCheck 覆盖，建议给 LLMClient 错误映射补最小自检）。
- **F1–F5 修复锚点复核**：全部属实（LLMClient.swift:92-107 逐字节分行；SectionExtractor.swift:11-19 尾注节名；ImagePipeline.swift:14-48 纯 CG；CardViews.swift:70-86 stripFirstHeading/headWord；Carbon/AX 导入修正）。

## 6. 结论

Gloss M1 的核心链路（三条通道→路由→SSE 流式→四类卡片→缓存/历史/精读）实现完整、结构清晰，缓存键对账与 Keychain 纪律两项专项检查干净，L0 声明的 F1–F5 修复与 V1–V6 偏差均核实成立。主要缺陷集中在**生命周期管理**（未纳管的截图 Task、强捕获的精读 Task）、**设置语义**（死开关）、**规格交互缺口**（重查入口、二次确认）与**错误分类**（超时→网络）四处，无 P0。

**统计：P0×0 / P1×9 / P2×15**
