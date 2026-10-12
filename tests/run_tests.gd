extends SceneTree
## Ejecuta todos los tests headless:
##   godot --headless --path . --script res://tests/run_tests.gd
## Filtrar: añadir `-- test_brood` (subcadena del nombre del fichero o del método).
## Cualquier error de script durante un test cuenta como fallo.


class ErrorCounter extends Logger:
	var errors: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		errors.append("%s (%s:%d %s)" % [rationale if rationale != "" else code, file, line, function])

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _init() -> void:
	var logger := ErrorCounter.new()
	OS.add_logger(logger)
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]
	var dir := DirAccess.open("res://tests")
	var files: Array[String] = []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			files.append(f)
	files.sort()
	var total := 0
	var failed := 0
	var t0 := Time.get_ticks_msec()
	for f in files:
		logger.errors.clear()
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			print("  FAIL %s no compila" % f)
			for e in logger.errors:
				print("       - " + e)
			failed += 1
			total += 1
			continue
		var probe: Object = script.new()
		var methods: Array[String] = []
		for m in probe.get_method_list():
			var mname: String = m["name"]
			if mname.begins_with("test_"):
				methods.append(mname)
		methods.sort()
		for m in methods:
			if filter != "" and not (f.contains(filter) or m.contains(filter)):
				continue
			logger.errors.clear()
			var inst: TestCase = script.new()
			inst.current = "%s::%s" % [f, m]
			var ts := Time.get_ticks_msec()
			inst.call(m)
			var ms := Time.get_ticks_msec() - ts
			total += 1
			for e in logger.errors:
				inst.failures.append("error de script: " + e)
			if inst.failures.is_empty():
				print("  ok   %s (%d ms)" % [inst.current, ms])
			else:
				failed += 1
				print("  FAIL %s (%d ms)" % [inst.current, ms])
				for msg in inst.failures.slice(0, 12):
					print("       - " + msg)
	print("\n%d tests, %d fallos, %.1f s" % [total, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if failed > 0 else 0)
