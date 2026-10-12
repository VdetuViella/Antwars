class_name NavGrid
extends RefCounted
## Rejilla de navegación gruesa (celdas de 2×2 px) y campos de distancia BFS.
## Las hormigas «conocen» el nido: siguen gradientes de distancia hacia la
## entrada, la cámara de cría, el granero o el frente de excavación (memoria
## espacial + olor del nido). En la superficie caminan pegadas al suelo.

const C := SimConst.NAV_CELL
const INF_DIST := 1 << 29

var soil: SoilGrid
var nw: int = 0
var nh: int = 0
var walk: PackedByteArray = PackedByteArray()      ## 1 = transitable
var fields: Array[PackedInt32Array] = []
var field_sources: Array[PackedInt32Array] = []
var field_dirty: PackedByteArray = PackedByteArray()
var walk_version: int = 0

# Vecinos (8-conexión): dx, dy
const NB_DX := [1, -1, 0, 0, 1, 1, -1, -1]
const NB_DY := [0, 0, 1, -1, 1, -1, 1, -1]


func setup(s: SoilGrid) -> void:
	soil = s
	nw = s.w / C
	nh = s.h / C
	walk.resize(nw * nh)
	walk.fill(0)
	fields.clear()
	field_sources.clear()
	for _i in SimConst.N_FIELDS:
		var f := PackedInt32Array()
		f.resize(nw * nh)
		f.fill(INF_DIST)
		fields.append(f)
		field_sources.append(PackedInt32Array())
	field_dirty.resize(SimConst.N_FIELDS)
	field_dirty.fill(1)
	rebuild_all()


func node_of(px: float, py: float) -> int:
	var nx := clampi(int(px) / C, 0, nw - 1)
	var ny := clampi(int(py) / C, 0, nh - 1)
	return ny * nw + nx


func node_center(n: int) -> Vector2:
	return Vector2(float((n % nw) * C) + 1.0, float((n / nw) * C) + 1.0)


func node_x(n: int) -> int:
	return n % nw


func node_y(n: int) -> int:
	return n / nw


## ¿Está el nodo en el outworld (por encima del nivel original del suelo)?
func is_outworld(n: int) -> bool:
	var px := (n % nw) * C
	var py := (n / nw) * C + 1
	return py < soil.surface_h[px]


func _air_count(nx: int, ny: int) -> int:
	var x0 := nx * C
	var y0 := ny * C
	var c := 0
	for dy in C:
		for dx in C:
			if soil.is_air(x0 + dx, y0 + dy):
				c += 1
	return c


func _node_solidish(nx: int, ny: int) -> bool:
	if nx < 0 or ny < 0 or nx >= nw or ny >= nh:
		return true
	return _air_count(nx, ny) < 3


func _compute_walk(nx: int, ny: int) -> int:
	if _air_count(nx, ny) < 3:
		return 0
	var n := ny * nw + nx
	if not is_outworld(n):
		return 1  # dentro del nido: caminan por el cristal, todo hueco es transitable
	# En el outworld solo se camina pegado al suelo (o a la pila de tierra).
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			if dy >= 0 and _node_solidish(nx + dx, ny + dy):
				return 1
	return 0


func rebuild_all() -> void:
	for ny in nh:
		for nx in nw:
			walk[ny * nw + nx] = _compute_walk(nx, ny)
	walk_version += 1
	field_dirty.fill(1)
	soil.nav_full_dirty = false
	soil.nav_dirty.clear()


## Actualiza la transitabilidad a partir de las celdas de suelo cambiadas.
## Devuelve true si algo cambió.
func update_from_soil() -> bool:
	if soil.nav_full_dirty:
		rebuild_all()
		return true
	if soil.nav_dirty.is_empty():
		return false
	var touched := {}
	for i in soil.nav_dirty:
		var nx := (i % soil.w) / C
		var ny := (i / soil.w) / C
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var xx := nx + dx
				var yy := ny + dy
				if xx >= 0 and yy >= 0 and xx < nw and yy < nh:
					touched[yy * nw + xx] = true
	soil.nav_dirty.clear()
	var changed := false
	for n: int in touched:
		var v := _compute_walk(n % nw, n / nw)
		if walk[n] != v:
			walk[n] = v
			changed = true
	if changed:
		walk_version += 1
		field_dirty.fill(1)
	return changed


func is_walkable(n: int) -> bool:
	return n >= 0 and n < walk.size() and walk[n] == 1


## Nodo transitable más cercano a (px, py) dentro de un radio (en nodos).
func nearest_walkable(px: float, py: float, radius: int = 8) -> int:
	var cx := clampi(int(px) / C, 0, nw - 1)
	var cy := clampi(int(py) / C, 0, nh - 1)
	if walk[cy * nw + cx] == 1:
		return cy * nw + cx
	for r in range(1, radius + 1):
		var best := -1
		var best_d := 1 << 30
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var xx := cx + dx
				var yy := cy + dy
				if xx < 0 or yy < 0 or xx >= nw or yy >= nh:
					continue
				var n := yy * nw + xx
				if walk[n] == 1:
					var d := dx * dx + dy * dy
					if d < best_d:
						best_d = d
						best = n
		if best >= 0:
			return best
	return -1


func set_sources(field: int, sources: PackedInt32Array) -> void:
	if sources == field_sources[field]:
		return
	field_sources[field] = sources
	field_dirty[field] = 1


## Recalcula los campos marcados como sucios (BFS multi-fuente).
func refresh_fields() -> void:
	for f in SimConst.N_FIELDS:
		if field_dirty[f] == 1:
			_bfs(f)
			field_dirty[f] = 0


func _bfs(f: int) -> void:
	var dist := fields[f]
	dist.fill(INF_DIST)
	var queue := PackedInt32Array()
	queue.resize(nw * nh)
	var head := 0
	var tail := 0
	for s in field_sources[f]:
		if s >= 0 and s < walk.size() and walk[s] == 1 and dist[s] != 0:
			dist[s] = 0
			queue[tail] = s
			tail += 1
	while head < tail:
		var n := queue[head]
		head += 1
		var nx := n % nw
		var ny := n / nw
		var nd := dist[n] + 1
		for k in 8:
			var xx: int = nx + NB_DX[k]
			var yy: int = ny + NB_DY[k]
			if xx < 0 or yy < 0 or xx >= nw or yy >= nh:
				continue
			var m := yy * nw + xx
			if walk[m] != 1 or dist[m] <= nd:
				continue
			if k >= 4:  # diagonal: no cortar esquinas
				if walk[ny * nw + xx] != 1 or walk[yy * nw + nx] != 1:
					continue
			dist[m] = nd
			queue[tail] = m
			tail += 1
	fields[f] = dist


func dist_at(field: int, n: int) -> int:
	if n < 0 or n >= walk.size():
		return INF_DIST
	return fields[field][n]


## Siguiente nodo bajando por el gradiente del campo (hacia la fuente).
## Con `noise` > 0 a veces elige un vecino igual de bueno al azar.
func step_down(field: int, n: int, rng: RandomNumberGenerator) -> int:
	var dist := fields[field]
	var nx := n % nw
	var ny := n / nw
	var best := -1
	var best_d := dist[n] if n >= 0 else INF_DIST
	var ties := 0
	for k in 8:
		var xx: int = nx + NB_DX[k]
		var yy: int = ny + NB_DY[k]
		if xx < 0 or yy < 0 or xx >= nw or yy >= nh:
			continue
		var m := yy * nw + xx
		if walk[m] != 1:
			continue
		if k >= 4 and (walk[ny * nw + xx] != 1 or walk[yy * nw + nx] != 1):
			continue
		var d := dist[m]
		if d < best_d:
			best_d = d
			best = m
			ties = 1
		elif d == best_d and best >= 0:
			ties += 1
			if rng.randi_range(1, ties) == 1:
				best = m
	return best


## Vecino transitable aleatorio, con preferencia por mantener la dirección (dx, dy).
func step_wander(n: int, pref_dx: int, pref_dy: int, rng: RandomNumberGenerator, persistence: float = 0.7) -> int:
	var nx := n % nw
	var ny := n / nw
	if pref_dx != 0 or pref_dy != 0:
		if rng.randf() < persistence:
			var xx := nx + pref_dx
			var yy := ny + pref_dy
			if xx >= 0 and yy >= 0 and xx < nw and yy < nh and walk[yy * nw + xx] == 1:
				return yy * nw + xx
	var start := rng.randi_range(0, 7)
	for j in 8:
		var k := (start + j) % 8
		var xx: int = nx + NB_DX[k]
		var yy: int = ny + NB_DY[k]
		if xx >= 0 and yy >= 0 and xx < nw and yy < nh and walk[yy * nw + xx] == 1:
			return yy * nw + xx
	return n


## Paso por la superficie en la dirección horizontal dir (−1 o 1), siguiendo el
## relieve (sube y baja por la pila de tierra). Devuelve -1 si no puede avanzar.
func step_surface(n: int, dir: int) -> int:
	var nx := n % nw
	var ny := n / nw
	var xx := nx + dir
	if xx < 0 or xx >= nw:
		return -1
	# Preferir quedarse a la misma altura; si no, bajar (pegarse al suelo) o subir.
	for dy in [1, 0, -1, 2, -2]:
		var yy: int = ny + dy
		if yy < 0 or yy >= nh:
			continue
		var m := yy * nw + xx
		if walk[m] == 1 and is_outworld(m):
			# bajar solo si debajo hay suelo (evita meterse en la boca del nido)
			return m
	return -1
