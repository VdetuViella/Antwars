extends TestCase
## ADR-005: el detalle por niveles es solo de dibujo. No toca la simulación, es
## determinista y el interruptor viene apagado.


func _run(w: SimWorld, beh_seconds: float, view: AntViewState = null) -> void:
	var steps := int(beh_seconds / SimConst.BEHAVIOUR_DT)
	for _s in steps:
		w.advance(SimConst.BEHAVIOUR_DT)
		if view != null:
			view.update(w, 1.0, SimConst.BEHAVIOUR_DT)


func test_view_state_does_not_touch_sim() -> void:
	# Mismo mundo con y sin el estado de dibujo nuevo: state_hash y generadores
	# aleatorios idénticos (regla dura 2).
	var a := make_world(321)
	var b := make_world(321)
	a.set_time_scale(800.0)
	b.set_time_scale(800.0)
	var view := AntViewState.new()
	_run(a, 4800.0)
	_run(b, 4800.0, view)
	check(a.colony.total_workers() > 0, "hay obreras moviéndose (%d)" % a.colony.total_workers())
	check_eq(b.state_hash(), a.state_hash(), "state_hash igual con y sin la vista por niveles")
	check_eq(b.rng_ants.state, a.rng_ants.state, "la vista no consume la RNG de las hormigas")
	check_eq(b.rng_sim.state, a.rng_sim.state, "ni la del mundo")
	check_eq(b.rng_colony.state, a.rng_colony.state, "ni la de la colonia")
	a.dispose(); b.dispose()


func test_view_state_is_deterministic() -> void:
	var w1 := make_world(55)
	var w2 := make_world(55)
	w1.set_time_scale(800.0)
	w2.set_time_scale(800.0)
	var v1 := AntViewState.new()
	var v2 := AntViewState.new()
	_run(w1, 4800.0, v1)
	_run(w2, 4800.0, v2)
	check_eq(v1.dir, v2.dir, "mismas direcciones")
	check_eq(v1.frame, v2.frame, "mismos fotogramas")
	check_eq(v1.view, v2.view, "mismas vistas")
	check_eq(v1.glass, v2.glass, "mismas elecciones suelo/cristal")
	w1.dispose(); w2.dispose()


func test_view_choice_uses_both_views() -> void:
	# Con colonia en marcha hay hormigas de perfil (suelo/superficie) y cenitales (cristal).
	var w := make_world(11)
	w.set_time_scale(800.0)
	var v := AntViewState.new()
	_run(w, 5200.0, v)
	w.set_time_scale(24.0)
	_run(w, 60.0, v)
	var side := 0
	var top := 0
	for i in w.ants.cap:
		if w.ants.alive[i] == 1:
			if v.view[i] == AntViewState.VIEW_SIDE:
				side += 1
			else:
				top += 1
	check(side > 0 and top > 0, "hay hormigas de perfil (%d) y cenitales (%d)" % [side, top])
	w.dispose()


func test_dir_conversion_and_frames() -> void:
	check_eq(AntViewState.dir16_from_dir8(0), 0, "este → 0")
	check_eq(AntViewState.dir16_from_dir8(2), 12, "norte (dir8 = 2) → 12 en sentido horario")
	check_eq(AntViewState.dir16_from_dir8(6), 4, "sur (dir8 = 6) → 4")
	check_eq(AntViewState.row_of(SimConst.Caste.MINOR, 1), 4, "nanitic usa la fila 4")


func test_lod_zoom_steps() -> void:
	var main_script: GDScript = load("res://game/main.gd")
	check_eq(main_script._snap_lod_zoom(1), 1, "×1")
	check_eq(main_script._snap_lod_zoom(3), 2, "×3 → ×2 (sin ×3, D1)")
	check_eq(main_script._snap_lod_zoom(8), 4, "×8 → ×4")


func test_detail_switch_off_by_default() -> void:
	var s := GameSettings.new()
	check(not s.detail_levels_enabled, "el detalle por niveles viene apagado")


func test_atlas_contract() -> void:
	# Contrato del atlas: 16 direcciones × 2 vistas filas, 8 columnas, 3 niveles 1:1.
	for v: String in AntLodRenderer.VARIANTS:
		var at := AntAtlas.new()
		check(at.load_variant("res://assets/ants_lod/base%d" % AntLodRenderer.ANT_BASE_PX, v), "carga %s" % v)
		check_eq(int(at.manifest["directions"]), 16, "%s: 16 direcciones" % v)
		check_eq(int(at.manifest["frames"]), 8, "%s: 8 fotogramas" % v)
		check_eq(int(at.manifest["rest_frame"]), 0, "%s: reposo = fotograma 0" % v)
		for lv in 3:
			var cell := at.cells[lv]
			var tex := at.textures[lv]
			check_eq(tex.get_width(), cell * 8, "%s L%d: ancho = 8 celdas" % [v, lv])
			check_eq(tex.get_height(), cell * 32, "%s L%d: alto = 32 filas" % [v, lv])
		var img := at.textures[2].get_image()
		var semi := 0
		for y in range(0, img.get_height(), 3):
			for x in range(0, img.get_width(), 3):
				var al := img.get_pixel(x, y).a
				if al > 0.01 and al < 0.99:
					semi += 1
		check_eq(semi, 0, "%s: sin semitransparencias (alfa 0 o 255)" % v)
