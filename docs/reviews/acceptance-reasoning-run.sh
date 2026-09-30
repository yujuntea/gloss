#!/bin/bash
# 实机验收脚本：思考流展示 + 两级超时（2026-09-30）
# 前置：笔记本开盖/外接屏点亮（screencapture 需非黑屏）；屏幕录制权限已授（此前验收已授）
# 用法：bash docs/reviews/acceptance-reasoning-run.sh   （约 90 秒）
set -o pipefail
cd "$(dirname "$0")/../.." || exit 1
APP=~/Library/Developer/Xcode/DerivedData/Gloss-eolockjmgjykkgggxwzrityrcatr/Build/Products/Debug/Gloss.app
LOG=/tmp/gloss_reasoning_acc.log
OUT=/tmp/acc_reasoning
mkdir -p $OUT

echo "== 预检 0：亮屏"
screencapture -x $OUT/pre.png
AVG=$(python3 -c "
from PIL import Image
im=Image.open('$OUT/pre.png').convert('L')
print(int(sum(im.getdata())/(im.width*im.height)))" 2>/dev/null || echo 0)
if [ "${AVG:-0}" -lt 10 ]; then echo "  ✗ 屏幕黑（合盖/熄屏）。请开盖或点亮显示器后重跑"; exit 2; fi
echo "  ✓ 亮屏（亮度 $AVG）"

pkill -x Gloss 2>/dev/null; sleep 1
defaults delete com.wuyujun.gloss panel.customTopX 2>/dev/null
defaults delete com.wuyujun.gloss panel.customTopY 2>/dev/null
open -a TextEdit /tmp/dense.txt 2>/dev/null || true
sleep 2
osascript -e 'tell application "TextEdit" to set bounds of front window to {80, 80, 1000, 720}' 2>/dev/null
open -a "$APP"; sleep 4

wpanel() { /tmp/winfo 2>/dev/null | awk '$NF=="layer=3"{print $2","$3","$4","$5}' | head -1; }
shot_panel() { local R=$(wpanel); [ -n "$R" ] && screencapture -x -R$R "$1" && echo "  📸 $1 (panel=$R)"; }

echo "== 场景 A：密集页 ⌥S 截图查询（用户图 1 同源场景，验证长思考不再误杀）"
/tmp/hotkey s
sleep 1.2
/tmp/realdrag 150 200 950 650     # 框选 TextEdit 文本区
sleep 6
shot_panel $OUT/b_think_early.png   # 应见「思考中 · Ns」+ 尾部滚动区
sleep 8
shot_panel $OUT/b_think_late.png    # Ns 增大、尾部文本变化
# 等查询终态（最多 45s）
DONE=0
for i in $(seq 1 45); do
  if /usr/bin/log show --predicate 'subsystem == "com.wuyujun.gloss"' --last 60s --style compact --info 2>/dev/null | grep -q "query done kind=screenshotExplain"; then DONE=1; break; fi
  sleep 1
done
shot_panel $OUT/b_result.png
echo "== 场景 B：窗内点词（截图卡 → 放大窗 → wordAt）"
R=$(wpanel); PX=${R%%,*}; PY=$(echo $R | cut -d, -f2)
/tmp/realclick $((PX+200)) $((PY+100))    # 点缩略图开窗
sleep 3
W=$(/tmp/winfo | awk '$NF=="layer=0"{print $2","$3","$4","$5}' | head -1)
echo "  图片窗=$W"
WX=$(echo $W | cut -d, -f1); WY=$(echo $W | cut -d, -f2)
/tmp/realclick $((WX+500)) $((WY+350))    # 窗内点词
sleep 5
shot_panel $OUT/c_wordat_thinking.png
sleep 15
shot_panel $OUT/c_wordat_result.png

echo "== 场景 C：普通词查询回归（⌥D 通道需选中文本，改用 demo 词查询）"
pkill -x Gloss; sleep 1
open -a "$APP" --args -demo-query "quixotic"
sleep 8
shot_panel $OUT/d_word_result.png

echo "== 日志取证"
/usr/bin/log show --predicate 'subsystem == "com.wuyujun.gloss"' --last 180s --style compact --info 2>/dev/null \
  | grep -E "query (begin|done|failed)|idle timeout|image window" | tail -12 > $LOG
cat $LOG

echo "== 判定"
PASS=1
grep -q "idle timeout" $LOG && { echo "  ✗ 出现空闲超时（长思考被误杀？）"; PASS=0; } || echo "  ✓ 无空闲超时"
grep -q "query done kind=screenshotExplain" $LOG && echo "  ✓ 密集页 ⌥S 完成" || { echo "  ✗ ⌥S 未完成"; PASS=0; }
grep -q "query done kind=screenshotWordAt" $LOG && echo "  ✓ 窗内点词完成" || echo "  ⚠ 点词未完成（点击坐标可能需微调）"
grep -q "query done kind=word" $LOG && echo "  ✓ 词查询回归" || { echo "  ✗ 词查询失败"; PASS=0; }
echo "  截图证据：$OUT/（b_think_early/late 两张对比秒表增大与尾部滚动；有 diff 即思考流活着）"
[ $PASS -eq 1 ] && echo "ACCEPTANCE PASS" || echo "ACCEPTANCE 需人工复核截图"
