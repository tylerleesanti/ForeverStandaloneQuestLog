# Draws the dark theme's close button: a thin white "x" (16x16, transparent), tinted in game.
# Usage: python make_close_icon.py ../Media/close.tga [preview.png]
import sys
import numpy as np
from PIL import Image

N, SS = 16, 16
H = N * SS
ys, xs = np.mgrid[0:H, 0:H]
x = (xs + 0.5) / SS
y = (ys + 0.5) / SS

A, B, HALF_T = 4.0, 12.0, 0.85     # the strokes run from (A, A) to (B, B) and (A, B) to (B, A)

def seg_dist(x0, y0, x1, y1):
    dx, dy = x1 - x0, y1 - y0
    t = np.clip(((x - x0) * dx + (y - y0) * dy) / (dx * dx + dy * dy), 0, 1)
    return np.hypot(x - (x0 + t * dx), y - (y0 + t * dy))

d = np.minimum(seg_dist(A, A, B, B), seg_dist(A, B, B, A))
alpha = (d <= HALF_T).astype(float).reshape(N, SS, N, SS).mean(axis=(1, 3))
out = np.zeros((N, N, 4), np.uint8)
out[..., :3] = 255
out[..., 3] = (alpha * 255 + 0.5).astype(np.uint8)
im = Image.fromarray(out, "RGBA")
im.save(sys.argv[1])
if len(sys.argv) > 2:
    bg = Image.new("RGBA", (N, N), (20, 20, 22, 255))
    Image.alpha_composite(bg, im).resize((N * 12, N * 12), Image.NEAREST).save(sys.argv[2])
print("ok")
