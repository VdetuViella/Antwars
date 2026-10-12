class_name DecorLayer
extends Node2D
## Elementos del formicario que no son suelo ni hormigas: fondo de la
## habitación (solo en modo ventana), hierba, comedero, tubo de agua, semillas,
## cría, granero y el marco de cristal. Se redibuja ~8 veces por segundo.

const ITEM := 8
enum Layer { ROOM, BACK, FRONT }

var world: SimWorld
var layer: int = Layer.BACK
var draw_room: bool = true
var items_tex: Texture2D
var _t := 0.0
var _anim := 0.0


func setup(w: SimWorld, which: int) -> void:
	world = w
	layer = which
	items_tex = load("res://assets/sprites/items.png")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(delta: float) -> void:
	_anim += delta
	_t -= delta
	if _t <= 0.0:
		_t = 0.12
		queue_redraw()


static func room_color(light: float) -> Color:
	return Color8(38, 42, 56).lerp(Color8(222, 214, 196), light)


func _item(idx: int, pos: Vector2) -> void:
	draw_texture_rect_region(items_tex, Rect2(floorf(pos.x) - 4.0, floorf(pos.y) - 4.0, ITEM, ITEM),
		Rect2(idx * ITEM, 0, ITEM, ITEM))


func _draw() -> void:
	if world == null:
		return
	match layer:
		Layer.ROOM:
			_draw_room()
		Layer.BACK:
			_draw_back()
		_:
			_draw_front()


## Pared de la habitación detrás del formicario (solo modo ventana): clara de
## día, azulada de noche. Va en su propia capa, DETRÁS del suelo, para no tapar
## el montículo de tierra que sobresale por encima de la superficie. Es un color
## plano igual al del fondo de la ventana, así no se nota el borde del mundo al
## agrandar la ventana. Debajo del cristal, la balda de madera donde se apoya.
func _draw_room() -> void:
	if not draw_room:
		return
	var soil := world.soil
	var light := world.cal.light_level()
	var wall := room_color(light)
	draw_rect(Rect2(-2000, -2000, soil.w + 4000, 2000 + SimConst.SURFACE_Y + 4), wall)
	# Balda: tablero con canto claro arriba y sombra debajo; escuadras a los lados.
	var wood := Color8(124, 86, 54).lerp(Color8(52, 44, 52), 1.0 - light)
	var top := float(soil.h)
	draw_rect(Rect2(-24, top, soil.w + 48, 7), wood)
	draw_rect(Rect2(-24, top, soil.w + 48, 1), wood.lightened(0.25))
	draw_rect(Rect2(-24, top + 6, soil.w + 48, 1), wood.darkened(0.35))
	draw_rect(Rect2(-24, top + 7, soil.w + 48, 3), Color(0, 0, 0, 0.18))
	for bx in [30.0, float(soil.w) - 36.0]:
		draw_rect(Rect2(bx, top + 7, 6, 14), wood.darkened(0.15))
		draw_rect(Rect2(bx, top + 7, 1, 14), wood.lightened(0.1))


func _draw_back() -> void:
	var soil := world.soil
	# Mechones de hierba (detrás de las hormigas).
	var month := world.cal.month()
	var dry := 1.0 if month in [7, 8] else (0.5 if month in [6, 9] else 0.0)
	for tx in world.env.tuft_xs:
		var base_y := float(soil.col_top[clampi(tx, 0, soil.w - 1)])
		for b in 9:
			var bx := float(tx) + (b - 4) * 1.6
			var hgt := 10.0 + float((tx * 7 + b * 13) % 9)
			var sway := sin(_anim * 1.3 + b * 0.7 + tx) * 1.4
			var green := Color8(86, 128, 58).lerp(Color8(170, 150, 80), dry)
			if b % 3 == 0:
				green = green.darkened(0.15)
			var tip := Vector2(bx + sway, base_y - hgt)
			draw_line(Vector2(bx, base_y), Vector2(bx + sway * 0.5, base_y - hgt * 0.5), green, 1.0)
			draw_line(Vector2(bx + sway * 0.5, base_y - hgt * 0.5), tip, green.lightened(0.1), 1.0)
			if b % 2 == 1 and month in [5, 6, 7, 9, 10]:
				draw_rect(Rect2(floorf(tip.x), floorf(tip.y) - 1, 1, 2), Color8(196, 170, 96))
	# Comedero: platito de plástico sobre el suelo.
	var fx := float(world.env.feeder_x)
	var fy := float(soil.surface_h[world.env.feeder_x]) - 1.0
	draw_rect(Rect2(fx - 9, fy - 1, 19, 2), Color8(214, 220, 224))
	draw_rect(Rect2(fx - 10, fy - 3, 1, 3), Color8(190, 198, 204))
	draw_rect(Rect2(fx + 10, fy - 3, 1, 3), Color8(190, 198, 204))
	# Tubo de agua con algodón (bebedero típico de formicario).
	var ty := float(soil.surface_h[30]) - 6.0
	var water_frac := clampf(world.env.water_ml / FormicariumEnv.WATER_MAX_ML, 0.0, 1.0)
	draw_rect(Rect2(6, ty, 48, 5), Color(0.85, 0.92, 0.95, 0.35))
	draw_rect(Rect2(6, ty, 48, 1), Color(1, 1, 1, 0.5))
	draw_rect(Rect2(6, ty + 4, 48, 1), Color(0.6, 0.7, 0.75, 0.6))
	if water_frac > 0.0:
		var wl := 40.0 * water_frac
		draw_rect(Rect2(8, ty + 1, wl, 3), Color8(110, 170, 220, 210))
	draw_rect(Rect2(48, ty + 1, 6, 3), Color8(244, 244, 240))
	draw_rect(Rect2(5, ty, 2, 5), Color8(170, 60, 50))
	# Semillas en la superficie.
	for i in world.seed_alive.size():
		if world.seed_alive[i] == 1:
			_item(0 if world.seed_src[i] == 0 else 9, Vector2(world.seed_x[i], world.seed_y[i]))
	# Granero y cría (dentro de las cámaras).
	_draw_granary()
	_draw_brood()


func _chamber_floor_slots(ci: int, count: int, from_right: bool, spacing_wide: bool = false) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if ci < 0 or count <= 0:
		return out
	var c: Dictionary = world.plan.chambers[ci]
	var cx := int(c["cx"])
	var cy := int(c["cy"])
	var rx := int(c["rx"])
	var ry := int(c["ry"])
	var soil := world.soil
	var row := 0
	var step := 3 if spacing_wide else 2
	while out.size() < count and row < ry * 2:
		var y := cy + ry - 1 - row * step
		var xs: Array[int] = []
		for x in range(cx - rx + 1, cx + rx, step):
			xs.append(x)
		if from_right:
			xs.reverse()
		for x in xs:
			if out.size() >= count:
				break
			# Apoyado en el suelo de la cámara (aire aquí, sólido o pila debajo).
			if soil.is_air(x, y) and soil.is_air(x, y - 1) and NestPlan.in_ellipse(x, y, c):
				out.append(Vector2(x, y - 1))
		row += 1
	return out


func _draw_granary() -> void:
	var g := world.colony.granary
	if g < 0.5:
		return
	var cams := world.chambers_of("granary")
	if cams.is_empty():
		cams = world.chambers_of("brood")
	if cams.is_empty():
		return
	var total := clampi(ceili(sqrt(g) * 1.6), 1, 260)
	var husk_total := 0
	if world.colony.husks >= 1.0:
		husk_total = clampi(ceili(sqrt(world.colony.husks / maxf(world.work_value(), 1.0)) * 2.0), 1, 30)
	# Repartir la pila entre graneros, llenando primero los más altos (más secos).
	cams.reverse()
	var left := total
	for ci in cams:
		var c: Dictionary = world.plan.chambers[ci]
		var cap := int(float(c["rx"]) * float(c["ry"]) * 0.9)
		var n := mini(left, cap)
		var slots := _chamber_floor_slots(ci, n + husk_total, true)
		for k in slots.size():
			_item(10 if k < n else 3, slots[k])
		husk_total = 0
		left -= n
		if left <= 0:
			break


func _draw_brood() -> void:
	var cams := world.chambers_of("brood")
	if cams.is_empty():
		return
	var col := world.colony
	# Con mucha cría se dibuja un sprite por cada varios individuos (pila más legible).
	var total := col.brood_total()
	var k_div := 1 if total <= 60 else (2 if total <= 200 else 3)
	var eggs := mini(col.brood_count(Colony.Stage.EGG) / k_div, 90)
	var larvae := mini(col.brood_count(Colony.Stage.LARVA) / k_div, 90)
	var pupae := mini(col.brood_count(Colony.Stage.PUPA) / k_div, 90)
	# Huevos con la reina (cámara más profunda); larvas y pupas repartidas.
	var per := maxi(1, cams.size())
	for idx in cams.size():
		var ci: int = cams[idx]
		var e := (eggs + 2) / 3 if idx == 0 else 0
		var l := larvae / per + (larvae % per if idx == 0 else 0)
		var p := pupae / per + (pupae % per if idx == 0 else 0)
		var slots := _chamber_floor_slots(ci, p + l + e, false, true)
		var k := 0
		for _p in p:
			if k < slots.size():
				_item(8, slots[k])
			k += 1
		for j in l:
			if k < slots.size():
				_item(7 if j % 3 != 0 else 6, slots[k])
			k += 1
		for _e in e:
			if k < slots.size():
				_item(5, slots[k])
			k += 1


func _draw_front() -> void:
	var soil := world.soil
	# Marco de cristal del formicario.
	var glass := Color(0.78, 0.86, 0.9, 0.55)
	draw_rect(Rect2(0, 0, 1, soil.h), glass)
	draw_rect(Rect2(soil.w - 1, 0, 1, soil.h), glass)
	draw_rect(Rect2(0, soil.h - 1, soil.w, 1), glass)
	draw_rect(Rect2(0, 0, soil.w, 1), Color(0.78, 0.86, 0.9, 0.35))
	# Reflejos diagonales muy tenues sobre el cristal.
	for k in 3:
		var x0 := 80.0 + k * 210.0
		draw_line(Vector2(x0, soil.h), Vector2(x0 + 70.0, SimConst.SURFACE_Y - 20), Color(1, 1, 1, 0.022), 6.0)
