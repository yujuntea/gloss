# Gloss 技术实现文档

> 版本：V1.0（2026-09-26）。权威范围见 [DESIGN.md](DESIGN.md) 文档索引；交互规格以 [product-design.md](product-design.md) 为准，本文不重复。
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
| 第三方依赖 | 仅 `swift-markdown-ui`（SPM） | 流式 Markdown 渲染；其余全用系统框架（AVFoundation/PDFKit/Carbon） |
| 沙盒 | 关闭（D4 自签） | Services 的 NSPortName、⌘C 兜底、子进程截图在非沙盒下实现最简 |
| App 形态 | LSUIElement=YES（无 Dock 图标） | 菜单栏常驻工具型 App 惯例；设置/精读窗用 NSApp.activate 拉起 |

## 2. 工程结构

```
gloss/
├── Gloss.xcodeproj                # 提交工程文件（不使用 xcodegen）
├── docs/                          # 本文档集
├── Gloss/
│   ├── GlossApp.swift             # @main；AppDelegate 注入（Services/生命周期）
│   ├── App/
│   │   ├── AppDelegate.swift      # servicesProvider 注册、启动自检
│   │   ├── AppState.swift         # @Observable 单例：会话、配置、权限快照
│   │   ├── Onboarding/            # 4 步向导 + 权限引导视图
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
│   │   ├── PromptLibrary.swift    # 5 套模板 + PROMPT_VERSION
│   │   ├── ImagePipeline.swift    # 缩放/JPEG 压缩（截图 1568 / PDF 页 2200 长边上限）
│   │   ├── TTSEngine.swift        # AVSpeechSynthesizer 封装
│   │   ├── CacheStore.swift       # 响应缓存
│   │   ├── KeychainStore.swift    # API Key 存取
│   │   └── SettingsStore.swift    # UserDefaults + LLMConfig 管理
│   ├── UI/
│   │   ├── PanelController.swift  # NSPanel 生命周期/定位/事件监听
│   │   ├── ResultPanelView.swift  # 浮窗根视图（顶栏/卡片区/操作条）
│   │   ├── Cards/                 # WordCard/SentenceCard/ParagraphCard/ScreenshotCard
│   │   ├── ReaderWindow.swift     # 精读窗（文本模式 M1 / PDF 模式 M2）
│   │   ├── SettingsWindow.swift   # 四页签
│   │   └── HistoryWindow.swift
│   ├── Storage/
│   │   ├── GlossModels.swift      # SwiftData @Model
│   │   └── DataStore.swift        # ModelContainer/Context 管理
│   └── Resources/
│       └── ProviderPresets.json   # 内置厂商预设
├── GlossTests/                    # 单元测试（§10）
└── Info.plist                     # NSServices/LSUIElement 等键
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
4. 图上点词：缩略图 `onTapGesture` + `GeometryReader` 换算归一化坐标 (x%, y%) → 以原图 + 坐标重新请求（Prompt = 点词定位），复用同一面板切换为单词卡，卡顶加「返回整图」。

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
enum StreamEvent { case reasoningDelta(String); case contentDelta(String); case done(usage: Usage?) }
```

- 请求体：`{model, messages, stream:true, temperature}`；多模态消息的 content 为数组 `[{type:"text",text}, {type:"image_url",image_url:{url:"data:image/jpeg;base64,…"}}]`（OpenAI 兼容通行格式）。
- 传输：`URLSession.bytes(for:)` 逐行读，`SSEParser` 处理 `data:` 前缀、`[DONE]`、`choices[0].delta.content` 与 `delta.reasoning_content`（M3 混合推理：reasoning 流只驱动 UI「思考中…」指示，不渲染内容）。
- 超时：流式空闲（20s 无任何 delta）取消并抛 `timeout`；连接超时与流空闲共用 20s 口径（URLSession 单配置无法分离连接级 10s，原"连接 10s"设计经 K3 终审回填为本口径）。
- 重试：仅对 429/5xx 自动重试 2 次（1s/3s 指数退避），流已产出内容后不重试（避免重复渲染）。
- 错误域：`noAPIKey / network(URLError) / http(status, body) / parse / timeout / cancelled`。
- Provider 预设（`ProviderPresets.json`，内置随包）：MiniMax（区域单选：国内 `https://api.minimax.chat` / 国际 `https://api.minimaxi.com`，chat 路径与默认模型 MiniMax-M3 的准确取值**实现期校准**——以 MiniMax 官方 API 文档为准回填）；OpenAI / DeepSeek / 智谱 GLM / Kimi / 自定义（任意 baseURL+path+model）。预设只填默认值，用户可改。

### 4.3 PromptLibrary（全文，PROMPT_VERSION = "m1"）

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
**要点**：{2–4 条：生词、术语、值得注意的信息}
```

**图上点词（screenshotWordAt）**
```
你是 Gloss。用户在截图中点击了坐标（{x}%，{y}%）附近，想查那里的英文单词/短语。
定位最接近点击处的英文词，按"词"模板结构输出（## 词/音标 → 语境义取它在本图语境中的含义 → 释义 → 搭配 → 例句 → 辨析）。
若点击处附近没有英文单词：明确说明，并列出图中主要英文词供选择。
```

**精读（article，M1 文本模式）**：输入按 ~600 词分批。批次模板 = 段模板 + 追加「**本批要点**：2–3 条」与「**本批术语**（若有）：术语/领域/通俗解释」；批次失败：重试尽后标记该批失败并继续后续批次（已成功批可读，失败批可单独重试，product §9）。全部批次完成后发**聚合请求**，入参 = `{逐批要点 + 逐批难词表 + 逐批术语表}`（禁止只喂要点——入参覆盖不了的输出只能靠编造）→ 输出：逻辑解读（主线/论证结构/关键转折/结论/背景）+ 汇总生词表（逐批难词表**去重排序**取 top10–20，例句沿用批内条目不新造）+ 汇总术语表（逐批合并去重）。批次与聚合模板均要求：译文专业术语首次出现处保留英文括注。〔M2 的 pdfPage 模板 = 读图模板 + 文本层参考 + 分 Tab 输出，实现期定稿，缓存键口径一并收口（§4.9）。〕

### 4.4 TTSEngine

`speak(_ text: String, accent: US/UK, rateMultiplier: 0.5–1.5)`；实现：`AVSpeechUtterance`（`utterance.rate = AVSpeechUtteranceDefaultSpeechRate × rateMultiplier`，并钳制到系统合法域 [minRate, maxRate]——倍率不直传 rate）+ `AVSpeechSynthesisVoice(identifier:)`，音色偏好序：用户设置 > Siri/Ava 系 premium（`com.apple.ttsbundle.*premium`/Siri 前缀探测）> `en-US/en-GB` 默认；打断策略：新 speak 先 `stopSpeaking`；浮窗关闭即停。M3 接 MiniMax 在线 TTS（同接口增加 provider 分支）。

### 4.5 PanelController

`NSPanel(contentRect:, styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView], backing:, defer:)`；`isFloatingPanel=true`；`collectionBehavior=[.canJoinAllSpaces, .fullScreenAuxiliary]`；`becomesKeyOnlyIfNeeded=true`；内容 = NSHostingView(ResultPanelView)。定位算法按 product-design §4.1（选区 bounds 优先，翻转+钳制）。ESC：面板可见期间以 Carbon `RegisterEventHotKey` 注册 kVK_Escape（消费式、随显隐装拆、无需辅助功能权限）；外部点击：`NSEvent.addGlobalMonitorForEvents`（leftMouseDown 且不在 panel frame 内 → close，鼠标事件无需信任，同样随显隐装拆）。定位二次校正：面板先按鼠标位即时出现，AX 选区 bounds 迟到时（≤150ms）无动画校正一次。Markdown 渲染禁用链接点击（模型输出不可信，OpenURL 置空）。ESC 热键若注册失败（极端占用）则降级为仅外部点击关闭并在设置页提示。

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

- 缓存键 = `sha256(normalizedInput | kind | kindParams | model | PROMPT_VERSION)`；text 输入归一化 = trim + 连续空白折叠为单空格（不改大小写——此规则即 §10 键稳定性测试的判定基准）；image 输入的 normalizedInput = 图像字节 sha256；screenshotWordAt 的 kindParams = 量化到 1% 网格的坐标（防止同图不同点词互相命中错误缓存，也防浮点抖动永不命中）；pdfPage 的缓存键口径（§3.4.3 的"文档 sha256+页码"与本节 image 口径）随 M2 pdfPage 模板定稿一并收口。命中返回完整 Markdown。容量策略：LRU 上限 2000 条或 50MB，启动时清理（依赖 §5 的 lastAccessedAt 字段）。
- KeychainStore：`kSecClassGenericPassword`，service=`com.wuyujun.gloss.llm`，account=presetID+slot；设置页粘贴即写，任何日志/诊断输出对 key 脱敏（只显前 4 后 4）。
- SettingsStore：UserDefaults 存非敏感项（触发开关/快捷键/音色/语速/多套配置元数据），`LLMConfig` 数组 Codable 序列化存 UserDefaults，apiKey 永不入 UserDefaults。
- DataStore：SwiftData `ModelContainer`（主上下文 + 后台写入上下文）。

### 4.10 PermissionCenter

- 辅助功能：`AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: false])` 自检 + 引导窗（含"打开系统设置锚点" `AXPrivacy` / `Applications`）+「重新检测」。
- 屏幕录制：无直接 API——用 `CGDisplayStream` 短时试探（能开帧=已授权）判定；未授权仅禁用通道 C 并引导。**实现期校准**。
- 自签重签后 TCC 失效：每次启动自检两权限并在缺失且对应通道开启时菜单栏图标加红点提示。

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

`QuerySession { id, input, kind, state: streaming/done/error/cancelled, content: String, usedCache: Bool }`。规则：新查询 → cancel 旧 session 的 URLSessionTask 与 TTS；防抖 150ms（同文本重复触发合并）；所有 UI 更新经 @Observable AppState 主线程发布。长任务（全文精读）在独立 window 的 session 中运行，不与浮窗互斥。**面板内导航栈**：句/段/图卡内的子查询（难词词条、图上点词）入栈产生新卡，「← 返回」弹栈——切卡只换面板内容，不重触发捕获层；栈深 ≤2。

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

**单元（GlossTests）**
- QueryRouter：表驱动 ≥16 例（≤3 词/连字符词/带撇词/句末标点/60 词边界/400 词边界/CJK 占比/空输入/纯数字）；
- SSEParser：fixture 流（普通 delta、reasoning_content、`[DONE]`、chunk 中途截断的 `data:` 行拼接、多 choice 取 [0]）；
- PromptLibrary：模板渲染快照测试（变量注入与 PROMPT_VERSION 锚定）；分节提取器：按固定粗体节名切类型化块的边界测试（节缺失/空节/流式半节，对应 §4.3 取数契约）；
- CacheStore：键稳定性（同输入同键、改 prompt 版本换键）、LRU 清理；
- LLMClient：URLProtocol mock（200 流式、401、429→重试 2 次、超时取消）；
- ImagePipeline：同一输入两次 normalize 字节级一致的确定性测试（图像 sha256 入缓存键的前提）。
**手工验收矩阵（M1 发布前）**：通道（服务/⌥D/⌥S）× 目标 App（Safari、Chrome、微信、Preview 文本型 PDF、Terminal、VS Code）× 预期（取词成功或降级提示正确）；权限三态（未授权/授权后/重签后失效）；ESC/外点/固定；缓存徽标与重查。

## 11. 构建与自签（D4）

1. Xcode 16+ 新建 macOS App（Interface=SwiftUI），勾选提交 .xcodeproj；Signing & Capabilities → Team=个人免费 Team，自动签名；App Sandbox **不勾选**。
2. Info.plist：`LSUIElement=YES`；`NSServices`（§4.6）；`LSMinimumSystemVersion=14.0`。
3. SPM 引入 `swift-markdown-ui`。
4. 日常运行 = Xcode Run（本机自签）；证书 7 天到期：重新 Run 或 `xcodebuild -configuration Debug` 后运行——签名过期后**已运行实例可继续使用，但无法启动新实例**；重新签发后 TCC 权限可能重置（§4.10 启动自检兜底）。
5. 首次运行后右键服务若未出现：注销重登或确认服务已勾选（§4.6）。

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
