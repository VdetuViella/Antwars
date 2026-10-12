# Arquitectura técnica

## 1. Motor
**Godot 4.7.x estándar con GDScript tipado** (ADR-001). Renderizador *GL Compatibility* (OpenGL 3.3 / ES 3), necesario para la transparencia por píxel en Windows y para que funcione en gráficas integradas.

Comparativa original (de la investigación):

| Criterio | Godot 4 | Unity | Web + Tauri | Electron | Bevy |
|---|---|---|---|---|---|
| Ventana sin bordes, transparente y siempre encima | Nativo | Plugins o código nativo | Sí | Sí | Sí, vía winit |
| Click-through | `window_set_mouse_passthrough` | Código nativo | Sí | Sí | Parcial |
| Miles de agentes | MultiMesh + SoA | DOTS | WASM | Peor | Excelente |
| Consumo en segundo plano | Bueno, configurándolo a mano | Bueno | Bueno | Malo (RAM) | Bueno |
| Licencia | MIT | Por ingresos | Libre | Libre | Libre |
| Para un agente de IA | Proyecto en texto | Escenas pesadas | Alto | Alto | Sin editor |

## 2. Estructura del repositorio

```
AntWars/
├─ project.godot            # Godot 4.7, GL Compatibility, ventana transparente permitida
├─ CLAUDE.md                # guía para el agente programador
├─ data/species/*.json      # parámetros biológicos (procedencia [C]/[A]/[D])
├─ sim/                     # simulación pura (RefCounted, sin nodos)
│  ├─ sim_const.gd          # constantes y enums
│  ├─ sim_world.gd          # orquestador: relojes, estímulos, semillas, órdenes, diario, guardado
│  ├─ ants.gd               # agentes SoA: umbrales, máquinas de estados, locomoción, ocupación
│  ├─ colony.gd             # biología por cohortes (online y offline)
│  ├─ nav_grid.gd           # transitabilidad y campos BFS
│  ├─ nest_plan.gd          # zonas de excavación (galerías, cámaras, tapón)
│  ├─ soil_grid.gd          # materiales, partículas de tierra suelta, regiones sucias
│  ├─ pheromone_field.gd    # feromonas con evaporación perezosa
│  ├─ formicarium_env.gd    # habitación, manta, hibernación, humedad, agua, comedero
│  ├─ sim_calendar.gd       # calendario biológico, fotoperiodo
│  ├─ species_def.gd        # carga JSON, dev_rate, castas
│  ├─ offline_resolver.gd   # progreso con el juego cerrado
│  ├─ save_system.gd        # guardado atómico, comprimido, con copias
│  └─ journal.gd            # diario / cuaderno de campo
├─ game/                    # presentación (nodos)
│  ├─ main.tscn / main.gd   # entrada, vista, ventana, foco, guardado automático, entrada del usuario
│  ├─ soil_renderer.gd      # textura del suelo por bloques sucios (máx. 10 Hz)
│  ├─ decor_layer.gd        # habitación, hierba, comedero, tubo, semillas, cría, granero, cristal
│  ├─ ant_renderer.gd       # MultiMesh de hormigas y de cargas, interpolación
│  ├─ pheromone_overlay.gd  # capa de feromonas (patrones además de color)
│  ├─ desktop_window.gd     # modos ventana y franja, click-through
│  ├─ game_settings.gd      # preferencias (user://settings.cfg)
│  ├─ shaders/              # ants (atlas + contorno), magnifier (lupa)
│  └─ ui/hud.gd             # barra, paneles, diario, ayuda, bienvenida, lupa
├─ assets/sprites/          # atlas generados por tools/gen_sprites.py
├─ tests/                   # tests headless (run_tests.gd + test_*.gd)
├─ tools/                   # sim_probe, make_test_save, bench, gen_sprites.py
└─ docs/                    # este documento, GDD, BIOLOGIA, SIMULACION, ROADMAP, ADR…
```

## 3. Flujo de datos
```
main._process(dt) ──► SimWorld.advance(dt, coarse)
                         ├─ step_behaviour ×N  (Ants, SoilGrid, NavGrid, NestPlan, estímulos)
                         └─ step_bio ×M        (FormicariumEnv, Colony → eventos → sync_agents, diario)
render (lee el estado): SoilRenderer · DecorLayer · PheromoneOverlay · AntRenderer · Hud
órdenes: Hud.action → main._on_action → SimWorld.cmd_*
```

## 4. Rendimiento
- **Hormigas:** un único `MultiMeshInstance2D` con atlas; `INSTANCE_CUSTOM` = (columna, fila, volteo H, volteo V); buffer de 12 floats por instancia que se escribe de una vez cada frame. Las cargas (semillas, tierra, pan…) van en un segundo MultiMesh.
- **Suelo:** `Image` RGBA de 640×240; solo se repintan los bloques de 8×8 sucios, como mucho 10 veces por segundo.
- **Simulación:** SoA, evaporación perezosa de feromonas, BFS solo cuando algo cambia, partículas solo en celdas activas y hormigas en reposo sin coste.
- **Presupuesto objetivo:** tick de comportamiento por debajo de 4 ms con 1.200 agentes; menos del 2 % de CPU sin foco (10 FPS, pasos de 0,5 s). `tools/bench.gd` mide el tick.
- **Plan B** (ADR-001): GDExtension para `ants.gd` y `nav_grid.gd`.

## 5. Guardado (`SaveSystem`)
- Archivo `user://antwars_save.dat` (en Windows, `%APPDATA%\Godot\app_userdata\AntWars\`).
- Formato: `"ANTW"` + versión (u32) + tamaño (u32) + tamaño comprimido (u32) + `var_to_bytes(dict)` comprimido con zstd + hash.
- **Escritura atómica** (`.tmp` → renombrar) y 3 copias rotativas (`.bak1–3`). Si un guardado está dañado, se carga la copia siguiente (`test_corrupt_save_uses_backup`).
- `SimWorld.SAVE_VERSION` + `SaveSystem.migrate()`: cada cambio de formato sube la versión y añade una migración con su test.
- Guardado automático cada 120 s, al perder el foco y al cerrar. `saved_at_real` (hora real del sistema) alimenta la resolución offline.

## 6. Ventana de escritorio
Ver ADR-004. `project.godot`: `window/per_pixel_transparency/allowed=true`, `window/size/transparent=true` y `viewport/transparent_background=true`. En modo ventana hay un `ColorRect` opaco detrás.

## 7. Tests
`tests/run_tests.gd` (SceneTree headless) descubre `tests/test_*.gd`, que heredan de `TestCase` (`check`, `check_eq`, `make_world`), ejecuta los métodos `test_*` y admite un filtro por argumento.

| Archivo | Qué cubre |
|---|---|
| `test_basics.gd` | Calendario y luz, calibración de `dev_rate`, modelo de temperatura, generación del mundo |
| `test_simulation.gd` | Determinismo, secuencia de fundación, conservación del suelo, campos de navegación, forrajeo cruzando la boca |
| `test_save_offline.gd` | Ida y vuelta del guardado, copia de seguridad ante corrupción, offline coherente con online, no castigo, fundación offline |
| `test_scripts_compile.gd` | Todos los scripts del proyecto compilan |

Ejecutar: `godot --headless --path . --import` y después `godot --headless --path . --script res://tests/run_tests.gd -- [filtro]`.

## 8. Exportación
Plantillas de exportación de Godot 4.7.2. Destinos: Windows x86_64 (principal), Linux x86_64 y macOS (pendiente de firmar). La configuración vive en `export_presets.cfg`. Steam (Steamworks, nube y logros) llega en la beta.

## 9. Localización y accesibilidad
- Textos en es-ES en el código por ahora. ⬜ Pasar a `tr()` con claves y `.po` (es, en) antes de la alpha.
- Feromonas con patrón además de color ✅. ⬜ Escala de UI, reducir movimiento, controles remapeables.
