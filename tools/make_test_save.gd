extends SceneTree
## Crea una partida avanzada para pruebas visuales:
##   godot --headless --path . --script res://tools/make_test_save.gd -- <días_biológicos> <ruta> [semilla]
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var days := float(args[0]) if args.size() > 0 else 60.0
	var path := String(args[1]) if args.size() > 1 else "user://shot_test.dat"
	var seed_v := int(args[2]) if args.size() > 2 else 1234
	var w := SimWorld.new()
	var start := float(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 4, "day": 20, "hour": 11, "minute": 0, "second": 0}))
	w.new_game(seed_v, start)
	w.set_time_scale(400.0)
	var t := 0.0
	while w.bio_day() < days:
		w.advance(0.1)
		t += 0.1
		if w.env.feeder_seeds < 2000.0:
			w.env.feeder_seeds += 2000.0
		if w.env.water_ml < 30.0:
			w.env.water_ml = 100.0
	# Acabar con unos minutos a escala normal para que el reparto de tareas se asiente.
	w.set_time_scale(24.0)
	for _k in 1200:
		w.advance(0.1)
	SaveSystem.save(w, path)
	print("guardado %s: día %.1f, %d obreras, cría %d, granero %d" % [path, w.bio_day(), w.colony.total_workers(), w.colony.brood_total(), int(w.colony.granary)])
	w.dispose()
	quit()
