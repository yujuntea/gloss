#!/bin/bash
# Gloss 规范构建与发布：一次构建同时产出「本机安装包」「GitHub 发布 zip」与「Sparkle 更新 appcast」。
# 用法:
#   scripts/release.sh               # 构建 + 打 zip + 生成 dist/appcast.xml（不发布）
#   scripts/release.sh --publish     # 上述全部 + 创建 GitHub Release 并上传 zip 与 appcast
#   scripts/release.sh <版本号>      # 校验参数与构建产物版本一致（防 zip 名与 app 内版本错位）
# 版本号唯一来源: pbxproj 的 MARKETING_VERSION / CURRENT_PROJECT_VERSION（Info.plist 经 $(VAR) 注入）。
# 可选: dist/notes-v<版本>.md 存在时作为 release notes（GitHub Release 正文 + appcast 描述）。
# Sparkle 密钥: 默认读登录 Keychain（generate_keys 生成）；CI 可用 GLOSS_SPARKLE_KEY_FILE 指定私钥文件。
# 产物:
#   build/Gloss.app              本机安装（TCC 授权锚定 Apple Development 证书，重建不失效）
#   dist/Gloss-vX.Y.Z.zip        发布包（ditto 打包，保留签名与元数据）
#   dist/appcast.xml             Sparkle 更新描述（App 通过 /releases/latest/download/appcast.xml 获取）
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Gloss"
BUILD_DIR="build"
DIST_DIR="dist"
REPO_SLUG="yujuntea/gloss"
PUBLISH=0
VERSION_OVERRIDE=""

for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH=1 ;;
    v[0-9]*|[0-9]*)
      if [[ "$arg" =~ ^v?[0-9]+(\.[0-9]+)+$ ]]; then
        VERSION_OVERRIDE="${arg#v}"
      else
        echo "未知参数: ${arg}（版本号形如 0.1.4 / v0.1.4）" >&2; exit 2
      fi ;;
    *) echo "未知参数: ${arg}（用法见脚本头部）" >&2; exit 2 ;;
  esac
done

echo "==> 构建 Release（Apple Development 签名）"
xcodebuild -quiet -project Gloss.xcodeproj -scheme Gloss -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  build

SRC_APP="$BUILD_DIR/Build/Products/Release/Gloss.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$SRC_APP/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$SRC_APP/Contents/Info.plist")"
# Sparkle 只按 build 号判新,非数字 build 号会让后续递增校验 fail-open(bash [ -le ] 对非数字退出码 2 按假处理),此处硬拦
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "错误: CFBundleVersion 非数字: '$BUILD_NUMBER'(pbxproj CURRENT_PROJECT_VERSION)" >&2; exit 1; }
if [ -n "$VERSION_OVERRIDE" ] && [ "$VERSION_OVERRIDE" != "$VERSION" ]; then
  echo "错误: 参数版本 $VERSION_OVERRIDE 与构建产物版本 $VERSION 不一致（版本号以 pbxproj MARKETING_VERSION 为准）" >&2
  exit 1
fi

echo "==> 验证签名"
codesign -v --deep "$SRC_APP"
# 坑1（2026-09-26 实证）：codesign -dv 不显示 Authority= 行，必须 -dvvv——verbose 不够时误以为证书链没嵌入。
# 坑2：set -o pipefail 下 `codesign | grep -q` 会因 grep 匹配即退、上游 SIGPIPE(141) 而误判失败——
#       必须先命令替换取全输出再 grep。证书链是 TCC 锚定授权的前提，硬校验防静默降级。
CS_INFO="$(codesign -dvvv "$SRC_APP" 2>&1 || true)"
if ! echo "$CS_INFO" | grep -q "Authority="; then
  echo "错误：签名未嵌入证书链（codesign -dvvv 无 Authority= 行），拒绝出包" >&2
  exit 1
fi
echo "$CS_INFO" | grep -E "Authority=|TeamIdentifier=" | head -4

# 未公证 app 的 Gatekeeper 评估预期为 rejected（下载者走「系统设置→仍要打开」或 xattr 放行），非失败信号
echo "==> Gatekeeper 评估（未公证预期 rejected，属正常）"
spctl -a -t exec -vv "$SRC_APP" || true

echo "==> 校验 Sparkle 配置（防 Info.plist 残留占位符/空公钥出包）"
SPARKLE_FEED="$(/usr/libexec/PlistBuddy -c 'Print SUFeedURL' "$SRC_APP/Contents/Info.plist" 2>/dev/null || true)"
SPARKLE_PUBKEY="$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$SRC_APP/Contents/Info.plist" 2>/dev/null || true)"
case "$SPARKLE_FEED" in ""|\$*|*__*|http://127.0.0.1*|http://localhost*)
  echo "错误: 构建产物 SUFeedURL 异常: '$SPARKLE_FEED'" >&2; exit 1 ;;
esac
case "$SPARKLE_PUBKEY" in ""|*__*) echo "错误: 构建产物 SUPublicEDKey 为空或占位符" >&2; exit 1 ;; esac
echo "  SUFeedURL = $SPARKLE_FEED"

echo "==> 刷新本机安装 $BUILD_DIR/$APP_NAME.app"
rm -rf "$BUILD_DIR/$APP_NAME.app"
cp -R "$SRC_APP" "$BUILD_DIR/$APP_NAME.app"

ZIP_PATH="$DIST_DIR/$APP_NAME-v$VERSION.zip"
echo "==> 打发布 zip → $ZIP_PATH"
mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$SRC_APP" "$ZIP_PATH"

echo "==> 生成 Sparkle 更新签名与 appcast"
SIGN_UPDATE=""
for c in "$BUILD_DIR/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update" ".tools/sign_update"; do
  if [ -x "$c" ]; then SIGN_UPDATE="$c"; break; fi
done
if [ -z "$SIGN_UPDATE" ]; then
  echo "错误: 找不到 sign_update（先完整构建一次以拉取 Sparkle 工件，或把工具放入 .tools/）" >&2
  exit 1
fi
# CI/无 Keychain 场景可用 GLOSS_SPARKLE_KEY_FILE=<私钥文件路径> 代替 Keychain
if [ -n "${GLOSS_SPARKLE_KEY_FILE:-}" ]; then
  SIGN_OUT="$("$SIGN_UPDATE" --ed-key-file "$GLOSS_SPARKLE_KEY_FILE" "$ZIP_PATH")"
else
  SIGN_OUT="$("$SIGN_UPDATE" "$ZIP_PATH")"
fi
# 兼容两种输出:2.x 实测输出 length=（无前缀），旧版/未来版可能输出 sparkle:length=
ED_SIG="$(printf '%s' "$SIGN_OUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
ZIP_LEN="$(printf '%s' "$SIGN_OUT" | sed -n 's/.*[[:space:]]\(sparkle:\)\{0,1\}length="\([0-9]*\)".*/\2/p')"
if [ -z "$ED_SIG" ] || [ -z "$ZIP_LEN" ]; then
  echo "错误: 解析 sign_update 输出失败: $SIGN_OUT" >&2
  exit 1
fi

DOWNLOAD_URL="https://github.com/$REPO_SLUG/releases/download/v$VERSION/$(basename "$ZIP_PATH")"
RELEASES_URL="https://github.com/$REPO_SLUG/releases/tag/v$VERSION"
MIN_MACOS="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$SRC_APP/Contents/Info.plist")"
PUB_DATE="$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S %z")"

# release notes: dist/notes-v<版本>.md 存在则转 CDATA 内嵌（XML 转义 + 换行转 <br/>），否则只留发布页链接
NOTES_FILE="$DIST_DIR/notes-v$VERSION.md"
NOTES_HTML=""
if [ -f "$NOTES_FILE" ]; then
  NOTES_HTML="$(python3 -c '
import html, sys
with open(sys.argv[1], encoding="utf-8") as f:
    text = f.read()
print(html.escape(text).replace("\n", "<br/>\n"))
' "$NOTES_FILE")"
else
  NOTES_HTML="变更详情见 <a href=\"$RELEASES_URL\">GitHub Releases</a>"
fi

cat > "$DIST_DIR/appcast.xml" <<EOF
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0">
    <channel>
        <title>Gloss</title>
        <link>https://github.com/$REPO_SLUG</link>
        <description>Gloss — 划词即释的英文阅读助手</description>
        <language>zh-cn</language>
        <item>
            <title>Version $VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$BUILD_NUMBER</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$MIN_MACOS</sparkle:minimumSystemVersion>
            <description><![CDATA[$NOTES_HTML]]></description>
            <enclosure url="$DOWNLOAD_URL" sparkle:edSignature="$ED_SIG" length="$ZIP_LEN" type="application/octet-stream"/>
        </item>
    </channel>
</rss>
EOF

ls -lh "$ZIP_PATH" "$DIST_DIR/appcast.xml"
echo "==> 本地产物完成（v${VERSION} build ${BUILD_NUMBER}）"

if [ "$PUBLISH" = "1" ]; then
  echo "==> 发布 GitHub Release v$VERSION"
  # 发布闸 1:工作区必须干净且已推送——tag 锚定远端 HEAD,否则 Release 页源码与 zip 内容错位
  if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet HEAD 2>/dev/null; then
    echo "错误: 工作区有未提交变更,Release tag 将锚定远端旧 HEAD 导致源码与产物错位。请先 commit + push 再发布" >&2
    exit 1
  fi
  if [ -n "$(git rev-parse @{u} 2>/dev/null)" ] && [ "$(git rev-parse HEAD)" != "$(git rev-parse @{u} 2>/dev/null)" ]; then
    echo "错误: 本地 HEAD 未推送到远端,tag 将建在旧提交上。请先 git push" >&2
    exit 1
  fi
  # 发布闸 2:build 号必须比线上 latest 递增——Sparkle 只按 sparkle:version(build 号)判新,
  # 只 bump 版本号忘 bump build 号会发布成功但全体用户静默收不到更新。
  # 注:本校验假设 appcast 单 item(当前 release.sh 每次全量重写,天然满足)
  LATEST_BUILD="$(curl -sL --max-time 20 "$SPARKLE_FEED" | sed -n 's/.*<sparkle:version>\([0-9]*\)<\/sparkle:version>.*/\1/p' | head -1 || true)"
  if [ -n "$LATEST_BUILD" ]; then
    if [ "$BUILD_NUMBER" -le "$LATEST_BUILD" ]; then
      echo "错误: 线上 latest build 号为 $LATEST_BUILD，本次为 $BUILD_NUMBER——build 号未递增，发布后用户将收不到更新。请先在 pbxproj 提高 CURRENT_PROJECT_VERSION" >&2
      exit 1
    fi
    echo "  build 号校验通过: $LATEST_BUILD → $BUILD_NUMBER"
  else
    echo "警告: 无法获取线上 latest appcast（网络不稳或首个版本），跳过 build 号校验——请自行确认 CURRENT_PROJECT_VERSION 已递增" >&2
  fi
  if gh release view "v$VERSION" --repo "$REPO_SLUG" >/dev/null 2>&1; then
    echo "错误: Release v$VERSION 已存在，拒绝重复发布。如需重发：删除该 Release 后必须提高 CURRENT_PROJECT_VERSION 再发布（已装上旧 build 的用户只认更大的 build 号，同 build 号重发将使他们永久收不到修复版）" >&2
    exit 1
  fi
  NOTES_ARGS=(--notes "Gloss v$VERSION")
  if [ -f "$NOTES_FILE" ]; then NOTES_ARGS=(--notes-file "$NOTES_FILE"); fi
  gh release create "v$VERSION" "$ZIP_PATH" "$DIST_DIR/appcast.xml" \
    --repo "$REPO_SLUG" \
    --title "Gloss v$VERSION" \
    --latest \
    "${NOTES_ARGS[@]}"
  echo "==> 已发布。验证更新通道: curl -sIL https://github.com/$REPO_SLUG/releases/latest/download/appcast.xml"
else
  echo "==> 未发布（加 --publish 创建 GitHub Release 并上传 zip 与 appcast）"
fi
