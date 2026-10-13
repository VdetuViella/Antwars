#!/usr/bin/env python3
"""Atlas de objetos por nivel de detalle (ADR-005): semillas, terrón, pan de hormiga,
cáscara, cadáver, huevo, larvas, pupa, semilla de gramínea, grano del granero y gota.

  * L0 (×1): copia exacta del atlas actual `assets/sprites/items.png` (8×8 por objeto),
    así ×1 se ve igual que hoy.
  * L1 (×2) y L2 (×4): los mismos objetos al mismo tamaño de mundo (celda de 8 mm),
    dibujados con 2 y 4 px por mm: formas con sombreado duro, sin antialiasing
    (alfa 0 o 255) y deterministas (sin RNG: textura por hash de coordenadas).

    python3 tools/gen_items_lod.py      → assets/items_lod/items_L{0,1,2}.png + items.json
"""
import json
import math
import shutil
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "items_lod"
CELL_MM = 8
N_ITEMS = 12
NAMES = ["semilla", "terron", "pan", "cascara", "cadaver", "huevo", "larva_peq", "larva_gr",
         "pupa", "semilla_hierba", "granero", "gota"]

GOLD = [(150, 108, 40), (196, 152, 62), (220, 178, 84), (246, 216, 130)]
SOIL = [(96, 70, 46), (124, 92, 60), (150, 112, 74), (172, 134, 92)]
BREAD = [(200, 182, 140), (224, 208, 166), (238, 226, 192), (250, 244, 222)]
HUSK = [(146, 124, 82), (176, 154, 106), (198, 178, 128), (220, 204, 158)]
DARK = [(30, 26, 24), (48, 42, 38), (66, 58, 52), (92, 82, 74)]
CREAM = [(204, 194, 168), (228, 220, 198), (244, 238, 222), (255, 252, 242)]
PUPA = [(178, 164, 132), (206, 194, 162), (228, 218, 190), (244, 238, 216)]
WATER = [(70, 120, 180), (100, 160, 216), (140, 194, 236), (210, 236, 252)]


def h32(x, y, salt):
    v = (x * 0x8DA6B343) ^ (y * 0xD8163841) ^ (salt * 0xCB1AB31F)
    v &= 0xFFFFFFFF
    v ^= v >> 13
    v = (v * 0x5BD1E995) & 0xFFFFFFFF
    v ^= v >> 15
    return v


def shade(ramp, nx, ny, nz):
    """Tono por la normal (luz desde arriba a la izquierda), cuantizado a la rampa."""
    L = (-0.45, -0.6, 0.66)
    lam = max(0.0, nx * L[0] + ny * L[1] + nz * L[2])
    i = min(len(ramp) - 1, int(lam * len(ramp)))
    return ramp[i]


def blob(img, ppm, cx, cy, rx, ry, ramp, ang=0.0, grain=0, salt=0):
    """Elipse con relieve (como una cúpula), en mm. grain>0 añade granulado por hash."""
    w = img.shape[1]
    ca, sa = math.cos(ang), math.sin(ang)
    for py in range(img.shape[0]):
        for px in range(w):
            x = (px + 0.5) / ppm - cx
            y = (py + 0.5) / ppm - cy
            u = (x * ca + y * sa) / rx
            v = (-x * sa + y * ca) / ry
            d = u * u + v * v
            if d > 1.0:
                continue
            nz = math.sqrt(1.0 - d)
            nx = u * ca - v * sa
            ny = u * sa + v * ca
            col = shade(ramp, nx, ny, nz)
            if grain:
                hv = h32(px, py, salt) & 15
                if hv == 0:
                    col = ramp[min(3, ramp.index(col) + 1)]
                elif hv == 1:
                    col = ramp[max(0, ramp.index(col) - 1)]
            img[py, px] = (*col, 255)


def seg_line(img, ppm, a, b, r, col):
    for py in range(img.shape[0]):
        for px in range(img.shape[1]):
            x = (px + 0.5) / ppm
            y = (py + 0.5) / ppm
            abx, aby = b[0] - a[0], b[1] - a[1]
            t = max(0.0, min(1.0, ((x - a[0]) * abx + (y - a[1]) * aby) / (abx * abx + aby * aby + 1e-9)))
            if math.hypot(x - (a[0] + abx * t), y - (a[1] + aby * t)) <= max(r, 0.5 / ppm):
                img[py, px] = (*col, 255)


def draw_item(idx, ppm):
    n = CELL_MM * ppm
    img = np.zeros((n, n, 4), dtype=np.uint8)
    c = 3.9                                          # centro de la celda (≈ como en L0)
    if idx == 0:          # semilla del comedero
        blob(img, ppm, c, c + 0.4, 1.5, 0.95, GOLD, ang=-0.25)
        seg_line(img, ppm, (c - 0.9, c + 0.6), (c + 0.8, c + 0.2), 0.12, GOLD[0])
    elif idx == 1:        # terrón de tierra
        blob(img, ppm, c - 0.5, c + 0.5, 1.1, 0.9, SOIL, grain=1, salt=1)
        blob(img, ppm, c + 0.6, c + 0.3, 0.9, 0.8, SOIL, grain=1, salt=2)
        blob(img, ppm, c, c - 0.3, 0.8, 0.7, SOIL, grain=1, salt=3)
    elif idx == 2:        # pan de hormiga
        blob(img, ppm, c, c + 0.4, 1.2, 0.9, BREAD, grain=1, salt=4)
    elif idx == 3:        # cáscaras
        blob(img, ppm, c - 0.9, c + 0.7, 0.8, 0.45, HUSK, ang=0.5)
        blob(img, ppm, c + 0.6, c + 0.5, 0.9, 0.4, HUSK, ang=-0.6)
        blob(img, ppm, c - 0.1, c - 0.3, 0.6, 0.35, HUSK, ang=0.2)
    elif idx == 4:        # cadáver: hormiga encogida, boca arriba
        blob(img, ppm, c - 1.2, c + 0.6, 1.1, 0.8, DARK)
        blob(img, ppm, c + 0.3, c + 0.6, 0.7, 0.5, DARK)
        blob(img, ppm, c + 1.4, c + 0.4, 0.6, 0.55, DARK)
        for k in range(3):
            x0 = c + 0.1 + k * 0.35
            seg_line(img, ppm, (x0, c + 0.1), (x0 - 0.5 + k * 0.4, c - 0.8), 0.1, DARK[1])
    elif idx == 5:        # huevo
        blob(img, ppm, c, c + 0.5, 0.8, 0.6, CREAM, ang=0.3)
    elif idx in (6, 7):   # larvas (gusanito en forma de C, segmentado)
        big = idx == 7
        R = 1.3 if big else 0.9
        rr = 0.75 if big else 0.55
        for k in range(9):
            a = math.pi * (0.15 + 0.9 * k / 8.0)
            blob(img, ppm, c + R * math.cos(a) * 0.9, c + 0.9 - R * math.sin(a) * 0.7, rr * (0.75 + 0.25 * math.sin(a)), rr * 0.85, CREAM)
        # surcos de los segmentos
        for k in range(1, 6):
            a = math.pi * (0.2 + 0.8 * k / 6.0)
            px_ = c + R * math.cos(a) * 0.9
            py_ = c + 0.9 - R * math.sin(a) * 0.7
            seg_line(img, ppm, (px_ - 0.3 * math.cos(a), py_ + 0.3 * math.sin(a)),
                     (px_ + 0.25 * math.cos(a), py_ - 0.25 * math.sin(a)), 0.07, CREAM[0])
    elif idx == 8:        # pupa desnuda (Messor no teje capullo): hormiga pálida con patas plegadas
        blob(img, ppm, c - 1.6, c + 0.4, 1.1, 0.85, PUPA)
        blob(img, ppm, c + 0.3, c + 0.3, 0.9, 0.6, PUPA)
        blob(img, ppm, c + 1.8, c + 0.4, 0.7, 0.65, PUPA)
        for k in range(3):
            x0 = c - 0.2 + k * 0.45
            seg_line(img, ppm, (x0, c + 0.7), (x0 + 0.5, c + 1.2), 0.09, PUPA[0])
    elif idx == 9:        # semilla de gramínea (alargada)
        blob(img, ppm, c + 0.6, c + 0.7, 1.4, 0.45, GOLD[1:] + [GOLD[3]], ang=-0.35)
        seg_line(img, ppm, (c - 0.6, c + 1.1), (c + 1.8, c + 0.2), 0.08, GOLD[1])
    elif idx == 10:       # pila del granero (varias semillas)
        for (dx, dy, a) in [(-1.3, 0.7, 0.3), (0.2, 0.8, -0.2), (1.5, 0.7, 0.5), (-0.5, -0.2, -0.4), (0.9, -0.2, 0.1)]:
            blob(img, ppm, c + dx, c + dy, 0.95, 0.6, GOLD, ang=a)
    elif idx == 11:       # gota de agua
        blob(img, ppm, c, c + 0.5, 0.9, 0.9, WATER)
        seg_line(img, ppm, (c, c - 1.0), (c, c - 0.2), 0.3, WATER[1])
    return Image.fromarray(img, "RGBA")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / "assets" / "sprites" / "items.png", OUT / "items_L0.png")
    levels = [{"level": 0, "zoom": 1, "cell_px": 8, "file": "items_L0.png"}]
    for level, zoom in ((1, 2), (2, 4)):
        cell = CELL_MM * zoom
        sheet = Image.new("RGBA", (N_ITEMS * cell, cell), (0, 0, 0, 0))
        for i in range(N_ITEMS):
            sheet.paste(draw_item(i, zoom), (i * cell, 0))
        fname = f"items_L{level}.png"
        sheet.save(OUT / fname)
        levels.append({"level": level, "zoom": zoom, "cell_px": cell, "file": fname})
    (OUT / "items.json").write_text(json.dumps({"items": NAMES, "cell_mm": CELL_MM, "pivot": "cell_center",
                                                "levels": levels}, indent=2, ensure_ascii=False))
    print("atlas de objetos:", [l["cell_px"] for l in levels])


if __name__ == "__main__":
    main()
