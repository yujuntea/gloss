# M1 代码 L0 自查三工件 + 六项自审声明（2026-09-26）

> 对象：M1 全部代码（Gloss/ 26 个 Swift 源文件、SelfCheck/main.swift、Info.plist、Gloss.xcodeproj、scripts/mock_llm.py）。
> 规格：docs/DESIGN.md（D1–D7）、docs/product-design.md V1.0、docs/tech-design.md V1.0（§12 M1 任务 T1–T5）。
> 本文件是三段式审查 L2a/L2b 的任务书素材。

## 一、自查结论表（代码版 CI，口径=通过标准原文）

- **CI-1' 规格符合性**（任务书规格逐条 vs 实现逐条）：通过——tech-design §12 M1 五块逐条对照：T1 骨架（工程/LSUIElement/设置四页签/Keychain/预设/测试连接）✓；T2 服务通道（ServicesBridge+NSServices）/PanelController（nonactivating+canJoinAllSpaces+fullScreenAuxiliary）/SSE 多模态客户端/单词卡 ✓；T3 HotkeyManager(⌥D/⌥S)/AX+⌘C 双通道/PermissionCenter/句子卡/段落卡/TTSEngine（倍率钳制）✓；T4 ScreenshotManager(双条件取消判定)/ImagePipeline(1568/纯CG)/截图卡/读图/图上点词(1%网格量化入缓存键) ✓；T5 精读窗(分批+聚合入参=要点+难词表+术语表)/缓存(LRU+持久化)/历史窗/首启向导/开机自启(SMAppService)/错误态 ✓。product-design §4 卡片规格字段级对照 ✓（词条手势=点击主体切卡+尾随🔊朗读，K-P1-1 统一规则）。
- **CI-2' 自验证真实性**（编译/测试实际跑过且有输出留存）：通过——①`swiftc -typecheck` 全源通过（输出留存于会话）；②逻辑自检 55 项 PASS（/tmp/gloss_selfcheck 实跑，含 router 16/SSE 7/section 12/prompt 9/cache 8/image 4）；③xcodebuild BUILD SUCCEEDED（ad-hoc 签名）；④实机验收 11 场景全绿（统一日志 os_log 留存：query begin/done chars=516、cache hit、tts speak/didFinish、hotkeys registered d=true s=true）+ 8 张窗口级截图（词/句/段/读图/点词/精读/历史/设置/向导）。断言有效性：自检含边界（恰60词/400词、量化网格同键、LRU 淘汰、多choice取[0]）与反例（缓存 miss/空choices/节缺失）。
- **CI-3' 改动边界**：通过——全部为新增文件（Gloss/、SelfCheck/、scripts/、Info.plist、Gloss.xcodeproj、.gitignore），docs/ 与既有文件零改动；无顺手破坏。
- **CI-4' 依赖完整性**（改 A 处同步依赖 B 处）：通过——跨文件类型契约由编译背书（typecheck 零 error）；设计文档引用的机制逐处落实：取数契约（§4.3）→ SectionExtractor + 模板节名 + §10 分节提取器测试；点词缓存键含量化坐标（§4.9）→ CacheStore.makeKey kindParams；聚合入参禁只喂要点（K-P1-2）→ aggregatePrompt + ReaderViewModel.runAggregate 材料拼接；词条手势统一（K-P1-1）→ WordChipsRow 实现；ESC 消费式热键（K-P1-4）→ HotkeyManager.registerEscape 随显隐装拆。
- **CI-5' 风格一致**：通过——Swift API 风格、注释密度（约束性注释为主）、错误处理（AppError 统一）与日志（GlossLog 统一）全库一致。

## 二、修复清单（编码过程中发现并已修复）

| # | 问题 | 修复 |
|---|---|---|
| F1 | SSE 空行被 `bytes.lines` 吞掉（omittingEmptySubsequences）→ parser 缓冲永不 flush → 流式内容全丢（实机验收发现，**对真实 MiniMax 服务器同样致命**） | LLMClient 改为逐字节分行保留空行；netprobe 回归 516 字符 ✓ |
| F2 | `**本批术语**（若有）` 带尾注节名不被识别 → 术语表永远提取不到 | SectionExtractor.isSectionHeader 支持 "**xxx**任意尾注" 形式 + 新增测试 |
| F3 | NSGraphicsContext(bitmapImageRep:) 无 WindowServer 会话返回 nil（CLI/后台进程） | ImagePipeline 改纯 CoreGraphics（CGContext+ImageIO） |
| F4 | 单词卡标题与 markdown ## 标题重复渲染 | WordCardBody stripFirstHeading；点词卡头取模型识别词 |
| F5 | Carbon 常量 Swift 导入差异（optionKey/AXValueType case 名/kEventParamDirectObject Int 型） | import 补齐 + AXValueType(rawValue:) 绕开 case 命名 + EventParamName() 显式转换 |

## 三、已知偏差（设计↔实现，主 Agent 声明）

| # | 设计原文 | 实现现状 | 理由 |
|---|---|---|---|
| V1 | swift-markdown-ui（SPM） | 内置模板子集 MarkdownView | 消除 SPM 网络依赖；只渲染固定模板子集 |
| V2 | ProviderPresets.json 随包 | ProviderPresets.swift 类型化常量 | 免运行时解析失败路径 |
| V3 | GlossTests XCTest 目标 | SelfCheck CLI 联合编译 runner + 本地 mock 端到端 | 免 TEST_HOST 配置；mock 端到端覆盖面强于 URLProtocol mock |
| V4 | 快捷键可自定义 | 固定 ⌥D/⌥S + 冲突检测 | 录制控件后移；设置页已注明 |
| V5 | KeychainStore account=presetID+slot | account=配置 UUID | 多配置同预设需区分 |
| V6 | — | 验收/演示启动参数（-demo-*、-pin、-panel-at、-seed-key、-seed-history） | 实机验收自动化所需，集中在 AppDelegate，无 Keychain/网络副作用 |

## 四、关键锚点（供 reviewer 复验）

`LLMClient.swift:逐字节分行保留空行`、`CacheStore.makeKey|pt:%d,%d`、`SectionExtractor.isSectionHeader(dropFirst(2))`、`aggregatePrompt(batchMaterials:)`、`HotkeyManager.registerEscape id=99`、`ImagePipeline.normalize CGImageAlphaInfo.premultipliedLast`、`PositionOverride/-panel-at`、`PanelController ESC registerEscape/unregisterEscape 成对`。

## 五、六项自审声明（旗舰档，逐项举证）

- **通读全量**：26 源文件全部为本会话逐字新写并经 4 轮编译-修复循环（每轮 typecheck 全量输出复核）；docs 未动。
- **整体审视**：①达成目标——M1 五块任务全部落地且实机 11 场景走通，方案三原则（零打断/一秒钟/所见即可问）在实现中成立（浮窗不抢焦点/路由自动/截图与 PDF 共用图像管线）；②实现合理——更优路径已识别：URLSession.bytes.lines 的坑只能逐字节分行（standard 替代是无）；③整体自洽——错误域→状态表→文案三层对齐，导航栈深≤2 与 chips/点词互恰。
- **测试引用**：自检 55 项全绿（/tmp/gloss_selfcheck 实跑输出）；实机日志锚点=上文 CI-2'；修复 F1 后跑 netprobe 回归 + 场景 1 重跑 ✓。
- **断言验证**：跨文件断言由编译器验证；行为断言由实机日志/截图验证；不可验项（真实 MiniMax 行为）已列入 tech §13-C1 校准清单，未伪装已验证。
- **场景推演**：11 项实机场景即推演落地；另推演：取消流式（外点/ESC → panelDidHide → cancelCurrent ✓ 代码路径）、⌘C 兜底剪贴板恢复（asyncAfter 0.3s restore，恢复失败静默符合 §9）、TTS 与新查询互斥（cancelCurrent stop ✓）、历史回放四类形态（词句段浮窗/读开精读窗/图只回放）。
- **修复处复核**：F1–F5 修复后均回归（编译+自检+实机重跑对应场景）；本轮无未复核修复。

**范围之外、以及结论有误之处，仍需独立核验。**
