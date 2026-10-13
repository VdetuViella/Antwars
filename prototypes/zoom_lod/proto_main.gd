extends Node2D
## Prototipo del ADR-005 (Fase 1): detalle por zoom ×1 / ×2 / ×4.
## Escena independiente: usa SoilGrid y SoilRenderer solo como datos/referencia
## (no modifica sim/ ni la escena principal). Nada se escala con filtrado: el
## mundo se dibuja a resolución de pantalla y cada texel cae en un píxel.
##
## Teclas: + / − zoom · flechas o arrastrar (botón derecho) desplazar · B base 9/13 px
## · S entero/subpíxel · T tablero de texels · O contorno · V vista auto/cenital/perfil
## · P pausa · F1 ayuda en pantalla.
## Argumentos (tras --): --zoom=1|2|4 --base=9|13 --subpixel --debug --view=auto|top|side
## --centro=x,y --tam=AnchoxAlto --captura=ruta.png --serie=N

const AntAtlas := preload("res://prototypes/zoom_lod/ant_atlas.gd")
const ZOOMS := [1, 2, 4]
const VARIANTS := ["menor", "media", "mayor"]
const SOIL_SHADER := preload("res://prototypes/zoom_lod/soil_lod.gdshader")
const ANT_SHADER := preload("res://prototypes/zoom_lod/ant_lod.gdshader")
const DIR_HYSTERESIS_DEG := 4.0
const VIEW_SWITCH_S := 0.3
const DIR_SMOOTH_S := 0.15           ## suavizado de la dirección (el relieve en escalera no la hace saltar)

# --- Mundo de prueba ---
var holder: SimWorld                 ## solo como contenedor del suelo para SoilRenderer
var soil: SoilGrid
var soil_ref: SoilRenderer           ## textura actual (×1 exacto)
var mat_img: Image
var mat_tex: ImageTexture
var soil_rect: ColorRect
var soil_mat: ShaderMaterial
var surf_y := 60
var ex := 300                        ## boca del nido

# --- Estado de vista ---
var zi := 1                          ## índice en ZOOMS
var base_px := 9
var subpixel := false
var debug_texels := false
var outline := true
var view_mode := "auto"              ## auto | top | side
var paused := false
var cam_world := Vector2(330, 95)    ## punto del mundo en el centro de la pantalla
var _dragging := false
var hud: Label
var help: Label
var atlases: Array = []              ## AntAtlas por variante
var mmis: Array[MultiMeshInstance2D] = []

# --- Hormigas del prototipo (movimiento guionizado, solo de dibujo) ---
var ants: Array[Dictionary] = []

# --- Captura ---
var _shot_path := ""
var _shot_frames := -1
var _series_left := 0
var _series_idx := 0
var _test_size := Vector2i.ZERO
var _proc_ms_ema := 0.0
var _no_ants := false                ## --sin-hormigas (comprobar el suelo a ×1)
var _dump_base := ""                 ## --volcar-base=ruta.png (textura actual de SoilRenderer)


func _ready() -> void:
	_parse_args()
	get_viewport().transparent_bg = false
	RenderingServer.set_default_clear_color(Color8(222, 214, 196))
	_build_world()
	_build_soil_view()
	_load_atlases()
	_build_ants()
	_build_hud()
	get_viewport().size_changed.connect(_layout)
	if _no_ants:
		for mmi in mmis:
			mmi.visible = false
	if _dump_base != "":
		soil_ref.img.save_png(_dump_base)
	if _test_size != Vector2i.ZERO and DisplayServer.get_name() != "headless":
		_apply_size.call_deferred()
	_layout()


func _apply_size() -> void:
	get_window().position = Vector2i.ZERO
	get_window().size = _test_size


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--zoom="):
			zi = maxi(0, ZOOMS.find(int(a.substr(7))))
		elif a.begins_with("--base="):
			base_px = int(a.substr(7))
		elif a == "--subpixel":
			subpixel = true
		elif a == "--debug":
			debug_texels = true
		elif a.begins_with("--view="):
			view_mode = a.substr(7)
		elif a.begins_with("--centro="):
			var p := a.substr(9).split(",")
			cam_world = Vector2(float(p[0]), float(p[1]))
		elif a.begins_with("--tam="):
			var t := a.substr(6).split("x")
			_test_size = Vector2i(int(t[0]), int(t[1]))
		elif a.begins_with("--captura="):
			_shot_path = a.substr(10)
			_shot_frames = 75
		elif a.begins_with("--serie="):
			_series_left = int(a.substr(8))
		elif a == "--sin-hormigas":
			_no_ants = true
		elif a.begins_with("--volcar-base="):
			_dump_base = a.substr(14)


# ---------------------------------------------------------------------------
# Mundo: suelo real generado con una semilla fija y un nido tallado a mano
# ---------------------------------------------------------------------------

func _build_world() -> void:
	holder = SimWorld.new()
	soil = holder.soil
	soil.setup(SimConst.WORLD_W, SimConst.WORLD_H)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261013
	soil.generate(rng, ex)
	surf_y = soil.surface_h[ex]
	# Pozo vertical, dos cámaras y una galería inclinada entre ellas.
	_carve_capsule(Vector2(ex, surf_y - 1), Vector2(ex, surf_y + 48), 3.0)
	_carve_ellipse(Vector2(ex, surf_y + 56), 24.0, 6.5)
	_carve_capsule(Vector2(ex + 22, surf_y + 57), Vector2(ex + 80, surf_y + 70), 2.6)
	_carve_ellipse(Vector2(ex + 96, surf_y + 72), 17.0, 5.5)
	# Montículo de tierra suelta a ambos lados de la boca.
	soil.drop_loose(ex - 14, 160, SimConst.Mat.LOOSE, rng)
	soil.drop_loose(ex + 15, 140, SimConst.Mat.LOOSE, rng)
	for _k in 200:
		soil.step_particles(rng, 20000)
		if soil.active.is_empty():
			break


func _carve_capsule(a: Vector2, b: Vector2, r: float) -> void:
	var t := {"ax": a.x, "ay": a.y, "bx": b.x, "by": b.y, "r": r}
	for y in range(int(minf(a.y, b.y) - r - 1), int(maxf(a.y, b.y) + r + 2)):
		for x in range(int(minf(a.x, b.x) - r - 1), int(maxf(a.x, b.x) + r + 2)):
			if soil.in_bounds(x, y) and NestPlan.in_capsule(x, y, t) and soil.get_mat(x, y) != SimConst.Mat.ROCK:
				soil.set_mat(x, y, SimConst.Mat.AIR)


func _carve_ellipse(c: Vector2, rx: float, ry: float) -> void:
	var e := {"cx": int(c.x), "cy": int(c.y), "rx": rx, "ry": ry}
	for y in range(int(c.y - ry - 1), int(c.y + ry + 2)):
		for x in range(int(c.x - rx - 1), int(c.x + rx + 2)):
			if soil.in_bounds(x, y) and NestPlan.in_ellipse(x, y, e) and soil.get_mat(x, y) != SimConst.Mat.ROCK:
				soil.set_mat(x, y, SimConst.Mat.AIR)


# ---------------------------------------------------------------------------
# Suelo: textura de materiales (RG8) + shader por niveles
# ---------------------------------------------------------------------------

func _build_soil_view() -> void:
	soil_ref = SoilRenderer.new()
	soil_ref.setup(holder)
	soil_ref.visible = false
	add_child(soil_ref)
	mat_img = Image.create(soil.w, soil.h, false, Image.FORMAT_RG8)
	_refresh_mat_image()
	mat_tex = ImageTexture.create_from_image(mat_img)
	soil_mat = ShaderMaterial.new()
	soil_mat.shader = SOIL_SHADER
	soil_mat.set_shader_parameter("mat_tex", mat_tex)
	soil_mat.set_shader_parameter("base_tex", soil_ref.tex)
	soil_mat.set_shader_parameter("pal_tex", _palette_texture())
	soil_mat.set_shader_parameter("world_cells", Vector2(soil.w, soil.h))
	soil_rect = ColorRect.new()
	soil_rect.material = soil_mat
	soil_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(soil_rect)


func _refresh_mat_image() -> void:
	var data := PackedByteArray()
	data.resize(soil.w * soil.h * 2)
	for y in soil.h:
		for x in soil.w:
			var m := soil.mat[y * soil.w + x]
			var o := (y * soil.w + x) * 2
			data[o] = 255 if (m == SimConst.Mat.AIR and y < soil.surface_h[x]) else m
			data[o + 1] = int(clampf(float(y - soil.surface_h[x]) / float(soil.h), 0.0, 1.0) * 255.0)
	mat_img.set_data(soil.w, soil.h, false, Image.FORMAT_RG8, data)


func _palette_texture() -> ImageTexture:
	var pal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/palette.json"))
	var img := Image.create(4, 8, false, Image.FORMAT_RGBA8)
	var rows: Array = [pal["cavity"]]
	for m in range(1, 8):
		rows.append(pal["soil"][str(m)])
	for r in rows.size():
		for i in 4:
			var c: Array = rows[r][i]
			img.set_pixel(i, r, Color8(int(c[0]), int(c[1]), int(c[2])))
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------------
# Hormigas
# ---------------------------------------------------------------------------

func _load_atlases() -> void:
	atlases.clear()
	for v in VARIANTS:
		var a := AntAtlas.new()
		a.load_variant("res://assets/ants_lod/base%d" % base_px, v)
		atlases.append(a)
	if mmis.is_empty():
		for v in VARIANTS:
			var mmi := MultiMeshInstance2D.new()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_2D
			mm.use_custom_data = true
			mmi.multimesh = mm
			var mat := ShaderMaterial.new()
			mat.shader = ANT_SHADER
			mmi.material = mat
			add_child(mmi)
			mmis.append(mmi)
	_apply_zoom_to_ants()


func _apply_zoom_to_ants() -> void:
	var z: int = ZOOMS[zi]
	for vi in VARIANTS.size():
		var a = atlases[vi]
		var mmi := mmis[vi]
		var cell: int = a.cell_for_zoom(z)
		mmi.texture = a.texture_for_zoom(z)
		mmi.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if subpixel else CanvasItem.TEXTURE_FILTER_NEAREST
		var mesh := ArrayMesh.new()
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		var h := float(cell) * 0.5
		arr[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
		arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mmi.multimesh.mesh = mesh
		var mat := mmi.material as ShaderMaterial
		mat.set_shader_parameter("subpixel", subpixel)
		mat.set_shader_parameter("debug_texels", debug_texels)
		mat.set_shader_parameter("use_outline", outline)


func _build_ants() -> void:
	ants.clear()
	var fl := float(surf_y)
	# variante, recorrido (lista de puntos), velocidad mm/s, «superficie» (sigue el relieve)
	_add_ant(0, [Vector2(150, 0), Vector2(470, 0)], 14.0, true)
	_add_ant(1, [Vector2(420, 0), Vector2(180, 0)], 15.0, true)
	_add_ant(2, [Vector2(250, 0), Vector2(360, 0)], 12.0, true)
	_add_ant(0, [Vector2(ex, fl + 2), Vector2(ex, fl + 49)], 13.0, false)            # pozo
	_add_ant(1, [Vector2(ex, fl + 47), Vector2(ex, fl + 4)], 13.0, false)
	_add_ant(0, [Vector2(ex - 20, 0), Vector2(ex + 20, 0)], 11.0, false, fl + 62.5)   # suelo cámara A
	_add_ant(2, [Vector2(ex - 16, fl + 53), Vector2(ex + 14, fl + 58), Vector2(ex - 4, fl + 51)], 10.0, false)  # cristal
	_add_ant(0, [Vector2(ex + 24, fl + 57), Vector2(ex + 82, fl + 70)], 12.0, false)  # galería inclinada
	_add_ant(1, [Vector2(ex + 82, fl + 72), Vector2(ex + 110, fl + 70), Vector2(ex + 96, fl + 68)], 9.0, false)
	_add_ant(2, [Vector2(ex + 102, fl + 75)], 0.0, false)                              # en reposo
	for mmi in mmis:
		mmi.multimesh.instance_count = 0
	var counts := [0, 0, 0]
	for a in ants:
		counts[a["v"]] += 1
	for vi in VARIANTS.size():
		mmis[vi].multimesh.instance_count = counts[vi]


func _add_ant(v: int, path: Array, speed: float, surface: bool, floor_y: float = -1.0) -> void:
	var id := ants.size()
	var p := PackedVector2Array(path)
	ants.append({"v": v, "path": p, "seg": 0, "t": 0.0, "speed": speed, "surface": surface,
		"floor_y": floor_y, "pos": p[0], "prev": p[0], "dir": 0, "phase": float((id * 2654435761) & 0xFFFF) / 65536.0,
		"view": 1 if (surface or floor_y > 0.0) else 0, "view_t": 0.0, "fwd": true, "heading": Vector2.ZERO})


func _ground_pos(a: Dictionary, x: float) -> Vector2:
	var at = atlases[a["v"]]
	var feet: float = at.feet_mm()
	if a["surface"]:
		var cx := clampi(int(x), 0, soil.w - 1)
		return Vector2(x, float(soil.col_top[cx]) - feet)
	return Vector2(x, float(a["floor_y"]) - feet)


func _step_ants(dt: float) -> void:
	for a in ants:
		a["prev"] = a["pos"]
		var path: PackedVector2Array = a["path"]
		if path.size() < 2 or float(a["speed"]) <= 0.0:
			continue
		var budget: float = float(a["speed"]) * dt
		var guard := 0
		while budget > 0.0 and guard < 8:
			guard += 1
			var i: int = a["seg"]
			var j := i + 1 if a["fwd"] else i - 1
			if j < 0 or j >= path.size():
				a["fwd"] = not a["fwd"]
				continue
			var from: Vector2 = path[i]
			var to: Vector2 = path[j]
			var seg_len := from.distance_to(to)
			var left := seg_len * (1.0 - float(a["t"]))
			if budget >= left:
				budget -= left
				a["seg"] = j
				a["t"] = 0.0
			else:
				a["t"] = float(a["t"]) + budget / maxf(seg_len, 0.001)
				budget = 0.0
		var i2: int = a["seg"]
		var j2 := i2 + 1 if a["fwd"] else i2 - 1
		j2 = clampi(j2, 0, path.size() - 1)
		var p := path[i2].lerp(path[j2], float(a["t"]))
		if a["surface"] or float(a["floor_y"]) > 0.0:
			p = _ground_pos(a, p.x)
		a["pos"] = p


func _update_ant_render(dt: float) -> void:
	var z: int = ZOOMS[zi]
	var origin := _origin()
	var vs := get_viewport().get_visible_rect().size
	var bufs: Array[PackedFloat32Array] = []
	var ns := [0, 0, 0]
	for vi in VARIANTS.size():
		var b := PackedFloat32Array()
		b.resize(mmis[vi].multimesh.instance_count * 12)
		bufs.append(b)
	for a in ants:
		var vi: int = a["v"]
		var at = atlases[vi]
		var pos: Vector2 = a["pos"]
		var vel: Vector2 = pos - Vector2(a["prev"])
		var dist := vel.length()
		# Dirección: velocidad suavizada (media exponencial) y cuantizada a 16 con
		# histéresis, para que no parpadee entre vecinas ni salte en los escalones.
		if dist > 0.0005:
			var k := 1.0 - exp(-dt / DIR_SMOOTH_S)
			var heading: Vector2 = Vector2(a["heading"]).lerp(vel / maxf(dt, 0.001), k)
			if Vector2(a["heading"]) == Vector2.ZERO:
				heading = vel / maxf(dt, 0.001)
			a["heading"] = heading
			var ang := rad_to_deg(atan2(heading.y, heading.x))
			var cur := float(int(a["dir"]) * 22.5)
			var diff := absf(fposmod(ang - cur + 180.0, 360.0) - 180.0)
			if diff > 11.25 + DIR_HYSTERESIS_DEG:
				a["dir"] = posmod(roundi(ang / 22.5), 16)
		# Fase de la marcha ligada a la distancia recorrida (las patas no patinan).
		var frame := 0
		if dist > 0.0005:
			a["phase"] = fposmod(float(a["phase"]) + dist / at.stride_mm(), 1.0)
			frame = int(float(a["phase"]) * 8.0) % 8
		# Vista: perfil sobre un suelo, cenital por el cristal (con histéresis).
		var want: int = _wanted_view(a, vel)
		if want != int(a["view"]):
			a["view_t"] = float(a["view_t"]) + dt
			if float(a["view_t"]) >= VIEW_SWITCH_S:
				a["view"] = want
				a["view_t"] = 0.0
		else:
			a["view_t"] = 0.0
		var view: int = a["view"]
		if view_mode == "top":
			view = 0
		elif view_mode == "side":
			view = 1
		var cell: int = at.cell_for_zoom(z)
		var sp := Vector2(origin) + pos * float(z)
		var tx := sp.x
		var ty := sp.y
		if not subpixel:
			var half := 0.5 if (cell % 2) == 1 else 0.0
			tx = floorf(sp.x) + half
			ty = floorf(sp.y) + half
		# Descarte por vista: las que quedan fuera no se dibujan.
		if tx < -cell or ty < -cell or tx > vs.x + cell or ty > vs.y + cell:
			continue
		var o: int = ns[vi] * 12
		var b: PackedFloat32Array = bufs[vi]
		b[o] = 1.0; b[o + 1] = 0.0; b[o + 2] = 0.0; b[o + 3] = tx
		b[o + 4] = 0.0; b[o + 5] = 1.0; b[o + 6] = 0.0; b[o + 7] = ty
		b[o + 8] = float(a["dir"]); b[o + 9] = float(frame); b[o + 10] = float(view); b[o + 11] = 0.0
		bufs[vi] = b
		ns[vi] += 1
	for vi in VARIANTS.size():
		var mm := mmis[vi].multimesh
		if mm.instance_count > 0:
			mm.buffer = bufs[vi]
		mm.visible_instance_count = ns[vi]


func _wanted_view(a: Dictionary, vel: Vector2) -> int:
	if a["surface"]:
		return 1
	var at = atlases[a["v"]]
	var pos: Vector2 = a["pos"]
	var feet_y := pos.y + float(at.feet_mm())
	var supported := soil.is_solid(int(pos.x), int(feet_y + 1.5)) or soil.is_solid(int(pos.x), int(feet_y + 0.5))
	var horizontal := vel.length() < 0.0005 or absf(vel.y) <= absf(vel.x) * 0.7
	return 1 if (supported and horizontal) else 0


# ---------------------------------------------------------------------------
# Cámara, entrada y bucle
# ---------------------------------------------------------------------------

## Esquina del mundo en píxeles ENTEROS de pantalla (el suelo no «nada» al desplazarse).
func _origin() -> Vector2i:
	var z: int = ZOOMS[zi]
	var vs := get_viewport().get_visible_rect().size
	return Vector2i(roundi(vs.x * 0.5 - cam_world.x * float(z)), roundi(vs.y * 0.5 - cam_world.y * float(z)))


func _layout() -> void:
	var z: int = ZOOMS[zi]
	var o := _origin()
	soil_rect.position = Vector2(o)
	soil_rect.size = Vector2(soil.w * z, soil.h * z)
	soil_mat.set_shader_parameter("zoom", z)
	soil_mat.set_shader_parameter("debug_texels", debug_texels)


func _set_zoom_index(i: int) -> void:
	zi = clampi(i, 0, ZOOMS.size() - 1)      # tope en los extremos, cambio instantáneo
	_apply_zoom_to_ants()
	_layout()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: _set_zoom_index(zi + 1)
			KEY_MINUS, KEY_KP_SUBTRACT: _set_zoom_index(zi - 1)
			KEY_B:
				base_px = 13 if base_px == 9 else 9
				_load_atlases()
			KEY_S:
				subpixel = not subpixel
				_apply_zoom_to_ants()
			KEY_T:
				debug_texels = not debug_texels
				_apply_zoom_to_ants()
				_layout()
			KEY_O:
				outline = not outline
				_apply_zoom_to_ants()
			KEY_V:
				view_mode = {"auto": "top", "top": "side", "side": "auto"}[view_mode]
			KEY_P: paused = not paused
			KEY_F1: help.visible = not help.visible
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom_index(zi + 1)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom_index(zi - 1)
	elif event is InputEventMouseMotion and _dragging:
		cam_world -= (event as InputEventMouseMotion).relative / float(ZOOMS[zi])
		_layout()


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var pan := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if pan != Vector2.ZERO:
		cam_world += pan * 200.0 * delta / float(ZOOMS[zi])
		_layout()
	if not paused:
		_step_ants(minf(delta, 0.05))
	_update_ant_render(minf(delta, 0.05))
	_proc_ms_ema = lerpf(_proc_ms_ema, float(Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	hud.text = "×%d · base %d px · %s · vista %s · %d FPS (%.1f ms/frame) · lógica del prototipo %.2f ms   [F1 ayuda]" % [
		ZOOMS[zi], base_px, "subpíxel" if subpixel else "píxel entero", view_mode,
		Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0), _proc_ms_ema]
	_capture()


func _capture() -> void:
	if _shot_frames < 0:
		return
	_shot_frames -= 1
	if _shot_frames > 0:
		return
	var img := get_viewport().get_texture().get_image()
	if _series_left > 0:
		img.save_png(_shot_path.replace(".png", "_%d.png" % _series_idx))
		_series_idx += 1
		_series_left -= 1
		_shot_frames = 2
		return
	img.save_png(_shot_path)
	get_tree().quit()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(8, 6)
	hud.add_theme_color_override("font_color", Color(0.15, 0.12, 0.1))
	hud.add_theme_font_size_override("font_size", 13)
	layer.add_child(hud)
	help = Label.new()
	help.position = Vector2(8, 26)
	help.add_theme_color_override("font_color", Color(0.15, 0.12, 0.1))
	help.add_theme_font_size_override("font_size", 12)
	help.text = "+/− zoom ×1·×2·×4 · flechas o botón derecho: desplazar · B base 9/13 px · S entero/subpíxel · T tablero de texels · O contorno · V vista auto/cenital/perfil · P pausa"
	help.visible = false
	layer.add_child(help)
