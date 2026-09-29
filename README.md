# Gloss · 划词即释

[English](README_EN.md) | 简体中文

**Mac 系统级英文阅读助手**：选中即查、截图即问、长文精读——由你自己的大模型 API Key 驱动（默认 MiniMax M3，支持任意 OpenAI 兼容端点）。

<p align="center">
  <img src="docs/screenshots/screenshot-reading.png" width="880" alt="⌥S 截图即问：框选英文文档区域，读图翻译+术语解释">
  <br>
  <img src="docs/screenshots/word-card.png" width="420" alt="划词词卡">
</p>

<p align="center">
  <b>🌐 <a href="https://wbkais95q5wg3.space.mcode.cn">官网 · 划词即释</a></b><br>
  <sub>交互式功能演示 · 实机截图 · 图文使用说明 — 上面看不到的交互效果，官网里都能直接上手试</sub>
</p>

## 为什么做它

读英文文档时，遇到不认识的词要切去词典网站、遇到拿不准的长句要复制去问 ChatBot、看到图片里的英文要拍照发多模态模型——每一条都是 5 步以上的操作，打断阅读心流。Gloss 把这些收敛成**一个动作**：选中按 ⌥D，或框一块屏幕按 ⌥S。

## 功能

- **⌥D 划词即查**：选中即弹不抢焦点的浮窗。单词/短语/句子/段落自动路由：
  - 单词卡：美英音标、**结合上下文的语境义**、搭配、双语例句、词源辨析
  - 句子卡：忠实翻译 + 主干/从句结构拆解 + 句中难词（点击词条继续查）
  - 段落卡：对照翻译 + 难词表
- **⌥S 截图即问**：框选屏幕任意区域（图片、图表、视频画面、不可选中的界面），直接发给多模态模型读图解释；**在卡片缩略图上点某个单词**可继续查该词
- **长文精读**：选中 ≥400 词自动进入精读窗——分批全文翻译、生词表（音标/文中义/原文例句）、专业术语表、文章逻辑解读
- **朗读**：系统离线 TTS，美音/英音切换，词/句/识别文本均可朗读
- **生词沉淀**：查询历史回放；响应缓存（重复查询零成本零延迟）
- **多配置**：支持多套模型配置切换，兼容任意 OpenAI 兼容端点（MiniMax / OpenAI / DeepSeek / 智谱 / Kimi / 本地 Ollama…）

## 下载

从 [Releases](../../releases) 下载最新的 `Gloss-vX.Y.Z.zip`，解压得到 `Gloss.app`。

> 不想看命令行？[官网](https://wbkais95q5wg3.space.mcode.cn) 有四个能真上手点的交互演示、首次打开被 Gatekeeper 拦截的放行步骤，以及三步上手流程。

**自动更新**：v0.1.3 起 App 内置更新检查（基于 [Sparkle](https://sparkle-project.org)，更新包经 EdDSA 签名校验）。两个检查入口：**菜单栏图标 →「检查更新…」** 与 **设置 → 高级 →「检查更新…」**（高级页同时显示当前版本号、上次检查时间与自动检查开关，v0.1.4 起提供）。第二次启动会询问是否允许后台定期检查，允许后自动发现新版本弹出更新说明，点击即可下载安装并重启，无需再手动下载。

> v0.1.2 及更早版本无内置更新，请手动下载 v0.1.3 一次，之后即可自动更新。

> **首次打开**：App 使用 Apple Development 证书签名（未经过 Apple 公证），macOS 会拦截首次启动，任选其一放行：
> - **系统设置 → 隐私与安全性**，找到关于 Gloss 的提示，点「**仍要打开**」（macOS 15+ 推荐方式）；
> - 或在终端执行：
> ```bash
> xattr -cr /path/to/Gloss.app
> ```
>
> macOS 14 也可右键 App → 打开。

**系统要求**：macOS 14（Sonoma）及以上；**Apple Silicon（M 系列）与 Intel 都支持**。安装包是同时含两种架构的通用二进制，两种机器用同一个 zip，不需要分别下载，Intel 端也不需要装 Rosetta。

> Intel 机型需要能装 macOS 14，即 Apple 官方的 Sonoma 支持清单：MacBook Pro 2018 起（15″ 2018、13″ 2018 四雷雳口）、MacBook Air 2018 起、Mac mini 2018、iMac 2019 起、iMac Pro 2017、Mac Pro 2019。如果你的机器停在 macOS 13（Ventura）或更早（如 2017 款 MacBook Pro / MacBook / iMac），本 App 暂不支持——原因见 [DESIGN.md](docs/DESIGN.md) D10。

## 快速开始

1. 启动 Gloss（菜单栏常驻，无 Dock 图标），跟随首启向导
2. 在「配置模型」页选择 **MiniMax** 预设，粘贴你的 [MiniMax API Key](https://platform.minimaxi.com)，点「测试连接」验证
   - 也可以选其他预设或「自定义」，直接填写任意 OpenAI 兼容端点的 BaseURL / 路径 / 模型名
3. 完成。之后在任意 App 里选中英文按 **⌥D** 即可

### 三个触发通道

| 通道 | 操作 | 权限 |
|---|---|---|
| 右键服务 | 选中文本 → 右键 → 服务 →「Gloss 查词」 | 无 |
| 划词快捷键 | 选中文本 → **⌥D** | 辅助功能 |
| 截图快捷键 | **⌥S** → 框选屏幕区域 | 屏幕录制 |

> ⚠️ **右键服务找不到「Gloss 查词」？** macOS 对新装的第三方服务默认禁用。到 系统设置 → 键盘 → 键盘快捷键 → 服务快捷键 → 文本，勾选「Gloss 查词」即可（一次性）。
>
> ⌥D / ⌥S 首次使用会弹出系统权限请求，允许后即可。若之前卸载重装过 App 导致权限失效，重新在 系统设置 → 隐私与安全性 里关开对应开关即可。

## 隐私

- API Key 仅保存在本机钥匙串，任何日志/缓存/历史中不落明文
- 查询内容只发送给你自己配置的模型服务商
- 无遥测、无崩溃上报、无任何第三方数据收集

## 从源码构建

```bash
git clone https://github.com/<you>/gloss.git
cd gloss
open Gloss.xcodeproj   # Xcode 16+，直接 Cmd+R 运行
```

- 系统框架为主（AppKit / SwiftUI / SwiftData / PDFKit / AVFoundation / Carbon / Vision-free），唯一第三方依赖为 [Sparkle](https://github.com/sparkle-project/Sparkle) 2.10+（更新框架，SPM 拉取）
- 逻辑自检：`SelfCheck/main.swift` 与核心纯逻辑文件联合编译即可运行（路由/SSE/分节提取/缓存键/图像管线共 68 项断言）
- 签名：使用 Xcode 自动签名或本地自签证书均可；功能不依赖特定签名。**注意**：自动更新链锚定发布方的 EdDSA 密钥对——自编译版本会正常接受官方更新包并覆盖本地产物，请按需忽略更新提示或从 Releases 手动安装；发布方更换/丢失 EdDSA 私钥才会使老用户的自动更新断链
- 规范打包发布：`scripts/release.sh` 一条命令完成 Release 构建 → 签名验证 → ditto 打 zip → 生成 Sparkle 更新描述（`dist/appcast.xml`，`sign_update` EdDSA 签名，自动剥离 markdown 标记）；加 `--publish` 再创建 GitHub Release 并上传 zip 与 appcast，App 端即收到更新提醒
- 发版流程：版本号唯一来源是 pbxproj 的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`（Info.plist 经 `$(VAR)` 注入），两者**同步递增**后跑 `--publish` 即可；脚本内置三道发布闸——工作区须干净且已推送、build 号须大于线上 latest、重复发布拦截
- 更新签名密钥：`generate_keys` 生成的 EdDSA 私钥保存在登录钥匙串，**务必另存备份**（`generate_keys -x <文件>`）；私钥丢失后无法再向老用户推送自动更新

## 技术要点

- **取词**：Accessibility API 优先（含选区 bounds 与上下文提取），模拟 ⌘C 读剪贴板兜底，两通道自动降级
- **SSE 流式**：逐字节分行保留空行（`URLSession.bytes.lines` 会吞 SSE 事件分隔符——实测踩坑），支持 `reasoning_content` 与内联 `<think>` 两种思考形态，429/5xx 指数退避重试
- **多模态**：截图按长边 1568px 压缩为 JPEG 后以 `image_url` dataURL 发送
- **缓存**：键 = sha256(归一化输入 | 类型 | 参数 | 模型 | Prompt 版本)，LRU + SwiftData 持久化；截图点词查询的坐标量化到 1% 网格参与键计算
- **自动更新**：Sparkle 2 + GitHub Releases 静态 appcast（`releases/latest/download/appcast.xml`，GitHub 固定 302 到最新 Release 资产，**零自建后端**）；更新包经 EdDSA 签名校验（公钥内置于 Info.plist，私钥在发布方钥匙串）；菜单栏与设置页共用同一个 updater 实例（`UpdaterCenter`）
- **浮窗**：nonactivating NSPanel，不抢键盘焦点，全屏/多屏可用；ESC 为消费式全局热键随面板显隐装拆

## 文档

- [DESIGN.md](docs/DESIGN.md) — 决策记录与文档索引
- [product-design.md](docs/product-design.md) — 产品与交互设计（场景走查 / 卡片规格 / 状态表）
- [tech-design.md](docs/tech-design.md) — 技术方案（架构 / 数据流 / Prompt 全文 / 任务拆解）
- [reviews/](docs/reviews/) — 三阶段独立审查的完整记录（方案审 → 代码审 → 终审）

## License

[MIT](LICENSE)
