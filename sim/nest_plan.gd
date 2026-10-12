class_name NestPlan
extends RefCounted
## Plan de excavación del nido: cámaras (elipses) y galerías (cápsulas).
## Las hormigas no siguen un plano dibujado: el plan solo dice DÓNDE hay
## estímulo de excavación (frentes activos). El orden y la forma final emergen
## de qué frentes alcanzan primero las excavadoras (ver docs/SIMULACION.md §3.7).

const M := SimConst.Mat

var entrance_x: int = 320
var entrance_y: int = 60            ## primera fila de suelo en la boca del nido
var sealed: bool = false
var plug_cells: PackedInt32Array = PackedInt32Array()

## Cámaras: {cx, cy, rx, ry, max_rx, max_ry, purpose, done}
var chambers: Array[Dictionary] = []
## Galerías: {ax, ay, bx, by, r, done, chamber (índice de la cámara al final o -1)}
var tunnels: Array[Dictionary] = []

var founding_done: bool = false
var _stuck_time: Dictionary = {}     ## zona → segundos sin frentes (para abandonar)


func setup_founding(soil: SoilGrid, ex: int, rng: RandomNumberGenerator) -> void:
	entrance_x = ex
	entrance_y = soil.surface_h[ex]
	chambers.clear()
	tunnels.clear()
	var depth := rng.randi_range(26, 32)
	var dx := rng.randi_range(-6, 6)
	var bx := ex + dx
	var by := entrance_y + depth
	tunnels.append({"ax": ex, "ay": entrance_y - 1, "bx": bx, "by": by, "r": 2.1, "done": false, "chamber": 0})
	chambers.append({"cx": bx, "cy": by + 2, "rx": 6, "ry": 3, "max_rx": 13, "max_ry": 5,
		"purpose": "brood", "done": false})
	founding_done = false
	sealed = false


# ---------------------------------------------------------------------------
# Geometría de zonas
# ---------------------------------------------------------------------------

static func in_ellipse(x: int, y: int, c: Dictionary) -> bool:
	var nx := float(x - int(c["cx"])) / maxf(float(c["rx"]), 0.5)
	var ny := float(y - int(c["cy"])) / maxf(float(c["ry"]), 0.5)
	return nx * nx + ny * ny <= 1.0


static func in_capsule(x: int, y: int, t: Dictionary) -> bool:
	var a := Vector2(float(t["ax"]), float(t["ay"]))
	var b := Vector2(float(t["bx"]), float(t["by"]))
	var p := Vector2(float(x), float(y))
	var ab := b - a
	var tt := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(a + ab * tt) <= float(t["r"])


func in_any_active_zone(x: int, y: int) -> bool:
	for t in tunnels:
		if not t["done"] and in_capsule(x, y, t):
			return true
	for ci in chambers.size():
		var c := chambers[ci]
		if not c["done"] and _chamber_active(ci) and in_ellipse(x, y, c):
			return true
	if _plug_active() and plug_cells.has(y * SimConst.WORLD_W + x):
		return true
	if debris_ref != null and debris_ref.has(y * SimConst.WORLD_W + x):
		return true
	return false


var debris_ref: Dictionary = {}   ## referencia a SoilGrid.debris


var plug_open_requested: bool = false

func _plug_active() -> bool:
	return sealed and plug_open_requested


func _chamber_active(ci: int) -> bool:
	# Una cámara solo se excava cuando su galería de acceso ya está hecha.
	for t in tunnels:
		if int(t.get("chamber", -1)) == ci and not t["done"]:
			return false
	return true


## Celdas excavables pendientes dentro de las zonas activas (para los frentes).
func pending_cells(soil: SoilGrid) -> PackedInt32Array:
	var out := PackedInt32Array()
	for t in tunnels:
		if t["done"]:
			continue
		var x0 := mini(int(t["ax"]), int(t["bx"])) - 3
		var x1 := maxi(int(t["ax"]), int(t["bx"])) + 3
		var y0 := mini(int(t["ay"]), int(t["by"])) - 3
		var y1 := maxi(int(t["ay"]), int(t["by"])) + 3
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				if soil.in_bounds(x, y) and SoilGrid.is_diggable(soil.mat[y * soil.w + x]) and in_capsule(x, y, t):
					out.append(y * soil.w + x)
	for ci in chambers.size():
		var c := chambers[ci]
		if c["done"] or not _chamber_active(ci):
			continue
		for y in range(int(c["cy"]) - int(c["ry"]), int(c["cy"]) + int(c["ry"]) + 1):
			for x in range(int(c["cx"]) - int(c["rx"]), int(c["cx"]) + int(c["rx"]) + 1):
				if soil.in_bounds(x, y) and SoilGrid.is_diggable(soil.mat[y * soil.w + x]) and in_ellipse(x, y, c):
					out.append(y * soil.w + x)
	if _plug_active():
		for i in plug_cells:
			if soil.mat[i] != M.AIR:
				out.append(i)
	# Escombros dentro del nido (tierra suelta que se ha colado).
	var gone: Array = []
	for i: int in soil.debris:
		var m := soil.mat[i]
		if m == M.LOOSE or m == M.MIDDEN:
			out.append(i)
		else:
			gone.append(i)
	for i in gone:
		soil.debris.erase(i)
	return out


## Marca como hechas las zonas sin celdas pendientes y hace crecer cámaras.
## `need` = {brood: área necesaria, granary: área necesaria}. Devuelve eventos.
func update(soil: SoilGrid, need: Dictionary, rng: RandomNumberGenerator, dt: float) -> Array[String]:
	var events: Array[String] = []
	for ti in tunnels.size():
		var t := tunnels[ti]
		if t["done"]:
			continue
		if not _zone_has_pending(soil, "t", ti):
			t["done"] = true
	for ci in chambers.size():
		var c := chambers[ci]
		if c["done"] or not _chamber_active(ci):
			continue
		if not _zone_has_pending(soil, "c", ci):
			var purpose: String = c["purpose"]
			var wants_more := area_for(purpose) < float(need.get(purpose, 0.0))
			if not founding_done and ci == 0:
				wants_more = int(c["rx"]) < 7
			if wants_more and (int(c["rx"]) < int(c["max_rx"]) or int(c["ry"]) < int(c["max_ry"])):
				c["rx"] = mini(int(c["rx"]) + 2, int(c["max_rx"]))
				c["ry"] = mini(int(c["ry"]) + 1, int(c["max_ry"]))
			else:
				c["done"] = true
				events.append("chamber_done:%d" % ci)
	if not founding_done and tunnels[0]["done"] and chambers[0]["done"]:
		founding_done = true
		events.append("founding_dug")
	# El tapón se da por abierto cuando ya no queda tierra en él.
	if _plug_active():
		var left := 0
		for i in plug_cells:
			if soil.mat[i] != M.AIR:
				left += 1
		if left == 0:
			sealed = false
			plug_open_requested = false
			plug_cells.clear()
			events.append("plug_open")
	if founding_done and not sealed:
		_maybe_plan_new(soil, need, rng, events)
	return events


func _zone_has_pending(soil: SoilGrid, kind: String, i: int) -> bool:
	if kind == "t":
		var t := tunnels[i]
		var x0 := mini(int(t["ax"]), int(t["bx"])) - 3
		var x1 := maxi(int(t["ax"]), int(t["bx"])) + 3
		var y0 := mini(int(t["ay"]), int(t["by"])) - 3
		var y1 := maxi(int(t["ay"]), int(t["by"])) + 3
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				if soil.in_bounds(x, y) and in_capsule(x, y, t):
					var m := soil.mat[y * soil.w + x]
					if SoilGrid.is_diggable(m):
						return true
		return false
	var c := chambers[i]
	for y in range(int(c["cy"]) - int(c["ry"]), int(c["cy"]) + int(c["ry"]) + 1):
		for x in range(int(c["cx"]) - int(c["rx"]), int(c["cx"]) + int(c["rx"]) + 1):
			if soil.in_bounds(x, y) and in_ellipse(x, y, c):
				if SoilGrid.is_diggable(soil.mat[y * soil.w + x]):
					return true
	return false


## Área aproximada (px²) de las cámaras con un propósito.
func area_for(purpose: String) -> float:
	var a := 0.0
	for c in chambers:
		if c["purpose"] == purpose:
			a += PI * float(c["rx"]) * float(c["ry"])
	return a


func has_active_work() -> bool:
	if debris_ref != null and not debris_ref.is_empty():
		return true
	for t in tunnels:
		if not t["done"]:
			return true
	for ci in chambers.size():
		if not chambers[ci]["done"] and _chamber_active(ci):
			return true
	return _plug_active()


func chamber_for(purpose: String) -> int:
	## Cría → la cámara de cría más profunda; granero → la de granero más alta.
	var best := -1
	for i in chambers.size():
		var c := chambers[i]
		if c["purpose"] != purpose:
			continue
		if best < 0:
			best = i
		elif purpose == "brood" and int(c["cy"]) > int(chambers[best]["cy"]) and bool(c["done"]):
			best = i
		elif purpose == "granary" and int(c["cy"]) < int(chambers[best]["cy"]):
			best = i
	return best


func _maybe_plan_new(soil: SoilGrid, need: Dictionary, rng: RandomNumberGenerator, events: Array[String]) -> void:
	if has_active_work():
		return
	var order := ["granary", "brood"]
	for purpose: String in order:
		var needed := float(need.get(purpose, 0.0))
		if needed <= 0.0 or area_for(purpose) >= needed:
			continue
		# ¿Alguna cámara de ese tipo puede crecer todavía?
		for c in chambers:
			if c["purpose"] == purpose and (int(c["rx"]) < int(c["max_rx"]) or int(c["ry"]) < int(c["max_ry"])):
				c["done"] = false
				return
		if _plan_chamber(soil, purpose, rng):
			events.append("planned:%s" % purpose)
			return


func _plan_chamber(soil: SoilGrid, purpose: String, rng: RandomNumberGenerator) -> bool:
	for _attempt in 24:
		# Punto de partida: una cámara o galería existente.
		var sx: int
		var sy: int
		if rng.randf() < 0.6 and not chambers.is_empty():
			var c := chambers[rng.randi_range(0, chambers.size() - 1)]
			var side := -1 if rng.randf() < 0.5 else 1
			sx = int(c["cx"]) + side * int(c["rx"])
			sy = int(c["cy"])
		else:
			var t := tunnels[rng.randi_range(0, tunnels.size() - 1)]
			var tt := rng.randf_range(0.3, 1.0)
			sx = roundi(lerpf(float(t["ax"]), float(t["bx"]), tt))
			sy = roundi(lerpf(float(t["ay"]), float(t["by"]), tt))
		var dir := -1.0 if rng.randf() < 0.5 else 1.0
		var ang_min := 10.0 if purpose == "granary" else 30.0
		var ang_max := 30.0 if purpose == "granary" else 70.0
		var ang := deg_to_rad(rng.randf_range(ang_min, ang_max))
		var length := rng.randf_range(22.0, 40.0)
		var ex := sx + roundi(cos(ang) * length * dir)
		var ey := sy + roundi(sin(ang) * length)
		var rx := 11 if purpose == "granary" else 9
		var ry := 4
		var max_rx := 18 if purpose == "granary" else 15
		var max_ry := 5 if purpose == "granary" else 6
		var cx := ex + roundi(dir * 4.0)
		var cy := ey + 1
		if purpose == "granary" and cy > entrance_y + 90:
			continue
		if cx - max_rx < 4 or cx + max_rx > soil.w - 4 or cy + max_ry > soil.h - 4:
			continue
		if cy - max_ry < entrance_y + 10:
			continue
		# Lejos de otras cámaras.
		var ok := true
		for c2 in chambers:
			var ddx := absf(float(cx - int(c2["cx"]))) - float(max_rx + int(c2["max_rx"]))
			var ddy := absf(float(cy - int(c2["cy"]))) - float(max_ry + int(c2["max_ry"]))
			if ddx < 6.0 and ddy < 4.0:
				ok = false
				break
		if not ok:
			continue
		# Sin piedra en el centro de la futura cámara ni en el final de la galería.
		var rock := 0
		for y in range(cy - ry, cy + ry + 1):
			for x in range(cx - rx, cx + rx + 1):
				if soil.get_mat(x, y) == M.ROCK:
					rock += 1
		if rock > 6 or soil.get_mat(ex, ey) == M.ROCK:
			continue
		chambers.append({"cx": cx, "cy": cy, "rx": rx, "ry": ry, "max_rx": max_rx, "max_ry": max_ry,
			"purpose": purpose, "done": false})
		tunnels.append({"ax": sx, "ay": sy, "bx": ex, "by": ey, "r": 2.1, "done": false,
			"chamber": chambers.size() - 1})
		return true
	return false


## Sella la boca del nido con tierra (fundación claustral). Devuelve celdas.
func seal(soil: SoilGrid) -> void:
	plug_cells.clear()
	for y in range(entrance_y, entrance_y + 6):
		for x in range(entrance_x - 4, entrance_x + 5):
			if soil.is_air(x, y) and in_capsule(x, y, tunnels[0]):
				soil.set_mat(x, y, M.PLUG)
				soil.placed_total += 1
				plug_cells.append(y * soil.w + x)
	sealed = true


func to_dict() -> Dictionary:
	return {
		"entrance_x": entrance_x, "entrance_y": entrance_y, "sealed": sealed,
		"plug_cells": plug_cells, "chambers": chambers.duplicate(true), "tunnels": tunnels.duplicate(true),
		"founding_done": founding_done, "plug_open_requested": plug_open_requested,
	}


func from_dict(d: Dictionary) -> void:
	entrance_x = int(d["entrance_x"])
	entrance_y = int(d["entrance_y"])
	sealed = bool(d["sealed"])
	plug_cells = d["plug_cells"]
	chambers.clear()
	for c: Dictionary in d["chambers"]:
		chambers.append(c.duplicate())
	tunnels.clear()
	for t: Dictionary in d["tunnels"]:
		tunnels.append(t.duplicate())
	founding_done = bool(d["founding_done"])
	plug_open_requested = bool(d.get("plug_open_requested", false))
