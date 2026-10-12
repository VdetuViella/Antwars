extends SceneTree
## Herramienta de diagnóstico: ejecuta la simulación sin interfaz y vuelca
## estadísticas y una imagen PNG del corte del nido.
##   godot --headless --path . --script res://tools/sim_probe.gd -- <segundos_comportamiento> <escala> [semilla] [salida.png]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var beh_seconds := float(args[0]) if args.size() > 0 else 600.0
	var scale := float(args[1]) if args.size() > 1 else 24.0
	var seed_v := int(args[2]) if args.size() > 2 else 1234
	var out := String(args[3]) if args.size() > 3 else "/tmp/probe.png"
	var w := SimWorld.new()
	var start := float(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 10, "day": 12, "hour": 10, "minute": 0, "second": 0}))
	w.new_game(seed_v, start)
	w.set_time_scale(scale)
	var t0 := Time.get_ticks_msec()
	var steps := int(beh_seconds / SimConst.BEHAVIOUR_DT)
	var report_every := maxi(1, steps / 12)
	for s in steps:
		w.advance(SimConst.BEHAVIOUR_DT)
		if s % report_every == 0:
			_report(w)
	_report(w)
	var ms := Time.get_ticks_msec() - t0
	print("tiempo real de cálculo: %.1f s para %.0f s de comportamiento (%.2f ms/tick)" % [ms / 1000.0, beh_seconds, float(ms) / steps])
	for e in w.journal.entries:
		print("  [día %.1f] %s" % [e["day"], e["text"]])
	_dump(w, out)
	quit()


func _report(w: SimWorld) -> void:
	var c := w.colony
	var tasks := []
	for j in SimConst.N_TASKS + 1:
		tasks.append("%s=%d" % [SimConst.TASK_KEYS[j], w.ants.task_count[j]])
	print("día %.2f | %s | obreras %d (%d/%d/%d) cría h%d l%d p%d | granero %.1f pan %.1f | comedero %.0f | reservas %.1f | agentes %d | %s | frentes %d | hum %.0f%% agua %.0f" % [
		w.bio_day(), w.cal.format_date_es(), c.total_workers(), c.workers[0], c.workers[1], c.workers[2],
		c.brood_count(0), c.brood_count(1), c.brood_count(2), c.granary, c.bread, w.env.feeder_seeds,
		c.queen_reserves, w.ants.count, " ".join(tasks), w.dig_front_count, w.env.humidity, w.env.water_ml])


func _dump(w: SimWorld, path: String) -> void:
	var img := Image.create(w.soil.w, w.soil.h, false, Image.FORMAT_RGB8)
	var cols := {0: Color(0.85, 0.88, 0.9), 1: Color(0.35, 0.25, 0.15), 2: Color(0.5, 0.36, 0.22),
		3: Color(0.62, 0.45, 0.3), 4: Color(0.7, 0.55, 0.38), 5: Color(0.45, 0.45, 0.47), 6: Color(0.8, 0.7, 0.3), 7: Color(0.9, 0.2, 0.2)}
	for y in w.soil.h:
		for x in w.soil.w:
			var m := w.soil.mat[y * w.soil.w + x]
			var col: Color = cols[m]
			if m == 0 and y >= w.soil.surface_h[x]:
				col = Color(0.12, 0.09, 0.07)
			img.set_pixel(x, y, col)
	for i in w.seed_alive.size():
		if w.seed_alive[i] == 1:
			img.set_pixel(clampi(int(w.seed_x[i]), 0, w.soil.w - 1), clampi(int(w.seed_y[i]), 0, w.soil.h - 1), Color(0.95, 0.85, 0.2))
	for i in w.ants.cap:
		if w.ants.alive[i] == 1:
			var col := Color(0.1, 1.0, 0.3) if w.ants.caste[i] != SimConst.Caste.QUEEN else Color(1, 0.2, 1)
			img.set_pixel(clampi(int(w.ants.px[i]), 0, w.soil.w - 1), clampi(int(w.ants.py[i]), 0, w.soil.h - 1), col)
	img.resize(w.soil.w * 2, w.soil.h * 2, Image.INTERPOLATE_NEAREST)
	img.save_png(path)
	print("imagen: " + path)
