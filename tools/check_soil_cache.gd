extends SceneTree
## Comprueba (con render real, no headless) que la caché del suelo por niveles
## repintada por trozos queda IGUAL que un repintado completo del mismo suelo.
##   xvfb-run godot --path . --script res://tools/check_soil_cache.gd -- <zoom>
var w: SimWorld
var sr: SoilRenderer
var view: SoilLodView
var step := 0
var zoom := 2
var partial_img: Image


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	zoom = int(args[0]) if args.size() > 0 else 2
	w = SimWorld.new()
	w.new_game(4242, 1790000000.0)
	sr = SoilRenderer.new()
	sr.setup(w)
	root.add_child(sr)
	view = SoilLodView.new()
	root.add_child(view)
	view.zoom = zoom
	view.setup(w, sr)


func _process(_delta: float) -> bool:
	step += 1
	# Cambios repartidos: túneles nuevos en varios sitios y tierra suelta en la superficie.
	if step in [5, 9, 13, 17]:
		var cx := 120 + step * 23
		for y in range(70, 110):
			for x in range(cx - 2, cx + 3):
				w.soil.set_mat(x, y, SimConst.Mat.AIR)
		w.soil.drop_loose(cx + 40, 30, SimConst.Mat.LOOSE, w.rng_sim)
		for _k in 30:
			w.soil.step_particles(w.rng_sim)
	if step == 40:
		partial_img = view.vp.get_texture().get_image()
		view._request_full()
	if step == 44:
		var full := view.vp.get_texture().get_image()
		var diff := 0
		for y in full.get_height():
			for x in full.get_width():
				if full.get_pixel(x, y) != partial_img.get_pixel(x, y):
					diff += 1
		print("zoom ×%d · repintados parciales %d · píxeles distintos parcial/completo: %d de %d" % [zoom, view.patch_renders, diff, full.get_width() * full.get_height()])
		w.dispose()
		return true
	return false
