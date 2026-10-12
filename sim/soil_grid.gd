class_name SoilGrid
extends RefCounted
## Rejilla de suelo (1 celda = 1 px lógico). Material por celda, tierra suelta
## con física de arena (solo se actualizan las celdas activas) y registro de
## celdas modificadas para que el render solo repinte lo necesario.

const M := SimConst.Mat

var w: int = SimConst.WORLD_W
var h: int = SimConst.WORLD_H
var mat: PackedByteArray = PackedByteArray()
var surface_h: PackedInt32Array = PackedInt32Array()   ## altura original del terreno por columna
var col_top: PackedInt32Array = PackedInt32Array()     ## primera celda sólida de cada columna (cielo por encima)

var active: PackedInt32Array = PackedInt32Array()      ## celdas sueltas que pueden moverse
var _active_set: Dictionary = {}

var dirty: PackedInt32Array = PackedInt32Array()       ## celdas cambiadas desde el último consumo
var full_dirty: bool = true
var nav_dirty: PackedInt32Array = PackedInt32Array()   ## igual, pero para la rejilla de navegación
var nav_full_dirty: bool = true
var version: int = 0                                    ## sube con cada cambio de forma
const DIRTY_CAP := 6000

var debris: Dictionary = {}     ## celdas sueltas caídas dentro del nido (índice → true)
var removed_total: int = 0      ## celdas excavadas (para tests de conservación)
var dropped_total: int = 0      ## celdas depositadas como tierra suelta
var eroded_total: int = 0
var placed_total: int = 0       ## celdas sólidas creadas desde aire (p. ej. el tapón)


func setup(width: int, height: int) -> void:
	w = width
	h = height
	mat.resize(w * h)
	mat.fill(M.AIR)
	surface_h.resize(w)
	col_top.resize(w)


func idx(x: int, y: int) -> int:
	return y * w + x


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


func get_mat(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return M.ROCK  # el cristal del formicario cuenta como sólido
	return mat[y * w + x]


func is_solid(x: int, y: int) -> bool:
	return get_mat(x, y) != M.AIR


func is_air(x: int, y: int) -> bool:
	return in_bounds(x, y) and mat[y * w + x] == M.AIR


func set_mat(x: int, y: int, m: int) -> void:
	if not in_bounds(x, y):
		return
	var i := y * w + x
	if mat[i] == m:
		return
	mat[i] = m
	_mark_dirty(i)
	if not nav_full_dirty:
		if nav_dirty.size() >= DIRTY_CAP:
			nav_full_dirty = true
			nav_dirty.clear()
		else:
			nav_dirty.append(i)
	# Mantener col_top de forma incremental (evita recorrer la columna entera).
	if m != M.AIR:
		if y < col_top[x]:
			col_top[x] = y
	elif y == col_top[x]:
		var yy := y
		while yy < h and mat[yy * w + x] == M.AIR:
			yy += 1
		col_top[x] = yy
	version += 1


func _mark_dirty(i: int) -> void:
	if full_dirty:
		return
	if dirty.size() >= DIRTY_CAP:
		full_dirty = true
		dirty.clear()
		return
	dirty.append(i)


func consume_dirty() -> PackedInt32Array:
	var d := dirty
	dirty = PackedInt32Array()
	return d


func _update_col_top(x: int) -> void:
	var y := 0
	while y < h and mat[y * w + x] == M.AIR:
		y += 1
	col_top[x] = y


func recompute_col_tops() -> void:
	for x in w:
		_update_col_top(x)


## ¿Está la celda a cielo abierto (por encima de la primera celda sólida de su columna)?
func is_sky(x: int, y: int) -> bool:
	if x < 0 or x >= w:
		return false
	return y < col_top[x]


# ---------------------------------------------------------------------------
# Generación del terreno
# ---------------------------------------------------------------------------

func generate(rng: RandomNumberGenerator, keep_clear_x: int) -> void:
	setup(w, h)
	var ph1 := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	for x in w:
		var s := SimConst.SURFACE_Y + roundi(2.0 * sin(x * 0.02 + ph1) + 1.4 * sin(x * 0.071 + ph2))
		surface_h[x] = s
	var top_noise := rng.randf() * TAU
	for x in w:
		var s := surface_h[x]
		var a_depth := 16 + int(3.0 * sin(x * 0.05 + top_noise))
		var b_depth := 108 + int(6.0 * sin(x * 0.013 + top_noise * 2.0))
		for y in range(s, h):
			var d := y - s
			var m := M.TOPSOIL
			if d >= b_depth:
				m = M.CLAY
			elif d >= a_depth:
				m = M.SOIL
			mat[y * w + x] = m
	# Piedras incrustadas (obstáculos), lejos del punto de fundación.
	var n_rocks := 9 + rng.randi_range(0, 4)
	for _i in n_rocks:
		var cx := rng.randi_range(12, w - 12)
		if absi(cx - keep_clear_x) < 70:
			cx = (cx + 160) % w
		var cy := rng.randi_range(SimConst.SURFACE_Y + 24, h - 8)
		var rx := rng.randi_range(4, 11)
		var ry := rng.randi_range(3, 7)
		for y in range(cy - ry, cy + ry + 1):
			for x in range(cx - rx, cx + rx + 1):
				if not in_bounds(x, y):
					continue
				var nx := float(x - cx) / float(rx)
				var ny := float(y - cy) / float(ry)
				if nx * nx + ny * ny <= 1.0 and mat[y * w + x] != M.AIR:
					mat[y * w + x] = M.ROCK
	recompute_col_tops()
	full_dirty = true
	nav_full_dirty = true
	version += 1


# ---------------------------------------------------------------------------
# Excavación y tierra suelta
# ---------------------------------------------------------------------------

## Dureza relativa (tiempo de arranque) por material. [D]
static func hardness(m: int) -> float:
	match m:
		M.LOOSE, M.MIDDEN, M.PLUG:
			return 0.6
		M.TOPSOIL:
			return 1.0
		M.SOIL:
			return 1.6
		M.CLAY:
			return 2.6
	return INF


static func is_diggable(m: int) -> bool:
	return m != M.AIR and m != M.ROCK


## Arranca un «grano» (pellet): hasta `max_cells` celdas excavables dentro de un
## disco de radio r centrado en (cx, cy). Devuelve el número de celdas arrancadas.
func dig_pellet(cx: int, cy: int, r: float, max_cells: int = 6, only_inside: Callable = Callable()) -> int:
	var removed := 0
	var ri := ceili(r)
	var r2 := r * r
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if removed >= max_cells:
				break
			if float(dx * dx + dy * dy) > r2:
				continue
			var x := cx + dx
			var y := cy + dy
			if not in_bounds(x, y):
				continue
			var m := mat[y * w + x]
			if not is_diggable(m):
				continue
			if only_inside.is_valid() and not only_inside.call(x, y):
				continue
			set_mat(x, y, M.AIR)
			debris.erase(y * w + x)
			removed += 1
			_wake_around(x, y)
	removed_total += removed
	return removed


## Deposita `count` celdas de material suelto cayendo desde la columna x.
func drop_loose(x: int, count: int, material: int = M.LOOSE, rng: RandomNumberGenerator = null) -> int:
	var placed := 0
	for k in count:
		var px := clampi(x + (k % 3) - 1, 1, w - 2)
		if rng != null:
			px = clampi(x + rng.randi_range(-2, 2), 1, w - 2)
		var top := col_top[px]
		var py := top - 1
		if py < 2:
			continue  # columna llena hasta arriba: se pierde (el cuidador limpia)
		set_mat(px, py, material)
		_activate(py * w + px)
		placed += 1
	dropped_total += placed
	return placed


func _activate(i: int) -> void:
	if not _active_set.has(i):
		_active_set[i] = true
		active.append(i)


func _wake_around(x: int, y: int) -> void:
	for dy in range(-2, 1):
		for dx in range(-1, 2):
			var xx := x + dx
			var yy := y + dy
			if in_bounds(xx, yy):
				var m := mat[yy * w + xx]
				if m == M.LOOSE or m == M.MIDDEN:
					_activate(yy * w + xx)


## Un paso de física de arena para las celdas activas. Ángulo de reposo ~45°.
func step_particles(rng: RandomNumberGenerator, max_moves: int = 4000) -> void:
	if active.is_empty():
		return
	var cur := active
	active = PackedInt32Array()
	_active_set.clear()
	# Procesar de abajo arriba para que las pilas caigan de forma estable.
	cur.sort()
	cur.reverse()
	var moves := 0
	for i in cur:
		var m := mat[i]
		if m != M.LOOSE and m != M.MIDDEN:
			continue
		if moves >= max_moves:
			_activate(i)
			continue
		var x := i % w
		var y := i / w
		var nx := x
		var ny := y
		if is_air(x, y + 1):
			ny = y + 1
		else:
			var first := -1 if rng.randf() < 0.5 else 1
			if is_air(x + first, y + 1) and is_air(x + first, y):
				nx = x + first
				ny = y + 1
			elif is_air(x - first, y + 1) and is_air(x - first, y):
				nx = x - first
				ny = y + 1
		if nx != x or ny != y:
			set_mat(x, y, M.AIR)
			set_mat(nx, ny, m)
			_activate(ny * w + nx)
			_wake_around(x, y)
			moves += 1
			# Tierra que se ha colado dentro del nido: escombro que hay que retirar.
			if ny >= surface_h[nx] + 1:
				debris[ny * w + nx] = true


## Erosión lenta del montículo (viento, el cuidador lo retira…): quita hasta
## `n` celdas sueltas de las cimas de las columnas cercanas a `around_x`.
func erode_loose(rng: RandomNumberGenerator, n: int, around_x: int, spread: int) -> int:
	var done := 0
	var tries := n * 6
	while done < n and tries > 0:
		tries -= 1
		var x := clampi(around_x + rng.randi_range(-spread, spread), 0, w - 1)
		var y := col_top[x]
		if y >= h:
			continue
		var m := mat[y * w + x]
		if (m == M.LOOSE or m == M.MIDDEN) and y < surface_h[x]:
			set_mat(x, y, M.AIR)
			_wake_around(x, y)
			done += 1
	eroded_total += done
	return done


func count_material(m: int) -> int:
	return mat.count(m)


func to_dict() -> Dictionary:
	return {
		"w": w, "h": h, "mat": mat, "surface_h": surface_h,
		"removed_total": removed_total, "dropped_total": dropped_total, "eroded_total": eroded_total,
		"placed_total": placed_total, "debris": PackedInt32Array(debris.keys()),
	}


func from_dict(d: Dictionary) -> void:
	setup(int(d["w"]), int(d["h"]))
	mat = d["mat"]
	surface_h = d["surface_h"]
	removed_total = int(d.get("removed_total", 0))
	dropped_total = int(d.get("dropped_total", 0))
	eroded_total = int(d.get("eroded_total", 0))
	placed_total = int(d.get("placed_total", 0))
	debris.clear()
	for i: int in d.get("debris", PackedInt32Array()):
		debris[i] = true
	recompute_col_tops()
	active = PackedInt32Array()
	_active_set.clear()
	full_dirty = true
	nav_full_dirty = true
	version += 1
