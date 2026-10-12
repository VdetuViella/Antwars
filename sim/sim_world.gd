class_name SimWorld
extends RefCounted
## Orquestador de la simulación. No conoce Godot más allá de tipos básicos:
## no usa nodos, escenas ni el reloj del sistema. El host (game/) llama a
## advance(dt_real) y lee el estado para pintarlo.
##
## Dos relojes:
##  · Comportamiento: las hormigas se mueven a velocidad real (para poder mirarlas).
##  · Biológico: calendario, cría, consumo… avanza a `time_scale` (×1, ×24, ×96).
## Cada viaje visible representa `work_value()` segundos biológicos de trabajo,
## así la economía es coherente en cualquier escala (ver ADR-002).

const SAVE_VERSION := 1

const PK := PheromoneField.Kind

var seed_value: int = 0
var species: SpeciesDef
var soil := SoilGrid.new()
var nav := NavGrid.new()
var pher := PheromoneField.new()
var ants := Ants.new()
var colony := Colony.new()
var cal := SimCalendar.new()
var env := FormicariumEnv.new()
var plan := NestPlan.new()
var journal := Journal.new()

var rng_world := RandomNumberGenerator.new()
var rng_sim := RandomNumberGenerator.new()
var rng_colony := RandomNumberGenerator.new()
var rng_ants := RandomNumberGenerator.new()

var time_scale: float = 24.0        ## segundos biológicos por segundo real
var behaviour_speed: float = 1.0    ## multiplicador de velocidad de las hormigas
var beh_time: float = 0.0
var beh_accum: float = 0.0
var bio_accum: float = 0.0
var priority: String = "equilibrio"
var agent_cap: int = 1200

var stimuli := PackedFloat32Array()
var desired := PackedFloat32Array()

# Semillas visibles en la superficie.
var seed_x := PackedFloat32Array()
var seed_y := PackedFloat32Array()
var seed_alive := PackedByteArray()
var seed_src := PackedByteArray()       ## 0 = comedero, 1 = mechón de hierba
var tuft_stock: float = 0.0
var midden_x: float = 0.0
var soil_compacted: float = 0.0
var seeds_delivered_today: float = 0.0

var _nav_timer: float = 0.0
var _plan_timer: float = 0.0
var _stim_timer: float = 0.0
var _seed_timer: float = 0.0
var _dig_sources_version: int = -1
var dig_front_count: int = 0
## Un campo de distancias por cámara de descanso: cada hormiga tiene «su» cámara
## preferida, así se reparten por el nido en vez de amontonarse en la primera.
var rest_fields: Array[PackedInt32Array] = []
var _rest_timer: float = 0.0
var _rest_key: String = ""


# ---------------------------------------------------------------------------
# Creación
# ---------------------------------------------------------------------------

func new_game(seed_v: int, start_unix: float, species_id: String = "messor_barbarus") -> void:
	seed_value = seed_v
	species = SpeciesDef.load_by_id(species_id)
	rng_world.seed = seed_v
	rng_sim.seed = seed_v * 7919 + 17
	rng_colony.seed = seed_v * 104729 + 31
	rng_ants.seed = seed_v * 1299709 + 47
	var ex := SimConst.WORLD_W / 2 - 20 + rng_world.randi_range(-30, 30)
	soil.setup(SimConst.WORLD_W, SimConst.WORLD_H)
	soil.generate(rng_world, ex)
	nav.setup(soil)
	pher.setup(SimConst.WORLD_W, SimConst.WORLD_H)
	colony.setup(species, rng_colony)
	cal.setup(start_unix)
	env = FormicariumEnv.new()
	env.feeder_x = clampi(ex + 190, 40, SimConst.WORLD_W - 40)
	midden_x = float(clampi(ex - 120, 30, SimConst.WORLD_W - 30))
	env.tuft_xs = PackedInt32Array([clampi(ex - 210, 20, SimConst.WORLD_W - 20), clampi(ex - 70, 20, SimConst.WORLD_W - 20), clampi(ex + 95, 20, SimConst.WORLD_W - 20)])
	plan.setup_founding(soil, ex, rng_world)
	plan.debris_ref = soil.debris
	journal = Journal.new()
	stimuli.resize(SimConst.N_TASKS)
	stimuli.fill(0.0)
	desired.resize(SimConst.N_TASKS)
	desired.fill(0.0)
	_clear_seeds()
	ants.setup(self, agent_cap)
	ants.spawn(SimConst.Caste.QUEEN, float(ex), float(plan.entrance_y - 2), 0.0, false)
	_refresh_sources(true)
	nav.refresh_fields()
	journal.add(0.0, cal.format_date_es(),
		"Una reina de Messor barbarus recién fecundada aterriza en tu formicario. Se arranca las alas y busca dónde excavar.",
		Journal.Level.MILESTONE)


## Rompe la referencia circular mundo ↔ hormigas (RefCounted) al descartar el mundo.
func dispose() -> void:
	ants.world = null
	ants.nav = null


func _clear_seeds() -> void:
	seed_x = PackedFloat32Array()
	seed_y = PackedFloat32Array()
	seed_alive = PackedByteArray()
	seed_src = PackedByteArray()


# ---------------------------------------------------------------------------
# Reloj
# ---------------------------------------------------------------------------

## Segundos biológicos que representa cada segundo de comportamiento visible.
func work_value() -> float:
	return time_scale / maxf(behaviour_speed, 0.01)


func bio_day() -> float:
	return cal.days_elapsed()


## Avanza la simulación con el tiempo real transcurrido.
## `coarse` = modo de bajo consumo (pasos de comportamiento más largos).
func advance(real_dt: float, coarse: bool = false) -> void:
	real_dt = clampf(real_dt, 0.0, 5.0)
	var bdt := SimConst.BEHAVIOUR_DT if not coarse else 0.5
	beh_accum += real_dt
	var steps := 0
	var max_steps := 6 if not coarse else 4
	while beh_accum >= bdt and steps < max_steps:
		step_behaviour(bdt)
		beh_accum -= bdt
		steps += 1
	if beh_accum > 1.0:
		beh_accum = 0.0   # si vamos con retraso, se descarta tiempo de comportamiento
	bio_accum += real_dt * time_scale
	var bio_steps := 0
	while bio_accum >= SimConst.BIO_STEP_SECONDS and bio_steps < 400:
		step_bio(SimConst.BIO_STEP_SECONDS)
		bio_accum -= SimConst.BIO_STEP_SECONDS
		bio_steps += 1


func step_behaviour(dt: float) -> void:
	beh_time += dt
	pher.now = beh_time
	ants.step(dt)
	soil.step_particles(rng_sim)
	_nav_timer -= dt
	if _nav_timer <= 0.0:
		_nav_timer = 0.5
		var changed := nav.update_from_soil()
		if changed or soil.version != _dig_sources_version:
			_refresh_sources(false)
		nav.refresh_fields()
	_plan_timer -= dt
	if _plan_timer <= 0.0:
		_plan_timer = 2.0
		_update_plan()
	_rest_timer -= dt
	if _rest_timer <= 0.0:
		_rest_timer = 5.0
		_refresh_rest_fields()
	_stim_timer -= dt
	if _stim_timer <= 0.0:
		_stim_timer = 3.0
		compute_stimuli()
	_seed_timer -= dt
	if _seed_timer <= 0.0:
		_seed_timer = 1.0
		_maintain_seeds()


func step_bio(dt_s: float) -> void:
	cal.elapsed += dt_s
	var days := dt_s / SimConst.SECONDS_PER_DAY
	var temp := env.nest_temp(cal)
	var hib := env.is_hibernating(cal)
	env.step(days, temp)
	var brood_depth := _chamber_depth_frac("brood")
	var gran_depth := _chamber_depth_frac("granary")
	var ctx := {
		"temp": temp, "hibernating": hib,
		"hum_brood": env.humidity_at_depth(brood_depth),
		"hum_granary": env.humidity_at_depth(gran_depth) - 10.0,
	}
	var ev := colony.step(days, ctx, rng_colony)
	_apply_colony_events(ev)
	# Semillas de los mechones de hierba según la estación.
	tuft_stock += _tuft_season_factor() * 5.0 * env.tuft_xs.size() * days
	tuft_stock = minf(tuft_stock, 400.0)
	# Erosión lenta del montículo y del basurero. [D]
	var n_erode := Colony._stoch_round(8.0 * days, rng_sim)
	if n_erode > 0:
		soil.erode_loose(rng_sim, n_erode, plan.entrance_x, 40)
		soil.erode_loose(rng_sim, Colony._stoch_round(6.0 * days, rng_sim), int(midden_x), 12)
	_journal_checks(ev, hib)


func _tuft_season_factor() -> float:
	match cal.month():
		5, 6:
			return 1.0
		7:
			return 0.6
		9, 10:
			return 0.5
		4:
			return 0.4
	return 0.1


# ---------------------------------------------------------------------------
# Eventos de la colonia ↔ agentes
# ---------------------------------------------------------------------------

func _apply_colony_events(ev: Dictionary) -> void:
	if ev.get("queen_died", false) and ants.queen_index >= 0:
		ants.despawn(ants.queen_index)
	sync_agents(ev.get("born", []))


## Ajusta las hormigas visibles a la población real (sin pasar del tope).
func sync_agents(born: Array = []) -> void:
	var spawn_pos := brood_site_pos()
	for k in 3:
		var have := ants.count_caste(k)
		var want := colony.workers[k]
		while have > want:
			if ants.despawn_one_of_caste(k) < 0:
				break
			have -= 1
		while have < want and ants.count < agent_cap:
			var nan := false
			for b: Dictionary in born:
				if int(b["caste"]) == k and bool(b["nanitic"]):
					nan = true
					break
			if ants.spawn(k, spawn_pos.x + rng_sim.randf_range(-4.0, 4.0), spawn_pos.y, bio_day(), nan) < 0:
				break
			have += 1


func brood_site_pos() -> Vector2:
	var ci := plan.chamber_for("brood")
	if ci < 0:
		return Vector2(plan.entrance_x, plan.entrance_y + 20)
	var c := plan.chambers[ci]
	return Vector2(float(c["cx"]), float(int(c["cy"]) + int(c["ry"]) - 2))


func granary_site_pos() -> Vector2:
	var ci := plan.chamber_for("granary")
	if ci < 0 or not _chamber_reachable(ci):
		return brood_site_pos()
	var c := plan.chambers[ci]
	return Vector2(float(c["cx"]), float(int(c["cy"]) + int(c["ry"]) - 2))


func _refresh_rest_fields() -> void:
	var srcs: Array[int] = []
	for ci in plan.chambers.size():
		var c := plan.chambers[ci]
		if String(c["purpose"]) == "granary" or not _chamber_reachable(ci):
			continue
		var n := nav.nearest_walkable(float(c["cx"]), float(c["cy"]), 5)
		if n >= 0:
			srcs.append(n)
	var key := "%d:%s" % [nav.walk_version, str(srcs)]
	if key == _rest_key:
		return
	_rest_key = key
	rest_fields.clear()
	for n in srcs:
		rest_fields.append(nav.bfs_from(PackedInt32Array([n])))


## Distancia de un nodo a la cámara de descanso preferida de la hormiga i.
func rest_dist(i: int, n: int) -> int:
	if rest_fields.is_empty():
		return nav.dist_at(SimConst.Field.REST, n)
	return rest_fields[i % rest_fields.size()][n]


## Nodos de suelo de todas las cámaras excavadas con esos propósitos.
func _chamber_sources(purposes: Array, fallback: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for ci in plan.chambers.size():
		var c := plan.chambers[ci]
		if not purposes.has(String(c["purpose"])) or not _chamber_reachable(ci):
			continue
		var n := nav.nearest_walkable(float(c["cx"]), float(int(c["cy"]) + int(c["ry"]) - 2), 5)
		if n >= 0 and not out.has(n):
			out.append(n)
	if out.is_empty() and fallback >= 0:
		out.append(fallback)
	out.sort()
	return out


## Cámaras excavadas de un tipo (índices), de la más profunda a la menos.
func chambers_of(purpose: String) -> Array[int]:
	var out: Array[int] = []
	for ci in plan.chambers.size():
		if String(plan.chambers[ci]["purpose"]) == purpose and _chamber_reachable(ci):
			out.append(ci)
	out.sort_custom(func(a: int, b: int) -> bool: return int(plan.chambers[a]["cy"]) > int(plan.chambers[b]["cy"]))
	return out


func _chamber_reachable(ci: int) -> bool:
	var c := plan.chambers[ci]
	return soil.is_air(int(c["cx"]), int(c["cy"]))


func _chamber_depth_frac(purpose: String) -> float:
	var ci := plan.chamber_for(purpose)
	var y := float(plan.entrance_y + 30)
	if ci >= 0:
		y = float(plan.chambers[ci]["cy"])
	return clampf((y - float(SimConst.SURFACE_Y)) / float(SimConst.WORLD_H - SimConst.SURFACE_Y), 0.0, 1.0)


# ---------------------------------------------------------------------------
# Plan de excavación y campos de navegación
# ---------------------------------------------------------------------------

func space_need() -> Dictionary:
	var w := float(colony.total_workers())
	var b := float(colony.brood_total())
	# [D] Área de corte (px²) que la colonia «quiere» tener. Crece de forma
	# sublineal: el corte del formicario solo muestra una rebanada del nido real.
	var need_b := 150.0 + 60.0 * pow(w, 0.65) + 5.0 * pow(b, 0.85)
	var need_g := 0.0
	if colony.granary > 1.0:
		need_g = 80.0 + 30.0 * pow(colony.granary / 50.0, 0.7)
	return {"brood": need_b, "granary": need_g}


func _update_plan() -> void:
	if plan.sealed and not colony.founding and colony.total_workers() > 0:
		plan.plug_open_requested = true
	var events := plan.update(soil, space_need(), rng_sim, 2.0)
	for e in events:
		var day := bio_day()
		var date := cal.format_date_es()
		if e == "founding_dug":
			journal.once("founding_dug", day, date, "La reina ha terminado su cámara de fundación.", Journal.Level.INFO)
		elif e == "plug_open":
			journal.once("plug_open", day, date, "Las primeras obreras han reabierto la entrada del nido. ¡Empieza el forrajeo!")
		elif e == "planned:granary":
			journal.once("first_granary", day, date, "Las obreras empiezan a excavar un granero, una cámara seca para guardar semillas.")
		elif e == "planned:brood":
			journal.throttled("new_brood_chamber", 5.0, day, date, "Falta espacio: las obreras excavan una cámara nueva más profunda.", Journal.Level.INFO)
	_refresh_sources(true)


func _refresh_sources(force: bool) -> void:
	# Entrada: el nodo de superficie justo encima de la boca.
	var ent := nav.nearest_walkable(float(plan.entrance_x), float(plan.entrance_y - 2), 4)
	nav.set_sources(SimConst.Field.ENTRANCE, PackedInt32Array([ent]) if ent >= 0 else PackedInt32Array())
	# La reina vive en la cámara de cría más profunda; la cría y las reservas se
	# reparten entre todas las cámaras de su tipo (fuentes múltiples).
	var bp := brood_site_pos()
	var bn := nav.nearest_walkable(bp.x, bp.y, 6)
	nav.set_sources(SimConst.Field.QUEEN, PackedInt32Array([bn]) if bn >= 0 else PackedInt32Array())
	nav.set_sources(SimConst.Field.BROOD, _chamber_sources(["brood"], bn))
	var gp := granary_site_pos()
	var gn := nav.nearest_walkable(gp.x, gp.y, 6)
	nav.set_sources(SimConst.Field.GRANARY, _chamber_sources(["granary"], gn))
	nav.set_sources(SimConst.Field.REST, _chamber_sources(["brood", "rest"], bn))
	if force or soil.version != _dig_sources_version:
		_dig_sources_version = soil.version
		# Frente = nodo transitable a ≤ 1 nodo de una celda pendiente de excavar.
		var fronts := {}
		for i in plan.pending_cells(soil):
			var cn := nav.node_of(float(i % soil.w), float(i / soil.w))
			var cx := nav.node_x(cn)
			var cy := nav.node_y(cn)
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var xx := cx + dx
					var yy := cy + dy
					if xx < 0 or yy < 0 or xx >= nav.nw or yy >= nav.nh:
						continue
					var n := yy * nav.nw + xx
					if nav.is_walkable(n):
						fronts[n] = true
		var arr := PackedInt32Array(fronts.keys())
		arr.sort()
		dig_front_count = arr.size()
		nav.set_sources(SimConst.Field.DIG, arr)


# ---------------------------------------------------------------------------
# Estímulos para la asignación de tareas
# ---------------------------------------------------------------------------

func forage_allowed() -> bool:
	if colony.founding or env.is_hibernating(cal):
		return false
	var dl := cal.is_daylight() if bool(species.section("behaviour").get("diurnal", true)) else true
	return dl and env.surface_temp(cal) >= species.num("climate", "forage_min_temp_c", 14.0)


func compute_stimuli() -> void:
	var w := float(maxi(ants.count - (1 if ants.queen_index >= 0 else 0), 0))
	desired.fill(0.0)
	desired[SimConst.Task.NURSE] = minf(ceilf(float(colony.brood_total()) / 8.0), w * 0.5)
	if forage_allowed():
		var fd := colony.food_days()
		var frac := 0.05
		if fd < 20.0:
			frac = 0.4
		elif fd < 60.0:
			frac = 0.25
		elif fd < 150.0:
			frac = 0.12
		var supply := env.feeder_seeds + tuft_stock
		if supply < 1.0:
			frac *= 0.3
		desired[SimConst.Task.FORAGE] = maxf(1.0 if w >= 3.0 else 0.0, roundf(w * frac))
	if plan.has_active_work() and dig_front_count > 0:
		var deficit := plan.space_deficit(space_need())
		var by_deficit := deficit / 60.0
		var base := clampf(maxf(float(dig_front_count) / 3.0, by_deficit), 1.0, maxf(1.0, minf(w * 0.3, float(dig_front_count) * 1.5)))
		if plan.plug_open_requested:
			base = maxf(base, minf(3.0, w))
		desired[SimConst.Task.DIG] = base
	if colony.granary > 5.0:
		desired[SimConst.Task.MILL] = ceilf(w * 0.05)
	var refuse := colony.husks / maxf(work_value(), 1.0) + float(colony.corpses)
	if refuse >= 1.0:
		desired[SimConst.Task.CLEAN] = minf(ceilf(refuse / 2.0), maxf(1.0, w * 0.15))
	var mult := {"crecer": [1.0, 1.5, 1.2, 1.0, 1.0, 1.0], "acumular": [1.0, 1.0, 1.6, 0.8, 1.2, 1.0],
		"excavar": [1.0, 0.9, 0.9, 1.8, 1.0, 1.0]}
	var m: Array = mult.get(priority, [1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
	# Estímulo dinámico (Bonabeau et al. 1996): sube mientras falten obreras en
	# la tarea y baja cuando sobran, así la plantilla converge a la demanda.
	for j in SimConst.N_TASKS:
		var cur := float(ants.task_count[j])
		var d := desired[j] * float(m[j])
		if d <= 0.0:
			stimuli[j] = 0.0
			continue
		stimuli[j] = clampf(stimuli[j] + 0.6 * (d - cur) / maxf(d, 2.0), 0.0, 5.0)


# ---------------------------------------------------------------------------
# Semillas en la superficie
# ---------------------------------------------------------------------------

func _maintain_seeds() -> void:
	var wv := maxf(work_value(), 0.001)
	var n_feeder := 0
	var n_tuft := 0
	for i in seed_alive.size():
		if seed_alive[i] == 1:
			if seed_src[i] == 0:
				n_feeder += 1
			else:
				n_tuft += 1
	var want_feeder := mini(14, ceili(env.feeder_seeds / wv))
	while n_feeder < want_feeder:
		_spawn_seed(env.feeder_x + rng_sim.randi_range(-6, 6), 0)
		n_feeder += 1
	var want_tuft := mini(6 * env.tuft_xs.size(), floori(tuft_stock / wv))
	while n_tuft < want_tuft:
		var tx := env.tuft_xs[rng_sim.randi_range(0, env.tuft_xs.size() - 1)]
		_spawn_seed(tx + rng_sim.randi_range(-12, 12), 1)
		n_tuft += 1


func _spawn_seed(x: int, src: int) -> void:
	x = clampi(x, 2, soil.w - 3)
	var y := float(soil.col_top[x] - 1)
	var slot := seed_alive.find(0)
	if slot < 0:
		seed_x.append(float(x) + 0.5)
		seed_y.append(y)
		seed_alive.append(1)
		seed_src.append(src)
	else:
		seed_x[slot] = float(x) + 0.5
		seed_y[slot] = y
		seed_alive[slot] = 1
		seed_src[slot] = src


func find_seed(x: float, y: float, r: float) -> int:
	var best := -1
	var best_d := r
	for i in seed_alive.size():
		if seed_alive[i] == 0:
			continue
		var dx := absf(seed_x[i] - x)
		if dx <= best_d and absf(seed_y[i] - y) <= 8.0:
			best_d = dx
			best = i
	return best


func seed_exists(i: int) -> bool:
	return i >= 0 and i < seed_alive.size() and seed_alive[i] == 1


func seed_x_of(i: int) -> float:
	return seed_x[i]


## Recoge una semilla visible. Devuelve cuántas semillas reales representa.
func take_seed(i: int) -> float:
	if not seed_exists(i):
		return 0.0
	seed_alive[i] = 0
	var wv := work_value()
	var v := 0.0
	if seed_src[i] == 0:
		v = minf(wv, env.feeder_seeds)
		env.feeder_seeds -= v
	else:
		v = minf(wv, tuft_stock)
		tuft_stock -= v
	return v


func count_seeds_near(x: float, r: float) -> int:
	var n := 0
	for i in seed_alive.size():
		if seed_alive[i] == 1 and absf(seed_x[i] - x) <= r:
			n += 1
	return n


func deliver_seed(amount: float) -> void:
	colony.granary += amount
	colony.seeds_harvested_total += amount
	seeds_delivered_today += amount


# ---------------------------------------------------------------------------
# Acciones físicas de las hormigas
# ---------------------------------------------------------------------------

func dig_at(x: float, y: float) -> int:
	var cx := int(x)
	var cy := int(y)
	var best := -1
	var best_d := 1 << 30
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var xx := cx + dx
			var yy := cy + dy
			if not soil.in_bounds(xx, yy):
				continue
			if not SoilGrid.is_diggable(soil.mat[yy * soil.w + xx]):
				continue
			if not plan.in_any_active_zone(xx, yy):
				continue
			var d := dx * dx + dy * dy
			if d < best_d:
				best_d = d
				best = yy * soil.w + xx
	if best < 0:
		return 0
	return soil.dig_pellet(best % soil.w, best / soil.w, 1.5, 5, Callable(plan, "in_any_active_zone"))


func dig_time_at(x: float, y: float) -> float:
	var cx := int(x)
	var cy := int(y)
	var hmin := 1.6
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var m := soil.get_mat(cx + dx, cy + dy)
			if SoilGrid.is_diggable(m):
				hmin = minf(hmin, SoilGrid.hardness(m))
	# La tierra húmeda se trabaja mejor.
	var wet := clampf((env.humidity - 40.0) / 60.0, 0.0, 0.4)
	return 2.2 * hmin * (1.0 - wet)


func drop_soil(x: float, amount: float) -> void:
	soil.drop_loose(int(x), roundi(amount), SimConst.Mat.LOOSE, rng_sim)


func compact_soil(amount: float) -> void:
	soil_compacted += amount


func drop_midden(x: float, _kind: int) -> void:
	soil.drop_loose(int(x), 1, SimConst.Mat.MIDDEN, rng_sim)


func pick_dump_x() -> float:
	var side := -1.0 if rng_sim.randf() < 0.5 else 1.0
	return clampf(float(plan.entrance_x) + side * rng_sim.randf_range(7.0, 24.0), 4.0, float(soil.w - 4))


func pick_midden_x() -> float:
	return midden_x + rng_sim.randf_range(-5.0, 5.0)


func take_refuse() -> int:
	if colony.corpses > 0:
		colony.corpses -= 1
		return SimConst.Carry.CORPSE
	if colony.husks >= 1.0:
		colony.husks = maxf(0.0, colony.husks - maxf(work_value(), 1.0))
		return SimConst.Carry.HUSK
	return SimConst.Carry.NONE


func seal_entrance() -> void:
	plan.seal(soil)
	journal.once("sealed", bio_day(), cal.format_date_es(),
		"La reina ha sellado la entrada desde dentro. Fundación claustral: no comerá hasta que nazcan sus primeras obreras.")
	_refresh_sources(true)


# ---------------------------------------------------------------------------
# Órdenes del jugador (el cuidador del formicario)
# ---------------------------------------------------------------------------

func cmd_refill_feeder(seeds: float) -> void:
	env.feeder_seeds += seeds
	journal.add(bio_day(), cal.format_date_es(), "Has rellenado el comedero con %d semillas." % int(seeds))


func cmd_refill_water(ml: float) -> void:
	env.water_ml = minf(env.water_ml + ml, FormicariumEnv.WATER_MAX_ML)
	journal.add(bio_day(), cal.format_date_es(), "Has rellenado el depósito de agua.")


func cmd_toggle_heater() -> void:
	env.heater_on = not env.heater_on


func cmd_paint_trail(x: float, y: float) -> void:
	pher.deposit(PK.PLAYER, x, y, 3.0)


func cmd_set_priority(p: String) -> void:
	priority = p
	compute_stimuli()


func set_time_scale(s: float) -> void:
	time_scale = maxf(s, 0.0)


# ---------------------------------------------------------------------------
# Diario
# ---------------------------------------------------------------------------

func _journal_checks(ev: Dictionary, hib: bool) -> void:
	var day := bio_day()
	var date := cal.format_date_es()
	if colony.eggs_total > 0:
		journal.once("first_eggs", day, date, "La reina ha puesto sus primeros huevos.")
	if colony.brood_count(Colony.Stage.LARVA) > 0:
		journal.once("first_larva", day, date, "Han eclosionado las primeras larvas. La reina las alimenta con sus reservas.")
	if colony.brood_count(Colony.Stage.PUPA) > 0:
		journal.once("first_pupa", day, date, "Las primeras larvas han pupado. Messor no teje capullo: las pupas están desnudas.")
	if colony.workers_ever > 0:
		journal.once("first_worker", day, date, "¡Ha nacido la primera obrera! Es una nanitic: más pequeña y frágil que las que vendrán.")
	for b: Dictionary in ev.get("born", []):
		if int(b["caste"]) == SimConst.Caste.MEDIA:
			journal.once("first_media", day, date, "Nace la primera obrera media.")
		elif int(b["caste"]) == SimConst.Caste.MAJOR:
			journal.once("first_major", day, date, "Nace la primera obrera mayor, de cabeza enorme: se encargará de moler las semillas.")
	var w := colony.total_workers()
	for m in [10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000]:
		if w >= m:
			journal.once("pop_%d" % m, day, date, "La colonia alcanza las %d obreras." % m)
	if ev.get("queen_died", false):
		journal.once("queen_dead", day, date, "La reina ha muerto. Sin ella la colonia se irá apagando.", Journal.Level.CRITICAL)
	if not colony.founding:
		if env.feeder_seeds < 1.0 and tuft_stock < 1.0:
			journal.throttled("feeder_empty", 3.0, day, date, "El comedero está vacío. Rellénalo para que las obreras tengan semillas.")
		if colony.food_days() < 5.0 and w > 0:
			journal.throttled("food_low", 5.0, day, date, "Al granero le quedan menos de 5 días de reservas.")
		if ev.get("starving", false) and colony.starving_days > 2.0:
			journal.throttled("starving", 4.0, day, date, "La colonia está pasando hambre.", Journal.Level.CRITICAL)
	if env.water_ml <= 0.0:
		journal.throttled("water_empty", 5.0, day, date, "El depósito de agua está vacío: el sustrato se irá secando.")
	if env.humidity < 30.0:
		journal.throttled("too_dry", 5.0, day, date, "El nido está muy seco; la cría puede desecarse.")
	if ev.get("mold", false):
		journal.throttled("mold", 6.0, day, date, "Hay moho en el granero: demasiada humedad. Se están perdiendo semillas.")
	var y := int(cal.date_dict()["year"])
	if hib:
		journal.once("hib_start_%d" % y, day, date, "Llega la diapausa invernal: la colonia se aletarga y la reina deja de poner.", Journal.Level.INFO)
	elif journal.flags.has("hib_start_%d" % (y - 1)) or journal.flags.has("hib_start_%d" % y):
		journal.once("hib_end_%d" % y, day, date, "Fin de la diapausa: la colonia se despereza.", Journal.Level.INFO)


# ---------------------------------------------------------------------------
# Huella del estado (tests de determinismo) y serialización
# ---------------------------------------------------------------------------

func state_hash() -> int:
	var parts := [
		hash(soil.mat), hash(ants.px), hash(ants.py), hash(ants.task), hash(ants.carry),
		colony.total_workers(), colony.brood_total(), snappedf(colony.granary, 0.001),
		snappedf(cal.elapsed, 0.001), seed_alive.count(1),
	]
	return hash(str(parts))


func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION, "seed": seed_value, "species": species.id,
		"time_scale": time_scale, "behaviour_speed": behaviour_speed, "priority": priority,
		"agent_cap": agent_cap, "beh_time": beh_time, "bio_accum": bio_accum,
		"rng": {
			"world": [rng_world.seed, rng_world.state], "sim": [rng_sim.seed, rng_sim.state],
			"colony": [rng_colony.seed, rng_colony.state], "ants": [rng_ants.seed, rng_ants.state],
		},
		"soil": soil.to_dict(), "pher": pher.to_dict(), "ants": ants.to_dict(),
		"colony": colony.to_dict(), "cal": cal.to_dict(), "env": env.to_dict(),
		"plan": plan.to_dict(), "journal": journal.to_dict(),
		"seeds": {"x": seed_x, "y": seed_y, "alive": seed_alive, "src": seed_src},
		"tuft_stock": tuft_stock, "midden_x": midden_x, "soil_compacted": soil_compacted,
		"tuft_xs": env.tuft_xs,
	}


func from_dict(d: Dictionary) -> void:
	seed_value = int(d["seed"])
	species = SpeciesDef.load_by_id(String(d["species"]))
	time_scale = float(d.get("time_scale", 24.0))
	behaviour_speed = float(d.get("behaviour_speed", 1.0))
	priority = String(d.get("priority", "equilibrio"))
	agent_cap = int(d.get("agent_cap", 1200))
	beh_time = 0.0
	bio_accum = float(d.get("bio_accum", 0.0))
	var r: Dictionary = d["rng"]
	rng_world.seed = int(r["world"][0]); rng_world.state = int(r["world"][1])
	rng_sim.seed = int(r["sim"][0]); rng_sim.state = int(r["sim"][1])
	rng_colony.seed = int(r["colony"][0]); rng_colony.state = int(r["colony"][1])
	rng_ants.seed = int(r["ants"][0]); rng_ants.state = int(r["ants"][1])
	soil.from_dict(d["soil"])
	nav.setup(soil)
	pher.from_dict(d["pher"], soil.w, soil.h)
	colony.sp = species
	colony.from_dict(d["colony"])
	cal.from_dict(d["cal"])
	env = FormicariumEnv.new()
	env.from_dict(d["env"])
	env.tuft_xs = d.get("tuft_xs", env.tuft_xs)
	plan.from_dict(d["plan"])
	plan.debris_ref = soil.debris
	journal.from_dict(d["journal"])
	var s: Dictionary = d["seeds"]
	seed_x = s["x"]; seed_y = s["y"]; seed_alive = s["alive"]; seed_src = s["src"]
	tuft_stock = float(d.get("tuft_stock", 0.0))
	midden_x = float(d.get("midden_x", 100.0))
	soil_compacted = float(d.get("soil_compacted", 0.0))
	stimuli.resize(SimConst.N_TASKS)
	stimuli.fill(0.0)
	desired.resize(SimConst.N_TASKS)
	desired.fill(0.0)
	ants.world = self
	ants.nav = nav
	ants.rng = rng_ants
	ants.from_dict(d["ants"])
	_dig_sources_version = -1
	_refresh_sources(true)
	nav.refresh_fields()
	compute_stimuli()
