#!/bin/bash
# Gloss 规范构建：一次构建同时产出「本机安装包」与「GitHub 发布 zip」（同一产物、同一签名）。
# 用法: scripts/release.sh [版本号]
#   版本号缺省时从构建产物 Info.plist 的 CFBundleShortVersionString 读取（与 pbxproj MARKETING_VERSION 同步）。
# 产物:
#   build/Gloss.app              本机安装（TCC 授权锚定 Apple Development 证书，重建不失效）
#   dist/Gloss-vX.Y.Z.zip        发布包（ditto 打包，保留签名与元数据）
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Gloss"
BUILD_DIR="build"
DIST_DIR="dist"
VERSION_OVERRIDE="${1:-}"

echo "==> 构建 Release（Apple Development 签名）"
xcodebuild -quiet -project Gloss.xcodeproj -scheme Gloss -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  build

SRC_APP="$BUILD_DIR/Build/Products/Release/Gloss.app"
VERSION="$VERSION_OVERRIDE"
if [ -z "$VERSION" ]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$SRC_APP/Contents/Info.plist")"
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

echo "==> 刷新本机安装 $BUILD_DIR/$APP_NAME.app"
rm -rf "$BUILD_DIR/$APP_NAME.app"
cp -R "$SRC_APP" "$BUILD_DIR/$APP_NAME.app"

echo "==> 打发布 zip → $DIST_DIR/$APP_NAME-v$VERSION.zip"
mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/$APP_NAME-v$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$SRC_APP" "$DIST_DIR/$APP_NAME-v$VERSION.zip"

ls -lh "$DIST_DIR/$APP_NAME-v$VERSION.zip"
echo "==> 完成（v${VERSION}）。若 Gloss 正在运行，重启 App 后新版生效。"
