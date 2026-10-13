class_name AntViewState
extends RefCounted
## Estado de DIBUJO de cada hormiga para el detalle por niveles (ADR-005).
##
## Solo LEE la simulación (posiciones, casta, nodo, superficie); nunca escribe en
## ella ni usa sus generadores aleatorios (reglas duras 1 y 2). Todo lo aleatorio
## de aquí sale de un hash del índice de la hormiga.
##
##  · Dirección: velocidad interpolada suavizada (media exponencial) y cuantizada a
##    16 direcciones con histéresis: no parpadea ni salta en los escalones.
##  · Fotograma: la fase avanza con la distancia recorrida / zancada; quieta → 0.
##  · Vista (decisión del propietario): en la superficie camina por el suelo
##    (perfil). Dentro del nido, si tiene suelo bajo los pies y va en horizontal,
##    ELIGE ir por el suelo (perfil) o por el cristal (cenital); la elección se
##    renueva en cada tramo (al parar o dar la vuelta). Sin suelo debajo, cristal.
##    El cambio de vista tiene histéresis.

const DIRS := 16
const FRAMES := 8
const DIR_HYST_DEG := 4.0
const SMOOTH_S := 0.15
const VIEW_SWITCH_S := 0.3
const GLASS_CHOICE := 0.4            ## [D] probabilidad de elegir el cristal pudiendo ir por el suelo
const MOVE_EPS := 0.0005
const VIEW_TOP := 0
const VIEW_SIDE := 1

var cap := 0
var heading := PackedVector2Array()
var dir := PackedByteArray()
var phase := PackedFloat32Array()
var frame := PackedByteArray()
var view := PackedByteArray()
var view_t := PackedFloat32Array()
var leg := PackedInt32Array()
var glass := PackedByteArray()       ## elección del tramo actual: 1 = cristal
var moving := PackedByteArray()
var last_pos := PackedVector2Array()
var draw_pos := PackedVector2Array() ## posición final (mundo), apoyada en el suelo si va de perfil
var was_alive := PackedByteArray()

## Por fila del atlas (menor, media, mayor, reina, nanitic): mm del tórax al suelo y zancada.
var feet_mm := PackedFloat32Array([2.0, 2.3, 2.7, 3.4, 1.7])
var stride_mm := PackedFloat32Array([2.8, 3.2, 3.8, 4.7, 2.4])


func setup(capacity: int) -> void:
	cap = capacity
	heading.resize(cap); heading.fill(Vector2.ZERO)
	dir.resize(cap); dir.fill(0)
	phase.resize(cap); phase.fill(0.0)
	frame.resize(cap); frame.fill(0)
	view.resize(cap); view.fill(VIEW_TOP)
	view_t.resize(cap); view_t.fill(0.0)
	leg.resize(cap); leg.fill(0)
	glass.resize(cap); glass.fill(0)
	moving.resize(cap); moving.fill(0)
	last_pos.resize(cap); last_pos.fill(Vector2.ZERO)
	draw_pos.resize(cap); draw_pos.fill(Vector2.ZERO)
	was_alive.resize(cap); was_alive.fill(0)


static func hash_u(a: int, b: int) -> int:
	var h := (a * 73856093) ^ (b * 19349663) ^ 0x5bd1e995
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7FFFFFFF


static func row_of(caste: int, nanitic: int) -> int:
	if caste == SimConst.Caste.MINOR and nanitic == 1:
		return 4
	return caste


## Dirección de la simulación (dir8, antihorario desde el este) → 16, horario en pantalla.
static func dir16_from_dir8(d8: int) -> int:
	return posmod(-d8 * 2, DIRS)


func _choose_glass(i: int) -> int:
	return 1 if float(hash_u(i, leg[i]) % 1000) < GLASS_CHOICE * 1000.0 else 0


## Actualiza el estado de dibujo. `alpha` = fracción del paso de comportamiento
## (interpolación); `dt` = tiempo real del fotograma (0 en las capturas congeladas).
func update(world: SimWorld, alpha: float, dt: float) -> void:
	var a := world.ants
	if a.cap != cap:
		setup(a.cap)
	var soil := world.soil
	var nav := world.nav
	var k_smooth := 1.0 - exp(-dt / SMOOTH_S) if dt > 0.0 else 0.0
	for i in cap:
		if a.alive[i] == 0:
			was_alive[i] = 0
			continue
		var pos := Vector2(lerpf(a.prev_px[i], a.px[i], alpha), lerpf(a.prev_py[i], a.py[i], alpha))
		var row := row_of(a.caste[i], a.nanitic[i])
		if was_alive[i] == 0:
			# Hormiga nueva (o ranura reutilizada): estado inicial determinista.
			was_alive[i] = 1
			last_pos[i] = pos
			heading[i] = Vector2.ZERO
			dir[i] = dir16_from_dir8(a.dir8[i])
			phase[i] = float(hash_u(i, 7) % 1000) / 1000.0
			leg[i] = 0
			glass[i] = _choose_glass(i)
			view[i] = VIEW_SIDE if nav.is_outworld(a.node[i]) else VIEW_TOP
			view_t[i] = 0.0
			moving[i] = 0
		var vel := pos - last_pos[i]
		last_pos[i] = pos
		var dist := vel.length()
		var is_moving := dist > MOVE_EPS
		# Nuevo tramo al arrancar o al dar la vuelta: renueva la elección suelo/cristal.
		if is_moving and dt > 0.0:
			var v := vel / dt
			var old := heading[i]
			if moving[i] == 0 or (old != Vector2.ZERO and old.dot(v) < 0.0):
				leg[i] += 1
				glass[i] = _choose_glass(i)
			heading[i] = v if old == Vector2.ZERO else old.lerp(v, k_smooth)
			var h := heading[i]
			var ang := rad_to_deg(atan2(h.y, h.x))
			var cur := float(dir[i]) * 22.5
			var diff := absf(fposmod(ang - cur + 180.0, 360.0) - 180.0)
			if diff > 11.25 + DIR_HYST_DEG:
				dir[i] = posmod(roundi(ang / 22.5), DIRS)
			phase[i] = fposmod(phase[i] + dist / maxf(stride_mm[row], 0.1), 1.0)
			frame[i] = int(phase[i] * FRAMES) % FRAMES
		elif not is_moving:
			frame[i] = 0
		moving[i] = 1 if is_moving else 0
		# Vista.
		var outworld := nav.is_outworld(a.node[i])
		var feet := feet_mm[row]
		var floor_y := -1.0
		var want := VIEW_TOP
		if outworld:
			want = VIEW_SIDE
		else:
			floor_y = _floor_below(soil, pos, feet)
			var h2 := heading[i]
			var horizontal := h2 == Vector2.ZERO or absf(h2.y) <= absf(h2.x) * 0.7
			if floor_y >= 0.0 and horizontal and glass[i] == 0:
				want = VIEW_SIDE
		if want != view[i]:
			view_t[i] += dt
			if view_t[i] >= VIEW_SWITCH_S:
				view[i] = want
				view_t[i] = 0.0
		else:
			view_t[i] = 0.0
		# Posición de dibujo: de perfil, los pies apoyados en el suelo.
		var dp := pos
		if view[i] == VIEW_SIDE:
			if outworld:
				var cx := clampi(int(pos.x), 0, soil.w - 1)
				dp.y = float(soil.col_top[cx]) - feet
			elif floor_y >= 0.0:
				dp.y = floor_y - feet
		draw_pos[i] = dp


## Primera celda sólida bajo los pies (hasta 3 mm). -1 si no hay suelo cerca.
static func _floor_below(soil: SoilGrid, pos: Vector2, feet: float) -> float:
	var x := int(pos.x)
	var y0 := int(pos.y + feet) - 1
	for dy in 5:
		if soil.is_solid(x, y0 + dy):
			return float(y0 + dy)
	return -1.0
