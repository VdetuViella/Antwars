# CLAUDE.md — AntWars

## Qué es
Simulador idle de un formicario de *Messor barbarus* en 2D (pixel art fino) que vive en el escritorio, en una ventana normal o en una franja transparente. Godot 4.7 estándar + GDScript tipado (ADR-001).

Documentación: `docs/GDD.md` (diseño y estado), `docs/SIMULACION.md` (cómo funciona la sim), `docs/BIOLOGIA.md` (de dónde salen los números), `docs/ARQUITECTURA.md`, `docs/ROADMAP.md` (qué toca ahora), `docs/adr/`.
Ante una duda de diseño no resuelta en docs/, escribe un ADR nuevo y pregunta.

## Reglas de oro
1. **`sim/` no usa nodos, escenas, señales ni el reloj del sistema.** Solo `RefCounted` y tipos básicos. El tiempo real entra por `SimWorld.advance(dt)` y por `OfflineResolver.resolve(world, segundos)`.
2. **`game/` solo presenta y envía órdenes** (`SimWorld.cmd_*`). Nada de lógica de juego en escenas ni en la interfaz.
3. **Determinismo:** todo el azar pasa por `rng_world`, `rng_sim`, `rng_colony` o `rng_ants`. Prohibido `randf()` global, `Time.*` dentro de `sim/` (salvo conversiones de fecha en `SimCalendar`) e iterar diccionarios cuyo orden dependa de inserciones no deterministas.
4. **Números biológicos en `data/species/*.json`**, con su procedencia [C]/[A]/[D] en `_src`. Nada de números mágicos biológicos en el código.
5. **Packed*Array en GDScript son de copia en escritura:** modifícalos in situ a través del miembro (`ants.px[i] = …`), nunca a través de una variable local, o perderás los cambios (y en bucles copiarás el array entero).
6. **Rendimiento:** en bucles por hormiga, nada de crear Arrays o Dictionaries, nada de `str()` ni lambdas. Usa índices y Packed arrays.
7. **Guardado:** si cambia el formato, sube `SimWorld.SAVE_VERSION`, añade la migración en `SaveSystem.migrate()` y un test.
8. **No castigar la ausencia:** la resolución offline nunca mata a la reina salvo por vejez.

## Convenciones
- GDScript con tipos explícitos o inferidos (`:=`). Clases con `class_name`. Un sistema por archivo.
- Identificadores en inglés; comentarios, documentación y textos del juego en **español de España**.
- Commits en español, estilo descriptivo; terminar con las líneas de atribución que indique la sesión.

## Comandos
```bash
G=/ruta/a/godot   # Godot 4.7.2 estándar
$G --headless --path . --import                                      # registrar clases nuevas
$G --headless --path . --script res://tests/run_tests.gd -- [filtro] # tests (~3 min la suite completa)
$G --headless --path . --script res://tools/sim_probe.gd -- 6000 800 11 /tmp/p.png  # traza + imagen del nido
$G --headless --path . --script res://tools/make_test_save.gd -- 120 /tmp/t.dat     # partida avanzada
$G --path . -- --guardado=/tmp/t.dat --ventana --captura=/tmp/shot.png               # captura (con xvfb-run)
python3 tools/gen_sprites.py                                         # regenerar atlas de sprites
```
Argumentos del juego: `--nueva`, `--guardado=<ruta>`, `--escala=<realista|acompanante|acelerado|debug>`, `--franja`, `--ventana`, `--captura=<png>`.

## Cómo trabajar
- Tareas pequeñas: test que falla (si aplica) → cambio en `sim/` → integración en `game/` → documentación.
- Después de tocar la simulación: suite de tests y `sim_probe` con un par de semillas. Después de tocar el render: una captura en modo ventana y otra en franja con una partida avanzada.
- Actualiza el estado ✅/🟡/⬜ en `docs/GDD.md` y `docs/ROADMAP.md` al terminar una funcionalidad.

## Definición de «hecho»
- [ ] Todos los tests pasan (`run_tests.gd`), incluido el de compilación de scripts.
- [ ] Hay tests nuevos para el comportamiento nuevo (con algún caso límite).
- [ ] Sin regresiones de rendimiento apreciables (`tools/bench.gd`).
- [ ] Captura revisada si cambia algo visual.
- [ ] Documentación y estado actualizados.

## Qué NO hacer
- No crear un nodo por hormiga (usar el MultiMesh).
- No cambiar parámetros [C] sin citar la fuente.
- No añadir dependencias ni addons sin un ADR.
