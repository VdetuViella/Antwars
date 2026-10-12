extends TestCase
## Guardado (ida y vuelta, copias de seguridad, corrupción) y progreso offline.

const PATH := "user://test_save.dat"


func _run(w: SimWorld, beh_seconds: float) -> void:
	for _s in int(beh_seconds / SimConst.BEHAVIOUR_DT):
		w.advance(SimConst.BEHAVIOUR_DT)


func test_save_roundtrip() -> void:
	SaveSystem.delete_all(PATH)
	var w := make_world(42)
	w.set_time_scale(500.0)
	_run(w, 1200.0)
	check_eq(SaveSystem.save(w, PATH, 1000.0), OK, "guardar")
	var d := SaveSystem.load_dict(PATH)
	check(not d.is_empty(), "cargar")
	check_eq(float(d["saved_at_real"]), 1000.0, "marca de tiempo real")
	var w2 := SimWorld.new()
	w2.from_dict(d)
	check_eq(w2.soil.mat, w.soil.mat, "suelo idéntico")
	check_eq(w2.colony.total_workers(), w.colony.total_workers(), "obreras")
	check_eq(w2.colony.brood_total(), w.colony.brood_total(), "cría")
	check_near(w2.colony.queen_reserves, w.colony.queen_reserves, 0.0001, "reservas de la reina")
	check_eq(w2.ants.count, w.ants.count, "hormigas visibles")
	check_eq(w2.journal.entries.size(), w.journal.entries.size(), "diario")
	check_near(w2.cal.elapsed, w.cal.elapsed, 0.001, "calendario")
	# Tras cargar, ambos mundos siguen igual de deterministas.
	_run(w, 300.0)
	_run(w2, 300.0)
	check_eq(w2.colony.total_workers(), w.colony.total_workers(), "evolución tras cargar (obreras)")
	w.dispose(); w2.dispose()
	SaveSystem.delete_all(PATH)


func test_corrupt_save_uses_backup() -> void:
	SaveSystem.delete_all(PATH)
	var w := make_world(43)
	SaveSystem.save(w, PATH, 1.0)
	w.set_time_scale(500.0)
	_run(w, 50.0)
	SaveSystem.save(w, PATH, 2.0)
	# Corromper el principal.
	var f := FileAccess.open(PATH, FileAccess.READ_WRITE)
	f.seek(40)
	f.store_buffer(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9]))
	f.close()
	var d := SaveSystem.load_dict(PATH)
	check(not d.is_empty(), "se recupera de una copia")
	check_eq(String(d.get("_recovered_from", "")), PATH + ".bak1", "desde .bak1")
	w.dispose()
	SaveSystem.delete_all(PATH)


func test_offline_founding_progress() -> void:
	# 3 días reales cerrados en modo acompañante (×24) ≈ 72 días biológicos.
	var w := make_world(7)
	w.set_time_scale(300.0)
	_run(w, 1500.0)   # fundación excavada y sellada
	check(w.journal.flags.has("sealed"), "sellado antes de cerrar")
	w.set_time_scale(24.0)
	var s := OfflineResolver.resolve(w, 3.0 * 86400.0)
	check_range(float(s["bio_days"]), 70.0, 74.0, "días biológicos simulados")
	check(w.colony.queen_alive, "la reina sigue viva")
	check(w.colony.total_workers() >= 5, "hay obreras tras la fundación (%d)" % w.colony.total_workers())
	check(w.journal.flags.has("first_worker"), "hito de primera obrera en el diario")
	check_eq(w.ants.count, mini(w.colony.total_workers() + 1, w.agent_cap), "hormigas visibles = población + reina")
	w.dispose()


func test_offline_matches_online_population() -> void:
	# La población offline debe parecerse a la del juego abierto (mismo modelo de colonia).
	var online: Array[int] = []
	var offline: Array[int] = []
	for seed_v in [11, 12]:
		var a := make_world(seed_v)
		a.set_time_scale(800.0)
		_run(a, 4400.0)   # ≈ 40 días: fundación completa, primeras obreras
		var b := SimWorld.new()
		b.from_dict(a.to_dict())
		# Online: 35 días biológicos a ×200.
		a.set_time_scale(200.0)
		_run(a, 35.0 * 86400.0 / 200.0)
		# Offline: lo mismo de golpe.
		b.set_time_scale(200.0)
		OfflineResolver.resolve(b, 35.0 * 86400.0 / 200.0)
		online.append(a.colony.total_workers() + a.colony.brood_total())
		offline.append(b.colony.total_workers() + b.colony.brood_total())
		a.dispose(); b.dispose()
	var so := 0.0
	var sf := 0.0
	for k in online.size():
		so += online[k]
		sf += offline[k]
	check(so > 20.0, "hay población online (%s)" % str(online))
	check_range(sf / maxf(so, 1.0), 0.6, 1.5, "offline/online (online %s, offline %s)" % [str(online), str(offline)])


func test_offline_does_not_kill_queen_by_starvation() -> void:
	var w := make_world(8)
	w.set_time_scale(300.0)
	_run(w, 600.0)
	w.env.feeder_seeds = 0.0
	w.tuft_stock = 0.0
	w.set_time_scale(96.0)
	OfflineResolver.resolve(w, 10.0 * 86400.0)   # 30 días reales máximo ⇒ años biológicos, sin comida
	check(w.colony.queen_alive, "la reina no muere de hambre estando ausente")
	w.dispose()
