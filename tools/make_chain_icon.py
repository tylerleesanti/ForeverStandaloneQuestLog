# Draws a two-link chain icon (32x32, transparent) as a TGA for the add-on, plus a big PNG preview.
import sys, math
import numpy as np
from PIL import Image

N, SS = 32, 8                      # size, supersampling
H = N * SS
ys, xs = np.mgrid[0:H, 0:H]
x = (xs + 0.5) / SS
y = (ys + 0.5) / SS

def capsule_dist(cx, cy, angle, half_len, r):
    # distance from the ring's centre line (a stadium of half length half_len and radius r)
    dx, dy = math.cos(angle), math.sin(angle)
    px, py = x - cx, y - cy
    t = np.clip(px * dx + py * dy, -half_len, half_len)
    qx, qy = px - t * dx, py - t * dy
    return np.abs(np.hypot(qx, qy) - r)

ang = -math.pi / 4                 # links run bottom-left to top-right
links = [(11.2, 20.8), (20.8, 11.2)]
HALF, R, T, O = 4.2, 4.4, 1.35, 1.25  # half length, radius, metal half-thickness, outline width

rgba = np.zeros((H, H, 4))
for i, (cx, cy) in enumerate(links):
    d = capsule_dist(cx, cy, ang + (0 if i == 0 else 0), HALF, R)
    outline = d < T + O
    metal = d < T
    # simple shading: lighter towards the top-left
    shade = 0.78 + 0.22 * np.clip(((-(x - cx) - (y - cy)) / 10), -1, 1)
    col = np.stack([0.86 * shade, 0.87 * shade, 0.92 * shade], -1)
    layer = np.zeros((H, H, 4))
    layer[outline] = [0.05, 0.04, 0.03, 1]
    layer[metal, :3] = col[metal]
    layer[metal, 3] = 1
    # second link drawn over the first, so they look interlocked at the top crossing only
    if i == 1:
        cross = (x + y < 32.0)     # where link 2 should pass *behind* link 1
        keep = ~(cross & (rgba[..., 3] > 0))
        layer[~keep] = 0
    a = layer[..., 3:4]
    rgba[..., :3] = layer[..., :3] * a + rgba[..., :3] * (1 - a)
    rgba[..., 3:4] = a + rgba[..., 3:4] * (1 - a)

img = rgba.reshape(N, SS, N, SS, 4).mean(axis=(1, 3))
# un-premultiply colour for the averaged pixels
alpha = img[..., 3:4]
img[..., :3] = np.where(alpha > 0, img[..., :3] / np.maximum(alpha, 1e-6) * 1.0, 0)
out = (np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)
im = Image.fromarray(out, "RGBA")
im.save(sys.argv[1])               # .tga (Pillow writes uncompressed 32-bit with alpha)
bg = Image.new("RGBA", (N, N), (60, 40, 20, 255))
prev = Image.alpha_composite(bg, im).resize((N * 8, N * 8), Image.NEAREST)
prev.save(sys.argv[2])
print("ok")
