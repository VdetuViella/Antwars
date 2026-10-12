extends SceneTree
## Mide el coste medio por tick de comportamiento con una partida guardada.
##   godot --headless --path . --script res://tools/bench.gd -- [ruta] [segundos]
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path := String(args[0]) if args.size() > 0 else "user://shot_test.dat"
	var secs := float(args[1]) if args.size() > 1 else 60.0
	var w := SimWorld.new()
	w.from_dict(SaveSystem.load_dict(path))
	w.set_time_scale(24.0)
	var n := int(secs / SimConst.BEHAVIOUR_DT)
	var t0 := Time.get_ticks_usec()
	var nav_us := 0
	for _i in n:
		w.step_behaviour(SimConst.BEHAVIOUR_DT)
	var total := Time.get_ticks_usec() - t0
	# Partes por separado
	var t1 := Time.get_ticks_usec()
	for _i in 100:
		w.ants.step(SimConst.BEHAVIOUR_DT)
	var ants_us := (Time.get_ticks_usec() - t1) / 100
	var t2 := Time.get_ticks_usec()
	for f in SimConst.N_FIELDS:
		w.nav._bfs(f)
	var bfs_us := (Time.get_ticks_usec() - t2) / SimConst.N_FIELDS
	print("hormigas %d · tick medio %.2f ms · ants.step %.2f ms · un BFS %.2f ms · CPU a 10 Hz ≈ %.1f %%" % [
		w.ants.count, total / 1000.0 / n, ants_us / 1000.0, bfs_us / 1000.0, total / 1000.0 / n * 10.0 / 10.0])
	w.dispose()
	quit()
