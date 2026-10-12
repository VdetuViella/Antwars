extends TestCase
## Tests de la simulación completa: determinismo, fundación, conservación.


func _run(w: SimWorld, beh_seconds: float) -> void:
	var steps := int(beh_seconds / SimConst.BEHAVIOUR_DT)
	for _s in steps:
		w.advance(SimConst.BEHAVIOUR_DT)


func test_determinism_same_seed() -> void:
	var a := make_world(77)
	var b := make_world(77)
	a.set_time_scale(300.0)
	b.set_time_scale(300.0)
	_run(a, 400.0)
	_run(b, 400.0)
	check_eq(a.state_hash(), b.state_hash(), "misma semilla ⇒ mismo estado")
	var c := make_world(78)
	c.set_time_scale(300.0)
	_run(c, 400.0)
	check(a.state_hash() != c.state_hash(), "semilla distinta ⇒ estado distinto")
	a.dispose(); b.dispose(); c.dispose()


func test_founding_sequence() -> void:
	# La reina excava, sella, pone huevos y su primera camada sale adelante.
	var w := make_world(1234)
	w.set_time_scale(600.0)
	_run(w, 6000.0)   # ≈ 41 días biológicos
	check(w.journal.flags.has("founding_dug"), "cámara de fundación excavada")
	check(w.journal.flags.has("sealed"), "entrada sellada")
	check(w.journal.flags.has("first_eggs"), "primeros huevos")
	check(w.colony.queen_alive, "la reina sigue viva")
	check(w.colony.queen_reserves > 20.0, "a la reina le quedan reservas (%.1f)" % w.colony.queen_reserves)
	check(w.colony.workers_ever > 0, "ha nacido alguna obrera a los ~41 días")
	w.dispose()


func test_soil_conservation() -> void:
	# Balance exacto: sólidas = iniciales − excavadas − erosionadas + depositadas + colocadas.
	var w := make_world(99)
	w.set_time_scale(400.0)
	var solid0 := w.soil.mat.size() - w.soil.count_material(SimConst.Mat.AIR)
	_run(w, 2500.0)
	var solid1 := w.soil.mat.size() - w.soil.count_material(SimConst.Mat.AIR)
	check(w.soil.removed_total > 50, "se ha excavado algo (%d)" % w.soil.removed_total)
	var expected := solid0 - w.soil.removed_total - w.soil.eroded_total + w.soil.dropped_total + w.soil.placed_total
	check_eq(solid1, expected, "balance de celdas sólidas")
	w.dispose()


func test_nav_fields_reach_brood() -> void:
	var w := make_world(5)
	w.set_time_scale(300.0)
	_run(w, 1500.0)
	var q := w.ants.queen_index
	check(q >= 0, "reina viva")
	var d := w.nav.dist_at(SimConst.Field.BROOD, w.ants.node[q])
	check(d < NavGrid.INF_DIST, "la reina puede llegar a la cámara de cría")
	w.dispose()


func test_foragers_reach_feeder_across_entrance() -> void:
	# Regresión: la boca del nido cortaba el camino por la superficie y las
	# forrajeras solo podían ir hacia un lado.
	var w := make_world(11)
	w.set_time_scale(800.0)
	# Se avanza hasta que las primeras obreras reabren la entrada (≈ día 42),
	# con un tope de ~69 días biológicos por si la fundación se atasca.
	var waited := 0.0
	while w.plan.sealed or w.colony.founding:
		_run(w, 100.0)
		waited += 100.0
		if waited > 7500.0:
			break
	check(not w.plan.sealed, "el tapón está abierto (día %.1f)" % w.bio_day())
	w.set_time_scale(200.0)
	_run(w, 1500.0)
	check(w.colony.seeds_harvested_total > 0.0, "se han recogido semillas del comedero")
	w.dispose()


func test_resting_ants_spread_out() -> void:
	# Las obreras que descansan buscan un nodo libre en vez de apilarse (Ants.occ).
	var w := make_world(5)
	w.set_time_scale(300.0)
	_run(w, 1500.0)   # cámara de fundación excavada
	w.set_time_scale(24.0)
	var bp := w.brood_site_pos()
	w.colony.workers[0] = 20
	for k in 20:
		w.ants.spawn(SimConst.Caste.MINOR, bp.x + float(k % 5) - 2.0, bp.y, w.bio_day() - 30.0, false)
	_run(w, 90.0)
	var resting := 0
	var shared := 0
	for i in w.ants.cap:
		if w.ants.alive[i] == 1 and w.ants.state[i] == Ants.St.RESTING:
			resting += 1
			if w.ants.occ[w.ants.node[i]] > 1:
				shared += 1
	check(resting >= 5, "hay obreras descansando (%d)" % resting)
	check(float(shared) <= 0.35 * float(resting), "pocas comparten nodo (%d de %d)" % [shared, resting])
	w.dispose()
