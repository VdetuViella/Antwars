extends Node
## Punto de entrada. Crea o carga la partida, resuelve el tiempo que estuvo
## cerrado, monta la vista (suelo, decorado, hormigas) y la interfaz, y
## gestiona la ventana de escritorio y el bajo consumo sin foco.
## Toda la lógica de juego vive en sim/; aquí solo se presenta y se envían órdenes.

const AUTOSAVE_SECONDS := 120.0
const PRIORITIES := ["equilibrio", "crecer", "acumular", "excavar"]
const PRIORITY_NAMES := {"equilibrio": "Equilibrio", "crecer": "Crecer", "acumular": "Acumular", "excavar": "Excavar"}

var settings := GameSettings.new()
var world: SimWorld
var world_root: Node2D
var soil_r: SoilRenderer
var decor_room: DecorLayer
var decor_back: DecorLayer
var decor_front: DecorLayer
var pher_r: PheromoneOverlay
var ant_r: AntRenderer
var hud: Hud
var backdrop: ColorRect     ## fondo opaco en modo ventana (la ventana admite transparencia)

var focused := true
var _autosave := AUTOSAVE_SECONDS
var _ui_timer := 0.0
var _pan := Vector2.ZERO
var _dragging := false
var _painting := false
var _strip_size := Vector2i.ZERO
var _region_timer := 0.0
var _save_path := SaveSystem.DEFAULT_PATH
var _screenshot_frames := -1
var _screenshot_path := ""


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	settings.load_settings()
	_parse_cmdline()
	var offline_summary := {}
	world = SimWorld.new()
	var saved := SaveSystem.load_dict(_save_path)
	if not saved.is_empty():
		world.from_dict(saved)
		world.set_time_scale(settings.time_scale())
		var elapsed := Time.get_unix_time_from_system() - float(saved.get("saved_at_real", Time.get_unix_time_from_system()))
		if elapsed > 60.0:
			offline_summary = OfflineResolver.resolve(world, elapsed)
	else:
		var seed_v := int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
		world.new_game(seed_v, _local_now_unix())
	world.set_time_scale(settings.time_scale())
	world.behaviour_speed = settings.behaviour_speed
	_build_view()
	_build_ui()
	_apply_window_mode()
	if not offline_summary.is_empty() and float(offline_summary.get("real_seconds", 0.0)) > 300.0:
		hud.show_welcome(offline_summary)


func _parse_cmdline() -> void:
	# --nueva: partida nueva (borra la actual). --guardado=<ruta>. --captura=<png> (pruebas).
	for a in OS.get_cmdline_user_args():
		if a == "--nueva":
			SaveSystem.delete_all(_save_path)
		elif a.begins_with("--guardado="):
			_save_path = a.substr(11)
		elif a.begins_with("--captura="):
			_screenshot_path = a.substr(10)
			_screenshot_frames = 90
		elif a.begins_with("--escala="):
			settings.time_scale_key = a.substr(9)
		elif a == "--franja":
			settings.window_mode = "franja"
		elif a == "--ventana":
			settings.window_mode = "ventana"


static func _local_now_unix() -> float:
	var tz := Time.get_time_zone_from_system()
	return Time.get_unix_time_from_system() + float(tz.get("bias", 0)) * 60.0


# ---------------------------------------------------------------------------
# Vista
# ---------------------------------------------------------------------------

func _build_view() -> void:
	var back_layer := CanvasLayer.new()
	back_layer.layer = -1
	add_child(back_layer)
	backdrop = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back_layer.add_child(backdrop)
	world_root = Node2D.new()
	world_root.name = "World"
	add_child(world_root)
	# Orden de pintado: habitación → suelo → decorado (cría, granero, comedero…)
	# → feromonas → hormigas → cristal.
	decor_room = DecorLayer.new()
	decor_room.setup(world, DecorLayer.Layer.ROOM)
	world_root.add_child(decor_room)
	soil_r = SoilRenderer.new()
	soil_r.setup(world)
	world_root.add_child(soil_r)
	decor_back = DecorLayer.new()
	decor_back.setup(world, DecorLayer.Layer.BACK)
	world_root.add_child(decor_back)
	pher_r = PheromoneOverlay.new()
	pher_r.setup(world)
	world_root.add_child(pher_r)
	ant_r = AntRenderer.new()
	ant_r.setup(world)
	world_root.add_child(ant_r)
	decor_front = DecorLayer.new()
	decor_front.setup(world, DecorLayer.Layer.FRONT)
	world_root.add_child(decor_front)


func _build_ui() -> void:
	hud = Hud.new()
	add_child(hud)
	hud.build(world)
	hud.action.connect(_on_action)
	hud.info_panel.visible = settings.show_info
	_refresh_buttons()
	hud.refresh(settings.time_scale_key)


func _refresh_buttons() -> void:
	hud.set_button_text("heater", "Calor: " + ("sí" if world.env.heater_on else "no"))
	hud.set_button_text("speed", Hud._scale_name(settings.time_scale_key))
	hud.set_button_text("priority", PRIORITY_NAMES.get(world.priority, "Equilibrio"))
	hud.set_button_text("mode", "Ventana" if settings.window_mode == "franja" else "Franja")
	hud.set_button_text("ontop", "Encima: " + ("sí" if settings.always_on_top else "no"))
	hud.set_button_pressed_look("pher", pher_r.visible)
	hud.set_button_pressed_look("brush", hud.tool_brush)
	hud.set_button_pressed_look("lupa", hud.mag_enabled)
	hud.set_button_pressed_look("info", hud.info_panel.visible)


func _apply_window_mode() -> void:
	var z := float(settings.zoom)
	world_root.scale = Vector2(z, z)
	if settings.window_mode == "franja":
		_strip_size = DesktopWindow.apply_strip_mode(settings.strip_height, settings.always_on_top)
		decor_room.draw_room = false
		backdrop.visible = false
		hud.info_panel.visible = false
		get_viewport().transparent_bg = true
		# Mostrar la superficie y la parte alta del nido.
		_pan = Vector2(0, -float(SimConst.SURFACE_Y - 46) * z)
	else:
		DesktopWindow.apply_window_mode(settings.always_on_top, settings.window_pos)
		decor_room.draw_room = true
		backdrop.visible = true
		hud.info_panel.visible = settings.show_info
		get_viewport().transparent_bg = true
		_pan = Vector2.ZERO
	_layout_world()
	_refresh_buttons()


func _view_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func _layout_world() -> void:
	var vs := _view_size()
	var z := world_root.scale.x
	var ww := float(world.soil.w) * z
	var wh := float(world.soil.h) * z
	var avail_h := vs.y - Hud.BAR_H
	var x_center := floorf((vs.x - ww) * 0.5)
	var x := x_center
	if ww > vs.x:
		_pan.x = clampf(_pan.x, vs.x - ww - x_center, -x_center)
		x = floorf(x_center + _pan.x)
	else:
		_pan.x = 0.0
	var y_min := minf(0.0, avail_h - wh)
	var y_base := avail_h - wh if settings.window_mode != "franja" else 0.0
	if wh < avail_h:
		y_base = avail_h - wh
		y_min = y_base
	_pan.y = clampf(_pan.y, y_min - y_base, 0.0 if settings.window_mode == "franja" else maxf(0.0, -y_min))
	var y := floorf(y_base + _pan.y)
	if settings.window_mode != "franja":
		y = floorf(clampf(y_base + _pan.y, y_min, maxf(0.0, avail_h - wh)))
	world_root.position = Vector2(x, y)


func _update_click_region() -> void:
	if settings.window_mode != "franja":
		return
	# Zona que capta el ratón: el formicario desde un poco por encima del suelo,
	# más la barra y los paneles abiertos. El resto deja pasar los clics.
	var z := world_root.scale.x
	var vs := _view_size()
	var top_world := float(SimConst.SURFACE_Y - 18)
	var top := clampf(world_root.position.y + top_world * z, 0.0, vs.y)
	var x0 := maxf(world_root.position.x, 0.0)
	var x1 := minf(world_root.position.x + world.soil.w * z, vs.x)
	var bar_top := vs.y - Hud.BAR_H
	var poly := PackedVector2Array([
		Vector2(0, bar_top), Vector2(x0, bar_top), Vector2(x0, top), Vector2(x1, top),
		Vector2(x1, bar_top), Vector2(vs.x, bar_top), Vector2(vs.x, vs.y), Vector2(0, vs.y)])
	DesktopWindow.set_click_region(poly)


# ---------------------------------------------------------------------------
# Bucle
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	var coarse := not focused and settings.low_power_unfocused
	world.advance(delta, coarse)
	var bdt := SimConst.BEHAVIOUR_DT if not coarse else 0.5
	ant_r.alpha = clampf(world.beh_accum / bdt, 0.0, 1.0)
	_ui_timer -= delta
	if _ui_timer <= 0.0:
		_ui_timer = 0.25
		hud.refresh(settings.time_scale_key)
		if backdrop.visible:
			backdrop.color = DecorLayer.room_color(world.cal.light_level())
	_region_timer -= delta
	if _region_timer <= 0.0:
		_region_timer = 1.0
		_update_click_region()
	_autosave -= delta
	if _autosave <= 0.0:
		_autosave = AUTOSAVE_SECONDS
		_save()
	_update_magnifier()
	if _screenshot_frames > 0:
		_screenshot_frames -= 1
		if _screenshot_frames == 0:
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			get_tree().quit()


func _update_magnifier() -> void:
	var on := hud.mag_enabled and focused
	hud.magnifier.visible = on
	hud.mag_label.visible = on
	if not on:
		return
	var vs := _view_size()
	var m := get_viewport().get_mouse_position()
	var mat := hud.magnifier.material as ShaderMaterial
	mat.set_shader_parameter("center_uv", m / vs)
	mat.set_shader_parameter("screen_px", vs)
	# Información de la hormiga más cercana al centro de la lupa.
	var wp := (m - world_root.position) / world_root.scale.x
	var best := -1
	var best_d := 16.0
	var a := world.ants
	for i in a.cap:
		if a.alive[i] == 1:
			var d := Vector2(a.px[i], a.py[i]).distance_to(wp)
			if d < best_d:
				best_d = d
				best = i
	hud.mag_label.text = _describe_ant(best) if best >= 0 else _describe_place(wp)
	hud.mag_label.position = m + Vector2(78, -12)
	if hud.mag_label.position.x + 260 > vs.x:
		hud.mag_label.position.x = m.x - 330


func _describe_ant(i: int) -> String:
	var a := world.ants
	const CASTE := ["Obrera menor", "Obrera media", "Obrera mayor", "Reina"]
	const TASK := ["descansando", "cuidando la cría", "forrajeando", "excavando", "moliendo semillas", "limpiando", "reina"]
	const CARRY := ["", "lleva una semilla", "lleva tierra", "lleva pan de hormiga", "lleva cáscaras", "lleva un cadáver"]
	var name: String = CASTE[a.caste[i]]
	if a.caste[i] == SimConst.Caste.MINOR and a.nanitic[i] == 1:
		name = "Nanitic (primera camada)"
	var age := int(world.bio_day() - a.born_day[i])
	var t := name
	if a.caste[i] != SimConst.Caste.QUEEN:
		t += " · %d días · %s" % [age, TASK[a.task[i]]]
	else:
		t += " · %d días en el formicario" % int(world.colony.queen_age_days)
	var cs: String = CARRY[a.carry[i]]
	if cs != "":
		t += "\n" + cs
	return t


func _describe_place(wp: Vector2) -> String:
	var x := int(wp.x)
	var y := int(wp.y)
	if not world.soil.in_bounds(x, y):
		return ""
	match world.soil.get_mat(x, y):
		SimConst.Mat.ROCK:
			return "Piedra"
		SimConst.Mat.LOOSE:
			return "Tierra excavada"
		SimConst.Mat.MIDDEN:
			return "Basurero (cáscaras y restos)"
		SimConst.Mat.PLUG:
			return "Tapón de la fundación"
		SimConst.Mat.CLAY:
			return "Arcilla"
	return ""


# ---------------------------------------------------------------------------
# Entrada
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_pan.y += 24.0
			_layout_world()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_pan.y -= 24.0
			_layout_world()
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_painting = mb.pressed and hud.tool_brush
			if _painting:
				_paint_at(mb.position)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			_pan += mm.relative
			_layout_world()
		elif _painting:
			_paint_at(mm.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_1: _set_scale("realista")
			KEY_2: _set_scale("acompanante")
			KEY_3: _set_scale("acelerado")
			KEY_F9: _set_scale("debug")
			KEY_F: _on_action("pher", null)
			KEY_L: _on_action("lupa", null)
			KEY_I: _on_action("info", null)
			KEY_J: _on_action("journal", null)
			KEY_H: _on_action("help", null)
			KEY_F11: _on_action("mode", null)
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: _zoom(1)
			KEY_MINUS, KEY_KP_SUBTRACT: _zoom(-1)
			KEY_ESCAPE:
				hud.journal_panel.visible = false
				hud.help_panel.visible = false
				hud.welcome_panel.visible = false


func _paint_at(screen_pos: Vector2) -> void:
	var wp := (screen_pos - world_root.position) / world_root.scale.x
	if world.soil.in_bounds(int(wp.x), int(wp.y)) and wp.y < float(world.soil.surface_h[int(wp.x)] + 2):
		world.cmd_paint_trail(wp.x, float(world.soil.col_top[int(wp.x)] - 2))


func _zoom(d: int) -> void:
	settings.zoom = clampi(settings.zoom + d, 1, 4)
	world_root.scale = Vector2(settings.zoom, settings.zoom)
	_layout_world()
	settings.save_settings()


func _set_scale(key: String) -> void:
	settings.time_scale_key = key
	world.set_time_scale(settings.time_scale())
	settings.save_settings()
	_refresh_buttons()


func _on_action(id: String, _arg: Variant) -> void:
	match id:
		"feeder":
			world.cmd_refill_feeder(500.0)
		"water":
			world.cmd_refill_water(80.0)
		"heater":
			world.cmd_toggle_heater()
		"speed":
			var order := ["realista", "acompanante", "acelerado"]
			var k := order.find(settings.time_scale_key)
			_set_scale(order[(k + 1) % order.size()])
		"priority":
			var p := PRIORITIES.find(world.priority)
			world.cmd_set_priority(PRIORITIES[(p + 1) % PRIORITIES.size()])
		"pher":
			pher_r.visible = not pher_r.visible
		"brush":
			hud.tool_brush = not hud.tool_brush
			if hud.tool_brush:
				pher_r.visible = true
		"lupa":
			hud.mag_enabled = not hud.mag_enabled
		"info":
			hud.info_panel.visible = not hud.info_panel.visible
			settings.show_info = hud.info_panel.visible
			settings.save_settings()
		"journal":
			if hud.journal_panel.visible:
				hud.journal_panel.visible = false
			else:
				hud.show_journal()
		"help":
			hud.help_panel.visible = not hud.help_panel.visible
		"mode":
			_remember_window_pos()
			settings.window_mode = "ventana" if settings.window_mode == "franja" else "franja"
			settings.save_settings()
			_apply_window_mode()
		"ontop":
			settings.always_on_top = not settings.always_on_top
			DesktopWindow.set_on_top(settings.always_on_top)
			settings.save_settings()
	_refresh_buttons()
	hud.refresh(settings.time_scale_key)
	_update_click_region()


func _remember_window_pos() -> void:
	if settings.window_mode == "ventana" and not DesktopWindow.is_headless():
		settings.window_pos = DisplayServer.window_get_position()


# ---------------------------------------------------------------------------
# Foco, guardado y cierre
# ---------------------------------------------------------------------------

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			focused = false
			if settings.low_power_unfocused:
				Engine.max_fps = 10
				OS.low_processor_usage_mode = true
			_save()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			focused = true
			Engine.max_fps = 0
			OS.low_processor_usage_mode = false
		NOTIFICATION_WM_CLOSE_REQUEST:
			_remember_window_pos()
			settings.save_settings()
			_save()
			world.dispose()
			get_tree().quit()
		NOTIFICATION_WM_SIZE_CHANGED:
			if world_root != null:
				_layout_world()


func _save() -> void:
	if world == null or _screenshot_frames >= 0:
		return
	var err := SaveSystem.save(world, _save_path)
	if err != OK:
		push_warning("No se pudo guardar la partida: %s" % error_string(err))
