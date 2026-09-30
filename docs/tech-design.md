# Gloss 技术实现文档

> 版本：V1.1（2026-09-27）。权威范围见 [DESIGN.md](DESIGN.md) 文档索引；交互规格以 [product-design.md](product-design.md) 为准，本文不重复。
> 外部接口事实（MiniMax 端点/模型 ID、系统权限实际行为、Services 注册细节）凡标注"实现期校准"处，须在 M1-T1/T2 联调时实测确认并回填本文。

## 1. 架构总览

### 1.1 分层

```
┌─────────────────────────── AppShell ───────────────────────────┐
│  菜单栏(NSStatusItem 自定义视图) / 生命周期 / 首启向导 / 权限引导(PermissionCenter) │
├─────────────── 捕获层 Capture ─────────────────────────────────┤
│  AXTextFetcher / ClipboardFallback(⌘C) / ServicesBridge        │
│  HotkeyManager(⌥D/⌥S) / ScreenshotManager / PDFImporter〔M2〕   │
├─────────────── 路由层 Router ──────────────────────────────────┤
│  QueryRouter：输入(text/image/pdfPage) → QueryKind + Prompt 选择  │
├─────────────── 服务层 Core ────────────────────────────────────┤
│  LLMClient(SSE 流式+多模态) / PromptLibrary / TTSEngine         │
│  CacheStore / KeychainStore / SettingsStore / DataStore         │
├─────────────── 展示层 UI ──────────────────────────────────────┤
│  PanelController(NSPanel) / 四类卡片 / 精读窗 / 设置窗 / 历史窗     │
└─────────────────────────────────────────────────────────────────┘
```

单向数据流：捕获层产出 `QueryInput` → `SessionCoordinator` 建立会话（状态机）→ 服务层流式产出增量 → UI 层订阅渲染。UI 永不直接调用捕获层。

### 1.2 技术选型

| 项 | 选择 | 理由 |
|---|---|---|
| 系统/语言 | macOS 14+ / Swift 5.10+ | 本机 15.6；SwiftData 需 14。菜单栏用 NSStatusItem 自定义视图（弃 MenuBarExtra——后者不支持图标拖放，M2 拖拽 PDF 需要；菜单用原生 NSMenu 搭建。注：statusItem.view 自 10.14 标记废弃，自签自用可用，拖放承接验证列入 M2 开工项） |
| UI 框架 | SwiftUI + AppKit 混合 | SwiftUI 快速搭建卡片/设置；NSPanel/Services/PDFView 需 AppKit |
| 第三方依赖 | [Sparkle](https://github.com/sparkle-project/Sparkle) 2.10+（SPM，v0.1.3 引入） | App 内自动更新：静态 appcast + EdDSA 验签 + 原地替换安装；其余全用系统框架（AVFoundation/PDFKit/Carbon），Markdown 渲染为自研 `UI/MarkdownView`（未引入 swift-markdown-ui） |
| 沙盒 | 关闭（D4 自签） | Services 的 NSPortName、⌘C 兜底、子进程截图在非沙盒下实现最简 |
| App 形态 | LSUIElement=YES（无 Dock 图标） | 菜单栏常驻工具型 App 惯例；设置/精读窗用 NSApp.activate 拉起 |

## 2. 工程结构

```
gloss/
├── Gloss.xcodeproj                # 提交工程文件（不使用 xcodegen）
├── docs/                          # 本文档集
├── scripts/release.sh             # 规范构建 + EdDSA 签名 + appcast 生成 + GitHub 发布
├── SelfCheck/main.swift           # 逻辑自检入口（swiftc 联合编译，见 §10）
├── Gloss/
│   ├── GlossApp.swift             # @main；AppDelegate 注入（Services/生命周期）
│   ├── App/
│   │   ├── AppDelegate.swift      # 菜单栏/热键/生命周期/菜单栏「检查更新…」项
│   │   ├── OnboardingView.swift   # 4 步向导 + 权限引导视图
│   │   └── PermissionCenter.swift # AX/屏幕录制 检测+引导+复检
│   ├── Capture/
│   │   ├── TextFetching.swift     # protocol：fetch() async -> CaptureResult
│   │   ├── AXTextFetcher.swift    # AX 取词（含选区 bounds/上下文 best-effort）
│   │   ├── ClipboardFallback.swift# ⌘C 模拟：快照→发送→轮询→读取→恢复
│   │   ├── ServicesBridge.swift   # doQueryService(pboard:userData:error:)
│   │   ├── HotkeyManager.swift    # Carbon RegisterEventHotKey
│   │   └── ScreenshotManager.swift# screencapture -i -c 子进程 + 取图
│   ├── Core/
│   │   ├── QueryRouter.swift      # 输入分类 → QueryKind
│   │   ├── SessionCoordinator.swift # 会话状态机、取消、防抖
│   │   ├── LLMClient.swift        # OpenAI 兼容 SSE + 多模态
│   │   ├── SSEParser.swift        # data: 行解析（独立可测）
│   │   ├── PromptLibrary.swift    # 5 套模板 + 分 kind 版本号
│   │   ├── SectionExtractor.swift # 精读文本分节（独立可测）
│   │   ├── ImagePipeline.swift    # 缩放/JPEG 压缩（截图 1568 / PDF 页 2200 长边上限）
│   │   ├── TTSEngine.swift        # AVSpeechSynthesizer 封装
│   │   ├── CacheStore.swift       # 响应缓存
│   │   ├── KeychainStore.swift    # API Key 存取
│   │   ├── SettingsStore.swift    # UserDefaults + LLMConfig 管理
│   │   ├── ProviderPresets.swift  # 内置厂商预设（代码内常量）
│   │   ├── GlossLog.swift         # 统一日志
│   │   └── UpdaterCenter.swift    # Sparkle 更新单例：版本号/检查/自动检查开关（v0.1.3）
│   ├── UI/
│   │   ├── WindowManager.swift    # 设置/精读/历史/向导/图片放大 窗口编排
│   │   ├── PanelController.swift  # NSPanel 生命周期/定位/事件监听
│   │   ├── ResultPanelView.swift  # 浮窗根视图（顶栏/卡片区/操作条）
│   │   ├── CardViews.swift        # WordCard/SentenceCard/ParagraphCard/ScreenshotCard
│   │   ├── MarkdownView.swift     # 自研流式 Markdown 渲染
│   │   ├── ImageZoomWindow.swift  # 图片放大窗（原图 fit 满窗/十字准星/整图点词，§4.12）
│   │   ├── ReaderWindow.swift     # 精读窗（文本模式 M1 / PDF 模式 M2）
│   │   ├── SettingsWindow.swift   # 四页签（高级页含版本与更新区块，v0.1.4）
│   │   └── HistoryWindow.swift
│   └── Storage/
│       ├── GlossModels.swift      # SwiftData @Model
│       └── DataStore.swift        # ModelContainer/Context 管理
├── scripts/                       # release.sh
├── dist/                          # 产物（zip/appcast/notes，不入库）
└── Info.plist                     # NSServices/LSUIElement/SU* 更新键等
```

## 3. 核心数据流

### 3.1 ⌥D 划词流

1. `HotkeyManager` 回调（主线程）→ `SessionCoordinator.begin(.hotkey)`。
2. `AXTextFetcher.fetch()`（预算 150ms）：`AXUIElementCreateSystemWide` → `kAXFocusedApplication` → `kAXFocusedUIElement` 读 `kAXSelectedText`；为空则对该子树做受限度优先搜索（深度≤6、访问元素≤200、总预算 150ms）。
3. 成功：附带 best-effort 上下文（`kAXSelectedTextRange` 扩展后用 `AXStringForParameterizedAttribute` 取 ±100 字符）与选区 bounds（用于浮窗定位）。
4. 失败：`ClipboardFallback.fetch()`（预算 300ms）：快照 pasteboard 全 items → `CGEventPostToPid(前台 pid, ⌘C)` → 每 50ms 轮询 `changeCount` → 读 string → 异步恢复快照（尽力而为）。
5. `QueryRouter.classify(text)` → `QueryKind` → 取 Prompt → 查 `CacheStore`：
   - 命中：面板直接渲染缓存 + 徽标，结束；
   - 未命中：`LLMClient.stream()` 建立 `QuerySession`，面板骨架→流式渲染。
6. 成功完成：写缓存 + `DataStore` 落 `QueryRecord`（受设置「历史记录」开关控制，product-design §6）。

### 3.2 Services 流（右键）

`ServicesBridge` 收到 pasteboard 文本（系统直接给，免权限免取词）→ 跳过 3.1 的 2–4 步，直接进 5；面板定位用鼠标位置。

### 3.3 ⌥S 截图流

1. `ScreenshotManager.capture()`：`Process` 执行 `/usr/sbin/screencapture -i -c`（交互框选，结果进剪贴板）。取消判定 = "退出码 + 剪贴板无新图"双条件（退出码语义以 §13-C2 实测为准，勿单独依赖）。取消 → 直接返回不弹窗。
2. 成功：读 pasteboard 图片 → **立即恢复**用户原剪贴板 → `ImagePipeline.normalize(image, maxEdge: 1568)`（等比缩放 + JPEG q0.85 + 计算 sha256 用作缓存键成分）。
3. `SessionCoordinator` 以 `QueryInput.image` 建立 → 默认 Prompt = 读图解释 → 多模态请求（§6.2）→ 截图卡流式渲染。
4. 图上点词：缩略图 `SpatialTapGesture` + `GeometryReader` 换算归一化坐标 (x%, y%) → 以原图 + 坐标重新请求（Prompt = 点词定位），复用同一面板切换为单词卡，卡顶加「返回整图」。缩略图点击**按原图自然宽度与卡片实测可用宽分流**（`ImageGeometry.needsZoomWindow`）：原图自然宽 ≤ 卡片当前可用宽就地点词；宽于此则正文在 160pt 缩略图里不可读，改为打开图片放大窗（§4.12）在整图上点词。卡宽取实测 `geo.size.width`（当前 `ResultPanelView` 以 `.frame(width: 400)` 把内容宽钉死，实测恒为 376；按实测值判定可免面板将来可调宽时回头改此处）。历史回放卡只有 ≤200px 缩略图，自然落在阈值内 → 永不开放大窗。
5. 截图卡的生词入口：读图 prompt 输出 `**难词表**`（§4.3），卡片按 §4.3 的取数契约拆成 chips（`WordChipsRow`），每行以「图中原文例句」为语境下钻；该表同时从卡片正文中移除，不重复渲染。

### 3.4 PDF 流〔M2〕

1. 打开文件 → `PDFDocument` + 左栏 `PDFView`。
2. 「解析当前页」：`page.thumbnail(of:CGSize(按 2200px 长边折算, for: .mediaBox))` 渲染页图 → `ImagePipeline.normalize(…, maxEdge: 2200)`；`page.string` 非空时作文本层参考随图附上；多模态请求 → 四 Tab。
3. 「解析全文」：执行前确认页数与预估 token（product-design S6-4）；逐页串行（并发=1 防限流）循环 2，每页独立缓存键（含文档 sha256 前缀 + 页码）；可随时取消（已完成页缓存保留）；全部完成后把各页"要点"聚合做一次"逻辑解读"汇总请求。
4. 页内划词：`PDFView` 选区回调（`PDFSelection.string`）→ 直接走文本管线（内嵌文本层，非 OCR——D6）。

## 4. 模块设计（关键接口与实现要点）

### 4.1 QueryRouter

```swift
enum QueryKind: String { case word, sentence, paragraph, article, screenshotExplain, screenshotWordAt, pdfPage }
enum InputOrigin: String { case service, hotkeyAX, hotkeyClipboard, screenshot, pdfSelection, pdfPage }

func classify(_ text: String, origin: InputOrigin) -> QueryKind
// 带参 kind 的参数由会话外置持有：struct KindParams { var point: CGPoint? /*已量化到 1% 网格*/; var pageIndex: Int? /*M2 pdfPage*/ }
// 纯字符串枚举不带关联值（rawValue 可持久化、可入缓存键）；screenshotWordAt 的坐标经 KindParams 传递
```

分类规则（与 product-design §4.4 一致，表驱动可测）：
- 去首尾空白后：词数 ≤3 且无句中标点/句末标点 → `word`（连字符/撇号词算 1 词）；
- 含句末标点且词数 <60 → `sentence`；词数 <400 → `paragraph`；≥400 → `article`；
- 以 CJK 字符占比 >50% → 标记为中文输入（M1 显示"即将支持"，M3 路由反向查询）；
- 截图输入固定 `screenshotExplain` / `screenshotWordAt`。
上下文（AX 抓到的 ±100 字符）只对 `word`/`sentence` 附带。

### 4.2 LLMClient（OpenAI 兼容）

```swift
struct LLMConfig: Codable { var presetID: String; var baseURL: URL; var chatPath: String; var apiKeyRef: String /*Keychain*/; var model: String; var temperature: Double }
struct ChatMessage { var role: Role; var text: String; var images: [ProcessedImage] }  // images 非空 → 多模态
func stream(_ messages: [ChatMessage], config: LLMConfig) -> AsyncThrowingStream<StreamEvent, Error>
enum StreamEvent { case reasoningDelta(String); case contentDelta(String); case done }
```

- 请求体：`{model, messages, stream:true, temperature}`；多模态消息的 content 为数组 `[{type:"text",text}, {type:"image_url",image_url:{url:"data:image/jpeg;base64,…"}}]`（OpenAI 兼容通行格式）。
- 传输：`URLSession.bytes(for:)` 逐行读，`SSEParser` 处理 `data:` 前缀、`[DONE]`、`choices[0].delta.content` 与 `delta.reasoning_content`（M3 混合推理：reasoning 流驱动骨架屏内的思考尾部预览，见下方「思考流展示」）。
- 超时：**三层**——①网络层 `timeoutIntervalForRequest`（20s）管「连接死」；②流外计时器 `VisibleIdleMonitor`（与流消费 `async let` 竞速）两级：**20s 无任何 delta**（连思考都没有，流假活/SSE 空转）→「模型响应超时」，**90s 有思考流但零正文**（思考死循环）→「模型思考时间过长」。**计时必须在流外**——写进 `for try await` 循环体只在有事件时才被检查，流零事件时守卫形同虚设、卡片永远停在 loading（实机验收实证）；睡眠须切片（≤0.25s）以免快速失败要等计时器自然醒才上卡。
- 思考流展示（2026-09-30）：reasoning delta 经 `InlineThinkFilter` 剥出后**不再丢弃**——`CardState.reasoningText` 节流（0.2s）累加，骨架屏内 `ReasoningPreview` 以固定高 ~3 行尾部滚动区 + 「思考中 · Ns」秒表实时展示；思考即进展，重置「无事件」计时但不重置「纯思考」计时（否则死循环永不超时）。正文到达即随骨架屏收起；思考文本**不入缓存不入历史**（回放卡无此区）；预览文本封顶 4000 字符（只需尾部）。旧口径「reasoning 不计、20s 无正文即超时」已废止——它与混合推理模型的长思考（图上点词实测 4–20s+）直接冲突，是密集页误杀超时的根因。
- 重试：仅对 429/5xx 自动重试 2 次（1s/3s 指数退避），流已产出内容后不重试（避免重复渲染）。
- 错误域：`noAPIKey / network(URLError) / http(status, body) / parse / timeout / cancelled`。
- Provider 预设（`Core/ProviderPresets.swift`，代码内常量而非资源文件）：MiniMax（区域单选：国内 `https://api.minimax.chat` / 国际 `https://api.minimaxi.com`，chat 路径与默认模型 MiniMax-M3 的准确取值**实现期校准**——以 MiniMax 官方 API 文档为准回填）；OpenAI / DeepSeek / 智谱 GLM / Kimi / 自定义（任意 baseURL+path+model）。预设只填默认值，用户可改。

### 4.3 PromptLibrary（全文；版本号按 kind 分档，见 `version(for:)`）

输出约定：全部 Markdown。**取数契约**——①查询对象原文（原词/原句）取自输入侧；②来自模型输出的可交互内容（截图「识别内容」、例句、句中难词、难词表词条）按**固定分节标记**提取：模板规定的粗体节名（**识别内容**/**例句**/**句中难词**/**难词表**）即提取锚点，渲染层把流式输出按节切成类型化块（朗读/复制/词条点击交互挂在块上），不做自由 Markdown 事后正则解析（分节提取器有独立测试，§10）。

**词（word）**
```
你是 Gloss——专业英文词典。解释下面的英文单词或短语，中文回答，Markdown，严格按此结构：
## {原词}
/{美式音标}/ /{英式音标}/
**语境义**：{结合"语境"的准确中文含义；无语境则写"（通用）"并给最常用义}
**词性与释义**
1. {词性}. {释义}
**高频搭配**
- {搭配} — {中文}
**例句**
1. {英文例句}（{中文翻译}）
**辨析**：{易混词/词源/使用注意，≤3 句；无则省略本节}
---
查询：{selection}
语境：{context 或 "无"}
```

**句（sentence）**
```
你是 Gloss——英文长难句解析助手。中文回答，Markdown，严格按此结构：
**翻译**
{忠实流畅的中文翻译；有歧义处附（直译：…）}
**结构拆解**
- 主干：{…}
- {修饰/从句}：{…}——{为什么这么理解}
**难点**：{习语/倒装/指代/省略等 1–3 条}
**句中难词**
| 词/短语 | 音标 | 文中义 |
|---|---|---|
{2–3 行，按难度排序}
---
句子：{selection}
语境：{context 或 "无"}
```

**段（paragraph）**
```
你是 Gloss——英文段落翻译助手。中文回答，Markdown，严格按此结构：
**译文**
{逐句对应翻译，保持段落结构}
**难词表**
| 词/短语 | 音标 | 文中义 | 原文例句 |
|---|---|---|---|
{3–6 行，按对理解的重要性排序；原文例句取自输入原文，不新造}
---
段落：{selection}
```

**读图（screenshotExplain）**
```
你是 Gloss。解读这张 Mac 截图中的内容（可能是文本、图表、界面或混合）。中文回答，Markdown，严格按此结构：
**识别内容**
{忠实转写图中全部可读英文文本，保留原有结构；无文本则描述画面}
**翻译与解释**
{中文翻译；若含图表/界面，先说明它展示什么，再解释关键信息}
**要点**
- {2–4 条：生词、术语、值得注意的信息}
**难词表**
| 词/短语 | 音标 | 图中义 | 图中原文例句 |
|---|---|---|---|
| {3–6 行，按对理解的重要性排序；图中原文例句须与**识别内容**节的转写逐字一致，不新造不改写（防污染传入 word 查询的语境）；例句内含竖线 `\|` 时以 `/` 替代（表格按朴素 `\|` 切分，防单元格错位）；无值得深挖的英文词则整节省略}
```

**图上点词（screenshotWordAt）**
```
你是 Gloss。用户在截图中点击了坐标（{x}%，{y}%）附近，想查那里的英文单词/短语。
定位最接近点击处的英文词，按"词"模板结构输出（## 词/音标 → 语境义取它在本图语境中的含义 → 释义 → 搭配 → 例句 → 辨析）。
若点击处附近没有英文单词：明确说明，并列出图中主要英文词供选择。
若该位置附近存在多个候选词且无法确定：不要猜测，列出 2–4 个候选并请用户选择。
```

**精读（article，M1 文本模式）**：输入按 ~600 词分批。批次模板 = 段模板 + 追加「**本批要点**：2–3 条」与「**本批术语**（若有）：术语/领域/通俗解释」；批次失败：重试尽后标记该批失败并继续后续批次（已成功批可读，失败批可单独重试，product §9）。全部批次完成后发**聚合请求**，入参 = `{逐批要点 + 逐批难词表 + 逐批术语表}`（禁止只喂要点——入参覆盖不了的输出只能靠编造）→ 输出：逻辑解读（主线/论证结构/关键转折/结论/背景）+ 汇总生词表（逐批难词表**去重排序**取 top10–20，例句沿用批内条目不新造）+ 汇总术语表（逐批合并去重）。批次与聚合模板均要求：译文专业术语首次出现处保留英文括注。〔M2 的 pdfPage 模板 = 读图模板 + 文本层参考 + 分 Tab 输出，实现期定稿，缓存键口径一并收口（§4.9）。〕

### 4.4 TTSEngine

`speak(_ text: String, accent: US/UK, rateMultiplier: 0.5–1.5)`；实现：`AVSpeechUtterance`（`utterance.rate = AVSpeechUtteranceDefaultSpeechRate × rateMultiplier`，并钳制到系统合法域 [minRate, maxRate]——倍率不直传 rate）+ `AVSpeechSynthesisVoice(identifier:)`，音色偏好序：用户设置 > Siri/Ava 系 premium（`com.apple.ttsbundle.*premium`/Siri 前缀探测）> `en-US/en-GB` 默认；打断策略：新 speak 先 `stopSpeaking`；浮窗关闭即停。M3 接 MiniMax 在线 TTS（同接口增加 provider 分支）。

### 4.5 PanelController

`NSPanel(contentRect:, styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView], backing:, defer:)`；`isFloatingPanel=true`；`collectionBehavior=[.canJoinAllSpaces, .fullScreenAuxiliary]`；`becomesKeyOnlyIfNeeded=true`；内容 = NSHostingView(ResultPanelView)。定位算法按 product-design §4.1（选区 bounds 优先，翻转+钳制）。ESC：面板可见期间以 Carbon `RegisterEventHotKey` 注册 kVK_Escape（消费式、随显隐装拆、无需辅助功能权限）；外部点击：`NSEvent.addGlobalMonitorForEvents`（leftMouseDown 且不在 panel frame 内 → close，鼠标事件无需信任，同样随显隐装拆）。**local monitor 排除图片窗**：图内点击是"连续点词"不是"点浮窗外关窗"，命中 `WindowManager.isImageWindow(ev.window)` 直接放行，否则每次图内点击都会藏一次面板（面板闪隐 + ESC 热键拆装 + 旧流式卡被打成已取消）。定位二次校正：面板先按鼠标位即时出现，AX 选区 bounds 迟到时（≤150ms）无动画校正一次。Markdown 渲染禁用链接点击（模型输出不可信，OpenURL 置空）。ESC 热键若注册失败（极端占用）则降级为仅外部点击关闭并在设置页提示。

### 4.6 Services 注册（Info.plist 键 + 运行时）

```xml
<key>NSServices</key>
<array><dict>
  <key>NSMenuItem</key><dict><key>default</key><string>Gloss 查词</string></dict>
  <key>NSMessage</key><string>doQueryService</string>
  <key>NSPortName</key><string>Gloss</string>          <!-- 非沙盒=可执行名；不生效则按 Apple 文档校准（实现期校准） -->
  <key>NSSendTypes</key><array><string>NSTextType</string></array>
  <key>NSRequiredContext</key><dict><key>NSTextType</key><string>Plain text</string></dict>
</dict></array>
```
启动时 `NSApp.servicesProvider = ServicesBridge()` + `NSUpdateDynamicServices()`。若服务项不出现：引导用户在 系统设置→键盘→键盘快捷键→服务 中确认 Gloss 查词已勾选（product-design §9 状态表末行）。

### 4.7 HotkeyManager

Carbon `RegisterEventHotKey`（⌥D=`kVK_ANSI_D`+optionKey，⌥S=`kVK_ANSI_S`+optionKey）；注册失败=占用冲突→SettingsStore 置无效并通知 UI（product-design §5）；设置页录制控件 = 临时捕获下一个 `CGEventTap`（listen only）组合键。Carbon API 老但无更好原生替代，封装隔离在单文件。

### 4.8 ScreenshotManager

`Process(/usr/sbin/screencapture, ["-i","-c"])` 同步等待退出码；0 → 读 `NSPasteboard.general` 的 image（`NSImage(pasteboard:)`）；屏幕录制权限：按 TCC 常规归属需要授予本 App——**实现期校准**（若子进程路径实测豁免则移除引导）；取消（退出码或剪贴板无新图判定，语义以 §13-C2 实测为准）静默返回。

### 4.9 CacheStore / KeychainStore / SettingsStore / DataStore

- 缓存键 = `sha256(normalizedInput | kind | kindParams | model | version(for: kind) [| ctx:<context 摘要>])`；版本号**按 kind 分档**（`PromptLibrary.version(for:)`：截图整图与图上点词 = `m2`，词/句/段/长文/PDF = `m1`）——改某类 prompt 只失效该类缓存，不牵连其他。`ctx:` 段**仅 word 类且 context 非空时**追加（`cacheNormalized` 归一后取 sha 前 8 位），防同词跨语境命中错结果；text 输入归一化 = trim + 连续空白折叠为单空格（不改大小写——此规则即 §10 键稳定性测试的判定基准）；image 输入的 normalizedInput = 图像字节 sha256；screenshotWordAt 的 kindParams = 量化到 1% 网格的坐标（防止同图不同点词互相命中错误缓存，也防浮点抖动永不命中）；pdfPage 的缓存键口径（§3.4.3 的"文档 sha256+页码"与本节 image 口径）随 M2 pdfPage 模板定稿一并收口。命中返回完整 Markdown。容量策略：LRU 上限 2000 条或 50MB，启动时清理（依赖 §5 的 lastAccessedAt 字段）。
- KeychainStore：`kSecClassGenericPassword`，service=`com.wuyujun.gloss.llm`，account=presetID+slot；设置页粘贴即写，任何日志/诊断输出对 key 脱敏（只显前 4 后 4）。
- SettingsStore：UserDefaults 存非敏感项（触发开关/快捷键/音色/语速/多套配置元数据），`LLMConfig` 数组 Codable 序列化存 UserDefaults，apiKey 永不入 UserDefaults。
- DataStore：SwiftData `ModelContainer`（主上下文 + 后台写入上下文）。

### 4.10 PermissionCenter

- 辅助功能：`AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: false])` 自检 + 引导窗（含"打开系统设置锚点" `AXPrivacy` / `Applications`）+「重新检测」。
- 屏幕录制：无直接 API——用 `CGDisplayStream` 短时试探（能开帧=已授权）判定；未授权仅禁用通道 C 并引导。**实现期校准**。
- 权限失效处理：每次启动自检两权限，状态写入菜单栏（`PermissionCenter.summaryLine()` 文本行；图标红点未实现）。**注意**：现行 Apple Development 证书（§11）跨构建稳定，重签不再导致 TCC 授权丢失——早期"自签重签后权限失效"的前提已不成立。

### 4.11 UpdaterCenter（自动更新，v0.1.3）

- **单例约束**：菜单栏「检查更新…」与设置页「高级 → 检查更新…」共用同一个 `SPUStandardUpdaterController`（`UpdaterCenter.controller`）。多实例会让各自的检查周期与驱动状态分叉，故控制器必须全局唯一。首次访问发生在 `setupStatusItem`（启动链内），满足 Sparkle「app 基本初始化后再启动 updater」的要求。
- **两个检查入口**：菜单项 target 指向控制器本身（`#selector(SPUStandardUpdaterController.checkForUpdates(_:))`，借其自带菜单校验实现不可用时自动置灰）；设置页按钮走 `UpdaterCenter.checkForUpdates()`。
- **`checkForUpdates` 在 updater 异步启动完成前是静默 no-op**（`SPUUpdater` 校验 `_startedUpdater` 后直接 return，既不检查也不报错）——验收钩子 `-check-updates` 因此轮询 `canCheckForUpdates` 就绪后再触发（`checkWhenReady`，上限 30s），固定延迟在慢网络下会静默失效。
- **状态回显**：Sparkle 的 `automaticallyChecksForUpdates` / `lastUpdateCheckDate` 是 ObjC 属性，SwiftUI 不自动观察 KVO；设置页须在 `onAppear` 与低频定时器中主动同步，否则开关与时间戳会停留在窗口创建那一刻的旧值（实测：权限询问框点了「自动检查」，UI 仍显示未勾选）。
- **Info.plist**：`SUFeedURL` = `$(SPARKLE_FEED_URL)`（仅 Release 配置注入，Debug 不设 → 更新功能自然禁用，避免开发中误把 Debug 实例替换成 Release 包）、`SUPublicEDKey`（EdDSA 公钥）。刻意不设 `SUAllowsAutomaticUpdates`（Sparkle 缺省跟随自动检查开关，官方亦不建议显式设置）。
- **更新通道**：静态 appcast `releases/latest/download/appcast.xml`（GitHub 固定 302 到最新 Release 资产，零自建后端；走静态文件而非 REST API，无未认证限流）。已知限制：国内访问 GitHub 不稳，检查失败静默、菜单栏另设「前往下载页…」兜底；GitHub `/releases/latest/` 重定向有 2~3 分钟 CDN 传播延迟，传播期内旧版客户端会看到"已是最新"。

### 4.12 图片放大窗（WindowManager.showImage / ImageZoomWindow）

- **定位**：密集截图的正文在 160pt 缩略图里物理不可读（13px 渲染后 ≈2.1px），点击即盲指。缩略图按原图自然宽度与卡片实测可用宽分流（`ImageGeometry.needsZoomWindow(imageWidth:cardWidth:)`，卡宽取 `geo.size.width`；当前面板内容宽被 `.frame(width: 400)` 钉死故实测恒为 376）：≤ 卡片可用宽就地点词（保留现状），宽于它则开独立放大窗。历史回放卡只有 ≤200px 缩略图 → 恒不就地点大窗（放大只会糊）。
- **窗口**：复用 `WindowManager.makeWindow(title:size:)` 工厂与精读窗同一套模式（`.titled, .closable, .miniaturizable, .resizable` → 自带最大化/拖拽调窗）；打开走 `activate()` + `makeKeyAndOrderFront`；默认 1000×700；每次装全新 `NSHostingView`（同 `showReader`：复用 hosting view 换 rootView 不触发 `onAppear`）。`windowWillClose` 补 `imageWindow` 分支，**只置空引用**——窗内无可取消任务（点词请求归 `SessionCoordinator`），勿照抄 reader 的 VM cancel。
- **fit 满窗是坐标换算的前提（勿破坏）**：图片恒 `scaledToFit` 铺满内容区，**不加 ScrollView / magnification / 缩放手势**；放大手段就是拉大窗口。一旦引入滚动或缩放，`ImageGeometry.normalizedPoint` 的公式必须叠加滚动偏移与缩放因子。
- **坐标换算两段契约**：①`ImageGeometry.normalizedPoint(viewSize:imagePixelSize:click:)`（视图局部 y 向下，落在 fit 后的空白处返回 nil）出 0…1 归一化点，与缩略图共用同一纯函数；②`clickRect` 必须是 **Cocoa 全局屏幕坐标**（y 向上、多屏各自 frame，`PanelController.positionBySelection` 的既有契约），换算路径钉死为 `NSView.convert(_:to: nil)` → `NSWindow.convertToScreen(_)`，由系统按所在屏换算——**禁止手搓 `NSScreen.main.frame.height - y` 单屏翻转公式**（仅主屏正上方布局时偶然成立，多屏即错）。故图片显示区用 `NSViewRepresentable` 承载真实 `NSView`，准星与坐标读数在 SwiftUI 侧叠加（`allowsHitTesting(false)`，不参与布局也不吃事件）。
- **生命周期绑定栈根会话**：`SessionCoordinator` 的栈根赋值收口在唯一私有入口 `setRoot(card:)`，置新根前 `closeImageWindow()`（orderOut + 置空）——否则旧图点词卡会压在新根上（跨会话混栈），换根为文本卡后窗内点击又是静默死路。栈顶替换（D-e）：栈首仍是截图卡时，第 2 次点击先 `removeLast()` 再 push，深度仍 ≤2，「← 返回整图」语义不变。
- **结果面板去向**：点击源在另一个窗口，`pushWordAtQuery` 追加后**条件式**置前（`if !PanelController.shared.isVisible { show(near: clickRect) }`）——就地路径面板必可见故不重定位（现状行为完全保留）；图片窗路径面板被藏时复活并就近浮出。`show(near:)` 内部 `orderFrontRegardless()` 不抢焦点，用户可点回图片窗继续点下一个词。
- **ESC 两级**：面板可见期间 ESC 已被 Carbon 热键消费为「藏面板」，不会到达图片窗；面板隐藏后再按 ESC 才关图片窗（`ImageZoomView` 的 NSView 接管 first responder + `keyDown`）。

## 5. 数据模型（SwiftData，schema v1）

```swift
@Model final class QueryRecord {
    @Attribute(.unique) var id: UUID
    var inputText: String?          // image 时为 nil
    var inputKind: String           // QueryKind.rawValue
    var kindParamsJSON: String?     // 带参 kind 的参数（如已量化的点词坐标）
    var origin: String              // InputOrigin.rawValue
    var thumbnail: Data?            // 截图查询存 ≤200px JPEG 缩略
    var responseMarkdown: String
    var model: String
    var createdAt: Date
    var isStarred: Bool             // M3 生词本前身
}
@Model final class ResponseCache {
    @Attribute(.unique) var key: String   // sha256 复合键
    var response: String
    var createdAt: Date
    var lastAccessedAt: Date             // LRU 淘汰依据，命中时更新
}
// M3 预留：WordEntry(word, phoneticUS, phoneticUK, meaning, sourceContext, createdAt, reviewCount)
```
迁移策略：schema 版本化（SwiftData lightweight migration），v1 起始。

## 6. 多模态与图片管线（D5/D6 落地）

### 6.1 ImagePipeline

`normalize(_ image: NSImage, maxEdge: Int) -> ProcessedImage{jpeg: Data, sha256: String, pixelSize: CGSize}`——等比缩放（`NSBitmapImageRep` 重采样，高质量）至长边 ≤ maxEdge，JPEG 质量 0.85。调用参数：截图 1568 / PDF 页 2200（PDF 文字密度高需更高分辨率）。两者同一管线不同参数，改参数不改机制。

### 6.2 多模态消息组装

ChatMessage.images 非空时 content 组数组（text part 永远在前——先指令后图片）。点词查询携带原图（非缩略图）+ 归一化坐标字符串注入 Prompt。图片不入库：QueryRecord 只存小缩略，缓存键用 sha256。

## 7. 会话与并发（SessionCoordinator）

`QuerySession { id, input, kind, state: streaming/done/error/cancelled, content: String, usedCache: Bool }`。规则：新查询 → cancel 旧 session 的 URLSessionTask 与 TTS；防抖 150ms（同文本重复触发合并）；所有 UI 更新经主线程发布（实现为 `ObservableObject` + `@Published`，无独立 AppState 单例）。长任务（全文精读）在独立 window 的 session 中运行，不与浮窗互斥。**面板内导航栈**：句/段/图卡内的子查询（难词词条、图上点词）入栈产生新卡，「← 返回」弹栈——切卡只换面板内容，不重触发捕获层；栈深 ≤2。

## 8. 性能预算

| 指标 | 预算 |
|---|---|
| 冷启动→菜单栏图标 | <1s |
| ⌥D→浮窗出现 | <0.2s |
| ⌥S 松手→浮窗出现 | <0.3s |
| 浮窗→首个 content 字符（p50，直连） | <1.5s；读图 <3s；缓存命中渲染 <0.1s |
| 图片 normalize（2x retina 区域） | <0.2s |
| 常驻内存 | <100MB（不含模型，纯客户端） |

## 9. 安全与隐私

- API Key 仅存 Keychain；诊断/日志脱敏。
- 查询内容只发往用户配置的服务商；开启"第三方词典首屏"（默认关）时单词另发 dictionaryapi.dev（设置页明示）。
- 无遥测、无崩溃上报（自签自用；问题靠本地日志开关排障）。

## 10. 测试策略

**单元（SelfCheck，无 XCTest 目标）**
工程内不存在 `GlossTests` target：单元自检以 `SelfCheck/main.swift` 与纯逻辑文件联合编译运行替代（三阶段评审已声明该偏差）。编译命令（文件清单需显式给出，勿通配 `Core/`——`UpdaterCenter.swift` 依赖 Sparkle 不属纯逻辑）：

```bash
swiftc -O -o /tmp/selfcheck \
  Gloss/Core/QueryRouter.swift Gloss/Core/SSEParser.swift Gloss/Core/SectionExtractor.swift \
  Gloss/Core/PromptLibrary.swift Gloss/Core/LLMClient.swift Gloss/Core/CacheStore.swift \
  Gloss/Core/ImagePipeline.swift Gloss/Core/ImageGeometry.swift Gloss/Core/GlossLog.swift \
  SelfCheck/main.swift && /tmp/selfcheck
```

当前 **88 项断言全绿**（2026-09-30 实测；两级超时重构合并了旧守卫断言）。覆盖：QueryRouter 表驱动（≤3 词/连字符词/带撇词/句末标点/60 词边界/400 词边界/CJK 占比/空输入/纯数字）；SSEParser fixture 流（普通 delta、reasoning_content、`[DONE]`、chunk 中途截断的 `data:` 行拼接、多 choice 取 [0]）；分节提取器边界（节缺失/空节/流式半节/截图难词表与旧缓存无表兼容）；PromptLibrary 模板渲染（含截图难词表与点词多候选约束）；CacheStore 键稳定性（分 kind 版本、context 入键与归一、非 word 类不入键）与 LRU；ImageGeometry 归一化坐标换算（中心点 + letterbox 拒绝）；ImagePipeline 归一化字节级确定性；VisibleIdleMonitor 流外两级空闲超时（零事件 .noEvent / 思考死循环 .thinkingOnly / finish 切片打断 / 正文与思考的重置语义分野）。
未覆盖（需手工/集成验证）：LLMClient 的 HTTP 行为（200 流式/401/429 重试/超时取消）尚无 URLProtocol mock；AppKit 层的栈顶替换（D-e）、换根关窗（D-f）、monitor 排除、条件式置前由实机验收覆盖（方案 §10 验收 5/6/8/10）；更新链路以「本地 feed E2E + 真实发布包升级演示」验证（见 §4.11）。

**手工验收矩阵（M1 发布前）**：通道（服务/⌥D/⌥S）× 目标 App（Safari、Chrome、微信、Preview 文本型 PDF、Terminal、VS Code）× 预期（取词成功或降级提示正确）；权限三态（未授权/授权后/重签后失效）；ESC/外点/固定；缓存徽标与重查。

## 11. 构建与签名（D4/D10，2026-09-29 校准）

1. **直接打开工程运行**：`open Gloss.xcodeproj`（Xcode 16+，Cmd+R）。工程已提交且签名配置就绪——`CODE_SIGN_STYLE=Manual` + `CODE_SIGN_IDENTITY="Apple Development: yujundqq@icloud.com (2ZB8Z6VPSS)"`（Team ID = `XB7CMSZH3F`，注意 CN 括号内的 `2ZB8Z6VPSS` 是 UID 而非 Team ID）；App Sandbox **不勾选**。
2. **Info.plist 键**：`LSUIElement=YES`；`NSServices`（§4.6）；`LSMinimumSystemVersion=14.0`；`SUFeedURL`/`SUPublicEDKey`（§4.11）；版本号经 `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)` 注入，**不在 plist 里写字面量**。
3. **SPM 依赖**：`Sparkle`（upToNextMajor 2.10.0），版本由 `project.xcworkspace/xcshareddata/swiftpm/Package.resolved` 锁定并入库，保证可复现构建。
4. **规范构建/发布**：`scripts/release.sh`（Release 构建 → **通用二进制校验** → 证书链硬校验 → Sparkle 配置防呆 → ditto 打 zip → `sign_update` EdDSA 签名 → 生成 `dist/appcast.xml`）；`scripts/release.sh --publish` 追加创建 GitHub Release 并上传 zip + appcast。发版只需在 pbxproj 同步递增两个版本旋钮。产物：`build/Gloss.app`（本机安装）、`dist/Gloss-vX.Y.Z.zip`、`dist/appcast.xml`。
5. **通用二进制（arm64 + x86_64，D10）**：Release 产出同时含两种架构的 fat binary，Apple Silicon 与 Intel 共用同一个 zip（1.5MB → 2.0MB），Sparkle 更新链路不区分架构、无需 per-arch variants。三个必守约束——
   - **必须带 `-destination 'generic/platform=macOS'`**：不带 destination 时 xcodebuild 走「My Mac」目标只构建本机架构，工程里 `ARCHS=arm64 x86_64` 会被目标约束**静默覆盖**（v0.1.0~v0.1.6 七个版本全是 arm64 单架构，发布流程零报错）；脚本同时显式传 `ARCHS`/`ONLY_ACTIVE_ARCH=NO` 兜底。
   - **出包前 lipo 闸门**（`release.sh` 内「发布闸 0」，全部 fail-closed）：遍历 bundle 内**每一个** Mach-O（`find -type f -perm -u+x` + `lipo -archs` 过滤），逐一验双架构齐全 + 各切片 `minos` **不得高于** `LSMinimumSystemVersion`（高于 = 装得上却起不来；低于是正常的，如 Sparkle 各组件 minos=12.0，不能拦）。**必须遍历而非只验主二进制**：Sparkle 的 `Updater.app` / `Autoupdate` / `Downloader.xpc` / `Installer.xpc` 才是用户机器上真正执行更新动作的进程，Intel 上缺 x86_64 切片会表现为「App 能启动但更新静默失败」，而这些进程不在启动路径上，本地任何环节都不报错。当前 6 个 Mach-O，另有「识别数 < 2 即视为扫描失效」的兜底，防遍历静默失效。另对 `Sparkle.framework` 本体显式点名验存在——它整个缺失时遍历扫不到，而 `codesign -v --deep` 对不存在的嵌套代码同样不报错。
   - **pbxproj 侧**：Release 配置显式写 `ARCHS = "arm64 x86_64"` + `ONLY_ACTIVE_ARCH = NO`；Debug 保留 `ONLY_ACTIVE_ARCH = YES`（本机快迭代）。
   - **下限 14.0 不动**：缓存层用 SwiftData（`GlossModels.swift`/`DataStore.swift`，macOS 14+），降到 13 需重写存储层。故 Intel 覆盖面 = Apple 官方 macOS 14 Sonoma 支持清单：MacBook Pro 2018 起（15″ 2018、13″ 2018 四雷雳口）、MacBook Air 2018 起、Mac mini 2018、**iMac 2019 起**（无 2018 款 iMac）、**iMac Pro 2017**、Mac Pro 2019；停在 Ventura 13 及更早的机型（2017 款 MacBook Pro / MacBook / iMac）不支持。
   - **代码零改动**：全量 import 无架构相关框架（无 Metal/CoreML/SIMD/Accelerate），无 `#if arch(...)`/`uname`，Carbon 热键与 AVFoundation TTS 均架构中立；x86_64 切片经 Rosetta 实测可正常启动。
6. **脚本编码坑（2026-09-29 实证）**：macOS 默认 UTF-8 locale 下，bash 会把紧跟 `$VAR` 的**全角标点**并入变量名，`"$APP_ARCHS（…"` 解析成 `APP_ARCHS\xef…`，在 `set -u` 下直接以 unbound variable 中止脚本。凡 `$VAR` 后紧跟全角标点，一律写 `${VAR}`。已修 `release.sh` 三处（新增的架构回显 + `--publish` 的 build 号闸门错误/通过回显；后两处一旦走到就会中断发布）。
7. **证书有效期与权限**：Apple Development 证书有效期至 **2027-09-26**（年度续签，非早期免费 Team 的 7 天 profile）。实证：同一证书跨多次重建稳定，**TCC（辅助功能/屏幕录制）授权不随重建丢失**——更新包沿用同一证书签名，升级后授权保持。实证补充：universal 与 arm64 单架构的 **designated requirement 字符串逐字一致**（`codesign -dr -`），故 arm64 老用户升到通用二进制版后权限授权同样保持。更换 Apple 证书不影响 Sparkle 更新链（锚定的是 EdDSA 密钥对）。
8. **未公证的既有负担**：未走 Apple 公证，Gatekeeper 首次拦截为预期行为，下载者需在「系统设置 → 隐私与安全性 → 仍要打开」放行一次。
9. 首次运行后右键服务若未出现：注销重登或确认服务已勾选（§4.6）。

## 12. 里程碑任务拆解

**M1（=D7 合并：划词+截图+文本精读）**

| 块 | 内容 | 验收标准 |
|---|---|---|
| T1 骨架与配置 | 工程/菜单栏/LSUIElement/设置窗四页签/Keychain/Provider 预设/测试连接 | 冷启动 <1s 图标可见；Key 写入钥匙串可查；测试连接显示延迟；无 Key 时浮窗提示条「未配置 API Key · 去设置」（product-design §9/S1） |
| T2 服务通道+面板+LLM | ServicesBridge/PanelController/SSE 多模态客户端/单词卡 | Safari 选词右键服务→卡片流式出全字段（🔊 朗读按钮 T3 生效）；ESC/外点/固定可用；401/429 文案正确 |
| T3 热键取词+句段卡+TTS | HotkeyManager/AX+⌘C/PermissionCenter/句子卡/段落卡/TTSEngine | 验收矩阵（§10）六 App 取词通过；美英朗读切换；AX 失败自动兜底无感 |
| T4 截图通道 | ScreenshotManager/ImagePipeline/截图卡/读图/图上点词 | ⌥S→读图解释全链路；ESC 取消静默；点词定位正确（抽 5 词）；原剪贴板恢复 |
| T5 精读+打磨 | 精读窗文本模式/分批聚合/缓存/历史窗/首启向导/开机自启(SMAppService)/错误态巡检 | ≥400 词进精读窗分批不截断；历史回放与重查；断网/超时/429 巡检全过 |

**M2（PDF 精读）**：PDFImporter/ReaderWindow PDF 模式/页渲染 2200px/页与全文解析（含取消与成本确认）/页缓存/菜单栏图标拖放承接（NSStatusItem 自定义视图挂 NSDraggingDestination）/PDFView 划词桥接/pdfPage 四 Tab 输出模板定稿（§4.3 遗留项，开工前完成）。验收：文本型与扫描型 PDF 各一册端到端；页缓存翻页秒显；全文进度、取消、聚合逻辑解读正确。

**M3（增强）**：生词本 CRUD+CSV/Anki 导出；MiniMax 在线 TTS；选区跟随（AX observer 节流）；多 Provider 并行对照；DictionaryClient 第三方词典首屏（product-design §6 高级，默认关）；按查询类型分用不同模型配置评估；中→英反向查询评估结论落 DESIGN.md。

## 13. 实现期待校准清单（唯一登记处，校准后回填）

| # | 项 | 风险 | 校准动作 |
|---|---|---|---|
| C1 | MiniMax chat 路径/默认模型 ID/图像输入参数 | 文档演进 | **已校准（2026-09-26 真实 Key 实测）**：OpenAI 兼容端点 `https://api.minimaxi.com/v1/chat/completions` + 模型 `MiniMax-M3` 直接可用（HTTP 200，国际站 Key 与 Anthropic 兼容端点同域同 Key）；流式无 `reasoning_content` 字段——思考内联于 content 的 `<think>…</think>`，已由 `InlineThinkFilter` 状态机跨 chunk 剥离（自检 think.* 4 项）；多模态 image_url(dataURL) 实测可用。已回填 ProviderPresets（minimax 预设 baseURL 待更新为 api.minimaxi.com） |
| C2 | screencapture 子进程是否需本 App 屏幕录制权限；退出码语义（成功/取消/无图——man 未文档化，社区口径与"取消=1"不一致） | TCC 归属与退出码均未官方文档化 | T4 首次实测权限弹窗行为与退出码×三形态（成功/取消/无图），回填 §3.3/§4.8 与 product-design §5 |
| C3 | NSPortName 取值与服务出现时机；NSSendTypes 用 NSTextType 还是 NSStringPboardType | Services 老机制与 UTI 标识演进 | **已校准（2026-09-26 实测）**：NSSendTypes 用 `NSStringPboardType + public.utf8-plain-text`、NSPortName=可执行名可用（pbs dump 条目正常）；**关键坑=第三方服务在系统服务列表中默认禁用**——注册成功后仍不会出现在右键服务菜单，需在 系统设置→键盘→键盘快捷键→服务快捷键→文本 中勾选启用（已实测勾选后 TextEdit 真实服务调用端到端打通）。M2 考虑：首启向导/设置页加"服务未启用"检测与一键引导（pbs prefs 无编程勾选 API，只能引导或 Automation 打开该页） |
| C4 | M3 reasoning_content 字段名与思考时长 | 模型行为 | T1 实测流结构，回填 §4.2 超时预算 |
