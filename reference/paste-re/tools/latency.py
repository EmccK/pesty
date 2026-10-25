import subprocess, time, sys
from PIL import Image

def band_starts(path='/tmp/lat.png'):
    im = Image.open(path).convert('RGB'); w,h = im.size; px = im.load()
    row = 2350
    runs=[]; inrun=False
    for x in range(w):
        r,g,b = px[x,row]
        blue = b>180 and g>120 and r<140
        if blue and not inrun: start=x; inrun=True
        elif not blue and inrun: runs.append((start,x)); inrun=False
    if inrun: runs.append((start,w))
    return [r for r in runs if r[1]-r[0]>50]

def selection_ring_x(path='/tmp/lat.png'):
    """找选中环（更亮的蓝、在外沿）——用最左卡片外环的颜色判断"""
    im = Image.open(path).convert('RGB'); px = im.load()
    # 选中环在卡片外侧，取标题带左侧偏移 -6px 的像素
    return None

# 基准：记录当前选中卡位置（用左边缘 x 是否变化 + 卡片内容）
print("baseline bands:", len(band_starts()))
