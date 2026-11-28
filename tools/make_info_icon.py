# Draws the quest info icon (32x32, drawn at 64 and scaled down, transparent): a gold coin with a dark rim and a dark "i".
# Usage: python make_info_icon.py ../Media/info.tga [preview.png]
import sys
import numpy as np
from PIL import Image

N, SS = 64, 8                      # size, supersampling
H = N * SS
ys, xs = np.mgrid[0:H, 0:H]
x = (xs + 0.5) / SS
y = (ys + 0.5) / SS
cx = cy = N / 2

r = np.hypot(x - cx, y - cy)
R_OUT, RIM = 30.5, 3.2             # outer radius, dark rim width

def box(x0, y0, x1, y1, rad):
    # rounded rectangle mask
    qx = np.maximum(np.maximum(x0 + rad - x, x - (x1 - rad)), 0)
    qy = np.maximum(np.maximum(y0 + rad - y, y - (y1 - rad)), 0)
    return np.hypot(qx, qy) <= rad

rgba = np.zeros((H, H, 4))
disc = r <= R_OUT
rgba[disc] = [0.12, 0.07, 0.02, 1]                 # dark rim

face = r <= R_OUT - RIM
# gold face, lighter towards the top-left, a little darker at the bottom
t = np.clip(((x - cx) * 0.5 + (y - cy)) / (R_OUT * 1.4) + 0.5, 0, 1)
top = np.array([1.00, 0.88, 0.42])
bot = np.array([0.80, 0.52, 0.10])
col = top * (1 - t[..., None]) + bot * t[..., None]
rgba[face, :3] = col[face]
# thin bright inner edge for a bit of depth
inner = face & (r > R_OUT - RIM - 1.6) & (y < cy)
rgba[inner, :3] = np.minimum(rgba[inner, :3] + 0.12, 1)

# the "i": a dot and a stem with a small foot
dot = np.hypot(x - cx, y - 18.5) <= 4.4
stem = box(cx - 3.9, 26.5, cx + 3.9, 46.5, 1.2)
foot = box(cx - 7.5, 43.0, cx + 7.5, 47.5, 1.2)
cap = box(cx - 7.0, 26.5, cx, 30.5, 1.0)
glyph = (dot | stem | foot | cap) & face
rgba[glyph, :3] = [0.16, 0.09, 0.02]

img = rgba.reshape(N, SS, N, SS, 4)
a = img[..., 3:4]
prem = (img[..., :3] * a).mean(axis=(1, 3))
alpha = a.mean(axis=(1, 3))
colr = np.where(alpha > 0, prem / np.maximum(alpha, 1e-6), 0)
out = np.concatenate([colr, alpha], -1)
out = (np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)
im = Image.fromarray(out, "RGBA").resize((32, 32), Image.LANCZOS)  # shown at ~16-20 px in game
im.save(sys.argv[1])               # uncompressed 32-bit TGA with alpha
if len(sys.argv) > 2:
    bg = Image.new("RGBA", (32, 32), (200, 160, 90, 255))
    Image.alpha_composite(bg, im).resize((256, 256), Image.NEAREST).save(sys.argv[2])
print("ok")
