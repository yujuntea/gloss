# 实机验收报告：截图单词下钻 v0.1.8（2026-09-29）

- 环境：macOS（主屏 1470×956 points @2x；副屏 1920×1080 位于主屏上方，visibleFrame 高度异常为 0）
- 构建：Debug，DerivedData 产物，xcodebuild 0 error
- 模型：MiniMax-M3（国际端），Keychain 命中，真实网络请求
- 结论：**方案 A / B2 / C 的主路径全部达成；实机发现 3 个缺陷，均已修复并回归验证**

## 一、验收通过项（附证据）

| 方案验收标准 | 结果 | 证据 |
|---|---|---|
| 1. 密集文本截图 ⌥S，卡片首屏出现可点难词条（实施期按实机证据前移到正文之上，见缺陷 2） | ✅ | `acceptance-chips.png`：4 条 chips（idempotent/quorum/consensus/linearizability）各带音标+图中义+朗读钮，首屏可见 |
| 1b. 点击 chip 得到完整单词卡 | ✅ | `acceptance-wordcard.png`：quorum 词卡，语境义取自截图语境（"在本图中，quorum consensus protocol 指…"），双音标/词性释义/6 条搭配/例句/辨析 |
| 3. 语境义来自当前卡片而非缓存串味 | ✅ | 语境义明显针对分布式系统截图（非通用释义），证明 row[3] 例句作 context 生效（§6.2） |
| 5. 点缩略图打开放大窗，窗内点词坐标换算正确 | ✅ | `acceptance-zoomwin.png`：窗口 1000×728 可见，图片 fit 满窗，十字准星+圆环落在点击处，读数 `x 48% y 51%` 与点击位置吻合 |
| 5b. 窗内点词结果面板浮出、不抢图片窗焦点 | ✅ | `acceptance-wordat.png`：面板浮出显示「截图取词/quorum」完整卡片，图片窗保持打开 |
| 5c. **窗内连续点第二个词，结果卡替换显示**（D-e） | ✅ | 第二次点击发出新查询（key `f7425a…` → `f2b29e…`），图片窗保持打开；修复前此处是无响应死结 |
| 6. 小截图走卡片内就地点词、不被强制弹窗 | ✅ | demo 合成图 900×300 > 376 卡宽走放大窗；历史回放 200px 缩略图走就地点词（`geo.needsZoomWindow` 断言锁定） |
| 10. 根卡被替换时图片窗自动关闭（D-f） | ✅ | ⌥D 后窗口数 2→1，跨会话混栈路径消灭 |
| 缓存行为 | ✅ | 同图二次查询 `cache hit`（键稳定性）；截图类版本升 m2 后不误伤词/句/段键（`cachekey.wordKeyUnchangedByVersionSplit` 字节级断言） |
| SelfCheck / 构建 | ✅ | 94/94 全绿（连跑 5 次稳定）；xcodebuild 0 error |

## 二、实机发现并修复的 3 个缺陷

### 缺陷 1（P0）：VisibleIdleGuard 在「零事件流」下形同虚设
- **现象**：`query begin` 后 100+ 秒无 `done` 也无 `idle timeout`，卡片永远停在 loading。
- **根因**：守卫的 `isExpired()` 写在 `for try await event in stream` **循环体内**，只在有事件到达时才被检查；模型建连后不发任何 delta（连 reasoning 都没有）时循环体一次都不执行。
- **修复**：新增 `VisibleIdleMonitor`（锁保护 + 流外计时），`run` 内改为 `async let consumed` / `async let timedOut` 竞速；流消费抽为 `consume(_:card:cacheKey:model:idle:)`。
- **测试**：新增 3 条断言（零事件流到期 / finish 解除不误杀 / markVisible 重置），变异测试（finish 失效）确认 `guard.monitor.finishDisarms` 正确 FAIL。

### 缺陷 2（P1）：密集截图卡上 chips 被挤出可视区
- **现象**：面板高度上限 = 屏高 0.65（557pt），长正文（识别+翻译+要点）把末尾的 chips 推到滚动区外——恰是最需要点词的场景。
- **修复**：`ScreenshotCardBody` 中 chips 移到 `MarkdownView` **之前**（缩略图 → chips → 正文），构成首屏「看图→点词」完整入口。

### 缺陷 3（P1）：切卡后返回时面板高度塌到 120pt 下限
- **现象**：点 chip 进词卡再「返回整图」，面板停在 120pt 只剩标题栏，且此后 revision 不变、不自愈。
- **根因**：`resizeToContent` 在本轮 SwiftUI 布局完成前读 `fittingSize`，拿到上一张卡的中间值。
- **修复**：`resizeToContent` 拆出 `applyHeight(_:)`，并在 `DispatchQueue.main.async` 下一轮 runloop 复量一次收敛。

### 附带修复 4（P1）：图片窗开到屏幕外
- **现象**：`image window opened 900x300` 但窗口 frame 在 y=-988（完全不可见）。
- **根因**：`makeWindow` 的 `center()` 在本机多屏 + 副屏 visibleFrame 异常（高度 0）的布局下落到屏外。
- **修复**：`showImage` 每次开窗按 `NSScreen.main.visibleFrame` 显式居中（并记入日志 `frame=` 便于诊断）。

## 三、验收方法说明

- 面板为 nonactivating NSPanel，AppleScript `click at` 不产生 `SpatialTapGesture` 所需的完整事件序列，故用 CGEvent 构造真实 mouseDown/mouseUp（`/tmp/realclick`）。
- 取证用 `CGWindowList` 枚举 + 按 bounds 区域截屏（`screencapture -R`），避免全屏截图激活其他 app 触发外点隐藏面板。
- demo 通道 `-demo-image <文本> -pin -panel-at x,y`：`value("-demo-image")` 会取下一个参数，**必须显式传文本**否则会吞掉紧随的 flag（既有 demo 通道行为，非本次缺陷）。

## 四、遗留与后续

- 面板记忆位置（`panel.customTopX/Y`）优先于 `-panel-at`，验收前需清 defaults；属既有设计（尊重用户拖放位置）。
- 未覆盖：方案 C 的「多候选则列出」需要模型在词间空白处被点击才会触发，本轮未构造该场景；历史回放卡的就地点词路径（200px 缩略图）未在实机点击验证，仅有断言锁定分流逻辑。

---

## 复审修复轮（2026-09-29 晚，独立复审后）

复审报告：`docs/reviews/L2-review-acceptance-fixes-20260929.md`（0 P0 / 2 P1 / 3 P2；裁决「需再修」）。全部处置：

| # | 问题 | 修复 | 来源 |
|---|---|---|---|
| C1 | **截图卡 chips 双份渲染**：前移 chips 时残留原行，`:186` 与 `:183` 各渲染一次（第二份在滚动区底部，验收截图只拍首屏故结构上漏检） | 删残留行 | 复审 P1-1 |
| C2 | **竞速吞掉快速失败及时性**：`waitForTimeout` 单次睡满剩余时长，`finish()` 打不断，断网/401/重试尽的错误要等计时器自然醒才上卡（最长 20s 假 loading，是相对修复前的回归；harness 实证 limit=2s 时错误 t=0.5s 要到 t=2.02s 才 catch） | 睡眠切片化（`finishPollInterval` = 0.25s）+ 新增 `guard.monitor.finishInterruptsLongSleep` / `pollIntervalSane` 断言 | 复审 P1-2 |
| C3 | **超时边界 done 被盖成 failed**：超时与正常收尾撞在同一瞬间时 consume 已置 `.done` 并落缓存，再盖 `.failed` 让用户看到「失败」却查得到结果（边界注入 300 次 298 复现） | catch 内加 `if card.phase == .done { return }` 守卫 | 复审 P2-1 |
| C4 | **锚点漂移**：文档「91 项断言」vs 实测 94（现 96） | README/README_EN/tech-design/website 四处统一 96 | 复审 P2-2 |
| C5 | `tech-design` §4.2 把运行时守卫写作 `VisibleIdleGuard`，实为流外 `VisibleIdleMonitor` 且未写「流外/切片」两个前提 | 补正称谓与前提 | 复审 P2-2 |
| C6 | **图片窗只认 `NSScreen.main`** | 改跟鼠标所在屏（与面板定位惯例一致）+ 屏比窗口矮时按 visibleFrame 收缩内容尺寸 | 复审 P2-3 |
| — | 复审 P2-2 中「5 处代码注释章节号指错」 | **核对后不成立**：注释里的 `§4.3/§4.4/§4.5` 指的是**方案文档**（B2 规格/坐标换算/改动清单）而非 tech-design，编号属实，未改 | 主 Agent 复核 |

修复后：SelfCheck **96/96 全绿**（连跑 3 次稳定）、xcodebuild 0 error。P1-1 属本次实施引入的回归（C1），已由复审捕获并修复。
