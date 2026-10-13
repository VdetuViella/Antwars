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
	if step == 21:
		# Orden real del juego: main pide repintado completo (zoom/disposición) y,
		# en el mismo fotograma, SoilRenderer avisa de un parche.
		view._request_full()
		var r: Array[Rect2i] = [Rect2i(100, 60, 40, 40)]
		view._on_redrawn(r)
	if step in [1, 5, 9, 13, 17, 21]:
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
		# Bajo la superficie no puede quedar nada transparente (suelo sin pintar).
		var holes := 0
		for y in range(int(w.soil.h * 0.6) * zoom, full.get_height(), 3):
			for x in range(0, full.get_width(), 3):
				if partial_img.get_pixel(x, y).a < 0.5:
					holes += 1
		print("zoom ×%d · repintados parciales %d · píxeles distintos parcial/completo: %d de %d · huecos sin pintar: %d" % [zoom, view.patch_renders, diff, full.get_width() * full.get_height(), holes])
		w.dispose()
		return true
	return false
