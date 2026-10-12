class_name Hud
extends CanvasLayer
## Interfaz: barra de herramientas inferior, panel de información, diario,
## ayuda, «mientras no estabas» y la lupa. Emite `action(name, arg)` y deja
## la lógica a main.gd.

signal action(name: String, arg: Variant)

const BAR_H := 34
const C_PANEL := Color(0.13, 0.1, 0.08, 0.88)
const C_BORDER := Color(0.55, 0.45, 0.32, 0.9)
const C_TEXT := Color(0.95, 0.9, 0.8)
const C_DIM := Color(0.75, 0.68, 0.56)

var world: SimWorld
var bar: PanelContainer
var status_label: Label
var info_panel: PanelContainer
var info_label: Label
var journal_panel: PanelContainer
var journal_text: RichTextLabel
var welcome_panel: PanelContainer
var welcome_text: RichTextLabel
var help_panel: PanelContainer
var buttons := {}
var magnifier: ColorRect
var mag_label: Label
var mag_enabled := false
var tool_brush := false


func build(w: SimWorld) -> void:
	world = w
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)

	# --- Lupa (por debajo de los paneles) ---
	magnifier = ColorRect.new()
	magnifier.set_anchors_preset(Control.PRESET_FULL_RECT)
	magnifier.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://game/shaders/magnifier.gdshader")
	magnifier.material = mat
	magnifier.visible = false
	root.add_child(magnifier)
	mag_label = Label.new()
	mag_label.add_theme_font_size_override("font_size", 11)
	mag_label.add_theme_color_override("font_color", C_TEXT)
	mag_label.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.05))
	mag_label.add_theme_constant_override("outline_size", 4)
	mag_label.visible = false
	root.add_child(mag_label)

	# --- Barra inferior ---
	bar = PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -BAR_H
	root.add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	bar.add_child(hb)
	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.clip_text = true
	status_label.add_theme_color_override("font_color", C_TEXT)
	hb.add_child(status_label)
	_btn(hb, "feeder", "Comedero +500", "Rellenar el comedero con 500 semillas")
	_btn(hb, "water", "Agua", "Rellenar el tubo de agua (humedad del nido)")
	_btn(hb, "heater", "Calor: sí", "Encender o apagar la manta térmica (+3 °C)")
	_btn(hb, "speed", "×24", "Escala de tiempo: Realista ×1, Acompañante ×24, Acelerado ×96 (teclas 1-3)")
	_btn(hb, "priority", "Equilibrio", "Prioridad de la colonia: equilibrio, crecer, acumular o excavar")
	_btn(hb, "pher", "Feromonas", "Ver la capa de feromonas (F)")
	_btn(hb, "brush", "Pincel", "Pintar un rastro de feromona con el ratón para guiar a las forrajeras")
	_btn(hb, "lupa", "Lupa", "Lupa ×3 bajo el ratón (L)")
	_btn(hb, "info", "Info", "Mostrar u ocultar el panel de información (I)")
	_btn(hb, "journal", "Diario", "Cuaderno de campo de la colonia (J)")
	_btn(hb, "mode", "Franja", "Cambiar entre ventana y franja de escritorio (F11)")
	_btn(hb, "ontop", "Encima: no", "Mantener la ventana siempre encima")
	_btn(hb, "help", "?", "Ayuda (H)")

	# --- Panel de información ---
	info_panel = PanelContainer.new()
	info_panel.position = Vector2(8, 8)
	root.add_child(info_panel)
	info_label = Label.new()
	info_label.add_theme_color_override("font_color", C_TEXT)
	info_label.add_theme_font_size_override("font_size", 11)
	info_panel.add_child(info_label)

	# --- Diario ---
	journal_panel = _modal(root, "Cuaderno de campo", Vector2(560, 360))
	journal_text = journal_panel.get_meta("text")

	# --- Mientras no estabas ---
	welcome_panel = _modal(root, "Mientras no estabas", Vector2(520, 300))
	welcome_text = welcome_panel.get_meta("text")

	# --- Ayuda ---
	help_panel = _modal(root, "Cómo funciona", Vector2(600, 380))
	var ht: RichTextLabel = help_panel.get_meta("text")
	ht.text = _help_text()


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 12
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL
	sb.border_color = C_BORDER
	sb.set_border_width_all(1)
	sb.set_content_margin_all(6)
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	t.set_stylebox("panel", "PanelContainer", sb)
	var b := StyleBoxFlat.new()
	b.bg_color = Color(0.24, 0.19, 0.14, 0.95)
	b.border_color = Color(0.45, 0.36, 0.26)
	b.set_border_width_all(1)
	b.set_content_margin_all(4)
	b.content_margin_left = 7
	b.content_margin_right = 7
	var bh := b.duplicate() as StyleBoxFlat
	bh.bg_color = Color(0.34, 0.27, 0.19, 0.98)
	var bp := b.duplicate() as StyleBoxFlat
	bp.bg_color = Color(0.45, 0.33, 0.18, 1.0)
	t.set_stylebox("normal", "Button", b)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("hover_pressed", "Button", bp)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 0.97, 0.88))
	t.set_color("font_pressed_color", "Button", Color(1, 0.95, 0.75))
	t.set_color("default_color", "RichTextLabel", C_TEXT)
	t.set_font_size("normal_font_size", "RichTextLabel", 12)
	t.set_font_size("bold_font_size", "RichTextLabel", 12)
	return t


func _btn(parent: Control, id: String, text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: action.emit(id, null))
	parent.add_child(b)
	buttons[id] = b
	return b


func _modal(root: Control, title: String, size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = size
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.offset_left = -size.x / 2
	p.offset_right = size.x / 2
	p.offset_top = -size.y / 2 - BAR_H / 2.0
	p.offset_bottom = size.y / 2 - BAR_H / 2.0
	p.visible = false
	root.add_child(p)
	var vb := VBoxContainer.new()
	p.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var lt := Label.new()
	lt.text = title
	lt.add_theme_font_size_override("font_size", 14)
	lt.add_theme_color_override("font_color", Color(1, 0.92, 0.72))
	lt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(lt)
	var close := Button.new()
	close.text = "Cerrar"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: p.visible = false)
	head.add_child(close)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.scroll_following = true
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.custom_minimum_size = Vector2(size.x - 16, size.y - 44)
	vb.add_child(rt)
	p.set_meta("text", rt)
	return p


func set_button_text(id: String, text: String) -> void:
	if buttons.has(id):
		(buttons[id] as Button).text = text


func set_button_pressed_look(id: String, on: bool) -> void:
	if buttons.has(id):
		(buttons[id] as Button).modulate = Color(1.25, 1.15, 0.85) if on else Color(1, 1, 1)


## Región de la pantalla que capta el ratón en modo franja (barra + paneles visibles).
func ui_rects() -> Array[Rect2]:
	var out: Array[Rect2] = [bar.get_global_rect()]
	for p: Control in [info_panel, journal_panel, welcome_panel, help_panel]:
		if p.visible:
			out.append(p.get_global_rect())
	return out


func refresh(time_key: String) -> void:
	var w := world
	var c := w.colony
	var d := w.cal.date_dict()
	const MES := ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
	var phase := _phase_text()
	status_label.text = "  %d %s %d · %02d:%02d · %s · %d obreras · cría %d · granero %d · %s" % [
		d["day"], MES[int(d["month"]) - 1], d["year"], d["hour"], d["minute"],
		_scale_name(time_key), c.total_workers(), c.brood_total(), int(c.granary), phase]
	if info_panel.visible:
		var temp := w.env.nest_temp(w.cal)
		var lines: Array[String] = []
		lines.append("%s  %s" % [w.cal.format_date_es(), "☀" if w.cal.is_daylight() else "☾"])
		var queen := "viva" if c.queen_alive else "muerta"
		if c.founding and c.queen_alive:
			queen += " · reservas %d %%" % int(c.queen_reserves)
		lines.append("Reina %s · día %d de la colonia" % [queen, int(w.bio_day())])
		lines.append("Obreras %d  (%d menores · %d medias · %d mayores)" % [c.total_workers(), c.workers[0], c.workers[1], c.workers[2]])
		lines.append("Cría: %d huevos · %d larvas · %d pupas" % [c.brood_count(0), c.brood_count(1), c.brood_count(2)])
		var fd := c.food_days()
		lines.append("Granero %d semillas · %s" % [int(c.granary), ("reservas para %d días" % int(fd)) if fd < 9999.0 else "sin consumo aún"])
		lines.append("Nido %.1f °C · humedad %d %% · agua %d ml · comedero %d" % [temp, int(w.env.humidity), int(w.env.water_ml), int(w.env.feeder_seeds)])
		var tc := w.ants.task_count
		lines.append("Forrajeo %d · excavación %d · cría %d · molienda %d · limpieza %d · descanso %d" % [
			tc[SimConst.Task.FORAGE], tc[SimConst.Task.DIG], tc[SimConst.Task.NURSE], tc[SimConst.Task.MILL],
			tc[SimConst.Task.CLEAN], tc[SimConst.Task.REST]])
		info_label.text = "\n".join(lines)
	var unread := w.journal.unread
	set_button_text("journal", "Diario" + (" (%d)" % unread if unread > 0 else ""))


func _phase_text() -> String:
	var w := world
	if not w.colony.queen_alive:
		return "sin reina"
	if w.env.is_hibernating(w.cal):
		return "diapausa invernal"
	if w.colony.founding:
		return "fundación claustral" if w.plan.sealed else "la reina excava"
	if w.forage_allowed():
		return "forrajeando"
	return "de noche, dentro del nido" if not w.cal.is_daylight() else "dentro del nido"


static func _scale_name(key: String) -> String:
	match key:
		"realista":
			return "tiempo real"
		"acompanante":
			return "×24"
		"acelerado":
			return "×96"
		"debug":
			return "×1000 (depuración)"
	return key


func show_journal() -> void:
	var lines: Array[String] = []
	for e in world.journal.entries:
		var color := "#e8dcc4"
		match int(e["level"]):
			Journal.Level.WARN:
				color = "#f0c060"
			Journal.Level.CRITICAL:
				color = "#ff8a6a"
			Journal.Level.MILESTONE:
				color = "#b8e08a"
		lines.append("[color=#a89878]%s[/color]\n[color=%s]%s[/color]" % [e["date"], color, e["text"]])
	journal_text.text = "\n\n".join(lines)
	world.journal.unread = 0
	journal_panel.visible = true


func show_welcome(s: Dictionary) -> void:
	var real_h := float(s["real_seconds"]) / 3600.0
	var t := "Has estado fuera [b]%s[/b], que en la colonia han sido [b]%.1f días[/b].\n\n" % [_fmt_hours(real_h), float(s["bio_days"])]
	t += "• Obreras: %d → %d (nacieron %d, murieron %d)\n" % [s["workers_before"], s["workers_after"], s["born"], s["died"]]
	t += "• Cría: %d → %d · huevos puestos: %d\n" % [s["brood_before"], s["brood_after"], s["eggs"]]
	t += "• Semillas recogidas: %d · granero %d → %d\n" % [int(s["seeds_collected"]), int(s["granary_before"]), int(s["granary_after"])]
	t += "• Comedero: %d → %d semillas\n" % [int(s["feeder_before"]), int(s["feeder_after"])]
	if int(s["cells_dug"]) > 0:
		t += "• Han ampliado el nido (%d mm² excavados)\n" % int(s["cells_dug"])
	if bool(s["clamped"]):
		t += "\n[color=#f0c060]Solo se simulan los últimos 30 días de ausencia.[/color]\n"
	var from := int(s["journal_from"])
	if from < world.journal.entries.size():
		t += "\n[b]Novedades:[/b]\n"
		for k in range(from, world.journal.entries.size()):
			t += "– %s\n" % world.journal.entries[k]["text"]
	welcome_text.text = t
	welcome_panel.visible = true


static func _fmt_hours(h: float) -> String:
	if h < 1.0:
		return "%d minutos" % int(h * 60.0)
	if h < 48.0:
		return "%d h %d min" % [int(h), int(fmod(h, 1.0) * 60.0)]
	return "%.1f días" % (h / 24.0)


func _help_text() -> String:
	return """[b]AntWars[/b] es un formicario de Messor barbarus que vive en tu escritorio. Las hormigas deciden solas; tú eres el cuidador.

[b]Lo que puedes hacer[/b]
• [b]Comedero[/b]: las obreras recogen semillas y las guardan en el granero. Rellénalo de vez en cuando.
• [b]Agua[/b]: el tubo mantiene húmedo el sustrato. La cría necesita 50-70 % de humedad; el granero, seco.
• [b]Calor[/b]: la manta térmica acelera el desarrollo de la cría (más allá de 30 °C ya no ayuda).
• [b]Prioridad[/b]: empuja a la colonia a criar, acumular o excavar (umbrales de respuesta).
• [b]Pincel[/b]: pinta un rastro de feromona en la superficie para guiar a las forrajeras.
• [b]Lupa[/b] (L): amplía la zona bajo el ratón y muestra qué hace cada hormiga.

[b]El tiempo[/b]
Las hormigas se mueven a velocidad real para que puedas mirarlas, pero el calendario corre a la escala elegida: tiempo real (×1), acompañante (×24: un día cada hora) o acelerado (×96). Con el juego cerrado la colonia sigue viviendo y al volver te lo resume.

[b]Teclas[/b]
1/2/3 escala de tiempo · F feromonas · L lupa · I info · J diario · H ayuda · F11 ventana/franja · rueda o botón derecho para desplazarte · +/- zoom · 0 zoom automático (se ajusta a la ventana)

[b]Biología real[/b]
Fundación claustral, nanitics, castas por tamaño de colonia, desarrollo según temperatura, diapausa invernal y molienda de semillas siguen datos publicados y de criadores (ver docs/BIOLOGIA.md)."""
