# Draws Forever Standalone Quest Log's square project logo with plain Python (no image libraries):
# an open two-page book (the two-pane window: a quest list with difficulty-coloured dots on the left
# page, quest text on the parchment on the right) with a gold "!" quest badge on its corner.
# All shapes are simple originals drawn from signed distance functions, not the game's art.
# Usage: python make_logo.py <output.png> [size]
import math, struct, sys, zlib

OUT = sys.argv[1] if len(sys.argv) > 1 else "logo.png"
SIZE = int(sys.argv[2]) if len(sys.argv) > 2 else 512
K = SIZE / 512.0  # everything below is laid out on a 512 grid


# ---------------------------------------------------------------- shapes (distance < 0 inside)
def sd_rrect(px, py, cx, cy, hx, hy, r):
    qx = abs(px - cx) - hx + r
    qy = abs(py - cy) - hy + r
    return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - r


def sd_circle(px, py, cx, cy, r):
    return math.hypot(px - cx, py - cy) - r


def sd_poly(px, py, pts):
    d = (px - pts[0][0]) ** 2 + (py - pts[0][1]) ** 2
    s = 1
    j = len(pts) - 1
    for i in range(len(pts)):
        ex, ey = pts[j][0] - pts[i][0], pts[j][1] - pts[i][1]
        wx, wy = px - pts[i][0], py - pts[i][1]
        t = max(0.0, min(1.0, (wx * ex + wy * ey) / (ex * ex + ey * ey)))
        bx, by = wx - ex * t, wy - ey * t
        d = min(d, bx * bx + by * by)
        c1, c2, c3 = py >= pts[i][1], py < pts[j][1], ex * wy > ey * wx
        if (c1 and c2 and c3) or (not c1 and not c2 and not c3):
            s = -s
        j = i
    return s * math.sqrt(d)


def lerp(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def vgrad(c1, c2, y0, y1):
    return lambda x, y: lerp(c1, c2, (y - y0) / (y1 - y0))


# ---------------------------------------------------------------- layers, back to front
# Each layer: (distance function, bbox (x0, y0, x1, y1), colour or colour function, alpha, softness).
# softness is the edge blur in grid units; None = a crisp, anti-aliased edge.
layers = []


def add(fn, bbox, color, alpha=1.0, soft=None):
    layers.append((fn, bbox, color, alpha, soft))


def rrect(cx, cy, hx, hy, r, color, alpha=1.0, soft=None, grow=0.0):
    m = (soft or 1) * 2 + grow + 2
    add(lambda x, y: sd_rrect(x, y, cx, cy, hx, hy, r) - grow,
        (cx - hx - m, cy - hy - m, cx + hx + m, cy + hy + m), color, alpha, soft)


def circle(cx, cy, r, color, alpha=1.0, soft=None):
    m = (soft or 1) * 2 + 2
    add(lambda x, y: sd_circle(x, y, cx, cy, r), (cx - r - m, cy - r - m, cx + r + m, cy + r + m),
        color, alpha, soft)


def ring_rrect(cx, cy, hx, hy, r, width, color, alpha=1.0):
    add(lambda x, y: abs(sd_rrect(x, y, cx, cy, hx, hy, r)) - width / 2,
        (cx - hx - width - 2, cy - hy - width - 2, cx + hx + width + 2, cy + hy + width + 2), color, alpha)


# Book: leather cover with a gold trim line, a page block under the pages, and the two pages.
BX, BY, BHX, BHY = 248, 298, 196, 128
rrect(BX, BY + 14, BHX, BHY, 22, (0, 0, 0), 0.55, soft=14)                      # drop shadow
rrect(BX, BY, BHX, BHY, 20, vgrad((122, 46, 30), (72, 24, 16), BY - BHY, BY + BHY))
ring_rrect(BX, BY, BHX - 9, BHY - 9, 13, 2.5, (214, 172, 86), 0.9)

PAGE_TOP, PAGE_BOT = 182, 408
LP = (BX - 172, BX - 6)   # left page x range
RP = (BX + 6, BX + 172)   # right page x range
for x0, x1 in (LP, RP):   # page block (the thickness under the open pages)
    rrect((x0 + x1) / 2, (PAGE_TOP + PAGE_BOT) / 2 + 6, (x1 - x0) / 2, (PAGE_BOT - PAGE_TOP) / 2, 8,
          (196, 172, 124))


def page_color(x, y):
    base = lerp((243, 230, 190), (216, 192, 142), (y - PAGE_TOP) / (PAGE_BOT - PAGE_TOP))
    shade = 1 - 0.28 * math.exp(-abs(x - BX) / 16.0)  # darker towards the spine
    return tuple(c * shade for c in base)


for x0, x1 in (LP, RP):
    rrect((x0 + x1) / 2, (PAGE_TOP + PAGE_BOT) / 2, (x1 - x0) / 2, (PAGE_BOT - PAGE_TOP) / 2, 8, page_color)

INK = (104, 72, 40)

# Left page: a zone header (with its - box) and a list of quests with difficulty-coloured dots.
lx = LP[0] + 16
ring_rrect(lx + 6, 206, 6, 6, 2, 2, INK)
rrect(lx + 6, 206, 3.5, 1.2, 0.5, INK)
rrect(lx + 62, 206, 44, 4.5, 4, (86, 58, 30))
DIFF = [(64, 191, 64), (255, 209, 0), (255, 128, 32), (64, 191, 64), (150, 150, 150), (255, 40, 40), (255, 209, 0)]
LENS = [104, 120, 92, 112, 84, 116, 98]
SELECTED = 1
for i, (col, ln) in enumerate(zip(DIFF, LENS)):
    y = 234 + i * 24
    if i == SELECTED:
        rrect((LP[0] + LP[1]) / 2, y, (LP[1] - LP[0]) / 2 - 8, 10, 5, (255, 206, 70), 0.5)
    circle(lx + 8, y, 7.5, (60, 38, 18))
    circle(lx + 8, y, 5.8, col)
    rrect(lx + 22 + ln / 2, y, ln / 2, 3.6, 3.6, INK, 0.85)

# Right page: a title, then paragraphs of quest text.
rx = RP[0] + 18
rrect(rx + 52, 208, 52, 5.5, 5, (66, 42, 20))
y = 236
for ln in (128, 134, 122, 130, 70, None, 132, 118, 126, 88):
    if ln is None:
        y += 10
        continue
    rrect(rx + ln / 2, y, ln / 2, 3.2, 3.2, (128, 94, 58), 0.85)
    y += 17

# Gold "!" badge on the top-right corner.
GX, GY, GR = 404, 154, 68
circle(GX, GY + 8, GR, (0, 0, 0), 0.6, soft=12)                                  # drop shadow
circle(GX, GY, GR, vgrad((255, 226, 120), (196, 124, 8), GY - GR, GY + GR))       # gold ring
circle(GX, GY, GR - 9, (58, 34, 10))                                             # ring's dark edge
circle(GX, GY, GR - 12, vgrad((44, 50, 66), (20, 24, 34), GY - GR, GY + GR))     # badge face

BAR = [(GX - 14, GY - 46), (GX + 14, GY - 46), (GX + 8, GY + 14), (GX - 8, GY + 14)]
GOLD = vgrad((255, 232, 110), (232, 150, 0), GY - 46, GY + 40)
OUTLINE = (40, 24, 6)
add(lambda x, y: sd_poly(x, y, BAR) - 4 - 4, (GX - 30, GY - 62, GX + 30, GY + 30), OUTLINE)  # outline
circle(GX, GY + 30, 11 + 4, OUTLINE)
add(lambda x, y: sd_poly(x, y, BAR) - 4, (GX - 26, GY - 58, GX + 26, GY + 26), GOLD)
circle(GX, GY + 30, 11, GOLD)
# a soft highlight on the bar's upper left
add(lambda x, y: sd_poly(x, y, [(GX - 9, GY - 41), (GX - 2, GY - 41), (GX - 4, GY - 6), (GX - 7, GY - 6)]),
    (GX - 14, GY - 46, GX + 2, GY), (255, 250, 210), 0.55)


# ---------------------------------------------------------------- render
# The artwork above spans about x 52-472, y 86-426; it's scaled up and centred on the canvas.
ART_CX, ART_CY, ART_SCALE = 262, 256, 1.1


def background(x, y):
    d = math.hypot(x - 256, y - 236) / 362.0
    return lerp((38, 44, 60), (12, 14, 20), d)


rows = bytearray()
for j in range(SIZE):
    rows.append(0)  # PNG filter: none
    cy = (j + 0.5) / K
    y = (cy - 256) / ART_SCALE + ART_CY
    for i in range(SIZE):
        cx = (i + 0.5) / K
        x = (cx - 256) / ART_SCALE + ART_CX
        r, g, b = background(cx, cy)
        for fn, (x0, y0, x1, y1), color, alpha, soft in layers:
            if x < x0 or x > x1 or y < y0 or y > y1:
                continue
            d = fn(x, y)
            if soft:
                cov = max(0.0, min(1.0, 0.5 - d / (2 * soft)))
            else:
                cov = max(0.0, min(1.0, 0.5 - d * K * ART_SCALE))  # one output pixel of anti-aliasing
            if cov <= 0:
                continue
            a = cov * alpha
            cr, cg, cb = color(x, y) if callable(color) else color
            r, g, b = r + (cr - r) * a, g + (cg - g) * a, b + (cb - b) * a
        rows += bytes((int(r + 0.5), int(g + 0.5), int(b + 0.5)))


def chunk(tag, body):
    return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)


png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(bytes(rows), 9))
png += chunk(b"IEND", b"")
with open(OUT, "wb") as f:
    f.write(png)
print("wrote", OUT, SIZE, "x", SIZE)
