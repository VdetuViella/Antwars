# ADR-005 — Detalle por zoom (×1, ×2, ×4)

- **Estado:** propuesta (Fase 0 entregada, pendiente de decisiones del propietario)
- **Fecha:** 2026-10-13 · @Gabriel

## Cómo usar este documento

Este ADR define qué se construye y en qué orden; el código real lo descubres tú en la Fase 0. No cambies ningún comportamiento existente hasta que el propietario apruebe el informe de la Fase 0.

**Léelo todo antes de empezar y consulta, en este orden:**

1. El GDD y el ROADMAP del proyecto (pilar 4, §6.3 excavación, §6.5 órdenes, §9 controles).
2. Los ADR-001 a ADR-004 (simulación separada de la vista, tiempo, cuidador, modos de ventana).
3. `docs/BIOLOGIA.md`, solo si tocas el aspecto o la marcha de las hormigas.

**Reglas de trabajo:**

- Trabaja en una rama o en una carpeta de prototipo; nunca directamente sobre la escena principal.
- Si algo de este documento choca con el código real, para y pregunta. No improvises una desviación.
- Cada fase termina con los tests de determinismo existentes en verde y un resumen corto para el propietario.
- Detente al final de cada fase y espera confirmación.

**Glosario:** *celda* = una celda de la rejilla de simulación (≈ 1 mm); *píxel* = píxel de pantalla; *nivel* (L0, L1, L2) = el juego de recursos de detalle para ×1, ×2 y ×4.

## Contexto y objetivo

Al hacer zoom, cada paso debe mostrar más detalle real en todo el mundo (suelo, hormigas, semillas, rastros) en vez de agrandar los mismos píxeles. El GDD define hoy un zoom de ×1 a ×4 con las teclas + y −; la Fase 0 debe confirmar cómo se implementa.

Las hormigas actuales son PNG con pocas variaciones de animación y no convencen al propietario. Busca un aspecto más bonito, vivo y nítido, con *Dead Cells* (3D renderizado a pixel art) y *Rain World* (piezas animadas por reglas) como referencias. Hacerlas más pequeñas no le importa.

## Decisiones

Las decisiones D1 a D3 las ha tomado el propietario; el resto son la propuesta de este ADR y pueden ajustarse tras el prototipo.

1. **D1. Zoom por pasos: ×1, ×2 y ×4.** Sin ×3 y sin zoom continuo; el cambio es instantáneo, sin fundidos. Motivo: píxeles perfectos en todos los pasos y menos arte que generar y comprobar.
2. **D2. El píxel de pantalla mide siempre lo mismo.** A ×Z, cada milímetro del mundo ocupa Z×Z píxeles con detalle propio. Nunca se amplía una imagen con filtrado ni se repite cada píxel Z veces.
3. **D3. Todo gana resolución:** suelo, hormigas, cría, semillas, hierba, montículo, rastros de feromona y bordes de galería. No solo las hormigas.
4. **D4. ×1 es el aspecto actual.** La hormiga mide unos 9 px de largo a ×1 (hoy 8–9 px), unos 18 px a ×2 y unos 36 px a ×4. El tamaño base es una constante configurable (`ANT_BASE_PX`), porque el propietario acepta hacerla más pequeña tras probar.
5. **D5. La simulación no se entera del zoom.** La rejilla de 640×240 celdas de ≈ 1 mm no cambia. El detalle extra es solo de dibujo, decorativo y determinista: función pura de material, coordenadas y nivel.
6. **D6. Hormigas con atlas pre-renderizados.** Un modelo 3D simple se renderiza sin antialiasing a N direcciones × M frames por nivel (punto de partida: 16 × 8). Motivo: nitidez, ningún giro de sprite (rotar pixel art lo distorsiona) y reutilización entre castas.
7. **D7. Marcha en trípode alterno con la fase ligada al desplazamiento.** Las patas van en dos grupos de tres: delantera y trasera de un lado con la media del otro. La fase avanza con la distancia recorrida, así las patas no patinan.
8. **D8. El estilo *Rain World* (patas, antenas y gáster como piezas animadas por reglas) queda para otro ADR.** El contrato del atlas permite cambiar el origen del arte sin tocar el render.
9. **D9. Una paleta común para los tres niveles,** por material, en JSON siguiendo la convención del proyecto. Bordes duros, sin difuminar.

## Reglas duras

Estas reglas no se negocian. Si una tarea obliga a romperlas, para y pregunta.

1. **Nada de zoom ni de detalle dentro de `sim/`** (ADR-001). La escala vive en la vista (cámara, shaders, escenas), nunca en `Colony`.
2. **El determinismo no se toca.** `state_hash`, los tests de determinismo y la conservación del suelo pasan igual con y sin el nuevo dibujo. El dibujo solo lee estado: no lo escribe ni consume la RNG de la simulación.
3. **Los guardados no cambian:** ni formato, ni versión, ni campos nuevos. Una partida de la versión anterior carga igual (`migrate()` intacto).
4. **×1 se ve como hoy.** Con el interruptor del sistema apagado, la imagen es idéntica bit a bit.
5. **Ninguna textura se amplía con filtrado.** En los tres niveles cada texel cae en un píxel de pantalla (1:1). Filtro `Nearest`, sin mipmaps y sin compresión con pérdida en los atlas.
6. **El detalle estático es determinista.** Mismas coordenadas, mismo material y mismo nivel dan siempre los mismos píxeles. Sin RNG global y sin `TIME` en el detalle del suelo.
7. **Sin foco no hay trabajo extra por fotograma.** El modo de bajo consumo (10 FPS, pasos de 0,5 s) no puede consumir más que hoy.
8. **La escala de la interfaz es independiente del zoom del mundo** (la escala de UI llega en la Fase 3 del ROADMAP).

## Diseño técnico

El zoom lo aplica la vista, no el motor, y cada elemento se dibuja a resolución de pantalla. Todo lo de esta sección es el enfoque recomendado; la Fase 0 confirma que encaja con el código real o propone una alternativa antes de implementar.

### Escala

La recomendación es dejar `Camera2D.zoom` en 1 y multiplicar por Z (1, 2 o 4) al convertir mundo a pantalla: en el shader del suelo y al colocar y dimensionar las instancias. Así cada píxel dibujado es un píxel de pantalla entero. La posición de la cámara también va en píxeles enteros, para que el suelo no "nade" al desplazarse.

Si esto rompe algo (lupa, modo franja, click-through), el agente lo documenta y propone otra vía.

### Suelo

La rejilla de materiales (tierra vegetal, tierra, arcilla, piedra, vacío) no cambia. Se pinta con un shader `canvas_item` que, por cada píxel de pantalla, calcula su posición en el mundo (`pos_mundo = camara + pixel / Z`) y lee el material de la celda con muestreo `Nearest`. La fuente de materiales es la que ya usa la vista; la Fase 0 dice cuál es.

- **Subceldas:** cada celda se divide en Z×Z subceldas (1, 4 o 16). Cada una toma un tono de la paleta de su material con un hash de sus coordenadas enteras, sin RNG.
- **Bordes:** en las subceldas junto a un material distinto (galerías, cámaras), un hash decide de qué lado cae cada una según los materiales vecinos. El borde queda irregular pero duro, sin degradados.
- **Excavación:** los cambios ya llegan por la fuente de materiales. El shader no guarda nada propio.

### Hormigas

Se mantiene el `MultiMesh` con atlas. Cada instancia lleva en `INSTANCE_CUSTOM` cuatro valores: dirección, frame, variante (casta y estado) y uno reservado. El nivel activo es global: un atlas por nivel que se cambia al hacer zoom.

- **Dirección:** el ángulo del movimiento interpolado se cuantiza a N direcciones, con una histéresis de unos pocos grados para que no parpadee entre dos direcciones vecinas.
- **Frame:** `fase += distancia_interpolada / zancada`; el frame es `floor(fase mod 1 × M)`. Si la hormiga está parada, pose de reposo. La fase inicial sale de un hash del id de la hormiga.
- **Dónde se calcula:** orientación y fase se calculan en el dibujo con la posición interpolada, nunca en `sim/`. Si la simulación ya expone una orientación, se usa solo en lectura.
- **Posición en pantalla:** por defecto, ajustada al píxel entero (pixel art puro). La alternativa a evaluar en la Fase 1 es movimiento subpíxel con muestreo "fat pixel" (antialiasing analítico con `fwidth`).
- **Vista:** a ×2 y ×4 caben menos hormigas; no se dibujan las instancias fuera de la vista si hoy se dibujan todas.

### Otras entidades

Semillas, cáscaras, cadáveres, hierba, montículo de tierra suelta, cría (huevos, larvas, pupas), reina y rastros de feromona también cambian por nivel. Hay dos vías:

- **Atlas por nivel,** como las hormigas, para objetos con forma propia: semillas, cría, reina, mechones de hierba.
- **Shader con hash por subcelda,** para campos continuos como el montículo y las feromonas: cada celda se rellena con subpíxeles por umbral de ruido, de modo que a ×4 no se vea como bloques de 4×4.

Prioridad: suelo y hormigas primero (Fase 1); el resto en la Fase 2.

### Ajustes de Godot

- `texture_filter` en `Nearest` para todo el mundo, sin mipmaps, y compresión sin pérdida en los atlas.
- Probar los tres niveles en modo ventana y en modo franja, con la ventana transparente y el click-through (ADR-004).

## Contrato del atlas de hormigas

El atlas es la interfaz entre el arte y el código: quien lo genere (Blender, a mano o un script) cumple este contrato, y el dibujo no sabe de dónde viene.

| Nivel | Zoom | Largo de hormiga (px) | Celda por frame (px) | Memoria por variante (16 × 8, RGBA8) |
| --- | --- | --- | --- | --- |
| L0 | ×1 | 9 | 14 × 14 | 98 KiB |
| L1 | ×2 | 18 | 27 × 27 | 364 KiB |
| L2 | ×4 | 36 | 54 × 54 | 1.458 KiB |

El total es de unos 1,9 MiB por variante. La celda mide 1,5 veces el largo de la hormiga para dejar sitio a patas y antenas; es una estimación que se ajusta al modelo real. Con unas 8 variantes (castas × con o sin carga) salen unos 15 MiB, a confirmar con el propietario.

**Reglas del atlas:**

- Un PNG por variante y nivel, más un manifiesto JSON por variante.
- Filas = direcciones; columnas = frames del ciclo de marcha. La dirección 0 mira a la derecha (este) y el índice crece en sentido horario en pantalla.
- El frame 0 es la pose de reposo.
- El pivote es el centro del tórax, en píxeles desde la esquina superior izquierda de la celda; puede caer entre píxeles.
- Fondo transparente, sin antialiasing y sin semitransparencias (alfa 0 o 255). Colores de la paleta común (D9).
- `stride_mm` es la distancia de mundo que recorre la hormiga en un ciclo completo y es igual en los tres niveles. El valor 9 es provisional: se calibra mirando que las patas no patinen.

**Manifiesto de ejemplo:**

```json
{
  "variant": "obrera_media",
  "directions": 16,
  "direction_zero": "east",
  "direction_order": "clockwise_on_screen",
  "frames": 8,
  "gait": "alternating_tripod",
  "rest_frame": 0,
  "stride_mm": 9.0,
  "levels": [
    {"level": 0, "zoom": 1, "ant_length_px": 9,  "cell_px": [14, 14], "pivot_px": [7.0, 7.0],   "file": "ant_obrera_media_L0.png"},
    {"level": 1, "zoom": 2, "ant_length_px": 18, "cell_px": [27, 27], "pivot_px": [13.5, 13.5], "file": "ant_obrera_media_L1.png"},
    {"level": 2, "zoom": 4, "ant_length_px": 36, "cell_px": [54, 54], "pivot_px": [27.0, 27.0], "file": "ant_obrera_media_L2.png"}
  ]
}
```

En la Fase 1 vale un atlas provisional (cuerpo de tres elipses y seis líneas, generado por script) que cumpla este contrato.

## Plan por fases

Son cuatro fases en orden, y el agente se detiene al final de cada una para enseñar el resultado al propietario.

1. **Fase 0: auditoría, solo lectura.** No se cambia nada. Se entrega un informe breve, en `docs/` o en el chat, con:
   - Cómo se implementan hoy el zoom y el desplazamiento (`Camera2D`, `SubViewport` o escalado de textura).
   - Cómo se pintan el suelo, las partículas, las feromonas, las semillas, la hierba, la cría y la reina, y qué ajustes de importación usan (filtro, mipmaps, compresión).
   - Cómo se dibujan hoy las hormigas: giro libre del sprite o direcciones fijas, tamaño, número de frames y qué guarda cada instancia del `MultiMesh`.
   - Si la simulación expone la orientación de cada hormiga.
   - Cómo interactúan con el zoom la lupa, el modo franja y el click-through.
   - Medidas base de tiempo de frame con unas 1.200 hormigas, y la lista de riesgos y desviaciones respecto a este ADR.
2. **Fase 1: prototipo aparte.** Una escena independiente (`prototypes/zoom_lod/` o una rama) con un trozo de suelo, unas 10 hormigas con atlas provisional y los tres zooms con las teclas + y −. No se toca `sim/` ni la escena principal. Entregables: la escena, el shader del suelo, el cargador de atlas con su manifiesto, capturas a ×1, ×2 y ×4, la comparación entre posición entera y subpíxel, y el tiempo de frame.
3. **Fase 2: integración con interruptor.** Un ajuste `detail_levels_enabled`, apagado por defecto. Apagado, nada cambia. Encendido, el suelo y las hormigas usan los niveles; después las demás entidades. Con tests de determinismo y de guardados.
4. **Fase 3: arte definitivo.** Un script de Blender (`bpy`) que construye una hormiga simple (cabeza, tórax, gáster y seis patas con ciclo de trípode alterno), la renderiza en vista cenital ortográfica sin antialiasing y empaqueta atlas y manifiesto por nivel. Variantes por casta y por carga. El propietario revisa el resultado.

## Criterios de aceptación

Una fase se da por buena solo si cumple los criterios que le corresponden. Los umbrales marcados como propuesta los puede ajustar el propietario.

1. **Pasos de zoom:** solo existen ×1, ×2 y ×4. La tecla + sube un paso y − baja uno, con tope en los extremos y cambio instantáneo.
2. **×1 idéntico:** con el interruptor apagado, la captura de un guardado de referencia es idéntica bit a bit a la anterior. Encendido, ×1 coincide con el aspecto actual.
3. **Píxeles uniformes:** una vista de depuración comprueba 1 texel = 1 píxel de pantalla en los tres niveles. Ninguna imagen se amplía con filtrado.
4. **Determinismo:** tras N pasos de simulación, `state_hash` es igual con el dibujo nuevo activado y desactivado. Los tests existentes siguen en verde. El mismo guardado produce la misma captura (hash de captura) en dos ejecuciones.
5. **Guardados:** formato y versión sin cambios; una partida de la versión anterior carga.
6. **Rendimiento (propuesta):** con 1.200 hormigas, el tiempo de frame a ×1, ×2 y ×4 no supera el actual en más de un 10 %. Sin foco, el consumo es el mismo que hoy.
7. **Calidad visual (revisa el propietario):** a ×4 los bordes de galería son irregulares y duros, sin escalones de 4 px. Las patas alternan sin patinar y la dirección no parpadea.
8. **Modos de ventana:** ventana y franja funcionan en los tres niveles, y el click-through no empeora donde hoy funciona (Windows y X11).

## Fuera de alcance

Este ADR no cubre lo siguiente; cualquier cosa de esta lista necesita una decisión aparte.

- Zoom continuo o ×3 (descartados).
- Animación procedural al estilo *Rain World* de patas y antenas (el contrato del atlas la deja abierta).
- Cambios en la simulación, en el formato de guardado, en la economía o en la biología.
- Nuevas especies y sus sprites (*Polyergus* y las demás del ROADMAP).
- Rediseñar la lupa, hasta resolver la cuestión abierta 1.
- Localización, accesibilidad, escala de UI y audio (Fase 3 del ROADMAP).

## Cuestiones abiertas

Nueve cuestiones siguen abiertas. Cada una trae una propuesta por defecto que el agente puede usar mientras no haya respuesta, salvo la lupa, que no se toca.

| # | Cuestión | Propuesta por defecto | Decide |
| --- | --- | --- | --- |
| 1 | La lupa amplía ×3 (GDD §6.5) y no encaja con los pasos ×1, ×2 y ×4 | Que sea un zoom temporal local de un paso (×1→×2, ×2→×4) con el nivel de detalle correspondiente | Propietario |
| 2 | Anclaje del zoom: centro de la pantalla o cursor | Mantener el comportamiento actual | El agente lo confirma en la Fase 0 |
| 3 | Tamaño base de la hormiga a ×1 (`ANT_BASE_PX`) | 9 px; reducirlo si el prototipo lo permite | Propietario |
| 4 | Direcciones y frames por ciclo | 16 × 8; probar 8 direcciones a ×1 si 16 no se distinguen | Prototipo |
| 5 | Posición en pantalla: píxel entero o subpíxel | Entero; comparar con capturas en la Fase 1 | Propietario |
| 6 | Longitud de zancada (`stride_mm`) | 9 mm provisional, calibrada a ojo | Prototipo |
| 7 | Cómo se aplica el zoom hoy (motor o shader) | El enfoque recomendado en «Escala» | El agente lo confirma en la Fase 0 |
| 8 | Número de este ADR | 005 si es el siguiente libre | El agente lo verifica |
| 9 | Presupuesto de memoria de texturas | ≈ 15 MiB para unas 8 variantes (estimado) | Propietario |

## Cambios propuestos en otros documentos y evidencia

Estos cambios en el GDD y el ROADMAP se proponen; no se aplican sin confirmación del propietario.

- **GDD §9, Controles:** «Zoom (×1–×4)» pasa a «Zoom por pasos (×1, ×2, ×4)».
- **GDD §2, pilar 4 («Pequeño pero nítido»):** añadir que el detalle crece con el zoom y que el píxel de pantalla se mantiene.
- **GDD §6.5, Lupa:** pendiente de la cuestión abierta 1.
- **ROADMAP, Fase 3:** añadir «Detalle por zoom (ADR-005)»; el propietario decide si se adelanta a la Fase 2.

### Evidencia

La investigación previa buscó casos parecidos. Solo la página de *Dead Cells* se abrió completa; las demás se leyeron como resultados de búsqueda.

- [Dead Cells: una tubería 3D para animación 2D](https://www.gamedeveloper.com/production/art-design-deep-dive-using-a-3d-pipeline-for-2d-animation-in-i-dead-cells-i-): render diminuto sin antialiasing, mapas de normales y animaciones reutilizables. Los píxeles que parpadean quedan sin resolver.
- [Stepping patterns in ants (J Exp Biol)](https://cob.silverchair.com/jeb/article-pdf/192/1/95/2854548/jexbio_192_1_95.pdf): marcha en trípode alterno en hormigas.
- [RotSprite (Sonic Retro)](https://info.sonicretro.org/RotSprite) y el [foro de Aseprite](https://community.aseprite.org/t/rotating-is-causing-distortion-to-the-sprite-solved/4380): rotar pixel art lo distorsiona; conviene rotar siempre desde el original.
- [Sub-Pixel Accurate Pixel-Sprite Filtering (Godot Shaders)](https://godotshaders.com/shader/sub-pixel-accurate-pixel-sprite-filtering/): antialiasing analítico para sprites de píxel; escrito para Godot 3.2 y requiere el filtro activado.
- [Godot: miles de peces con MultiMesh](https://docs.godotengine.org/es/stable/tutorials/performance/vertex_animation/animating_thousands_of_fish.html), [shaders CanvasItem](https://docs.godotengine.org/de/stable/tutorials/shaders/shader_reference/canvas_item_shader.html) y [MultiMeshInstance2D](https://docs.godotengine.org/uk/stable/classes/class_multimeshinstance2d.html): animación en GPU y `INSTANCE_CUSTOM`.
- [Blender to Pixels](https://astropulse.itch.io/blender-to-pixels): herramienta de 3D a pixel art en Blender.
- [Rain World: animación procedural (blog)](https://handandmachine.org/classes/computational_fabrication/2024/08/26/introduction-logan-sullivan/): piezas animadas por algoritmos en tiempo real.
