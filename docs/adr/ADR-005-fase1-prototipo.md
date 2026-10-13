# ADR-005 · Fase 1 — Prototipo aparte

- **Fecha:** 2026-10-13 · rama `adr-005-detalle-zoom`
- **Alcance:** escena independiente `prototypes/zoom_lod/`. **No se ha tocado `sim/` ni la escena principal**; los 17 tests siguen en verde.

## Entregables

| Pieza | Archivo |
|---|---|
| Escena del prototipo (+ README con teclas y argumentos) | `prototypes/zoom_lod/zoom_lod.tscn`, `proto_main.gd`, `README.md` |
| Shader del suelo por niveles | `prototypes/zoom_lod/soil_lod.gdshader` |
| Cargador de atlas con manifiesto (contrato) | `prototypes/zoom_lod/ant_atlas.gd` + `ant_lod.gdshader` |
| Renderizador 3D de hormigas (sin Blender) | `tools/gen_ant_atlas_3d.py` → `assets/ants_lod/base9/`, `base13/` |
| Paleta común (D9) | `data/palette.json` |
| Capturas y comparaciones | `docs/adr/img/adr005-f1-*.png` |

## Cómo funciona

- **Escala:** `world_root` no existe en el prototipo. El suelo es un `ColorRect` del tamaño del mundo en píxeles de pantalla (640·Z × 240·Z) en una posición entera, y las hormigas, `MultiMeshInstance2D` sin escalar cuyo quad mide una celda del atlas. Nada se amplía: cada texel cae en un píxel.
- **Suelo:**
  - a ×1 copia la textura actual de `SoilRenderer`;
  - a ×2 y ×4, cada subcelda toma un tono de la paleta de su material con un hash de sus coordenadas enteras;
  - en los bordes entre materiales, otro hash decide de qué lado cae cada subcelda (borde irregular y duro);
  - la oclusión de las galerías se mide desde el centro de cada subcelda.

  Fuente: una textura RG8 (material + profundidad) construida desde `SoilGrid.mat`.
- **Hormigas:**
  - 16 direcciones × 8 fotogramas por vista y nivel; fotograma 0 = reposo, con los seis pies en el suelo;
  - dirección: velocidad suavizada (0,15 s) cuantizada a 16, con histéresis de 4°;
  - fase: distancia recorrida / `stride_mm`, con fase inicial por hash del índice;
  - vista: **perfil** si hay suelo bajo los pies y el movimiento es casi horizontal; **cenital** en otro caso, con 0,3 s de histéresis;
  - descarte por vista activo.
- **Arte:**
  - modelo 3D (elipsoides + cápsulas) con trazado de rayos ortográfico en numpy, sin antialiasing (alfa 0/255) y con sombreado cuantizado a la paleta;
  - grosor mínimo de 1 px en patas y antenas;
  - marcha en trípode alterno, con la zancada calculada del propio modelo: 2,8 mm para la menor de 9 px y 4,0 mm para la de 13.

## Criterios comprobados

| Criterio | Resultado |
|---|---|
| 1. Pasos de zoom | Solo ×1, ×2 y ×4; `+`/`−` (y la rueda) suben o bajan un paso, con tope en los extremos y cambio instantáneo ✅ |
| 2. ×1 igual que hoy | Suelo a ×1 frente a la textura de `SoilRenderer`: **115.474 píxeles comparados, 0 distintos** ✅ |
| 3. 1 texel = 1 píxel | Tablero de depuración (tecla T): el suelo alterna en el **100 %** de los píxeles a ×1, ×2 y ×4; sobre las hormigas, tablero uniforme a ×4 ✅ |
| 4. Determinismo | No se toca `sim/`; los 17 tests pasan. El detalle del suelo es función pura de (coordenadas, material, nivel) ✅ |
| 5. Guardados | Sin cambios ✅ |
| 7. Calidad visual | Bordes de galería irregulares y duros a ×4, sin escalones de 4 px. Patas en trípode sin patinar. La dirección parpadeaba en el montículo (escalones de 1 px) y se ha corregido con el suavizado (`adr005-f1-direccion-suavizada.png`). **La valoración final es tuya** |

## Medidas (render por software en 2 vCPU; en una GPU serán mucho menores)

| Ventana | ×1 | ×2 | ×4 |
|---|---|---|---|
| 1280×560 | 11 ms/frame | 34 ms | 38 ms |
| 1920×1040 | 23 ms | 50 ms | 83 ms |

El coste extra a ×2 y ×4 es el **shader del suelo, que se ejecuta en cada píxel y en cada frame**. En la Fase 2 propongo **cachearlo**: renderizarlo a una textura solo cuando cambia el suelo o se mueve la cámara. Así el coste por frame queda como hoy y se cumple la regla 7 (sin foco no hay trabajo extra).

## Entero frente a subpíxel

En capturas fijas a ×2 no hay diferencia apreciable (`adr005-f1-entero-vs-subpixel.png`). El subpíxel («fat pixel») mezcla un píxel en las costuras, lo que rompe el «alfa 0 o 255» y pide filtro lineal en el atlas. **Recomendación: píxel entero.** A ×2 y ×4 el paso ya es de 0,5 y 0,25 mm, así que el movimiento se ve fluido.

## Base de 9 px frente a 13 px

Ver `adr005-f1-base9-vs-13.png`. Con 13 px la hormiga se lee mejor a ×1 y ×2 pero ocupa mucho en las galerías (que miden 5–6 mm). Con 9 px se parece más a la escala real (*M. barbarus* menor: 3–6 mm) y gana mucho a ×4. **Recomendación: 9 px** (`ANT_BASE_PX = 9`), si te convence a ×1.

## Hallazgos y propuestas para la Fase 2

1. **Memoria:** con dos vistas, 5 variantes × 3 niveles ocupan **29 MiB** con la base de 9 (el presupuesto estimado era de 15). Opciones:
   - generar la vista de perfil solo en las 10 direcciones cercanas a la horizontal (≈ 24 MiB);
   - dejar la reina solo en cenital, porque casi no sale de la cámara;
   - aceptar los 29 MiB.
2. **Reposo:** el contrato solo tiene el fotograma 0. Se pierde el tanteo de antenas del arte actual. Propongo añadir al manifiesto un campo opcional `idle_frames` (2 fotogramas extra) en otro momento.
3. **Grano del suelo a ×4:** el hash por subcelda da un grano fino y uniforme. Se puede enriquecer con «piedrecitas» de 2–3 subceldas (ruido de valor por bloques) sin perder determinismo.
4. **Lupa:** sin tocar, pendiente de la cuestión 1.
5. **Integración:**
   - interruptor `detail_levels_enabled` (apagado por defecto);
   - sin `world_root.scale` cuando esté encendido;
   - el suelo con caché;
   - las hormigas con 5 `MultiMesh` (uno por variante), en lugar del actual.

   Después, feromonas, semillas, cría y hierba.
