#!/usr/bin/env python3
"""Genera el atlas de sprites pixel art de AntWars.

Las hormigas se rasterizan a partir de un modelo paramétrico (gáster, pecíolo,
mesosoma, cabeza, mandíbulas, antenas acodadas y tres pares de patas) con
supermuestreo 6x y umbral de cobertura, en 3 orientaciones (E, NE, N) y
4 fotogramas de marcha (trípode alterno). El resto de orientaciones se obtiene
volteando en el render. Uso:

    python3 tools/gen_sprites.py            # escribe assets/sprites/*.png
    python3 tools/gen_sprites.py --preview  # además, una vista ampliada x8
"""
import math
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "sprites"
CELL = 20          # tamaño de celda del atlas
SS = 6             # supermuestreo

# Paleta (Messor barbarus: menores negras, mayores con cabeza rojiza)
BODY = (28, 23, 21, 255)
BODY_HI = (70, 60, 54, 255)
LEG = (40, 33, 30, 255)
HEAD_RED = (122, 46, 30, 255)
HEAD_RED_HI = (160, 72, 46, 255)
QUEEN_BODY = (34, 27, 24, 255)
WING_STUB = (120, 110, 100, 255)

# Castas: (nombre, longitud, grosor gáster, tamaño cabeza, cabeza roja)
CASTES = [
    ("minor", 9.0, 1.0, 1.0, False),
    ("media", 10.0, 1.15, 1.25, False),
    ("major", 12.5, 1.25, 1.75, True),
    ("queen", 16.0, 1.55, 1.25, False),
    ("nanitic", 8.0, 0.95, 0.95, False),
]
DIRS = [0.0, 45.0, 90.0]   # E, NE, N
FRAMES = 4


def ellipse_cov(px, py, cx, cy, rx, ry):
    nx = (px - cx) / rx
    ny = (py - cy) / ry
    return nx * nx + ny * ny <= 1.0


def seg_dist(px, py, ax, ay, bx, by):
    abx, aby = bx - ax, by - ay
    t = ((px - ax) * abx + (py - ay) * aby) / max(abx * abx + aby * aby, 1e-9)
    t = max(0.0, min(1.0, t))
    qx, qy = ax + abx * t, ay + aby * t
    return math.hypot(px - qx, py - qy)


def ant_parts(length, thick, head_k, frame, queen):
    """Devuelve primitivas en coordenadas locales (x hacia la cabeza, y hacia abajo).
    El origen es el centro del cuerpo."""
    L = length
    s = L / 8.0
    parts = []  # (tipo, params, capa) capa: 'body', 'head', 'leg', 'hi'
    gx = -L * 0.5 + 1.7 * s * thick
    gr_x = max(1.9, 1.75 * s * thick)
    gr_y = max(1.45, 1.25 * s * thick)
    parts.append(("ell", (gx, 0.1 * s, gr_x, gr_y), "body"))
    # pecíolo (cintura): pequeño nodo separado por huecos
    pet_x = gx + gr_x + 0.55 * s
    parts.append(("ell", (pet_x, -0.15 * s, 0.42 * s, 0.5 * s), "body"))
    # mesosoma
    mx = pet_x + 1.35 * s
    mrx = max(1.15, 1.05 * s * (1.35 if queen else 1.0))
    mry = max(0.8, 0.62 * s * (1.4 if queen else 1.0))
    parts.append(("ell", (mx, -0.25 * s, mrx, mry), "body"))
    # cabeza
    hx = mx + mrx + 0.85 * s * head_k
    hrx = max(1.15, 0.95 * s * head_k)
    hry = max(1.0, 0.82 * s * head_k)
    parts.append(("ell", (hx, -0.35 * s, hrx, hry), "head"))
    # mandíbulas
    parts.append(("seg", (hx + hrx * 0.7, 0.1 * s, hx + hrx + 0.6 * s, 0.25 * s, 0.38 * s), "leg"))
    # antena acodada: escapo hacia arriba-delante, funículo hacia delante-abajo
    ex, ey = hx + hrx * 0.2, -0.35 * s - hry * 0.9
    kx, ky = ex + 0.9 * s, ey - 1.0 * s
    tx, ty = kx + 1.2 * s, ky + 0.55 * s
    wob = (0.25 * s) * math.sin(frame * math.pi / 2)
    parts.append(("seg", (ex, ey, kx, ky + wob * 0.3, 0.36), "leg"))
    parts.append(("seg", (kx, ky + wob * 0.3, tx, ty + wob, 0.36), "leg"))
    # patas: tres pares; trípode alterno (pares A: delantera y trasera de un lado + media del otro)
    ground = 1.55 * s * (1.25 if queen else 1.0) + 0.6
    hips = [mx + mrx * 0.55, mx, mx - mrx * 0.6]
    phase = frame % 4
    swing = [0.0, 0.9, 0.0, -0.9][phase] * s
    for k, hx0 in enumerate(hips):
        sgn = 1.0 if k % 2 == 0 else -1.0
        off = swing * sgn
        reach = [1.3, 0.2, -1.5][k] * s
        knee_x = hx0 + reach * 0.6 + off * 0.5
        knee_y = 0.55 * s
        foot_x = hx0 + reach + off
        foot_y = ground
        parts.append(("seg", (hx0, 0.2 * s, knee_x, knee_y, 0.36), "leg"))
        parts.append(("seg", (knee_x, knee_y, foot_x, foot_y, 0.36), "leg"))
    if queen:
        parts.append(("seg", (mx - mrx * 0.2, -0.25 * s - mry, mx - mrx * 1.2, -0.25 * s - mry - 0.2 * s, 0.4 * s), "wing"))
    return parts


def render_ant(caste, angle_deg, frame):
    name, length, thick, head_k, red = caste
    queen = name == "queen"
    parts = ant_parts(length, thick, head_k, frame, queen)
    a = math.radians(angle_deg)
    ca, sa = math.cos(a), math.sin(a)
    img = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    cx = cy = CELL / 2.0
    layer_order = {"leg": 0, "wing": 1, "body": 2, "head": 3}
    for py in range(CELL):
        for px in range(CELL):
            cover = {}
            for sy in range(SS):
                for sx in range(SS):
                    wx = px + (sx + 0.5) / SS - cx
                    wy = py + (sy + 0.5) / SS - cy
                    # pasar a coordenadas locales (rotación inversa; y hacia abajo)
                    lx = wx * ca - wy * sa
                    ly = wx * sa + wy * ca
                    lx, ly = lx, ly
                    hit = None
                    for kind, p, layer in parts:
                        inside = False
                        if kind == "ell":
                            inside = ellipse_cov(lx, ly, *p)
                        else:
                            inside = seg_dist(lx, ly, p[0], p[1], p[2], p[3]) <= p[4]
                        if inside and (hit is None or layer_order[layer] > layer_order[hit]):
                            hit = layer
                    if hit:
                        cover[hit] = cover.get(hit, 0) + 1
            total = sum(cover.values())
            if total == 0:
                continue
            frac = total / (SS * SS)
            dom = max(cover.items(), key=lambda kv: (layer_order[kv[0]] >= 2, kv[1]))[0]
            thr = 0.34 if dom in ("leg",) else 0.36
            if frac < thr:
                continue
            if dom == "leg":
                col = LEG
            elif dom == "wing":
                col = WING_STUB
            elif dom == "head":
                col = HEAD_RED if red else (QUEEN_BODY if queen else BODY)
            else:
                col = QUEEN_BODY if queen else BODY
            img.putpixel((px, py), col)
    # brillo dorsal: píxel superior de cada columna del cuerpo (luz cenital)
    hi_img = img.copy()
    for px in range(CELL):
        for py in range(CELL):
            c = img.getpixel((px, py))
            if c[3] and c[:3] in (BODY[:3], QUEEN_BODY[:3], HEAD_RED[:3]):
                above = img.getpixel((px, py - 1)) if py > 0 else (0, 0, 0, 0)
                below = img.getpixel((px, py + 1)) if py < CELL - 1 else (0, 0, 0, 0)
                if above[3] == 0 and below[3] and below[:3] in (BODY[:3], QUEEN_BODY[:3], HEAD_RED[:3]):
                    hi_img.putpixel((px, py), HEAD_RED_HI if c[:3] == HEAD_RED[:3] else BODY_HI)
                break
    return hi_img


# Sprites dibujados a mano para las castas pequeñas en vista lateral (E):
# a escala de 8-11 px el modelo paramétrico pierde la segmentación, así que
# aquí se fija píxel a píxel. G/P/M/H cuerpo, h brillo, L pata, a antena, m mandíbula.
HAND_E = {
    "minor": [
        ["........aa.",
         ".hh..h.hH.a",
         "GGGGPMMHHm.",
         ".GG.LLL....",
         "..L...L.L.."],
        ["........aa.",
         ".hh..h.hH.a",
         "GGGGPMMHHm.",
         ".GG..LL....",
         "...L.L.L..."],
        [".........a.",
         ".hh..h.hHa.",
         "GGGGPMMHHm.",
         ".GG.LLL....",
         ".L...L...L."],
        ["........aa.",
         ".hh..h.hH.a",
         "GGGGPMMHHm.",
         ".GG..LL....",
         "...L..LL..."],
    ],
    "nanitic": [
        [".......a.",
         ".h..h.hHa",
         "GGGPMMHHm",
         ".G.LLL...",
         ".L...L.L."],
        [".......a.",
         ".h..h.hHa",
         "GGGPMMHHm",
         ".G..LL...",
         "..L.L.L.."],
        ["......a..",
         ".h..h.hHa",
         "GGGPMMHHm",
         ".G.LLL...",
         "L...L..L."],
        [".......a.",
         ".h..h.hHa",
         "GGGPMMHHm",
         ".G..LL...",
         "..L..LL.."],
    ],
}


def hand_sprite(rows):
    img = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    w = len(rows[0])
    h = len(rows)
    ox = (CELL - w) // 2
    oy = CELL // 2 - 2
    cmap = {"G": BODY, "P": BODY, "M": BODY, "H": BODY, "h": BODY_HI, "L": LEG, "a": LEG, "m": LEG}
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in cmap:
                img.putpixel((ox + x, oy + y), cmap[ch])
    return img


def dead_ant(caste):
    img = render_ant(caste, 0.0, 1)
    out = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    for y in range(CELL):
        for x in range(CELL):
            c = img.getpixel((x, y))
            if c[3]:
                g = int(sum(c[:3]) / 3 * 0.8 + 30)
                out.putpixel((x, CELL - 1 - y), (g, g - 4, g - 8, 255))
    return out


def build_ant_atlas():
    cols = len(DIRS) * FRAMES + 1
    atlas = Image.new("RGBA", (cols * CELL, len(CASTES) * CELL), (0, 0, 0, 0))
    for r, caste in enumerate(CASTES):
        for d, ang in enumerate(DIRS):
            for f in range(FRAMES):
                if d == 0 and caste[0] in HAND_E:
                    spr = hand_sprite(HAND_E[caste[0]][f])
                else:
                    spr = render_ant(caste, ang, f)
                atlas.paste(spr, ((d * FRAMES + f) * CELL, r * CELL))
        atlas.paste(dead_ant(caste), ((cols - 1) * CELL, r * CELL))
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
