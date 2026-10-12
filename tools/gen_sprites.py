#!/usr/bin/env python3
"""Genera el atlas de sprites pixel art de AntWars.

Cuerpos en perfil dibujados a mano píxel a píxel (uno por casta); patas y
antenas en líneas de 1 px con fotogramas clave: 6 de marcha en trípode (pies
que se levantan al avanzar; patas del lado lejano más claras y en contrafase)
y 2 de reposo (antenas tanteando; la reina «respira»). Las orientaciones NE y N
se obtienen con RotSprite (Scale2x ×3, rotación y reducción), que conserva las
líneas de 1 px; el resto se consigue volteando en el render. Uso:

    python3 tools/gen_sprites.py            # escribe assets/sprites/*.png
    python3 tools/gen_sprites.py --preview  # además, una vista ampliada x8
"""
import math
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "sprites"
CELL = 24          # tamaño de celda del atlas
SS = 6             # supermuestreo

# Paleta (Messor barbarus: menores negras, mayores con cabeza rojiza)
BODY = (28, 23, 21, 255)
BODY_HI = (78, 67, 60, 255)
LEG = (36, 30, 27, 255)
LEG_FAR = (82, 70, 62, 255)       # patas del lado lejano: más claras, detrás del cuerpo
HEAD_RED = (122, 46, 30, 255)
HEAD_RED_HI = (170, 80, 50, 255)
WING_STUB = (132, 122, 112, 255)

WALK_FRAMES = 6            # marcha en trípode
IDLE_FRAMES = 2            # quieta: antenas tanteando (y gáster que «respira» en la reina)
FRAMES = WALK_FRAMES + IDLE_FRAMES
DIRS = [0, 45, 90]         # E, NE, N (el resto, volteando en el render)

# Cuerpos en perfil (mirando al este), dibujados a mano. G cuerpo, h brillo,
# R cabeza rojiza, r brillo rojizo, W muñón alar, m mandíbula.
# hips: caderas (x, y) delantera→trasera; ground: fila de los pies;
# reach: alcance de cada pata (px); amp: recorrido del pie; ant: base de la antena.
CASTES = [
    ("minor", dict(rows=[
        ".hh..h.hh.hh.",
        "GGGG.GGGGGGGm",
        ".GG..........",
     ], hips=[(8, 1), (7, 1), (6, 1)], ground=5, reach=[3, 0, -4], amp=1.5, ant=(10, 0), ant_len=(2, 3))),
    ("media", dict(rows=[
        ".hhh..h.hhh.hh..",
        "GGGGG.GGGGGGGGGm",
        ".GGG.....G.GGG..",
     ], hips=[(10, 1), (9, 1), (7, 1)], ground=6, reach=[4, 0, -5], amp=1.5, ant=(12, 0), ant_len=(2, 3))),
    ("major", dict(rows=[
        "............rr...",
        ".hhh..h.hh.RRRR..",
        "GGGGG.GGGG.RRRRRm",
        ".GGG....G..RRRR.m",
     ], hips=[(9, 2), (8, 2), (7, 2)], ground=7, reach=[5, 0, -5], amp=2, ant=(12, 0), ant_len=(2, 4))),
    ("queen", dict(rows=[
        "..........WWW........",
        "..hhhh....hhhh..hh...",
        ".GGGGGG..GGGGGG.GGG..",
        "GGGGGGGG.GGGGGGGGGGGm",
        "GGGGGGGG..GGGG..GG...",
        ".GGGGGG..............",
     ], hips=[(14, 3), (12, 3), (10, 3)], ground=9, reach=[5, 0, -6], amp=2, ant=(16, 1), ant_len=(2, 3))),
    ("nanitic", dict(rows=[
        ".h..h.hh.h.",
        "GGG.GGGGGGm",
        ".G.........",
     ], hips=[(7, 1), (6, 1), (5, 1)], ground=4, reach=[3, 0, -3], amp=1, ant=(8, 0), ant_len=(2, 2))),
]
CMAP = {"G": BODY, "h": BODY_HI, "R": HEAD_RED, "r": HEAD_RED_HI, "W": WING_STUB, "m": LEG}


def line(img, x0, y0, x1, y1, col, overwrite=True):
    """Línea de 1 px (Bresenham) en coordenadas de píxel."""
    x0, y0, x1, y1 = (int(math.floor(v + 0.5)) for v in (x0, y0, x1, y1))
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    while True:
        if 0 <= x0 < img.width and 0 <= y0 < img.height:
            if overwrite or img.getpixel((x0, y0))[3] == 0:
                img.putpixel((x0, y0), col)
        if x0 == x1 and y0 == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def gait(frame, group_a, amp):
    """Desplazamiento horizontal del pie y elevación en la marcha en trípode."""
    if frame >= WALK_FRAMES:
        return (0.5 if group_a else -0.5) * amp, 0
    p = (frame / WALK_FRAMES + (0.0 if group_a else 0.5)) % 1.0
    if p < 0.5:                       # apoyo: el pie va hacia atrás respecto al cuerpo
        return amp * (1.0 - 4.0 * p), 0
    q = (p - 0.5) * 2.0               # vuelo: avanza levantado
    return -amp + 2.0 * amp * q, 1 if 0.15 < q < 0.85 else 0


def draw_legs(img, ox, oy, spec, frame, far):
    """Fémur hacia fuera, pegado bajo el cuerpo; tibia en diagonal hasta el suelo."""
    hips, ground, reach, amp = spec["hips"], spec["ground"], spec["reach"], spec["amp"]
    col = LEG_FAR if far else LEG
    shift = 1 if far else 0                       # lado lejano: 1 px atrás y arriba
    for k, (hx, hy) in enumerate(hips):
        group_a = (k != 1) if not far else (k == 1)
        off, lift = gait(frame, group_a, amp)
        fx = hx + reach[k] + off + shift
        fy = ground - lift - shift
        kx = hx + reach[k] * 0.5 + off * 0.3 + shift
        ky = hy + 1 - shift
        line(img, ox + hx, oy + hy + 1, ox + kx, oy + ky, col, overwrite=not far)
        line(img, ox + kx, oy + ky, ox + fx, oy + fy, col, overwrite=not far)


def draw_antenna(img, ox, oy, spec, frame):
    """Antena acodada: escapo hacia arriba y funículo en diagonal hacia delante y abajo."""
    bx, by = spec["ant"]
    scape, fun = spec["ant_len"]
    if frame >= WALK_FRAMES:          # tanteando: muy alta / pegada al suelo
        up, fwd = [(1, -1), (-1, 1)][frame - WALK_FRAMES]
    else:                             # al andar, la antena cabecea un píxel
        up, fwd = [(0, 0), (0, 0), (1, 0), (1, 0), (0, 1), (0, 1)][frame]
    ex, ey = bx + 1, by - scape - up
    tx, ty = ex + fun + fwd, ey + fun - 1 + up + max(0, -up)
    line(img, ox + bx, oy + by, ox + ex, oy + ey, LEG)
    line(img, ox + ex, oy + ey, ox + tx, oy + ty, LEG)


def render_east(name, spec, frame):
    img = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    rows = spec["rows"]
    w = len(rows[0])
    h = spec["ground"] + 1
    ox = (CELL - w) // 2
    oy = (CELL - h) // 2 + 1
    breathe = name == "queen" and frame == WALK_FRAMES + 1
    draw_legs(img, ox, oy, spec, frame, far=True)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in CMAP:
                img.putpixel((ox + x, oy + y), CMAP[ch])
    if breathe:                       # el gáster de la reina se hincha un píxel
        gw = rows[3].index(".") if "." in rows[3] else 8
        for x in range(1, gw - 1):
            img.putpixel((ox + x, oy + len(rows)), BODY)
    draw_legs(img, ox, oy, spec, frame, far=False)
    draw_antenna(img, ox, oy, spec, frame)
    return img


# --- RotSprite: Scale2x ×3 (8×), rotar con vecino más cercano y reducir --------

def scale2x(img):
    w, h = img.size
    src = img.load()
    out = Image.new("RGBA", (w * 2, h * 2))
    dst = out.load()
    T = (0, 0, 0, 0)
    for y in range(h):
        for x in range(w):
            P = src[x, y]
            A = src[x, y - 1] if y > 0 else T
            B = src[x + 1, y] if x < w - 1 else T
            C = src[x - 1, y] if x > 0 else T
            D = src[x, y + 1] if y < h - 1 else T
            dst[2 * x, 2 * y] = C if (C == A and C != D and A != B) else P
            dst[2 * x + 1, 2 * y] = A if (A == B and A != C and B != D) else P
            dst[2 * x, 2 * y + 1] = D if (D == C and D != B and C != A) else P
            dst[2 * x + 1, 2 * y + 1] = B if (B == D and B != A and D != C) else P
    return out


def rotsprite(img, angle):
    if angle == 0:
        return img.copy()
    if angle == 90:
        return img.transpose(Image.ROTATE_90)
    big = scale2x(scale2x(scale2x(img)))
    rot = big.rotate(angle, resample=Image.NEAREST, center=(big.width / 2, big.height / 2))
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    rp = rot.load()
    for y in range(img.height):
        for x in range(img.width):
            # Muestra en el centro del bloque; si cae en transparente pero el bloque
            # tiene bastante tinta, toma el color mayoritario (no perder patas de 1 px).
            c = rp[x * 8 + 4, y * 8 + 4]
            if c[3] == 0:
                counts = {}
                for yy in range(y * 8 + 1, y * 8 + 7, 2):
                    for xx in range(x * 8 + 1, x * 8 + 7, 2):
                        q = rp[xx, yy]
                        if q[3]:
                            counts[q] = counts.get(q, 0) + 1
                if counts and sum(counts.values()) >= 4:
                    c = max(counts.items(), key=lambda kv: kv[1])[0]
            out.putpixel((x, y), c)
    return out


def dead_ant(name, spec):
    """Cadáver: boca arriba, patas encogidas y tono apagado."""
    img = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    rows = spec["rows"]
    w = len(rows[0])
    ox = (CELL - w) // 2
    oy = CELL // 2
    for y, row in enumerate(reversed(rows)):
        for x, ch in enumerate(row):
            if ch in CMAP:
                c = CMAP[ch]
                g = int(sum(c[:3]) / 3 * 0.8 + 34)
                img.putpixel((ox + x, oy + y), (g, g - 4, g - 8, 255))
    for (hx, hy) in spec["hips"]:
        line(img, ox + hx, oy - 1, ox + hx + 1, oy - 2, (70, 64, 58, 255))
    return img


def build_ant_atlas():
    """Filas = castas; columnas = dirección × fotograma (6 de marcha + 2 de reposo)
    y una última columna con el cadáver."""
    cols = len(DIRS) * FRAMES + 1
    atlas = Image.new("RGBA", (cols * CELL, len(CASTES) * CELL), (0, 0, 0, 0))
    for r, (name, spec) in enumerate(CASTES):
        for f in range(FRAMES):
            east = render_east(name, spec, f)
            for d, ang in enumerate(DIRS):
                atlas.paste(rotsprite(east, ang), ((d * FRAMES + f) * CELL, r * CELL))
        atlas.paste(dead_ant(name, spec), ((cols - 1) * CELL, r * CELL))
    return atlas


def build_items_atlas():
    """Objetos de 8x8: semilla, terrón, pan, cáscara, cadáver, huevo, larva p, larva g, pupa, semilla clara."""
    C = 8
    items = Image.new("RGBA", (C * 12, C), (0, 0, 0, 0))

    def put(i, pixels):
        for (x, y, col) in pixels:
            items.putpixel((i * C + x, y), col)

    gold = (214, 170, 72, 255); gold_d = (160, 118, 44, 255); gold_h = (240, 210, 120, 255)
    soil = (150, 112, 74, 255); soil_d = (112, 82, 54, 255)
    bread = (232, 214, 170, 255); husk = (190, 168, 120, 255)
    egg = (246, 240, 222, 255); egg_d = (216, 206, 182, 255)
    lar = (244, 236, 214, 255); lar_d = (206, 194, 166, 255)
    pup = (236, 226, 200, 255); pup_d = (196, 182, 150, 255)
    dark = (60, 52, 48, 255)
    # 0 semilla (3x2)
    put(0, [(3, 3, gold_h), (4, 3, gold), (2, 4, gold), (3, 4, gold), (4, 4, gold_d)])
    # 1 terrón
    put(1, [(3, 3, soil), (4, 3, soil), (3, 4, soil_d), (4, 4, soil), (2, 4, soil_d)])
    # 2 pan de hormiga
    put(2, [(3, 3, bread), (4, 3, bread), (3, 4, bread), (4, 4, husk)])
    # 3 cáscara
    put(3, [(2, 4, husk), (3, 3, husk), (4, 4, husk)])
    # 4 cadáver (bulto)
    put(4, [(2, 4, dark), (3, 4, dark), (4, 4, dark), (3, 3, dark), (5, 4, dark)])
    # 5 huevo
    put(5, [(3, 3, egg), (4, 3, egg), (3, 4, egg_d), (4, 4, egg)])
    # 6 larva pequeña
    put(6, [(2, 4, lar), (3, 4, lar), (4, 4, lar_d), (3, 3, lar), (4, 3, lar)])
    # 7 larva grande (forma de garbanzo)
    put(7, [(2, 3, lar), (3, 2, lar), (4, 2, lar), (5, 3, lar), (2, 4, lar_d), (3, 4, lar), (4, 4, lar), (5, 4, lar_d), (3, 3, lar), (4, 3, lar)])
    # 8 pupa desnuda (Messor no teje capullo): cuerpo con patas plegadas
    put(8, [(1, 3, pup), (2, 3, pup), (3, 3, pup), (4, 3, pup), (5, 3, pup), (6, 3, pup_d),
            (1, 4, pup_d), (2, 4, pup), (3, 4, pup_d), (4, 4, pup), (5, 4, pup_d), (6, 4, pup)])
    # 9 semilla clara (gramínea)
    put(9, [(3, 4, gold_h), (4, 4, gold), (5, 3, gold_h)])
    # 10 pila de semillas (granero) 3x3
    put(10, [(2, 4, gold), (3, 4, gold_d), (4, 4, gold), (3, 3, gold_h), (5, 4, gold_d), (4, 3, gold)])
    # 11 gota de agua
    put(11, [(3, 2, (150, 200, 240, 200)), (3, 3, (120, 180, 230, 220)), (2, 4, (120, 180, 230, 220)), (3, 4, (90, 150, 210, 230)), (4, 4, (120, 180, 230, 220))])
    return items


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    ants = build_ant_atlas()
    ants.save(OUT / "ants.png")
    items = build_items_atlas()
    items.save(OUT / "items.png")
    if "--preview" in sys.argv:
        ants.resize((ants.width * 8, ants.height * 8), Image.NEAREST).save("/tmp/claude-0/ants_preview.png")
        items.resize((items.width * 10, items.height * 10), Image.NEAREST).save("/tmp/claude-0/items_preview.png")
    print("atlas:", ants.size, items.size)


if __name__ == "__main__":
    main()
