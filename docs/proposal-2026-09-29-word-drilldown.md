# 方案：截图场景的单词下钻（2026-09-29）

> 状态：**已定稿（2026-09-29 经二轮复审 + L2a 独立审 + K3 异构终审三道审修），待实施**。
> 2026-09-29 决策：A + B2 + C 同版本
> 一次做完；context 入缓存键的代价接受。同日二轮复审修订：补 B2 连续点词栈顶替换（D-e）、
> `.screenshotWordAt` 版本升级（D-d）、坐标换算 fit 满窗前提（§4.4）及若干规格勘误；
> 同日 L2a 独立审后修订：图片窗生命周期绑定栈根会话（D-f）、P1 零打断例外条款收口（§4.2/§10 步骤 7）；
> 同日 K3 终审修订：条件式置前面板（§4.3）、屏幕坐标换算契约（§4.4）、竖线护栏等。
> 决策明细见 §0；审修记录见 `docs/reviews/`（L0 / L2a / L2b 三份）。
> 触发：2026-09-29 实机反馈——对密集文本截图，点缩略图「没有作用」。
> 关联：DESIGN.md D5（不使用本地 OCR）、D9（签名与授权链）。
> 实施完成后本文相应条目合并进 `product-design.md` / `tech-design.md`，本文转为决策留档。

---

## 0. 评审决策（2026-09-29）

| # | 决策点 | 结论 | 影响 |
|---|---|---|---|
| D-a | 方案 B 取 B1（就地放大）还是 B2（独立放大窗） | **B2** | 见 §4，实现范围收窄，无需缩放状态机与嵌套滚动手势 |
| D-b | §6.1 `context` 入缓存键的失效代价是否接受 | **接受** | 所有带上下文的词查询缓存失效一次（版本升级时一次性代价） |
| D-c | A / B / C 是否同版本发布 | **同版本一次做完** | 见 §10，单次版本升级内完成 |
| D-d | 方案 C 改了 `.screenshotWordAt` 的 prompt，其版本是否随之升（原 §5.1「prompt 不变故保持 m1」与 §7 自相矛盾） | **升 m2** | 点词缓存失效一次（失效面=同图同点精确重复条目，量小）；防老缓存复活旧 prompt 的「单猜」答案 |
| D-e | B2「图片窗保持打开、连续查多个词」与 `pushWordAtQuery` 栈深 ≤2 守卫冲突 | **栈顶替换** | `stack.count == 2` 且栈首为截图卡时先 pop 再 push，而非静默拒绝，见 §4.3 |
| D-f | 图片窗生命周期与栈根会话脱钩（L2a P1：换根后窗残留→静默死路 / 跨会话混栈） | **换根即关窗** | `show(card:)` / `replay` 置新栈根前 `closeImageWindow()`；可选 `pushWordAtQuery` 图像身份校验加固，见 §4.3 |

**连带影响**：B2 引入新窗口，需一并确认「点词后结果卡片出现在哪」——已在 §4.3 补充规格；
二轮复审补 D-d / D-e、L2a 审后补 D-f 与 P1 例外条款收口（各节以「二轮复审 / L2a 修订」注记标出修订处）。

---

## 1. 问题实测

### 1.1 现象

`ScreenshotCardBody`（`Gloss/UI/CardViews.swift:153-164`）的缩略图用 `ImageTapView` 渲染，
其约束为 `.frame(height: 160)`（`CardViews.swift:191`）+ `.scaledToFit()`（`CardViews.swift:179`）。
面板内宽约 376pt（400 − 2×12 padding）。

实测一张 1512×982 的全屏截图区域：

| 量 | 值 |
|---|---|
| 显示缩放比 | `min(376/1512, 160/982)` ≈ **0.163** |
| 卡片内实际占用宽 | 246pt（`scaledToFit` 另留约 130pt 空白） |
| 正文 13px 渲染后 | **≈ 2.1px** |

即：**正文在缩略图里物理上不可读**。此时点击是「盲指」——用户无法确认自己指的是哪个词。

### 1.2 双重失效

即使解决了可读性，机制本身仍有一层不确定性：点一个坐标，问模型「离 (43%, 18%) 最近的词是什么」，
是**视觉定位**任务。对一段含数百词的区域，该任务本身模糊，模型易误判。

对照实测数据（`log show`，2026-09-29 20:04）：

```
begin screenshotExplain → done  4.5s  ✓
begin screenshotWordAt  → done  4.0s  ✓   ← 截图小、词清晰时可用
begin screenshotWordAt  → done  4.0s  ✓
begin screenshotWordAt  → 无终态  ∞    ✗   ← 长思考流卡死（已由 VisibleIdleGuard 修复）
begin screenshotWordAt  → done 14.0s  ✓   ← 耗时显著变长
begin screenshotWordAt  → done 13.0s  ✓
```

4s 与 14s 的差异说明：**定位难度随区域内词密度上升而显著恶化**。

### 1.3 根因定位

`WordChipsRow` + `SectionExtractor` 这套「模型输出难词表 → 渲染成可点词条」的机制
**已在句子卡（`CardViews.swift:117`）与段落卡（`:146`）中落地并验证**。
唯独 `ScreenshotCardBody` 没有：

```swift
VStack(alignment: .leading, spacing: 8) {
    if let img = card.originalImage ?? card.thumbnail {
        ImageTapView(image: img)        // 唯一下钻入口：盲指
    }
    MarkdownView(markdown: card.content) // 要点/术语是纯文本，不可点
}
```

**截图恰恰是最容易遇到生词的场景**（不受划词限制，图里有什么就是什么），
却是唯一没有可靠下钻入口的卡片。这是能力覆盖的缺口，不是交互细节问题。

---

## 2. 使用场景分类

| # | 场景 | 现状 | 可读性 | 目标方案 |
|---|---|---|---|---|
| S1 | 聊天记录 / 长文档截图，词多 | 盲指，常解析不出 | 差 | **A** |
| S2 | 图表 / 数据可视化，术语在图里 | 盲指 | 差 | **A** 为主 |
| S3 | App 界面截图（按钮/菜单文字） | 盲指 | 中 | **A** 为主 |
| S4 | 视频画面 / 字幕 | 盲指 | 差 | **A** 为主 |
| S5 | OCR 把词**转写错了**（如 idempoteney） | 盲指 + 定位错对象 | 差 | **B**（A 覆盖不到） |
| S6 | 截图很小，单个词或短句 | 图上点词**可用** | 好 | **B** 保持 |

S1–S4 的共同点：**模型已经把词转写在「识别内容」里了**。用户不需要指着图找词，
只需要**读出那个词再点**。这正是 A 要做的。

S5 是 A 的盲区：chips 上是**错误的拼写**，点了得到错误答案。只有 B 能覆盖。

---

## 3. 方案 A：截图卡接入难词 chips（主路径）

### 3.1 改动

**① prompt 增节**（`Gloss/Core/PromptLibrary.swift`，`case .screenshotExplain`）

在 `**要点**` 之后追加，**格式与段落卡 `**难词表**` 节完全一致**（`SectionExtractor` 按独立
粗体行识别节名而非 `##` 标题，复用现成契约）：

```
**要点**
- {2–4 条：生词、术语、值得注意的信息}

**难词表**
| 词/短语 | 音标 | 图中义 | 图中原文例句 |
|---|---|---|---|
| {3–6 行，按对理解的重要性排序；图中原文例句须与**识别内容**节的转写逐字一致，不新造不改写（防污染 §6.2 传入 word 查询的 context）；例句内含竖线 `\|` 时以 `/` 替代（`tableRows` 按朴素 `\|` 切分，防单元格错位）；无值得深挖的英文词则整节省略}
```

用 `图中义` / `图中原文例句` 措辞与段落卡的 `文中义` / `原文例句` 区分，避免模型混淆来源。

**② 卡片渲染**（`CardViews.swift`）

`ScreenshotCardBody` 对齐 `ParagraphCardBody` 的写法：

```swift
private var chips: [[String]] {
    guard let sec = SectionExtractor.section(named: "难词表", in: card.content) else { return [] }
    return Array(SectionExtractor.tableRows(sec).dropFirst())
}
private var bodyMarkdown: String {
    SectionExtractor.removingSection(named: "难词表", in: card.content)
}
```

body 改为「缩略图 + `MarkdownView(bodyMarkdown)` + `WordChipsRow(chips, context:)`」。
`removingSection` 保证表格不被渲染两遍。

**③ context 取值**

`WordChipsRow` 目前传 `context: card.inputText`；截图卡的 `inputText` 是 `nil`，照传即可
（L2a 勘误：例句是 per-row 数据，调用侧无法也无需传——由 §6.2 在 `WordChipsRow` 内部
按行取 `row[3]`，`row[3]` 当前被丢弃的问题在那里修）。

### 3.2 收益

- **零新交互概念**：与句子卡 / 段落卡的交互完全一致，用户不需要学新东西
- **零视觉定位**：不做坐标→词的推断，命中即正确
- **单请求**：点词只发一次请求
- **顺带修 bug**：`row[3]`（原文例句）此前被丢弃，语境义质量因此受损

### 3.3 改动量

| 文件 | 改动 |
|---|---|
| `PromptLibrary.swift` | +6 行 |
| `CardViews.swift` | +10 行（`ScreenshotCardBody`）+ ~3 行（`WordChipsRow` 取例句） |
| `CacheStore.swift` | 见 §5 |
| `SelfCheck/main.swift` | +若干 |

---

## 4. 方案 B：图上点词的可读性（补充路径）

B 只服务 S5（OCR 转写错）与 S6（截图小）。**不追求替代 A，只追求「指得准」**。

### 4.1 问题定位

当前 `.frame(height: 160)` 是**硬约束**——无论原图多大、多小，都被压进 160pt。
这是不可读性的直接来源。`scaledToFit` 在此之上又叠加了一次「按高度限死」。

### 4.2 候选对比与选定（B2）

| | B1 就地放大 | **B2 独立放大窗（已选）** |
|---|---|---|
| 形态 | 点击后卡片内图片区放大，可缩放/平移 | 弹出标准窗口显示图片（复用 `WindowManager`） |
| 空间 | 卡片最大内宽 376pt | 默认 1000×700，可缩放 |
| 交互新词汇 | 滚轮缩放 / 拖拽平移 / 返回 | 无新词汇：拉大窗口即放大（缩放按钮=最大化），图片恒 fit 满窗 |
| 是否违反 P1 零打断 | 否 | ⚠️ 是（例外条款现为封闭单例外，需扩为例外 2 收口——见选定理由 3 与 §10 步骤 7） |
| 嵌套滚动风险 | 有（图片横竖滚动 vs 卡片竖滚动） | 无 |
| 与既有架构一致性 | 中 | **高**（精读窗即标准窗口） |
| 改动量 | 中（缩放状态机 + 手势 + 回归面） | 小（`WindowManager` 加一个 case） |
| 覆盖 S5 的能力 | 够（约 3–5 行文本视野） | 富（整图任意区域） |

**选定 B2 的理由**（决策 D-a）：

1. **376pt 卡片里塞缩放状态机，收益不抵复杂度**。为覆盖 S5 这一个窄场景，在主交互面
   叠一层嵌套滚动 + 缩放手势，长期维护成本高于收益。
2. **与既有架构同构**：`WindowManager` 已有 `makeWindow(title:size:)` 工厂与
   `readerWindow` 生命周期范式（`WindowManager.swift:11/46-62/72-80`），
   图片窗是同一模式的第二个实例，不是新机制。
3. **P1 零打断需条款收口（L2a 修订）**：product-design.md P1 现为封闭单例外（「唯一例外：
   ≥400 词长选段直接开精读窗」），B2 不能靠类比引申豁免。B2 与精读窗同为用户显式触发的
   一次性深看动作，且行为强度同级——`showReader` 同走 `activate()` 且 `makeWindow` 不设
   `collectionBehavior`（`WindowManager.swift:46-47/72-80`），全屏 Space 下开窗同样发生系统
   Space 切换。取舍：**接受同级打断，不引入第二种窗口行为范式**；P1 扩写为
   「例外 2：点击截图卡缩略图打开图片放大窗，属预期的显式细看动作」，修订随 §10 步骤 7
   落入 product-design.md；全屏 Space 切换为已接受成本记入 §9.1。
4. **S6（小截图）不需要任何改动**——现在就可读，保留卡片内就地点击路径。

### 4.3 B2 规格

**窗口**

- 复用 `makeWindow(title:size:)`，样式 `.titled, .closable, .miniaturizable, .resizable`
  （`WindowManager.swift:72-80`）→ 自动获得任意拖拽调窗与系统缩放按钮（最大化）；
  **无滚动条、无自研缩放手势**（图片恒 fit 满窗，见 §4.4 前提——滚动条本就来自内容视图的
  ScrollView，而非窗口样式）
- 打开方式照 `showReader` 模式：`activate()` + `makeKeyAndOrderFront`（`makeWindow` 只建窗
  不排序，不主动排序可能不开到前台）。activate 引发的活动 app 切换与全屏 Space 切换
  为**已接受的同类打断**（与精读窗一致，见 §4.2 理由 3 与 §9.1）
- 默认尺寸 1000×700；`isReleasedWhenClosed = false`，`contentView` 每次替换为全新
  `NSHostingView`（照 `showReader` 的做法，原因见 `WindowManager.swift:56-59` 的注释：
  复用 hosting view 换 rootView 不触发 `onAppear`/`onDisappear`）
- `WindowManager` 新增 `private var imageWindow: NSWindow?`、`func showImage(...)`、
  `func closeImageWindow()` 与 `func isImageWindow(_ w: NSWindow?) -> Bool` 访问器
  （K3 修订：monitor 排除在 PanelController 侧跨类型判同，不能直接读 private 属性，
  以访问器保封装）

**内容**

- 原始截图 `card.originalImage`（**全分辨率**，非 1568px 归一化版——`SessionCoordinator.swift:312`
  保存的就是原图，归一化版只用于发模型）
- 叠加十字准星与坐标读数，让用户确认自己指的是哪里
- 图片恒以 `scaledToFit` 铺满窗口内容区——**放大手段就是拉大窗口**；不加 ScrollView /
  缩放手势，这是 §4.4 换算公式成立的前提（一旦引入滚动或缩放，换算必须叠加偏移与缩放因子，
  复杂度即回到 B1）
- 历史回放卡 `originalImage` 已释放（仅 ≤200px 缩略图），按 §4.5 宽度阈值自然走就地点击，
  不开放大窗（放大只会糊）

**点词**

- 窗内任意位置点击 → 坐标换算（见 §4.4）→ `SessionCoordinator.pushWordAtQuery(image:point:clickRect:)`
  （**K3 修订**：`clickRect: CGRect? = nil` 可选——图片窗路径传点击点的 Cocoa 屏幕坐标
  CGRect（换算契约见 §4.4），卡片内就地点词路径与 demo 验收通道（`demoWordAtQuery`）
  传 nil，兼容现状调用方）
- 图片窗**保持打开**，便于连续查多个词
- **栈顶替换（二轮复审 D-e，P0 修复）**：现守卫 `guard stack.count < 2`（`SessionCoordinator.swift:172`）
  在第 2 次点击时静默拒绝；且此时面板已被外点 monitor 藏掉（见下），**面板从此不再浮出**
  （栈卡死在深度 2、图片窗无返回入口）。改为：栈首仍为 `.screenshotExplain` 时，
  `stack.count == 2` 先 `removeLast()` 再入栈（替换栈顶），仅此一处放宽；返回按钮语义不变
  （回到整图卡）。chips 路径（`pushWordQuery`）不动——chips 只在栈顶卡上可见，无连续点击场景
- **窗口生命周期绑定栈根会话（L2a 修订 D-f，P1 修复）**：置新栈根的路径在替换栈根前调用
  `WindowManager.shared.closeImageWindow()`。栈根赋值点全仓共三处（K3 补充枚举）：
  `show(card:)`——⌥D/⌥S/Services/demo 入口共用（`SessionCoordinator.swift:300-304`）、
  `replay`（:409-420）、`requery`（:205，`stack = [card]`）——第三处当前被其自身守卫挡住
  （root.inputText 非空才可达，而截图根卡 inputText 为 nil）故不可达，但为防未来改动静默
  绕过，建议把 `closeImageWindow()` 直接收口在三处栈根赋值点（或抽成唯一的
  `setRoot(card)` 入口）。
  不关窗的两条失效路径（L2a 独立推演）：① 换根为文本卡后，窗内点击命中
  `.screenshotExplain` 守卫静默 return，且 monitor 排除后连「藏面板」的副反馈都没有
  （静默死路）；② ⌥S 换新截图卡后，旧图的点词卡压在新根上，「返回整图」落错卡
  （跨会话混栈）。可选加固：`pushWordAtQuery` 校验
  `stack.first?.originalImage === image`（thumbnail 分支保历史回放就地点词不被误杀），
  身份不符时关窗

**结果卡片去向（本次评审补充的关键规格）**

`pushWordAtQuery` 目前只往栈里追加并更新面板，**不会把面板置前**。B2 的点击源在另一个窗口，
若不置前，用户点了词却看不到结果。`PanelController.show(near:)` 内部走
`panel.orderFrontRegardless()`（`PanelController.swift:72`），**不抢焦点**，正好适用：

```swift
// pushWordAtQuery 内，stack.append 之后新增（条件式置前，K3 修订）
if !PanelController.shared.isVisible {
    PanelController.shared.show(near: clickRect)
}
```

**为什么是条件式而非无条件置前（K3 P1 修复）**：`pushWordAtQuery` 同时服务图片窗与
卡片内就地点词两条路径（`ImageTapView` 手势回调，`CardViews.swift:188`）。无条件
`show(near:)` 会让 S6 就地点词的面板每次被重定位（现状是原地更新，行为未声明地改变，
与 §4.3「完全保留」承诺相抵）；且 clickRect 为 nil 时 `show(near: nil)` 走
`positionByMouse` 跳鼠定位（`PanelController.swift:60-66`）。条件式后：就地路径面板
必可见（用户正点在面板里）→ 不重定位，行为真正「完全保留」；图片窗路径面板可见时
原地换卡、被 ESC/外点藏掉时复活并就近定位。

- `clickRect` 由图片窗按点击点换算为屏幕坐标传入，使面板浮在点击处附近，与 ⌥D 行为一致。
  注：用户曾手动拖放过面板时，`show(near:)` 优先恢复记忆位置（`restoredOrigin` 分支，
  `PanelController.swift:56-59`），点击处就近定位只对未拖放过的用户生效——与 ⌥D 现状一致，不改
- 面板是 `nonactivating` NSPanel（`PanelController.swift:26-33`），`.floating` 层级恒在普通窗口
  （图片窗）之上，且 **不会抢走图片窗的键盘焦点**，用户读完点回图片窗即可继续点下一个词；
  面板本身可拖动，**不做图片窗让位动作**（二轮复审修订：原文「图片窗轻微下移让位」删除——
  移动用户正在交互的窗口比面板浮在其上更构成干扰）
- **外点 monitor 排除（二轮复审 P1 修复）**：面板可见期间，图片窗内 mouseDown 会先触发
  PanelController 的 local monitor 把面板 `hide()`（`PanelController.swift:179-206`），随后 tap 才
  `pushWordAtQuery` 再 `show()`——功能上可用但伴随面板闪隐、ESC 热键拆装、旧流式卡被打成
  「已取消」的 churn。修法：local monitor 判
  `WindowManager.shared.isImageWindow(ev.window)` 为真直接返回不 hide
  （global monitor 只收其他 app 的事件，图片窗属本 app，无需处理）；
  由验收标准第 5 条覆盖

**关闭**

- ESC / 关闭按钮关图片窗；`windowWillClose` 需扩展以识别 `imageWindow`
  （当前实现 `guard w === readerWindow else { return }`，`WindowManager.swift:67`，
  必须补 `imageWindow` 分支，否则图片窗关闭不走清理路径）。分支体 = **置空 `imageWindow`
  引用即可**（图片窗无可取消任务，勿照抄 reader 的 VM cancel 逻辑）；另需新增
  `closeImageWindow()`（orderOut + 置空）供 D-f 换根路径调用
- **ESC 两级优先级（二轮复审补充）**：面板可见期间 ESC 已被全局热键注册为「藏面板」
  （消费式，`PanelController.show → registerEscape`），此时 ESC 不会到达图片窗；面板隐藏后
  ESC 才关图片窗（图片窗 keyDown 实现）。即：先藏面板、再关图片窗，两级各按一次

**保留**

- 卡片内缩略图与就地点击**完全保留**：S6（小截图）场景它工作正常，不强制走窗口

### 4.4 坐标换算

`Gloss/UI/CardViews.swift:184-188` 已有此算法，抽成共享函数供缩略图与图片窗两处使用。
**前提（二轮复审钉死）**：公式仅在「图片恒 fit 满窗、无滚动无缩放」的渲染下成立——
两处调用方都不得引入 ScrollView / magnification，否则换算必须叠加滚动偏移与缩放因子：

**屏幕坐标换算（K3 补充，第二段契约）**：`clickRect` 需为 **Cocoa 全局屏幕坐标**
（y 向上、多屏各自 frame——这是 `PanelController.positionBySelection` 侧的既有契约，
`PanelController.swift:142`），而 SwiftUI tap 的 `v.location` 是视图局部坐标（y 向下）。
换算路径钉死为：`NSView.convert(_:to: nil)` 得窗口坐标 → `window.convertToScreen(_:)`
得全局坐标（多屏安全由系统保证）；**禁止手搓 `NSScreen.main.frame.height - y` 单屏
翻转公式**（仅主屏正上方布局时偶然成立，多屏即错）。可一并收口进共享函数
（入参追加 window frame / contentLayoutRect）。

```
s  = min(viewW / imgW, viewH / imgH)
dw = imgW * s ;  dh = imgH * s
ox = (viewW - dw) / 2 ;  oy = (viewH - dh) / 2
nx = (clickX - ox) / dw   // 已做 0…1 越界 guard
ny = (clickY - oy) / dh
```

抽成 `ImageTapView` 与图片窗共用的纯函数，并加 SelfCheck 锁定换算正确性
（给定固定 view/image 尺寸与点击点，断言输出的 0…1 归一化坐标）。

### 4.5 B2 的文件改动清单

| 文件 | 改动 |
|---|---|
| `Gloss/UI/WindowManager.swift` | +`imageWindow` 属性、+`showImage(...)`（activate + makeKeyAndOrderFront）、+`closeImageWindow()`（D-f）、`windowWillClose` 补 `imageWindow` 分支（置空引用） |
| `Gloss/UI/ImageZoomWindow.swift`（新） | 图片窗 SwiftUI 视图：原图 fit 满窗 + 十字准星 + 点击回调（含屏幕坐标换算）+ 坐标读数 + ESC keyDown |
| `Gloss/UI/CardViews.swift` | `ImageTapView` 拆出共用坐标换算函数；截图卡点击按宽度分流——≤卡片内宽就地点词，否则开窗（与下方注记同口径） |
| `Gloss/UI/PanelController.swift` | local monitor 排除图片窗内点击（~3 行，见 §4.3） |
| `Gloss/Core/SessionCoordinator.swift` | `pushWordAtQuery`：栈顶替换守卫（D-e）+ `clickRect` 可选参数 + 条件式置前（不可见才 `show(near:)`）；`show(card:)`/`replay`/`requery` 换根前关图片窗（D-f，建议收口在栈根赋值点） |
| `Gloss.xcodeproj` | 新文件入 target |

> 注意：S6 场景（小截图就地点击）需保留。`ImageTapView` 的点击行为改为
> 「若原图自然宽度 ≤ 卡片内宽则直接点词，否则开放大窗」——用尺寸而非固定规则分流。

---

## 5. 连带必须处理：缓存版本策略（**阻塞项**）

`CacheStore.makeKey`（`CacheStore.swift:27`）把 `PromptLibrary.version` 拼进 payload：

```swift
var payload = "\(normalizedInput)|\(kind.rawValue)|\(model)|\(PromptLibrary.version)"
```

改 `.screenshotExplain` 的 prompt 而**不升版本**，则老用户会命中 v0.1.7 的旧缓存——
输出里没有难词表，**chips 永远不出现**，且「重新查询」之外没有任何路径能拿到新结果。

### 5.1 决策：按 kind 分版本，而非全局 bump

现有 `version = "m1"` 是全局常量。若直接改成 `"m2"`，**所有类型**（词/句/段/截图/点词）
的缓存同时失效，每个用户要为所有历史查询重新付费。

proposed：

```swift
enum PromptLibrary {
    static func version(for kind: QueryKind) -> String {
        switch kind {
        case .screenshotExplain, .screenshotWordAt: return "m2"
        default: return "m1"
        }
    }
}
```

`makeKey` 改用 `PromptLibrary.version(for: kind)`。**同时删除静态 `version` 常量**
（二轮复审补充：保留会形成双源漂移——makeKey 走 `version(for:)` 而静态值停滞；其现仅
两处引用：`CacheStore.swift:27` 与 SelfCheck 断言），并同步把 SelfCheck 现有断言
`prompt.version == "m1"`（`SelfCheck/main.swift:102`）改为 `PromptLibrary.version(for: .word) == "m1"`。

**代价**：截图整图解读与图上点词的缓存失效（二轮复审 D-d：点词失效面 = 同图同点精确
重复的条目，量小）；词/句/段缓存**完全保留**。

> 二轮复审修订（D-d）：原文「`.screenshotWordAt` 的 prompt 不变，故保持 `m1`」与 §7 矛盾
> ——方案 C 恰恰要改 `.screenshotWordAt` 的 prompt。若保持 `m1`，同图同点命中老缓存时返回
> 旧 prompt 的「单猜」答案，恰是 C 要消灭的编造类行为从缓存复活，故一并升 `m2`。
> 整图与点词两类键含 kind 与坐标，互不误命中。

---

## 6. 连带发现的问题

### 6.1 `context` 不进缓存键（潜在正确性缺陷）—— **决策 D-b：修复，代价接受**

`runText`（`SessionCoordinator.swift:320-326`）用 `card.inputText`（即词本身）构造键，
**`card.context` 不参与**。后果：

- 先在段落卡查 `operation`（context = 整段）→ 缓存写入
- 后在截图卡点同一个 `operation`（context = 图中例句）→ **键相同，命中旧结果**
- 得到的语境义是段落语境下的，与当前图无关

截图卡接入 chips 后，用户会**更频繁地**从不同语境查询同一个词，命中错结果的概率显著上升。

**建议**：`kind == .word` 且 `context != nil` 时，把 `context` 的 sha 短摘要并入 payload：

```swift
// makeKey 增加 context: String? = nil 参数（二轮复审补充：现签名无 context，需接线）
// ctx 先经 cacheNormalized 归一再入 sha（K3 修订：同一语境的空白变体同键，仅缓存效率）
if kind == .word, let c = context, !c.isEmpty {
    payload += "|ctx:" + glossSHA256(QueryRouter.cacheNormalized(c)).prefix(8)
}
```

调用侧（二轮复审补充）：`runText` 传 `card.context`；chips 例句经 §6.2 从
`pushWordQuery(word:context:)` 流入 `card.context`，无需单独接线。

**范围取舍（L2a 补充）**：sentence prompt 同样拼 `语境：`（`PromptLibrary.swift:46`），
但句/段输入自身即主导语境，context 边际影响小，且并入会使句卡缓存粒度剧增——故本修复
限 `kind == .word`，sentence 不并入；后续实测发现语境错配再评估扩围。

**代价**：带上下文的词查询缓存失效一次（`⌥D` 划词查出来的 `context` 非空，会一并失效）。
如不接受该代价，可先只在 chips 路径传 `nil` context 并在文档记录该限制。

### 6.2 `WordChipsRow` 丢弃 `原文例句`

`CardViews.swift:206-211` 只取 `row[0..2]`（词/音标/文中义），`row[3]`（原文例句）未使用。
三个卡类型都因此损失了最佳语境来源。

**建议**：改为 `row.count > 3 && !row[3].isEmpty ? row[3] : context`（二轮复审补判空：
模型可能输出空串第 4 列，空串会覆盖有效 context）。与 §6.1 的键修复配套后即可生效。

---

## 7. 方案 C：诚实降级

当前 `.screenshotWordAt` 的 prompt 只覆盖「附近**没有**英文单词」，未覆盖
「附近有**多个**词、无法确定用户指哪个」——而这正是密集截图下的常态。

补充约束（`PromptLibrary` `case .screenshotWordAt`）：

```
定位最接近点击处的英文词…
若该位置附近存在多个候选词且无法确定：不要猜测，列出 2–4 个候选并请用户选择。
```

配合 A：即便用户仍然走 B 拿不准，也不会得到一个编造的答案。

（版本耦合：本节改了 `.screenshotWordAt` 的 prompt，其版本随 §5.1 决策 D-d 一并升 `m2`，
防老缓存复活旧「单猜」行为。）

---

## 8. 自检扩展

`SelfCheck/main.swift` 新增（目标：65 + 9 + N 全绿）：

| 断言 | 覆盖 |
|---|---|
| `section.screenshotWords` | 含 `**难词表**` 节的 markdown 能被 `SectionExtractor.section(named:)` 取出 |
| `section.screenshotTableRows` | 该节表格解析出行列，跳过分隔行 |
| `section.screenshotRemoved` | `removingSection` 后正文不含难词表、不丢其他节 |
| `section.noWordTableIsNoop` | 无难词表时 `section` 返回 nil、`removingSection` 原样返回（老缓存兼容） |
| `prompt.versionPerKind` | `version(for: .screenshotExplain) == "m2"` 且 `version(for: .screenshotWordAt) == "m2"`，词/句/段为 `"m1"`（D-d） |
| `prompt.versionForWordUnchanged` | `version(for: .word) == "m1"`（原 `prompt.version` 断言的替换；K3 修订：静态常量删除由**编译期**保证——残留引用即编译错误，无运行时可断言对象，断言名不得暗示有运行时闸） |
| `cachekey.wordContextDiffers` | 同词不同 context → 键不同；context 为 nil/空串时键与旧版一致（§6.1） |
| `cachekey.screenshotVersionBumped` | 整图键与点词键均随版本变化；词/句/段键不随之变（D-d） |

> 栈顶替换（D-e）、monitor 排除与换根关窗（D-f）位于 AppKit/MainActor 层
> （SessionCoordinator / PanelController），不进 SelfCheck 纯逻辑联合编译，
> 由验收标准第 5/10 条手工覆盖。

---

## 9. 风险与明确不做的事

### 9.1 风险

| 风险 | 缓解 |
|---|---|
| 模型漏发 `**难词表**`（如纯界面截图无英文词） | 契约要求「无词则整节省略」，`chips` 为空时 `WordChipsRow` 本身不渲染（`if !rows.isEmpty`），无需特判 |
| 表格行数过多撑爆卡片 | prompt 限定 3–6 行；`WordChipsRow` 已是紧凑 Capsule 布局 |
| B2 窗口与既有 WindowManager 焦点策略冲突 | 复用精读窗既有的窗口模式，不新增焦点语义 |
| 图片窗点击触发外点 monitor 藏面板 | local monitor 排除 `imageWindow` 事件（§4.3）；栈顶替换（D-e）兜底 |
| 连续点词超栈深 ≤2 被静默拒绝 | D-e 栈顶替换，验收第 5 条覆盖 |
| 换栈根后图片窗残留（⌥D/⌥S/历史重放）→ 静默死路 / 跨会话混栈 | D-f 换根即 `closeImageWindow()`，验收第 10 条覆盖 |
| 全屏 Space 下开图片窗导致系统 Space 切换 | 与精读窗（既有例外）同级行为，接受；P1 扩写例外 2 收口（§4.2 理由 3、§10 步骤 7） |
| 缓存版本分 kind 后逻辑分叉 | 单一函数 `version(for:)` 收口，附单测锁定 |

### 9.2 明确不做

- **不做**图片 OCR / 词块高亮：D5 已定「不使用本地 OCR」，A 的 chips 来自**模型已输出的文本**，
  不引入任何客户端识别
- **不做**点击后放大为覆盖层再回卡片（会叠加一层焦点语义，与 P1 冲突）
- **不做**多 Provider 视觉定位对照（M3 评估项，本次不牵入）
- **不改** `ImageTapView` 的就地点击路径（S6 场景它工作正常，B2 是增量而非替换）

---

## 10. 实施顺序与验收

**A + B2 + C 同版本一次做完**（决策 D-c）。下列顺序按依赖排列，**同一分支内可并行**：

```
阶段一：缓存与键（其余全部的前置）
  ├─ 1  version(for:) 分 kind + makeKey 接线
  └─ 2  §6.1 context 入键 + §6.2 例句作 context
阶段二：功能（1、2 完成后可并行）
  ├─ 3  A  prompt 增 **难词表**              （依赖 1）
  ├─ 4  A  ScreenshotCardBody 渲染 chips     （依赖 3）
  ├─ 5  C  prompt 补「多候选则列出」          （依赖 1——prompt 变更须随版本升，与步骤 3 同理）
  └─ 6  B2 图片放大窗 + 坐标换算抽公共函数 + 栈顶替换 + monitor 排除 + 换根关窗（依赖 2、4）
  └─ 7  P1 例外 2 条款收口（product-design.md / tech-design.md）   （依赖 6）
```

| 步骤 | 内容 | 依赖 | 可独立验证 |
|---|---|---|---|
| 1 | `version(for:)` 分 kind + `makeKey` 接线 | — | SelfCheck 键断言 |
| 2 | §6.1 context 入键 + §6.2 例句作 context | 1 | SelfCheck 键断言 |
| 3 | prompt 增 `**难词表**` | 1 | 手工：⌥S 一次，看 chips 是否出现 |
| 4 | `ScreenshotCardBody` 渲染 chips + 移除该节 | 3 | 手工：点 chip 出词卡 |
| 5 | 方案 C prompt 补充（`.screenshotWordAt` → m2，D-d） | 1 | 手工：故意点在词间空白处 |
| 6 | 方案 B2 图片放大窗（坐标换算抽公共函数、栈顶替换 D-e、monitor 排除、换根关窗 D-f、面板置前） | 2、4 | 手工：点缩略图开窗、窗内**连续点两个词**、面板浮出且第二次仍出卡 |
| 7 | `product-design.md` P1 扩写「例外 2：点击截图卡缩略图打开图片放大窗」+ `tech-design.md` 相应条目同步 | 6 | 文档核对：裁决条款与实际行为一致 |

### 验收标准

1. 对**密集文本截图** ⌥S，卡片底部出现可点难词条；点击任一条得到该词的完整单词卡
2. 同一张图在 v0.1.7 已缓存过时，升级后**不会**命中旧缓存（步骤 1 生效）
3. 同一词在两张不同截图的 chips 中点击，**得到各自语境的语境义**（步骤 2 生效）
4. 现有句子卡 / 段落卡的难词 chips 行为**无回归**，且语境质量不降（步骤 2 附带改善）
5. 点缩略图打开放大窗，窗内点词坐标换算正确，**结果面板浮出（被藏时）或原地更新（可见时），
   且不抢图片窗焦点**（§4.3 条件式置前），词卡内容与 A 路径一致；**窗内连续点第二个词，
   结果卡替换显示**（D-e 栈顶替换生效，不出现面板消失 / 点击无响应；monitor 排除生效，无闪隐）
6. 小截图（S6）仍走卡片内就地点词路径，**不被强制弹窗，面板不被重定位**（条件式置前
   保留现状行为）
7. 点在无词/多词位置时，模型列出候选而非编造（步骤 5 生效）
8. 图片窗关闭走 `windowWillClose` 清理路径，不泄漏引用；ESC 两级语义正确——
   面板可见时先藏面板，面板隐藏后再按 ESC 才关图片窗
9. `SelfCheck` 全绿；`scripts/release.sh` 三道发布闸通过
10. 根卡被替换（⌥D 划词 / ⌥S 新截图 / 历史重放）时图片窗**自动关闭**，不出现静默死路
    与跨会话混栈（D-f 生效）
11. `product-design.md` P1 例外条款已扩写例外 2、`tech-design.md` 同步——裁决文档与
    实际行为一致（步骤 7 生效）

---

## 11. 决策状态

| # | 决策点 | 状态 |
|---|---|---|
| D-a | B2 独立放大窗 | ✅ 已定（2026-09-29） |
| D-b | `context` 入缓存键 | ✅ 已定，接受失效代价 |
| D-c | A + B2 + C 同版本 | ✅ 已定 |
| D-d | `.screenshotWordAt` 随方案 C 升 `m2` | ✅ 已定（2026-09-29 二轮复审） |
| D-e | B2 连续点词 = 栈顶替换 | ✅ 已定（2026-09-29 二轮复审） |
| D-f | 图片窗生命周期绑定栈根会话（换根即关窗） | ✅ 已定（2026-09-29 L2a 审后修订） |
| — | P1 零打断例外条款扩写例外 2（B2 图片窗） | ✅ 已定（2026-09-29 L2a 审后修订，§4.2 理由 3） |

### 实施期仍需确认的次级项

以下不阻塞开工，但需在对应步骤落地前定：

1. **§4.5 的分流阈值**：「原图自然宽度 ≤ 卡片内宽则直接点词，否则开放大窗」——
   阈值是否用自然宽度，还是改用「按 160pt 缩放后正文是否 < 4pt」这类可读性判据
2. **图片窗默认尺寸**：拟定 1000×700，是否需要记忆用户上次尺寸
3. **图片窗标题**：拟定 `Gloss 图片`，是否需带来源（如「Gloss 读图」）

---

## 附：与本次改动的版本关系

本文方案（v0.1.8）与同批的 **可见内容空闲超时兜底**（`VisibleIdleGuard`）建议同版本发布：
两者都属「截图/长请求路径的健壮性」，且 §4.5 的图片窗会复用同一套
`pushWordAtQuery` → 超时 → 错误态「重试」链路，一并验证更省事。
