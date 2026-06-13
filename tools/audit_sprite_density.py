#!/usr/bin/env python3
"""Audit sprite pixel density. Usage: python3 tools/audit_sprite_density.py <png>..."""
import sys, os
from PIL import Image
import numpy as np


def native_block(im, maxf=16):
    a = np.asarray(im).astype(np.int32); w, h = im.size; best = 1
    for f in range(2, maxf + 1):
        if w % f or h % f:
            continue
        back = im.resize((w // f, h // f), Image.NEAREST).resize((w, h), Image.NEAREST)
        m = a[:, :, 3] > 16
        if m.sum() == 0:
            continue
        if np.abs(np.asarray(back).astype(np.int32) - a)[:, :, :3][m].mean() < 3.0:
            best = f
    return best


def content_bbox(im):
    a = np.asarray(im)
    ys, xs = np.where(a[:, :, 3] > 16)
    if len(xs) == 0:
        return (0, 0, im.size[0], im.size[1])
    return (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)


for p in sys.argv[1:]:
    im = Image.open(p).convert("RGBA")
    w, h = im.size
    f = native_block(im)
    bb = content_bbox(im)
    bw, bh = bb[2] - bb[0], bb[3] - bb[1]
    print(f"{os.path.basename(p):22s} canvas {w}x{h}  native-block={f}  body {bw}x{bh}px")
