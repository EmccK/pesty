#!/bin/bash
# $1 = 逻辑 x，$2 = 逻辑 y（卡片中心）
X=$1; Y=$2
screencapture -x -o /tmp/lat_before.png
/tmp/click $X $Y >/dev/null
# 点击后立刻连拍
for i in 1 2 3 4 5 6; do
  screencapture -x -o /tmp/lat_$i.png
done
echo done
