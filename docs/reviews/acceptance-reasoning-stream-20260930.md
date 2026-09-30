# 实机验收报告：思考流展示 + 两级超时（2026-09-30）

- 环境：外接 4K + 内置屏，Debug 构建（DerivedData），MiniMax-M3 真实 Key（Keychain 命中），真实网络请求
- 驱动：`docs/reviews/acceptance-reasoning-run.sh`（⌥S 系统截图 + CGEvent 合成拖拽/点击 + 窗口区域截屏）
- 结论：**全部通过**——思考流实时可见、长思考不再误杀、正文到达即收起、chips/点词/词查询三路径无回归；额外实证方案 C 多候选降级在真机触发

## 一、判定与证据

### 场景 A：密集页 ⌥S（用户痛点同源场景）
- 4 段 LLM 技术文本（268 词）框选截图 → `screenshotExplain` 15.6s 完成（2976 字符），**无空闲超时**
- `acc-think-early.png`：骨架屏 + **「思考中 · 0s」秒表** + 尾部滚动区实时显示思考（"Looking at the image, I can see three paragraphs of text about LLM training…"）
- `acc-think-late-content.png`：正文到达后思考区**按设计收起**，「识别内容」流式转写中
- `acc-chips-result.png`：终态卡 6 条难词 chips 首屏可见（over-parameterized / pairwise human preferences / hallucination / token / vector database / reranking，各带音标+图中义+朗读钮）
- **面板高度 528→1114**（两帧对比）：L2a P1-1 修复（首条思考 delta bump revision）实机生效——预览区落在可视区内

### 场景 B：图片窗内点词（旧口径误杀临界场景）
- 缩略图点击 → 放大窗（`image window opened 801x451`，定位正确）→ 窗内点词 → `screenshotWordAt` **思考 18.5s 正常完成**（714 字符）——旧「20s 无正文即超时」口径下这正是临界/必杀场景
- `acc-wordat-thinking.png`：「思考中 · 4s」+ 尾部显示**视觉定位的推理过程**（"Let me look at what's at 50% horizontal in the third paragraph. The text reads approximately: 'embedding quality, and reranking dominate end-to-end accuracy.'"）——用户第一次能看到模型在"找哪个词"
- **额外收获**：该点击落在多词交界，方案 C 的「多候选诚实降级」真机触发——`acc-wordat-candidates.png` 显示列出 reranking / dominate / end-to-end 三个候选词（各带美英音标、词性、释义、搭配）而非编造（下钻方案验收标准 7 的旁证）

### 场景 C：词查询回归
- `acc-word-regression.png`：quixotic 词卡完整（语境义/词性/搭配/例句），无思考区残留

### 系统日志（全程）
```
query begin kind=screenshotExplain → done（15.6s，2976 chars）——无 idle timeout
image window opened 801x451 frame=(235.0, 112.0, ...)  ——开窗定位正确
query begin kind=screenshotWordAt → done（18.5s，714 chars）——无 idle timeout（旧口径临界）
query begin kind=word → done（728 chars）
```
**grep 全程日志 0 条 `idle timeout`**——长思考误杀已消除。

## 二、优化目标逐条核验

| 目标（批准方案） | 结果 | 证据 |
|---|---|---|
| 清晰看到进展（思考流展示） | ✅ | 秒表 + 尾部滚动实时更新（场景 A/B 两段视频级截图对） |
| 解决频繁超时（长思考不再误杀） | ✅ | 18.5s 思考点词正常完成；全程 0 次 idle timeout |
| 两级超时语义（20s 无事件 / 90s 纯思考） | ✅（断言层） | SelfCheck `zeroEventTimesOutWithReason` / `reasoningPreventsNoEventButThinkingExpires`；90s 死循环不可实跑，缩比断言覆盖 |
| 正文到达即收起、不入缓存历史 | ✅ | `acc-think-late-content.png` 无思考区；缓存/历史只落正文（代码路径 + L2a/K3 核验） |
| 既有功能无回归 | ✅ | chips（6 条首屏）/ 放大窗 / 点词 / 词查询 / 多候选降级全部正常 |

## 三、验收方法与脚本

- `acceptance-reasoning-run.sh` 已入库：预检亮屏（合盖黑屏自动拦截）→ 场景 A/B/C → 日志取证 → 自动判定 PASS/FAIL。原判定「词查询失败」为日志窗口截早（done 在快照后 10s 落盘），人工复核为完成。
- 面板为 nonactivating NSPanel，AppleScript click 不触发 SpatialTapGesture，故用 CGEvent 真实事件序列（realclick/realdrag/hotkey）；截图按 CGWindowList bounds 区域截取。

## 四、遗留

- 90s 纯思考死循环的实机复现不可行（需 90s+ 真实等待且无法稳定构造），由缩比断言（0.6s 口径）+ 双向变异闭合覆盖。
- ⌥D 划词通道未单独回归（demo 通道覆盖同一 runText 路径）。
