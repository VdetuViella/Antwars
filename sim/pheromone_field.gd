class_name PheromoneField
extends RefCounted
## Campos de feromonas en una rejilla gruesa (4×4 px). La evaporación es
## perezosa: cada celda guarda su valor y el instante de la última escritura, y
## al leer se aplica v·e^(−ρ·Δt). Así no hay que recorrer toda la rejilla en
## cada tick (importante en GDScript) y el resultado es exacto.

enum Kind { FOOD = 0, DIG = 1, ALARM = 2, PLAYER = 3 }
const N_KINDS := 4
## Tasa de evaporación ρ por segundo de comportamiento. [D] Ver docs/SIMULACION.md.
const RHO := [1.0 / 420.0, 1.0 / 90.0, 1.0 / 20.0, 1.0 / 900.0]
const MAX_V := 50.0

var pw: int = 0
var ph: int = 0
var val: Array[PackedFloat32Array] = []
var stamp: Array[PackedFloat32Array] = []
var now: float = 0.0          ## tiempo de comportamiento actual


func setup(world_w: int, world_h: int) -> void:
	pw = world_w / SimConst.PHER_CELL
	ph = world_h / SimConst.PHER_CELL
	val.clear()
	stamp.clear()
	for _k in N_KINDS:
		var v := PackedFloat32Array()
		v.resize(pw * ph)
		v.fill(0.0)
		val.append(v)
		var s := PackedFloat32Array()
		s.resize(pw * ph)
		s.fill(0.0)
		stamp.append(s)


func cell_of(px: float, py: float) -> int:
	var cx := clampi(int(px) / SimConst.PHER_CELL, 0, pw - 1)
	var cy := clampi(int(py) / SimConst.PHER_CELL, 0, ph - 1)
	return cy * pw + cx


func read_cell(kind: int, c: int) -> float:
	var v := val[kind][c]
	if v <= 0.0001:
		return 0.0
	var dt := now - stamp[kind][c]
	return v * exp(-RHO[kind] * dt)


func read(kind: int, px: float, py: float) -> float:
	return read_cell(kind, cell_of(px, py))


func deposit(kind: int, px: float, py: float, amount: float) -> void:
	var c := cell_of(px, py)
	var v := read_cell(kind, c) + amount
	val[kind][c] = minf(v, MAX_V)
	stamp[kind][c] = now


## Suma de feromona en una franja horizontal de la superficie a un lado de x.
func sample_side(kind: int, px: float, py: float, dir: int, span_px: int) -> float:
	var total := 0.0
	var step := SimConst.PHER_CELL
	var x := px + dir * step
	var end := px + dir * span_px
	while (dir > 0 and x <= end) or (dir < 0 and x >= end):
		total += read(kind, x, py) + read(kind, x, py - step)
		x += dir * step
	return total


func to_dict() -> Dictionary:
	# Guardamos el valor ya evaporado al instante actual (stamp = now).
	var out := []
	for k in N_KINDS:
		var arr := PackedFloat32Array()
		arr.resize(pw * ph)
		for c in pw * ph:
			arr[c] = read_cell(k, c)
		out.append(arr)
	return {"pw": pw, "ph": ph, "val": out}


func from_dict(d: Dictionary, world_w: int, world_h: int) -> void:
	setup(world_w, world_h)
	now = 0.0
	var arrs: Array = d.get("val", [])
	for k in mini(arrs.size(), N_KINDS):
		var a: PackedFloat32Array = arrs[k]
		if a.size() == pw * ph:
			val[k] = a
