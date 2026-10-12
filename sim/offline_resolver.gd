class_name OfflineResolver
extends RefCounted
## Progreso mientras el juego estaba cerrado. No re-simula hormiga a hormiga:
## avanza el MISMO modelo de colonia (Colony.step) en pasos de 1 hora biológica,
## estima el forrajeo con un modelo de capacidad limitado por el suministro y
## excava el nido de forma acelerada siguiendo el plan existente.
## Regla de diseño: la ausencia no se castiga de golpe (la reina no muere por
## hambre offline; las crisis quedan en aviso para cuando vuelvas).

const MAX_REAL_SECONDS := 30.0 * 86400.0
const MAX_BIO_DAYS := 730.0
const STEP_S := 3600.0
const SEEDS_PER_FORAGER_HOUR := 30.0       ## [D] capacidad de carga offline
const DIG_CELLS_PER_WORKER_DAY := 40.0     ## [D]


static func resolve(w: SimWorld, real_seconds: float) -> Dictionary:
	var summary := {
		"real_seconds": 0.0, "bio_days": 0.0, "born": 0, "died": 0, "eggs": 0,
		"seeds_collected": 0.0, "feeder_before": w.env.feeder_seeds, "feeder_after": w.env.feeder_seeds,
		"workers_before": w.colony.total_workers(), "workers_after": w.colony.total_workers(),
		"brood_before": w.colony.brood_total(), "brood_after": w.colony.brood_total(),
		"granary_before": w.colony.granary, "granary_after": w.colony.granary,
		"cells_dug": 0, "journal_from": w.journal.entries.size(), "clamped": false,
	}
	if real_seconds <= 1.0:
		return summary
	if real_seconds > MAX_REAL_SECONDS:
		real_seconds = MAX_REAL_SECONDS
		summary["clamped"] = true
	summary["real_seconds"] = real_seconds
	var bio := real_seconds * w.time_scale + w.bio_accum
	bio = minf(bio, MAX_BIO_DAYS * SimConst.SECONDS_PER_DAY)
	var steps := int(bio / STEP_S)
	w.bio_accum = fmod(bio, STEP_S)
	var dig_budget := 0.0
	for _s in steps:
		var dt_days := STEP_S / SimConst.SECONDS_PER_DAY
		w.cal.elapsed += STEP_S
		# Forrajeo estimado (de día, con temperatura y fuera de la diapausa).
		if w.forage_allowed() and w.colony.total_workers() > 0 and not w.plan.sealed:
			var foragers := maxf(1.0, 0.2 * float(w.colony.total_workers()))
			var cap := foragers * SEEDS_PER_FORAGER_HOUR
			var from_feeder := minf(cap, w.env.feeder_seeds)
			w.env.feeder_seeds -= from_feeder
			var from_tuft := minf(cap - from_feeder, w.tuft_stock)
			w.tuft_stock -= from_tuft
			var got := from_feeder + from_tuft
			w.colony.granary += got
			w.colony.seeds_harvested_total += got
			summary["seeds_collected"] = float(summary["seeds_collected"]) + got
		# Biología.
		var temp := w.env.nest_temp(w.cal)
		var hib := w.env.is_hibernating(w.cal)
		w.env.step(dt_days, temp)
		var ctx := {
			"temp": temp, "hibernating": hib,
			"hum_brood": w.env.humidity_at_depth(w._chamber_depth_frac("brood")),
			"hum_granary": w.env.humidity_at_depth(w._chamber_depth_frac("granary")) - 10.0,
		}
		var queen_was_alive := w.colony.queen_alive
		var old_age := w.colony.queen_age_days > w.colony.queen_lifespan_days
		var ev := w.colony.step(dt_days, ctx, w.rng_colony)
		if queen_was_alive and not w.colony.queen_alive and not old_age:
			# No castigar la ausencia: la reina aguanta hasta que vuelvas.
			w.colony.queen_alive = true
			w.colony.queen_reserves = maxf(w.colony.queen_reserves, 1.0)
			w.colony.corpses = maxi(0, w.colony.corpses - 1)
			ev["queen_died"] = false
		w.colony.starving_days = minf(w.colony.starving_days, 20.0)
		summary["born"] = int(summary["born"]) + (ev["born"] as Array).size()
		var died: PackedInt32Array = ev["died"]
		summary["died"] = int(summary["died"]) + died[0] + died[1] + died[2]
		summary["eggs"] = int(summary["eggs"]) + int(ev["eggs"])
		# Los cadáveres y cáscaras se retiran solos con el tiempo.
		w.colony.corpses = maxi(0, w.colony.corpses - Colony._stoch_round(dt_days * 2.0, w.rng_sim))
		w.colony.husks = maxf(0.0, w.colony.husks - dt_days * 50.0)
		w.tuft_stock = minf(w.tuft_stock + w._tuft_season_factor() * 5.0 * w.env.tuft_xs.size() * dt_days, 400.0)
		w._journal_checks(ev, hib)
		# Excavación acelerada cada día biológico.
		dig_budget += DIG_CELLS_PER_WORKER_DAY * float(w.colony.total_workers()) * dt_days
		if dig_budget >= 60.0:
			summary["cells_dug"] = int(summary["cells_dug"]) + _fast_dig(w, int(dig_budget))
			dig_budget = 0.0
	summary["bio_days"] = float(steps) * STEP_S / SimConst.SECONDS_PER_DAY
	# Las hormigas visibles se adaptan a la población nueva.
	w.sync_agents([])
	for i in w.ants.cap:
		if w.ants.alive[i] == 1:
			w.ants.state[i] = Ants.St.IDLE
			w.ants.task_timer[i] = w.rng_ants.randf_range(0.0, 5.0)
	w.nav.update_from_soil()
	w._refresh_sources(true)
	w.nav.refresh_fields()
	w.compute_stimuli()
	summary["feeder_after"] = w.env.feeder_seeds
	summary["workers_after"] = w.colony.total_workers()
	summary["brood_after"] = w.colony.brood_total()
	summary["granary_after"] = w.colony.granary
	return summary


## Excava hasta `budget` celdas del plan activo (de arriba abajo, desde el aire
## existente hacia dentro) y deposita la tierra en el montículo.
static func _fast_dig(w: SimWorld, budget: int) -> int:
	var dug := 0
	for _round in 12:
		if dug >= budget:
			break
		w.plan.update(w.soil, w.space_need(), w.rng_sim, 2.0)
		if w.plan.sealed and not w.colony.founding and w.colony.total_workers() > 0:
			w.plan.plug_open_requested = true
		var pending := w.plan.pending_cells(w.soil)
		if pending.is_empty():
			break
		var progressed := false
		for i in pending:
			if dug >= budget:
				break
			var x := i % w.soil.w
			var y := i / w.soil.w
			# Solo celdas que tocan aire: el túnel avanza desde lo ya excavado.
			if not (w.soil.is_air(x + 1, y) or w.soil.is_air(x - 1, y) or w.soil.is_air(x, y + 1) or w.soil.is_air(x, y - 1)):
				continue
			w.soil.set_mat(x, y, SimConst.Mat.AIR)
			w.soil.debris.erase(i)
			w.soil.removed_total += 1
			dug += 1
			progressed = true
		if not progressed:
			break
	if dug > 0:
		var left := dug / 2
		w.soil.drop_loose(int(w.pick_dump_x()), left, SimConst.Mat.LOOSE, w.rng_sim)
		w.soil.drop_loose(int(w.pick_dump_x()), dug - left, SimConst.Mat.LOOSE, w.rng_sim)
		# Asentar la tierra suelta del montículo.
		for _k in 60:
			w.soil.step_particles(w.rng_sim, 20000)
			if w.soil.active.is_empty():
				break
		w.soil.erode_loose(w.rng_sim, dug / 3, w.plan.entrance_x, 40)
	return dug
