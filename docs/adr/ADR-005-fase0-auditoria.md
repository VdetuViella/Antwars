# ADR-005 · Fase 0 — Auditoría (solo lectura)

- **Fecha:** 2026-10-13 · rama `adr-005-detalle-zoom`
- **Alcance:** no se ha cambiado ningún comportamiento. Solo se añaden este informe y el ADR-005 a `docs/adr/`.
- **Número del ADR:** 005 es el siguiente libre (existen 001–004). ✅

## 1. Cómo se hace hoy el zoom y el desplazamiento

- **No hay `Camera2D` ni `SubViewport`.** Todo el mundo cuelga de un `Node2D` (`world_root`, en `game/main.gd`) al que se le aplica `scale = Z` (entero) y `position` = desplazamiento en píxeles enteros (`_layout_world`).
- **Zoom actual** (cambiado ayer, a petición tuya): en modo ventana es **automático**, el mayor entero que cabe (×2 en 1280×560, ×3 en 1920×1040). Con `+`/`−` pasa a manual (×1–×8) y con `0` vuelve al automático. En la franja es manual (×2 por defecto). El ADR asume «×1–×4 con + y −», que ya no es lo que hay.
- **Anclaje del zoom (cuestión 2):** si el formicario cabe, se centra. Si no cabe, `_pan` es un desplazamiento absoluto que se recorta a los bordes, así que en la práctica el zoom se ancla en la esquina superior izquierda de lo que se ve. No se ancla al centro ni al cursor.
- La interfaz (`Hud`) va en su propio `CanvasLayer` sin escalar, así que la regla 8 (escala de UI independiente) ya se cumple.

## 2. Cómo se pinta cada cosa

| Elemento | Implementación actual | Resolución | ¿Cumple D2? |
|---|---|---|---|
| Suelo y partículas (tierra suelta, montículo, basurero, tapón) | `SoilRenderer` (`Sprite2D`) con un `ImageTexture` RGBA de 640×240 (1 texel = 1 celda) calculado en GDScript: rampa de 4 tonos por material con hash de coordenadas, oclusión en las galerías y oscurecimiento por profundidad. Se repinta por bloques sucios de 8×8 a 10 Hz como máximo | 1 texel/celda, ampliado por `world_root.scale` | ❌ repite cada texel Z×Z |
| Feromonas | `PheromoneOverlay` (`Sprite2D`) con una imagen de 160×60 (celda de 4×4 px de mundo), escala ×4 y luego ×Z; se actualiza cada 0,4 s si está visible | 1 texel / 4 celdas | ❌ |
| Semillas, cría, granero, comedero, tubo de agua, reina (cría) | `DecorLayer.BACK`: llamadas `draw_texture_rect_region` con el atlas de objetos de 8×8 (`items.png`) y `draw_rect` en coordenadas de mundo; redibujo cada 0,12 s | Atlas de 1 texel = 1 mm | ❌ |
| Hierba | `DecorLayer`: `draw_line` de 1 unidad de mundo, con vaivén ligado al tiempo | 1 mm por línea → Z px | ❌ |
| Pared, balda, cristal | `DecorLayer.ROOM` / `FRONT`: rectángulos y líneas | Se escalan | ❌ (decorado) |
| Hormigas y cargas | 2 `MultiMeshInstance2D` (ver §3) | Atlas de 1 texel = 1 mm | ❌ |

**Importación y filtros:** `default_texture_filter = Nearest` (proyecto), `snap_2d_transforms/vertices_to_pixel = true`; los atlas `ants.png` e `items.png` se importan **sin pérdida** (`compress/mode=0`) y **sin mipmaps**. Las texturas del suelo y de las feromonas son `ImageTexture` creadas en tiempo de ejecución (sin compresión) con `TEXTURE_FILTER_NEAREST` en el nodo. ✅ (la regla 5 se cumple hoy, salvo que todo se amplía Z veces)

## 3. Cómo se dibujan hoy las hormigas

- **Un `MultiMesh`** (transform 2D + `INSTANCE_CUSTOM`) con quads de 24×24 unidades de mundo; los objetos que llevan en las mandíbulas van en un segundo `MultiMesh` superpuesto (8×8).
- `INSTANCE_CUSTOM` = **(columna del atlas, fila = casta, volteo H, volteo V)**. Columna = dirección base × 8 + fotograma.
- **Direcciones:** 8, sin giro libre. Se dibujan 3 bases (E, NE, N) y el resto sale de **volteos**. **NE y N se obtienen rotando pixel art con RotSprite** en `tools/gen_sprites.py`, justo lo que el ADR desaconseja (D6).
- **Fotogramas:** 6 de marcha en trípode + 2 de reposo (antenas). El cadáver va en otra columna.
- **Tamaño a ×1 (desde ayer):** cuerpo de 13 px (menor), 16 (media), 17 (mayor), 21 (reina) y 11 (nanitic); con las patas abarcan unos 17 px. ⚠️ **El ADR supone «hoy 8–9 px» (D4)**: eso era el arte de antes de ayer.
- **Posición:** interpolada entre pasos de comportamiento y ajustada al píxel de mundo (`floorf(x) + 0.5`). A ×Z se mueven a saltos de Z píxeles de pantalla.
- **Contorno de 1 px** en el shader `ants.gdshader` (lee los 4 vecinos del atlas dentro de la celda).
- **Sin descarte por vista:** cada fotograma se recorren las `cap` = 1.200 ranuras en GDScript y se suben todas las vivas.
- La orientación y la elección de fotograma ya se calculan en el dibujo (`AntRenderer`), salvo el contador de animación (ver §4).

## 4. ¿Expone la simulación la orientación?

Sí, en solo lectura:

- `Ants.dir8` (0–7, cuantizado de `atan2` del último paso, sin histéresis) y `Ants.hdir` (lado en la superficie).
- `Ants.prev_px/prev_py` + `px/py` permiten calcular en la vista la dirección de movimiento interpolada para **16 direcciones con histéresis**, sin tocar `sim/`.
- ⚠️ **Desviación del ADR:** el contador de fase de la marcha (`Ants.anim`) **vive en `sim/`**. Avanza con `dt·velocidad·0,9`, se guarda en la partida y se inicializa con `rng_ants.randf()` en `spawn`, así que consume RNG de la simulación. No entra en `state_hash`. Propuesta: **no tocarlo** (quitarlo cambiaría el formato del guardado y el consumo de RNG; reglas 2 y 3) y calcular la fase nueva en la vista con la distancia interpolada y un hash del índice, como pide el ADR. `anim` quedaría como campo heredado, sin uso en el camino nuevo.

## 5. Lupa, modo franja y click-through

- **Lupa:** `ColorRect` a pantalla completa con un shader que muestrea `hint_screen_texture` (filtro *nearest*) y amplía ×3 la imagen ya renderizada, es decir, repite píxeles de pantalla. No encaja con D2 ni con los pasos ×1/×2/×4 (cuestión abierta 1). No la toco.
- **Franja:** usa el zoom manual (×2 por defecto) y el formicario se pega a la barra con desplazamiento vertical. Con ×1/×2/×4 funciona igual; a ×4 una franja de 300 px enseña solo unos 66 mm de mundo en vertical.
- **Click-through:** el polígono se calcula con `world_root.position` y `world_root.scale.x`. Si `world_root` deja de escalarse (enfoque del ADR), hay que pasarle Z explícitamente. El cambio es trivial y no afecta a Windows ni a X11.
- Pincel de feromona y lupa convierten pantalla → mundo con `world_root.scale`: lo mismo.

## 6. Medidas base

Entorno: contenedor con 2 vCPU y **render por software (llvmpipe) en Xvfb**. Los FPS absolutos no son representativos de una GPU real; sirven para comparar.

| Caso | Tick de simulación (sin interfaz) | Frame (ventana ×2, 1280×560) | Frame (×3, 1920×1040) |
|---|---|---|---|
| 121 hormigas (día 120) | 0,8–1,5 ms | ~25 ms (40 FPS) | ~55 ms (18 FPS) |
| 1.200 hormigas (tope de agentes) | **12,4 ms** | ~100 ms (10 FPS) | ~150 ms (7 FPS) |

**Lectura:**

- Con 1.200 hormigas manda la **simulación en GDScript**, no el dibujo: 12 ms por tick, con 1–6 ticks por frame. Es un riesgo propio (ADR-001, plan B con GDExtension) y no lo causa este ADR, pero condiciona el criterio 6 (≤ +10 % de tiempo de frame).
- El coste fijo crece con el área de pantalla (rasterizado por software), algo que en tu PC lo hará la GPU.
- Para medir el criterio 6 de verdad, propongo un **contador de tiempo de frame activable (F3)** que puedas mirar en tu PC (Fase 1/2, desactivado por defecto).

## 7. Riesgos y desviaciones respecto al ADR

| # | Tema | Situación | Necesita decisión |
|---|---|---|---|
| R1 | **Zoom automático vs. D1 (solo ×1, ×2, ×4)** | Ayer pediste que el formicario crezca con la ventana; hoy da ×3 a 1920×1040. Con pasos {1, 2, 4}, a 1920×1040 solo cabe ×2 (1280×480): el formicario se vería **más pequeño que ahora**. ×4 (2560×960) no cabe a lo ancho y obliga a desplazarse | **Sí** (ver preguntas) |
| R2 | **Tamaño de la hormiga a ×1 (D4)** | El ADR dice «9 px, aspecto actual», pero el actual es de 13–17 px. Las dos cosas no pueden ser verdad a la vez | **Sí** |
| R3 | **Vista cenital (Fase 3) vs. perfil actual** | Las hormigas se ven ahora de **perfil** (el suelo de la superficie es una línea de perfil). La Fase 3 pide render **cenital** a 16 direcciones. Una hormiga cenital caminando por la superficie se verá «desde arriba» sobre un suelo dibujado de lado. Dentro del nido se justifica (caminan por el cristal) | **Sí** |
| R4 | D2 obliga a reestructurar toda la vista | `world_root.scale` debe quedar en 1 y cada capa dibujar a resolución de pantalla: suelo → shader; decorado (`DecorLayer`, ~200 líneas de `draw_*`) → por nivel; feromonas → shader; hormigas y objetos → atlas por nivel. Es la mayor parte del trabajo de la Fase 2. Encaja con lo recomendado en «Escala» (no hay `Camera2D` que mantener) | No (confirmación) |
| R5 | ×1 idéntico bit a bit con el interruptor apagado | Viable: con el interruptor apagado se ejecuta el camino actual sin cambios | No |
| R6 | ×1 con el interruptor encendido | El shader de suelo tiene que reproducir la oclusión de galerías y el oscurecimiento por profundidad de `SoilRenderer` para que ×1 «coincida». Es posible, pero exige pasar a GPU una textura de materiales (R8) y la lógica de color | No |
| R7 | Fase de la marcha en `sim/` (§4) | Se deja como está; la vista calcula su propia fase | No (confirmación) |
| R8 | Rotar pixel art (RotSprite) hoy | Desaparece con los atlas de 16 direcciones pre-renderizados | No |
| R9 | **Memoria de texturas (cuestión 9)** | Las cargas ya van en un `MultiMesh` aparte, así que **no hacen falta variantes «con carga»**. Con 5 castas × 3 niveles × 16×8 ≈ 9,5 MiB, por debajo de los 15 estimados | Confirmar |
| R10 | Blender / `bpy` para la Fase 3 | No hay Blender en el entorno y PyPI no responde ahora mismo (DNS). Alternativa: un **renderizador 3D propio en Python + numpy** (elipsoides y cápsulas, ortográfico, sin antialiasing, determinista) que cumpla el mismo contrato de atlas. Si quieres Blender de verdad, el script `bpy` se puede ejecutar en tu PC | Preferencia |
| R11 | Rendimiento con 1.200 hormigas | Ya está por encima de presupuesto en la simulación (§6) | Informativo |
| R12 | Sin descarte por vista | A ×2 y ×4 se suben todas las instancias; habrá que descartar las de fuera de la vista (lo pide el ADR) | No |

## 8. Preguntas para el propietario antes de la Fase 1

1. **Zoom (R1):** ¿qué prefieres?
   - **(a)** Pasos ×1/×2/×4 y, en ventana, el automático elige el mayor que cabe: ×2 en 1080p, más pequeño que ahora. *(Es la más fiel al ADR.)*
   - **(b)** Pasos ×1/×2/×4 sin automático; ×4 con desplazamiento libre.
   - **(c)** Mantener también ×3 como excepción del automático (rompe D1).
2. **Tamaño de la hormiga a ×1 (R2):** ¿el de ahora (13–17 px) o volvemos a unos 9 px como dice el ADR?
3. **Vista de las hormigas (R3):** ¿cenital en todas partes, o perfil en la superficie y cenital dentro del nido?
4. **Lupa (cuestión 1):** ¿te vale la propuesta por defecto (zoom temporal local de un paso, con el nivel de detalle correspondiente)? Mientras no decidas, no la toco.
5. **Arte de la Fase 3 (R10):** ¿renderizador propio en Python (todo aquí) o script de Blender para ejecutar en tu PC?

Mientras no respondas, para la Fase 1 usaré estos valores provisionales: (a) para el zoom; 9 px y 13 px como dos tamaños para comparar en el prototipo; cenital dentro del prototipo; la lupa sin tocar; y el renderizador propio.
