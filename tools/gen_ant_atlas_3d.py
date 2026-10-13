#!/usr/bin/env python3
"""Atlas de hormigas por nivel de detalle (ADR-005), renderizados desde un modelo 3D.

Un modelo 3D simple de hormiga se renderiza en proyección ortográfica, SIN
antialiasing (alfa 0 o 255), a 16 direcciones × 8 fotogramas por nivel:

  * Cuerpo: gáster, pecíolo, mesosoma y cabeza como elipsoides.
  * Patas (fémur + tibia), antenas acodadas y mandíbulas como cápsulas, con un
    grosor mínimo de ~1 px para que no desaparezcan a ×1.
  * Marcha en trípode alterno: delantera y trasera de un lado + media del otro.
    Fotograma 0 = pose de reposo (los seis pies en el suelo); la fase avanza con
    la distancia recorrida (`stride_mm` en el manifiesto).
  * Dos vistas (decisión del propietario, extensión del contrato): 16 filas en
    vista CENITAL (camina por el cristal) seguidas de 16 de PERFIL (camina sobre
    un suelo). Las dos salen del mismo modelo, sin rotar pixel art.
  * Sombreado de Lambert cuantizado a los tonos de data/palette.json (D9).

Salida: assets/ants_lod/base<N>/ant_<variante>_L<nivel>.png + ant_<variante>.json

    python3 tools/gen_ant_atlas_3d.py                 # bases de 9 y 13 px
    python3 tools/gen_ant_atlas_3d.py --base 9        # solo una base
    python3 tools/gen_ant_atlas_3d.py --preview       # además, hojas de muestra
"""
import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
PALETTE = json.loads((ROOT / "data" / "palette.json").read_text())["ant"]
OUT = ROOT / "assets" / "ants_lod"

DIRECTIONS = 16
FRAMES = 8
LEVELS = [(0, 1), (1, 2), (2, 4)]          # (nivel, zoom)
AMP = 0.13                                  # recorrido del pie (unidades de cuerpo) a cada lado
MODEL_LEN = 0.84                            # largo del modelo (cola del gáster → mandíbulas)
# Zancada: en un ciclo cada pie apoya media vuelta y el cuerpo avanza lo que el pie
# retrocede (2·AMP). Así las patas no patinan si la fase avanza distancia/zancada.
STRIDE_BODY = 2.0 * AMP / MODEL_LEN         # zancada en largos de cuerpo (~0,31)
CELL_FACTOR = 1.5                           # celda = 1,5 × largo (patas y antenas)

# Variantes: (nombre, largo relativo a la obrera menor, cabeza, gáster, cabeza roja, alas)
VARIANTS = [
    ("menor", 1.00, 1.00, 1.00, False, False),
    ("media", 1.15, 1.20, 1.10, False, False),
    ("mayor", 1.35, 1.70, 1.15, True, False),
    ("reina", 1.70, 1.10, 1.55, False, True),
    ("nanitic", 0.85, 0.95, 0.95, False, False),
]


# ---------------------------------------------------------------------------
# Modelo (unidades = largo del cuerpo; x hacia la cabeza, y a la izquierda, z arriba)
# ---------------------------------------------------------------------------

def ant_model(head_k, gaster_k, queen, phase):
    """Devuelve (elipsoides, cápsulas). Elipsoide: (centro, radios, material).
    Cápsula: (a, b, radio, material, lado) con lado = +1 izquierda / −1 derecha / 0."""
    z0 = 0.19                                # altura del cuerpo: patas largas (se ven de perfil)
    ell = []
    caps = []
    g = gaster_k
    ell.append(((-0.29 - 0.03 * (g - 1), 0.0, z0 + 0.005), (0.17 * g, 0.12 * g, 0.11 * g), "body"))
    ell.append(((-0.095, 0.0, z0 + 0.01), (0.035, 0.03, 0.045), "body"))            # pecíolo
    mx = 0.03
    ell.append(((mx, 0.0, z0 + 0.005), (0.12, 0.062 * (1.3 if queen else 1.0), 0.06 * (1.3 if queen else 1.0)), "body"))
    hx = 0.22 + 0.05 * (head_k - 1)
    ell.append(((hx, 0.0, z0 + 0.012), (0.085 * head_k, 0.078 * head_k, 0.06 * head_k), "head"))
    if queen:
        for side in (1, -1):
            ell.append(((mx - 0.06, 0.05 * side, z0 + 0.065), (0.08, 0.035, 0.012), "wing"))
    # Mandíbulas
    for side in (1, -1):
        caps.append(((hx + 0.07 * head_k, 0.03 * side * head_k, z0 - 0.01),
                     (hx + 0.12 * head_k, 0.012 * side, z0 - 0.02), 0.012, "leg", 0))
    # Antenas acodadas: escapo hacia delante y arriba, funículo hacia delante y abajo
    for side in (1, -1):
        base = (hx + 0.03 * head_k, 0.04 * side * head_k, z0 + 0.05 * head_k)
        elbow = (base[0] + 0.07, base[1] + 0.07 * side, base[2] + 0.06)
        tip = (elbow[0] + 0.14, elbow[1] + 0.03 * side, elbow[2] - 0.05)
        caps.append((base, elbow, 0.011, "leg", 0))
        caps.append((elbow, tip, 0.010, "leg", 0))
    # Patas: caderas bajo el mesosoma; pies en el suelo (z = 0)
    hips_x = [mx + 0.07, mx, mx - 0.065]
    feet = [(0.31, 0.17), (0.03, 0.22), (-0.30, 0.20)]   # delanteras adelante, traseras atrás
    amp, lift_h = AMP, 0.05
    for k in range(3):
        for side in (1, -1):
            # Grupo A: delantera y trasera izquierdas + media derecha.
            group_a = (k != 1) if side == 1 else (k == 1)
            p = (phase + (0.0 if group_a else 0.5)) % 1.0
            if p < 0.5:
                off, lift = amp * (1.0 - 4.0 * p), 0.0
            else:
                q = (p - 0.5) * 2.0
                off, lift = -amp + 2.0 * amp * q, lift_h * math.sin(math.pi * q)
            hip = (hips_x[k], 0.035 * side, z0 - 0.02)
            foot = (feet[k][0] + off, feet[k][1] * side, lift)
            # Rodilla alta y hacia fuera: de perfil la pata forma un arco (fémur
            # subiendo, tibia bajando en diagonal hasta el pie).
            knee = (hip[0] + (foot[0] - hip[0]) * 0.42, (hip[1] + foot[1]) * 0.62,
                    z0 + 0.07 + lift * 0.5)
            caps.append((hip, knee, 0.014, "leg", side))
            caps.append((knee, foot, 0.012, "leg", side))
    return ell, caps, z0


# ---------------------------------------------------------------------------
# Proyección y rasterizado
# ---------------------------------------------------------------------------

def view_matrix(view, direction):
    """Matriz ortonormal modelo → vista (sx derecha, sy abajo, profundidad hacia la cámara).
    Dirección 0 = este; el índice crece en sentido horario en pantalla."""
    a = 2.0 * math.pi * direction / DIRECTIONS
    F = np.array([math.cos(a), math.sin(a)])
    if view == "top":
        L = np.array([math.sin(a), -math.cos(a)])          # la izquierda del modelo, en pantalla
        return np.array([[F[0], L[0], 0.0], [F[1], L[1], 0.0], [0.0, 0.0, 1.0]]), 1
    s = 1 if math.cos(a) >= -1e-9 else -1                   # mirando a la derecha o a la izquierda
    U = np.array([math.sin(a), -math.cos(a)]) * s           # el «arriba» del modelo, en pantalla
    return np.array([[F[0], 0.0, U[0]], [F[1], 0.0, U[1]], [0.0, -s, 0.0]]), s


def tone(ramp, shade):
    cols = PALETTE[ramp]
    i = min(len(cols) - 1, max(0, int(shade * len(cols))))
    return cols[i]


def render(variant, base_px, zoom, view, direction, frame):
    name, len_k, head_k, gaster_k, red, wings = variant
    queen = name == "reina"
    length_px = base_px * len_k * zoom
    cell = int(math.ceil(CELL_FACTOR * length_px))
    ell, caps, z0 = ant_model(head_k, gaster_k, queen, frame / FRAMES)
    M, s = view_matrix(view, direction)
    scale = length_px / MODEL_LEN
    # Pivote = centro del tórax en las dos vistas (contrato). `feet_px` dice cuánto
    # hay del pivote al suelo en perfil, para apoyar la hormiga en la superficie.
    pivot_model = np.array([0.03, 0.0, z0])
    c = cell / 2.0
    ys, xs = np.mgrid[0:cell, 0:cell]
    px = (xs + 0.5 - c) / scale
    py = (ys + 0.5 - c) / scale
    depth = np.full((cell, cell), -1e9)
    color = np.zeros((cell, cell, 4), dtype=np.uint8)
    light = np.array([-0.35, -0.65, 0.68])
    light /= np.linalg.norm(light)

    def put(mask, d, rgb):
        upd = mask & (d > depth)
        depth[upd] = d[upd]
        color[upd, 0], color[upd, 1], color[upd, 2] = rgb[0], rgb[1], rgb[2]
        color[upd, 3] = 255

    min_r = 0.52 / scale                                   # ~1 px como mínimo
    for (cen, rad, mat) in ell:
        cv = M @ (np.array(cen) - pivot_model)
        R = M @ np.diag(1.0 / np.array(rad) ** 2) @ M.T     # forma cuadrática en vista
        dx = px - cv[0]
        dy = py - cv[1]
        # (dx, dy, t)ᵀ R (dx, dy, t) = 1  →  a t² + b t + cc = 0
        a = R[2, 2]
        b = 2.0 * (R[0, 2] * dx + R[1, 2] * dy)
        cc = R[0, 0] * dx * dx + 2 * R[0, 1] * dx * dy + R[1, 1] * dy * dy - 1.0
        disc = b * b - 4 * a * cc
        hit = disc >= 0
        t = (-b + np.sqrt(np.maximum(disc, 0))) / (2 * a)
        d = cv[2] + t
        nx = R[0, 0] * dx + R[0, 1] * dy + R[0, 2] * t
        ny = R[1, 0] * dx + R[1, 1] * dy + R[1, 2] * t
        nz = R[2, 0] * dx + R[2, 1] * dy + R[2, 2] * t
        nn = np.sqrt(nx * nx + ny * ny + nz * nz) + 1e-9
        lam = np.clip((nx * light[0] + ny * light[1] + nz * light[2]) / nn, 0, 1)
        ramp = {"body": "body", "head": "red" if red else "body", "wing": "wing"}[mat]
        for i in range(len(PALETTE[ramp])):
            lo = i / len(PALETTE[ramp])
            hi = (i + 1) / len(PALETTE[ramp]) if i < len(PALETTE[ramp]) - 1 else 2.0
            sel = hit & (lam * 0.95 + 0.05 >= lo) & (lam * 0.95 + 0.05 < hi)
            put(sel, d, PALETTE[ramp][i])
    for (pa, pb, r, mat, side) in caps:
        A = M @ (np.array(pa) - pivot_model)
        B = M @ (np.array(pb) - pivot_model)
        rr = max(r, min_r)
        abx, aby = B[0] - A[0], B[1] - A[1]
        L2 = abx * abx + aby * aby + 1e-12
        tt = np.clip(((px - A[0]) * abx + (py - A[1]) * aby) / L2, 0, 1)
        qx = A[0] + abx * tt
        qy = A[1] + aby * tt
        dist = np.sqrt((px - qx) ** 2 + (py - qy) ** 2)
        hit = dist <= rr
        d = A[2] + (B[2] - A[2]) * tt + np.sqrt(np.maximum(rr * rr - dist * dist, 0))
        # Patas del lado lejano (perfil): tono más claro, como en el arte actual.
        far = view == "side" and side != 0 and (side * -s) < 0
        ramp = "leg_far" if far else "leg"
        if far:
            put(hit, d, PALETTE[ramp][0])
        else:   # el eje de la pata algo más claro que el borde (volumen)
            put(hit & (dist >= rr * 0.5), d, PALETTE[ramp][0])
            put(hit & (dist < rr * 0.5), d, PALETTE[ramp][1])
    img = Image.fromarray(color, "RGBA")
    meta = {"cell": cell, "length_px": length_px, "scale": scale, "z0": z0,
            "head_reach_px": (0.22 + 0.05 * (head_k - 1) + 0.12 * head_k - 0.03) * scale,
            "feet_px": z0 * scale}
    return img, meta


def build(base_px, preview):
    out_dir = OUT / f"base{base_px}"
    out_dir.mkdir(parents=True, exist_ok=True)
    for variant in VARIANTS:
        name = variant[0]
        levels = []
        for level, zoom in LEVELS:
            sheet = None
            meta = None
            for vi, view in enumerate(("top", "side")):
                for d in range(DIRECTIONS):
                    for f in range(FRAMES):
                        img, meta = render(variant, base_px, zoom, view, d, f)
                        cell = meta["cell"]
                        if sheet is None:
                            sheet = Image.new("RGBA", (FRAMES * cell, 2 * DIRECTIONS * cell), (0, 0, 0, 0))
                        sheet.paste(img, (f * cell, (vi * DIRECTIONS + d) * cell))
            fname = f"ant_{name}_L{level}.png"
            sheet.save(out_dir / fname)
            cell = meta["cell"]
            levels.append({
                "level": level, "zoom": zoom, "ant_length_px": round(meta["length_px"], 2),
                "cell_px": [cell, cell], "pivot_px": [cell / 2.0, cell / 2.0],
                "head_reach_px": round(meta["head_reach_px"], 2), "feet_px": round(meta["feet_px"], 2),
                "file": fname,
            })
            if preview and level == 1:
                sheet.resize((sheet.width * 3, sheet.height * 3), Image.NEAREST).save(
                    out_dir / f"_preview_{name}_L1.png")
        manifest = {
            "variant": name, "base_px": base_px,
            "directions": DIRECTIONS, "direction_zero": "east", "direction_order": "clockwise_on_screen",
            "frames": FRAMES, "gait": "alternating_tripod", "rest_frame": 0,
            "stride_mm": round(STRIDE_BODY * base_px * variant[1], 3),   # 1 px a ×1 = 1 mm
            "views": ["top", "side"], "rows_per_view": DIRECTIONS,
            "pivot": "thorax_center",
            "levels": levels,
        }
        (out_dir / f"ant_{name}.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False))
        print(f"base {base_px}: {name} → celdas {[l['cell_px'][0] for l in levels]}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", type=int, action="append")
    ap.add_argument("--preview", action="store_true")
    a = ap.parse_args()
    for b in (a.base or [9, 13]):
        build(b, a.preview)


if __name__ == "__main__":
    main()
