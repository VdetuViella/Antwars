extends SceneTree
## Vuelve a guardar una partida con la hora real de ahora (sin resolución offline),
## para entregar partidas de prueba que no arranquen con horas de ausencia.
##   godot --headless --path . --script res://tools/refresh_save.gd -- <origen> <destino>
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var w := SimWorld.new()
	var d := SaveSystem.load_dict(String(args[0]))
	if d.is_empty():
		printerr("No se pudo leer %s" % args[0])
		quit(1)
		return
	w.from_dict(d)
	SaveSystem.save(w, String(args[1]))
	print("guardado %s: día %.1f, %d obreras, cría %d, granero %d" % [args[1], w.bio_day(), w.colony.total_workers(), w.colony.brood_total(), int(w.colony.granary)])
	w.dispose()
	quit()
