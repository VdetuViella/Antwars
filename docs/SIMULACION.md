# Especificación de la simulación

Describe la simulación **tal como está implementada** en `sim/`. Ninguna clase de `sim/` usa nodos, escenas ni el reloj del sistema (ADR-001). El host (`game/main.gd`) llama a `SimWorld.advance(dt_real)` y lee el estado para pintarlo.

## 1. Mundo y escalas

| Constante (`SimConst`) | Valor | Significado |
|---|---|---|
| `WORLD_W × WORLD_H` | 640 × 240 | Celdas de suelo (1 celda = 1 px lógico ≈ 1 mm) |
| `SURFACE_Y` | 60 | Altura media del suelo; por encima, el outworld |
| `NAV_CELL` | 2 | Nodos de navegación de 2×2 px (320 × 120 nodos) |
| `PHER_CELL` | 4 | Celdas de feromona de 4×4 px |
| `BEHAVIOUR_DT` | 0,1 s | Paso fijo de comportamiento |
| `BIO_STEP_SECONDS` | 600 s | Paso fijo de biología (10 min biológicos) |

## 2. Relojes (ADR-002)

`advance(real_dt, coarse)`:
1. Acumula tiempo real y ejecuta `step_behaviour(0,1)` (o pasos de 0,5 s en modo de bajo consumo), con un máximo de 6 por frame. Si va con mucho retraso, descarta el tiempo de comportamiento sobrante: lo visible no tiene que ser exacto.
2. Acumula `real_dt × time_scale` y ejecuta `step_bio(600)` las veces necesarias (máximo 400 por frame).

`work_value() = time_scale / behaviour_speed`: segundos biológicos de trabajo por segundo visible.

## 3. `step_behaviour`
En orden: hormigas (`Ants.step`) → partículas de tierra suelta → cada 0,5 s, transitabilidad y campos de distancia → cada 2 s, plan de nido → cada 5 s, campos de descanso por cámara → cada 3 s, estímulos de tareas → cada 1 s, mantenimiento de semillas visibles.

## 4. Biología de la colonia (`Colony.step`, paso de 10 min)

Es el **mismo código** online y offline.

- **Reina.** Envejece. En la fundación gasta reservas `0,25/día × metabolismo(T)` más `2,2` por cada larva que cría. Muere por vejez, por agotar las reservas o tras más de 25 días de hambre fuera de la fundación.
- **Puesta.** Por encima de 18 °C y fuera de la diapausa. En la fundación pone el lote (16 ± 3) en unos 6 días. Después, `min(30, 1 + 0,5·w^0,7) × f(T) × f(comida) × f(capacidad de nodrizas)`, con 6 larvas por obrera más 8 como capacidad máxima.
- **Cría.** Cohortes `{stage, n, p, fed}`. Avance `dev_rate(T)/días_etapa`; las larvas mal alimentadas avanzan más despacio y mueren más. Mortalidad basal del 0,2 % al día, desecación si la humedad de la cría baja de unos 35 % y hongos en los huevos si supera el 88 %.
- **Eclosión.** Las primeras `founding_batch_eggs` obreras son nanitics. Después, la casta sale al azar con las proporciones de `caste_ratios(w)` multiplicadas por la alimentación de la larva.
- **Molienda.** Capacidad de `0,6·menores + 1,5·medias + 4·mayores` semillas al día; mantiene unas reservas de pan para 3 días de larvas. Cada semilla molida deja cáscaras.
- **Consumo.** Las obreras comen del granero y del pan; en diapausa, el 15 %. Hambre → `starving_days` → mortalidad extra.
- **Moho.** Si la humedad del granero supera el 60 %, se pierde un 1,5 % de las semillas al día.
- **Aleatoriedad.** `_stoch_round` (valor esperado exacto) y `_binomial` (exacta hasta n = 40; aproximación normal por encima), siempre con `rng_colony`.

Los eventos que devuelve (`born`, `died`, `queen_died`, `mold`, `starving`…) alimentan el diario y `sync_agents`, que ajusta las hormigas visibles a la población real por casta hasta el tope `agent_cap` (1.200).

## 5. Agentes (`Ants`, SoA)

Arrays paralelos por campo (`px`, `py`, `node`, `task`, `state`, `carry`…). En GDScript hay que modificarlos **in situ**: copiar un `Packed*Array` a una variable local provoca una copia completa.

### 5.1 Jerarquía
**Tarea** (umbrales, revisada cada 15–35 s) → **estado** (máquina de estados por tarea, enum `St`) → **locomoción** de nodo a nodo con un presupuesto `velocidad × dt`.

### 5.2 Asignación de tareas (Bonabeau, Theraulaz y Deneubourg 1996)
- `P(empezar j) = s_j² / (s_j² + θ_ij²)`, probando las tareas en orden aleatorio; quedarse en la tarea actual multiplica el estímulo por 1,3.
- Refuerzo: θ de la tarea elegida −0,06 (mínimo 0,2) y el resto +0,012 (máximo 4).
- Umbral efectivo = θ individual × edad (nodriza ×0,6 si tiene menos de 20 días y ×1,5 si tiene más de 60; forrajera al revés) × casta (las mayores: molienda ×0,3, nodriza ×2,5).
- **Estímulo dinámico:** `SimWorld.compute_stimuli` calcula la plantilla deseada por tarea (nodrizas = cría/8; forrajeras según los días de reservas; excavadoras según los frentes y el déficit de espacio, con un tope de 0,7 por frente; molienda; limpieza) y la multiplica por la prioridad del jugador. Cada 3 s, `s_j ← clamp(s_j + 0,6·(deseadas − actuales)/max(deseadas, 2), 0, 5)`, así que la plantilla converge a la demanda.

### 5.3 Comportamientos
| Tarea | Ciclo |
|---|---|
| Forrajear | Ir a la entrada → buscar en superficie (elige lado según la feromona de comida y la pintada) → ir a la semilla → recogerla (vale `work_value()` semillas) → volver dejando rastro (intensidad = 1 + 0,35 × semillas cercanas) → granero |
| Excavar | Ir al frente (campo DIG) → excavar `dig_time_at` (dureza × humedad) → bolita de hasta 5 celdas → sacarla y tirarla junto a la entrada (con el nido sellado, se compacta en las paredes) |
| Nodriza | Cámara de cría ↔ granero (llevando pan) y paseo local entre la cría |
| Moler | Trabajo local en el granero |
| Limpiar | Granero → recoger cáscaras o cadáveres → basurero exterior |
| Descansar | Ir a «su» cámara (campo de descanso `i % n_cámaras`) → buscar un nodo libre → quieta 12–40 s |
| Reina | Excava la fundación → sella → vive en la cámara de cría más profunda, casi inmóvil |

### 5.4 Ocupación de nodos
En cada paso se recalcula `occ` (hormigas por nodo). `_local` y `_local_rest` eligen el vecino menos ocupado. Antes de pararse a descansar se buscan hasta 6 huecos libres con un radio creciente, y `NavGrid.step_down` reparte el tráfico entre los vecinos igual de buenos. Resultado: las obreras se reparten por las cámaras en vez de apilarse.

## 6. Navegación (`NavGrid`)
- Un nodo es transitable si tiene al menos 3 de sus 4 píxeles de aire. Dentro del nido, cualquier hueco (caminan por el cristal). En el outworld, solo pegado al suelo o a la pila de tierra.
- **Campos de distancia BFS** (8 vecinos, sin cortar esquinas) desde fuentes: ENTRANCE, BROOD (todas las cámaras de cría), GRANARY, DIG (nodos junto a celdas pendientes), REST y QUEEN. Las hormigas bajan por el gradiente: es su memoria espacial más el olor del nido.
- Los campos se recalculan solo cuando cambia la transitabilidad (`walk_version`) o las fuentes.
- `step_surface` camina por el relieve del outworld (sube y baja por el montículo).

## 7. Feromonas (`PheromoneField`)
Rejillas de 160 × 60. Tipos: FOOD (ρ = 1/420 s⁻¹), DIG (1/90), ALARM (1/20) y PLAYER (1/900). **Evaporación perezosa:** cada celda guarda su valor y la hora de la última escritura, y al leer se aplica `v·e^(−ρΔt)`. Es exacta y no obliga a recorrer la rejilla en cada tick. No hay difusión en esta versión ⬜.

## 8. Plan de nido (`NestPlan`)
- **Fundación:** una galería vertical de 26–32 px y una cámara de cría de 6×3 que crece hasta 13×5 de radio.
- **Necesidad de espacio** (`SimWorld.space_need`, [D]): cría `150 + 34·w^0,9 + 4·b^0,85` px²; granero `80 + 30·(semillas/50)^0,7` px².
- Cuando una cámara no tiene celdas pendientes y falta espacio, crece (+2 rx, +1 ry) hasta su máximo (19×7 para cría, 22×6 para granero). Si no puede crecer, se planea una cámara nueva: una galería inclinada de 22–40 px desde una cámara o galería existente, sin chocar con otras cámaras, sin piedra en el centro, y con los graneros a menos de 90 px de profundidad (más secos).
- Con déficit alto se abren hasta 4 zonas a la vez (`1 + déficit/700`).
- **Tapón:** al terminar la fundación, la reina sella la boca con material PLUG. Cuando nace la primera obrera, el tapón entra en las zonas activas y las obreras lo excavan (evento `plug_open`).

## 9. Suelo (`SoilGrid`)
- Materiales: AIR, TOPSOIL, SOIL, CLAY, LOOSE, ROCK, MIDDEN y PLUG, con dureza 1–3 y piedra no excavable.
- **Tierra suelta** con física de arena: solo se actualizan las celdas de la lista `active` (cae y se desliza en diagonal). La tierra que cae dentro del nido se registra como `debris` y las obreras la retiran.
- El montículo y el basurero se erosionan poco a poco (8 y 6 celdas al día).
- Contadores de conservación (`removed_total`, `dropped_total`, `eroded_total`, `placed_total`), comprobados por `test_soil_conservation`.

## 10. Entorno (`FormicariumEnv`, ADR-003)
Temperatura de la habitación `22,5 + 3,5·cos(2π(día_del_año − 205)/365) + 1·cos(2π(hora − 17)/24)`, más 3 °C con la manta. Diapausa del 1 de diciembre al 31 de enero a 14 °C. Humedad: evaporación de unos 3 % al día (según la temperatura), y el tubo rehidrata hacia el 60 % gastando 0,25 ml por punto. La humedad local depende de la profundidad (`±15 %`).

## 11. Progreso offline (`OfflineResolver`)
- Hasta 30 días reales y 730 días biológicos, en pasos de 1 hora biológica.
- **Forrajeo estimado:** `max(1, 0,2·w)` forrajeras × 30 semillas por hora, limitado por el comedero y los mechones (de día, con temperatura y sin la entrada sellada).
- Biología: `Colony.step` con el mismo entorno.
- **No castigo:** la reina no muere salvo por vejez y el hambre se acota a 20 días. Los cadáveres y cáscaras se retiran solos.
- **Excavación acelerada:** 40 celdas por obrera y día siguiendo el plan existente (solo celdas que tocan aire, para que la galería avance desde lo excavado), con la tierra al montículo.
- Al terminar: `sync_agents`, se reinician los estados y se recalculan los campos. Validado frente a la simulación completa con `test_offline_matches_online_population`.

## 12. Determinismo
Cuatro `RandomNumberGenerator` con semillas derivadas de la semilla de la partida: `rng_world` (generación), `rng_sim` (partículas, decisiones del mundo), `rng_colony` (biología) y `rng_ants` (agentes). Sus estados se guardan en la partida. Orden de iteración estable por índice. `state_hash()` resume suelo, posiciones, tareas, población, granero y reloj → `test_determinism_same_seed`.

## 13. Pendiente para la simulación ⬜
Difusión de feromonas; alarma y defensa; vuelo nupcial y linajes; lluvia e inundación; colonias vecinas; LOD con agentes que representan grupos (por encima del tope de 1.200).
