class_name Ants
extends RefCounted
## Agentes (hormigas visibles) en estructura de arrays (SoA). Cada hormiga es
## una máquina de estados jerárquica: TAREA (elegida por umbrales de respuesta,
## Bonabeau et al. 1996) → COMPORTAMIENTO → LOCOMOCIÓN por la rejilla de nodos.
## Toda la lógica vive aquí para que los Packed*Array se modifiquen in situ
## (en GDScript copiarlos a variables locales provocaría copias completas).

const T := SimConst.Task
const CA := SimConst.Carry
const F := SimConst.Field
const PK := PheromoneField.Kind
const CASTE := SimConst.Caste

enum St {
	IDLE, TO_ENTRANCE, SURFACE_SEARCH, TO_SEED, RETURN_HOME, TO_GRANARY,
	TO_DIGFRONT, DIGGING, CARRY_OUT, SURFACE_DUMP, TO_BROOD, LOCAL, RESTING,
	TO_BREAD, BACK_BROOD, WORK, TO_SEAL, PICKING,
}

const ARRIVED := -1
const UNREACH := -2
const ELIGIBLE_TASKS := [T.NURSE, T.FORAGE, T.DIG, T.MILL, T.CLEAN]

var world: SimWorld
var nav: NavGrid
var rng: RandomNumberGenerator
var cap: int = 0
var count: int = 0

var alive := PackedByteArray()
var caste := PackedByteArray()
var task := PackedByteArray()
var state := PackedByteArray()
var carry := PackedByteArray()
var nanitic := PackedByteArray()
var hdir := PackedByteArray()          ## dirección en superficie: 0 = izquierda, 1 = derecha
var dir8 := PackedByteArray()          ## orientación del sprite (0 = E, 1 = NE, 2 = N … 7 = SE)
var node := PackedInt32Array()
var target := PackedInt32Array()
var aux := PackedInt32Array()          ## dato auxiliar (semilla objetivo…)
var px := PackedFloat32Array()
var py := PackedFloat32Array()
var speed := PackedFloat32Array()
var timer := PackedFloat32Array()
var task_timer := PackedFloat32Array()
var born_day := PackedFloat32Array()
var anim := PackedFloat32Array()
var carry_amt := PackedFloat32Array()
var dump_x := PackedFloat32Array()
var strength := PackedFloat32Array()   ## intensidad del rastro que deja al volver con comida
var thr := PackedFloat32Array()        ## umbrales [cap × N_TASKS]
var free_list := PackedInt32Array()
var task_count := PackedInt32Array()
var queen_index: int = -1


func setup(w: SimWorld, capacity: int) -> void:
	world = w
	nav = w.nav
	rng = w.rng_ants
	cap = capacity
	count = 0
	# Ojo: los Packed*Array son de copia en escritura; hay que redimensionar
	# cada miembro directamente (no a través de una variable de bucle).
	alive = _zeros_b(cap); caste = _zeros_b(cap); task = _zeros_b(cap); state = _zeros_b(cap)
	carry = _zeros_b(cap); nanitic = _zeros_b(cap); hdir = _zeros_b(cap); dir8 = _zeros_b(cap)
	node = _fill_i(cap, -1); target = _fill_i(cap, -1); aux = _fill_i(cap, -1)
	px = _zeros_f(cap); py = _zeros_f(cap); speed = _zeros_f(cap); timer = _zeros_f(cap)
	task_timer = _zeros_f(cap); born_day = _zeros_f(cap); anim = _zeros_f(cap)
	carry_amt = _zeros_f(cap); dump_x = _zeros_f(cap); strength = _zeros_f(cap)
	thr.resize(cap * SimConst.N_TASKS)
	thr.fill(1.0)
	free_list.clear()
	for i in range(cap - 1, -1, -1):
		free_list.append(i)
	task_count.resize(SimConst.N_TASKS + 1)
	task_count.fill(0)
	queen_index = -1


static func _zeros_b(n: int) -> PackedByteArray:
	var a := PackedByteArray()
	a.resize(n)
	a.fill(0)
	return a


static func _fill_i(n: int, v: int) -> PackedInt32Array:
	var a := PackedInt32Array()
	a.resize(n)
	a.fill(v)
	return a


static func _zeros_f(n: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	a.fill(0.0)
	return a


func spawn(c: int, x: float, y: float, bday: float, is_nanitic: bool) -> int:
	if free_list.is_empty():
		return -1
	var i := free_list[free_list.size() - 1]
	free_list.remove_at(free_list.size() - 1)
	alive[i] = 1
	caste[i] = c
	nanitic[i] = 1 if is_nanitic else 0
	var n := nav.nearest_walkable(x, y, 10)
	if n < 0:
		n = nav.node_of(x, y)
	node[i] = n
	target[i] = n
	var cpos := nav.node_center(n)
	px[i] = cpos.x
	py[i] = cpos.y
	var sp := world.species.speed_for_caste(c)
	if is_nanitic:
		sp *= 0.85
	speed[i] = sp * rng.randf_range(0.9, 1.1)
	timer[i] = 0.0
	task_timer[i] = rng.randf_range(0.5, 4.0)
	born_day[i] = bday
	anim[i] = rng.randf() * 4.0
	carry[i] = CA.NONE
	carry_amt[i] = 0.0
	aux[i] = -1
	hdir[i] = rng.randi_range(0, 1)
	dir8[i] = 0
	state[i] = St.IDLE
	var base := i * SimConst.N_TASKS
	for j in SimConst.N_TASKS:
		thr[base + j] = rng.randf_range(0.6, 1.6)   # variabilidad individual
	if c == CASTE.QUEEN:
		task[i] = T.QUEEN
		queen_index = i
	else:
		task[i] = T.REST
	task_count[task[i]] += 1
	count += 1
	return i


func despawn(i: int) -> void:
	if i < 0 or alive[i] == 0:
		return
	task_count[task[i]] -= 1
	alive[i] = 0
	count -= 1
	if i == queen_index:
		queen_index = -1
	free_list.append(i)


## Elimina una hormiga de la casta dada (preferiblemente una que descansa).
func despawn_one_of_caste(c: int) -> int:
	var fallback := -1
	for i in cap:
		if alive[i] == 1 and caste[i] == c:
			if carry[i] == CA.NONE and (task[i] == T.REST or task[i] == T.NURSE):
				despawn(i)
				return i
			if fallback < 0:
				fallback = i
	if fallback >= 0:
		despawn(fallback)
	return fallback


func count_caste(c: int) -> int:
	var n := 0
	for i in cap:
		if alive[i] == 1 and caste[i] == c:
			n += 1
	return n


func _set_task(i: int, t: int) -> void:
	if task[i] == t:
		return
	task_count[task[i]] -= 1
	task[i] = t
	task_count[t] += 1
	state[i] = St.IDLE
	aux[i] = -1


# ---------------------------------------------------------------------------
# Bucle principal
# ---------------------------------------------------------------------------

func step(dt: float) -> void:
	for i in cap:
		if alive[i] == 0:
			continue
		# Las que descansan apenas consumen CPU.
		if state[i] == St.RESTING and timer[i] > dt:
			timer[i] -= dt
			continue
		_update(i, dt)


func _update(i: int, dt: float) -> void:
	timer[i] -= dt
	task_timer[i] -= dt
	if task_timer[i] <= 0.0 and carry[i] == CA.NONE and caste[i] != CASTE.QUEEN:
		_reevaluate(i)
	var budget := speed[i] * world.behaviour_speed * dt
	var moved := false
	for _guard in 4:
		if node[i] == target[i]:
			var nt := _decide(i)
			if nt < 0:
				break
			target[i] = nt
		var c := nav.node_center(target[i])
		var dx := c.x - px[i]
		var dy := c.y - py[i]
		var d := sqrt(dx * dx + dy * dy)
		if d > 0.001:
			_set_dir(i, dx, dy)
		if d <= budget:
			px[i] = c.x
			py[i] = c.y
			budget -= d
			node[i] = target[i]
			moved = true
			if budget <= 0.01:
				break
		else:
			px[i] += dx / d * budget
			py[i] += dy / d * budget
			moved = true
			break
	if moved:
		anim[i] += dt * speed[i] * 0.55
	elif state[i] == St.DIGGING or state[i] == St.WORK:
		anim[i] += dt * 4.0


func _set_dir(i: int, dx: float, dy: float) -> void:
	var a := atan2(-dy, dx)          # y crece hacia abajo
	var k := posmod(roundi(a / (PI / 4.0)), 8)
	dir8[i] = k


# ---------------------------------------------------------------------------
# Navegación
# ---------------------------------------------------------------------------

func _path(i: int, field: int) -> int:
	var n := node[i]
	var d := nav.dist_at(field, n)
	if d == 0:
		return ARRIVED
	if d >= NavGrid.INF_DIST:
		return UNREACH
	var nx := nav.step_down(field, n, rng)
	if nx < 0:
		return UNREACH
	return nx


func _wander(i: int) -> int:
	var dx := 0
	var dy := 0
	match dir8[i]:
		0: dx = 1
		1: dx = 1; dy = -1
		2: dy = -1
		3: dx = -1; dy = -1
		4: dx = -1
		5: dx = -1; dy = 1
		6: dy = 1
		7: dx = 1; dy = 1
	var nx := nav.step_wander(node[i], dx, dy, rng, 0.6)
	if nx == node[i]:
		return -1
	return nx


## Paseo local alrededor de la fuente de un campo (dentro de un radio en nodos).
func _local(i: int, field: int, radius: int) -> int:
	var n := node[i]
	var start := rng.randi_range(0, 7)
	for j in 8:
		var k := (start + j) % 8
		var xx: int = nav.node_x(n) + NavGrid.NB_DX[k]
		var yy: int = nav.node_y(n) + NavGrid.NB_DY[k]
		if xx < 0 or yy < 0 or xx >= nav.nw or yy >= nav.nh:
			continue
		var m := yy * nav.nw + xx
		if nav.is_walkable(m) and nav.dist_at(field, m) <= radius:
			return m
	return -1


func _outworld(i: int) -> bool:
	return nav.is_outworld(node[i])


# ---------------------------------------------------------------------------
# Elección de tarea: umbrales de respuesta (Bonabeau, Theraulaz y Deneubourg)
# P(empezar j) = s_j² / (s_j² + θ_ij²), con refuerzo de umbrales.
# ---------------------------------------------------------------------------

func _effective_thr(i: int, j: int) -> float:
	var th := thr[i * SimConst.N_TASKS + j]
	var age := world.bio_day() - born_day[i]
	# Polietismo por edad: las jóvenes cuidan la cría, las veteranas forrajean.
	if j == T.NURSE:
		th *= 0.6 if age < 20.0 else (1.5 if age > 60.0 else 1.0)
	elif j == T.FORAGE:
		th *= 1.8 if age < 20.0 else (0.6 if age > 60.0 else 1.0)
	# Polietismo por casta (Messor: las mayores muelen y defienden).
	match caste[i]:
		CASTE.MAJOR:
			if j == T.MILL: th *= 0.3
			elif j == T.NURSE: th *= 2.5
			elif j == T.DIG: th *= 0.8
		CASTE.MEDIA:
			if j == T.MILL: th *= 0.6
			elif j == T.FORAGE: th *= 0.8
		CASTE.MINOR:
			if j == T.NURSE: th *= 0.8
	return th


func _reevaluate(i: int) -> void:
	task_timer[i] = rng.randf_range(15.0, 35.0)
	var s := world.stimuli
	var cur := task[i]
	var chosen := T.REST
	var start := rng.randi_range(0, ELIGIBLE_TASKS.size() - 1)
	for k in ELIGIBLE_TASKS.size():
		var j: int = ELIGIBLE_TASKS[(start + k) % ELIGIBLE_TASKS.size()]
		var sj := s[j]
		if sj <= 0.0:
			continue
		if j == cur:
			sj *= 1.3   # inercia: seguir con lo que se estaba haciendo
		var th := _effective_thr(i, j)
		var p := sj * sj / (sj * sj + th * th)
		if rng.randf() < p:
			chosen = j
			break
	# Refuerzo: aprender la tarea elegida y olvidar las demás.
	var base := i * SimConst.N_TASKS
	for j in SimConst.N_TASKS:
		if j == chosen:
			thr[base + j] = maxf(0.2, thr[base + j] - 0.06)
		else:
			thr[base + j] = minf(4.0, thr[base + j] + 0.012)
	_set_task(i, chosen)


# ---------------------------------------------------------------------------
# Comportamientos por tarea
# ---------------------------------------------------------------------------

func _decide(i: int) -> int:
	match task[i]:
		T.FORAGE:
			return _decide_forage(i)
		T.DIG:
			return _decide_dig(i)
		T.NURSE:
			return _decide_nurse(i)
		T.MILL:
			return _decide_work_at(i, F.GRANARY, 3)
		T.CLEAN:
			return _decide_clean(i)
		T.QUEEN:
			return _decide_queen(i)
	return _decide_rest(i)


func _decide_rest(i: int) -> int:
	if _outworld(i):
		var r := _path(i, F.BROOD)
		if r >= 0:
			return r
		r = _path(i, F.ENTRANCE)
		return r if r >= 0 else _wander(i)
	if state[i] != St.RESTING:
		# Caminar un poco por el nido y luego quedarse quieta.
		if state[i] != St.LOCAL:
			state[i] = St.LOCAL
			timer[i] = rng.randf_range(1.0, 5.0)
		if timer[i] > 0.0:
			return _wander(i)
		state[i] = St.RESTING
		timer[i] = rng.randf_range(12.0, 40.0)
		return -1
	if timer[i] <= 0.0:
		state[i] = St.LOCAL
		timer[i] = rng.randf_range(1.0, 4.0)
	return -1


func _decide_forage(i: int) -> int:
	if carry[i] == CA.SEED:
		if state[i] != St.TO_GRANARY:
			if _outworld(i) and strength[i] > 0.0:
				world.pher.deposit(PK.FOOD, px[i], py[i], strength[i])
			var r := _path(i, F.ENTRANCE)
			if r == ARRIVED:
				state[i] = St.TO_GRANARY
			elif r == UNREACH:
				return _wander(i)
			else:
				state[i] = St.RETURN_HOME
				return r
		var g := _path(i, F.GRANARY)
		if g == ARRIVED or (g == UNREACH and not _outworld(i)):
			world.deliver_seed(carry_amt[i])
			carry[i] = CA.NONE
			carry_amt[i] = 0.0
			state[i] = St.TO_ENTRANCE
			task_timer[i] = minf(task_timer[i], rng.randf_range(0.0, 6.0))
			return -1
		if g == UNREACH:
			return _wander(i)
		return g

	if not world.forage_allowed():
		task_timer[i] = 0.0
		return _decide_rest(i)

	match state[i]:
		St.SURFACE_SEARCH:
			if timer[i] <= 0.0:
				state[i] = St.RETURN_HOME
				return _decide_forage(i)
			var sid := world.find_seed(px[i], py[i], 16.0)
			if sid >= 0:
				aux[i] = sid
				state[i] = St.TO_SEED
				return _decide_forage(i)
			var d := 1 if hdir[i] == 1 else -1
			var ahead := world.pher.read(PK.FOOD, px[i] + d * 10.0, py[i]) + world.pher.read(PK.PLAYER, px[i] + d * 10.0, py[i])
			var behind := world.pher.read(PK.FOOD, px[i] - d * 10.0, py[i]) + world.pher.read(PK.PLAYER, px[i] - d * 10.0, py[i])
			if behind > ahead * 2.0 + 0.4 and rng.randf() < 0.5:
				d = -d
			elif rng.randf() < 0.006:
				d = -d
			var nx := nav.step_surface(node[i], d)
			if nx < 0:
				d = -d
				nx = nav.step_surface(node[i], d)
			hdir[i] = 1 if d > 0 else 0
			if nx < 0:
				return _wander(i)
			return nx
		St.TO_SEED:
			if not world.seed_exists(aux[i]):
				state[i] = St.SURFACE_SEARCH
				aux[i] = -1
				return nav.step_surface(node[i], 1 if hdir[i] == 1 else -1)
			var sx := world.seed_x_of(aux[i])
			if absf(sx - px[i]) <= 2.5:
				var v := world.take_seed(aux[i])
				if v > 0.0:
					carry[i] = CA.SEED
					carry_amt[i] = v
					strength[i] = 1.0 + 0.35 * float(world.count_seeds_near(px[i], 40.0))
				aux[i] = -1
				state[i] = St.PICKING
				timer[i] = rng.randf_range(0.4, 1.0)
				return -1
			var d2 := 1 if sx > px[i] else -1
			hdir[i] = 1 if d2 > 0 else 0
			var nx2 := nav.step_surface(node[i], d2)
			if nx2 < 0:
				state[i] = St.SURFACE_SEARCH
				return -1
			return nx2
		St.PICKING:
			if timer[i] > 0.0:
				return -1
			state[i] = St.RETURN_HOME
			return -1
		St.RETURN_HOME:
			var r2 := _path(i, F.ENTRANCE)
			if r2 == ARRIVED or r2 == UNREACH:
				state[i] = St.IDLE
				task_timer[i] = 0.0
				return -1 if r2 == ARRIVED else _wander(i)
			return r2
		_:
			if _outworld(i) and state[i] != St.TO_ENTRANCE:
				pass
			if _outworld(i):
				state[i] = St.SURFACE_SEARCH
				timer[i] = rng.randf_range(60.0, 140.0)
				# Elegir lado según el rastro de comida (reclutamiento).
				var left := world.pher.sample_side(PK.FOOD, px[i], py[i], -1, 200) + world.pher.sample_side(PK.PLAYER, px[i], py[i], -1, 200)
				var right := world.pher.sample_side(PK.FOOD, px[i], py[i], 1, 200) + world.pher.sample_side(PK.PLAYER, px[i], py[i], 1, 200)
				var pr := (right + 0.6) / (left + right + 1.2)
				hdir[i] = 1 if rng.randf() < pr else 0
				return _decide_forage(i)
			state[i] = St.TO_ENTRANCE
			var r3 := _path(i, F.ENTRANCE)
			if r3 == ARRIVED:
				return -1
			if r3 == UNREACH:
				task_timer[i] = minf(task_timer[i], 2.0)
				return _wander(i)
			return r3


func _decide_dig(i: int) -> int:
	if carry[i] == CA.SOIL:
		if state[i] == St.SURFACE_DUMP:
			if absf(px[i] - dump_x[i]) <= 2.0:
				world.drop_soil(px[i], carry_amt[i])
				carry[i] = CA.NONE
				carry_amt[i] = 0.0
				state[i] = St.TO_DIGFRONT
				return -1
			var d := 1 if dump_x[i] > px[i] else -1
			var nx := nav.step_surface(node[i], d)
			if nx < 0:
				world.drop_soil(px[i], carry_amt[i])
				carry[i] = CA.NONE
				carry_amt[i] = 0.0
				state[i] = St.TO_DIGFRONT
				return -1
			return nx
		if _outworld(i):
			state[i] = St.SURFACE_DUMP
			dump_x[i] = world.pick_dump_x()
			return -1
		state[i] = St.CARRY_OUT
		var r := _path(i, F.ENTRANCE)
		if r == ARRIVED:
			state[i] = St.SURFACE_DUMP
			dump_x[i] = world.pick_dump_x()
			return -1
		if r == UNREACH:
			# Nido sellado: la tierra se compacta en las paredes. [D]
			world.compact_soil(carry_amt[i])
			carry[i] = CA.NONE
			carry_amt[i] = 0.0
			state[i] = St.TO_DIGFRONT
			return -1
		return r

	if state[i] == St.DIGGING:
		if timer[i] > 0.0:
			return -1
		var got := world.dig_at(px[i], py[i])
		if got > 0:
			carry[i] = CA.SOIL
			carry_amt[i] = float(got)
			world.pher.deposit(PK.DIG, px[i], py[i], 1.0)
			state[i] = St.CARRY_OUT
		else:
			state[i] = St.TO_DIGFRONT
			task_timer[i] = minf(task_timer[i], 3.0)
		return -1

	state[i] = St.TO_DIGFRONT
	var r2 := _path(i, F.DIG)
	if r2 == ARRIVED:
		state[i] = St.DIGGING
		timer[i] = world.dig_time_at(px[i], py[i]) * rng.randf_range(0.8, 1.3)
		return -1
	if r2 == UNREACH:
		task_timer[i] = minf(task_timer[i], 1.5)
		return _wander(i)
	return r2


func _decide_nurse(i: int) -> int:
	match state[i]:
		St.TO_BREAD:
			var r := _path(i, F.GRANARY)
			if r == ARRIVED or r == UNREACH:
				carry[i] = CA.BREAD if world.colony.bread > 0.0 else CA.NONE
				state[i] = St.BACK_BROOD
				return -1
			return r
		St.BACK_BROOD:
			var r2 := _path(i, F.BROOD)
			if r2 == ARRIVED or r2 == UNREACH:
				carry[i] = CA.NONE
				state[i] = St.LOCAL
				timer[i] = rng.randf_range(6.0, 18.0)
				return -1
			return r2
		St.LOCAL:
			if timer[i] <= 0.0:
				if rng.randf() < 0.4 and world.colony.bread > 0.0:
					state[i] = St.TO_BREAD
					return -1
				timer[i] = rng.randf_range(6.0, 18.0)
			if rng.randf() < 0.35:
				return -1  # atendiendo a la cría
			return _local(i, F.BROOD, 3)
		_:
			var r3 := _path(i, F.BROOD)
			if r3 == ARRIVED or r3 == UNREACH:
				state[i] = St.LOCAL
				timer[i] = rng.randf_range(6.0, 18.0)
				return -1 if r3 == ARRIVED else _wander(i)
			return r3


func _decide_work_at(i: int, field: int, radius: int) -> int:
	if state[i] == St.WORK:
		if timer[i] > 0.0:
			return -1
		state[i] = St.LOCAL
		timer[i] = rng.randf_range(1.0, 3.0)
	if state[i] == St.LOCAL:
		if timer[i] <= 0.0:
			state[i] = St.WORK
			timer[i] = rng.randf_range(3.0, 9.0)
			return -1
		return _local(i, field, radius)
	var r := _path(i, field)
	if r == ARRIVED or r == UNREACH:
		state[i] = St.WORK
		timer[i] = rng.randf_range(3.0, 9.0)
		return -1 if r == ARRIVED else _wander(i)
	return r


func _decide_clean(i: int) -> int:
	if carry[i] == CA.HUSK or carry[i] == CA.CORPSE:
		if state[i] == St.SURFACE_DUMP:
			if absf(px[i] - dump_x[i]) <= 2.0:
				world.drop_midden(px[i], carry[i])
				carry[i] = CA.NONE
				state[i] = St.IDLE
				return -1
			var d := 1 if dump_x[i] > px[i] else -1
			var nx := nav.step_surface(node[i], d)
			if nx < 0:
				world.drop_midden(px[i], carry[i])
				carry[i] = CA.NONE
				state[i] = St.IDLE
				return -1
			return nx
		var r := _path(i, F.ENTRANCE)
		if r == ARRIVED or _outworld(i):
			state[i] = St.SURFACE_DUMP
			dump_x[i] = world.pick_midden_x()
			return -1
		if r == UNREACH:
			carry[i] = CA.NONE   # nido sellado: lo deja en un rincón
			return -1
		return r
	var g := _path(i, F.GRANARY)
	if g == ARRIVED or g == UNREACH:
		var what := world.take_refuse()
		if what == CA.NONE:
			task_timer[i] = minf(task_timer[i], 2.0)
			state[i] = St.LOCAL
			return _local(i, F.GRANARY, 3)
		carry[i] = what
		state[i] = St.CARRY_OUT
		return -1
	return g


func _decide_queen(i: int) -> int:
	var colony := world.colony
	var plan := world.plan
	if carry[i] != CA.NONE:
		return _decide_dig(i)
	if colony.founding and not plan.founding_done:
		return _decide_dig(i)
	if colony.founding and plan.founding_done and not plan.sealed and not world.journal.flags.has("sealed"):
		# Bajar al nido si está fuera; después subir por la galería hasta justo
		# debajo de la boca (sin quedarse dentro del tapón) y sellarla.
		if _outworld(i) or py[i] <= float(plan.entrance_y + 6):
			var rb := _path(i, F.BROOD)
			return rb if rb >= 0 else _wander(i)
		if py[i] <= float(plan.entrance_y + 14):
			world.seal_entrance()
			state[i] = St.IDLE
			return -1
		var r := _path(i, F.ENTRANCE)
		return r if r >= 0 else _wander(i)
	# Vida en la cámara de cría: casi inmóvil.
	if state[i] == St.RESTING:
		if timer[i] > 0.0:
			return -1
		state[i] = St.LOCAL
		timer[i] = rng.randf_range(1.0, 3.0)
	var r2 := _path(i, F.BROOD)
	if r2 >= 0 and nav.dist_at(F.BROOD, node[i]) > 2:
		return r2
	if state[i] == St.LOCAL and timer[i] > 0.0:
		return _local(i, F.BROOD, 2)
	state[i] = St.RESTING
	timer[i] = rng.randf_range(20.0, 60.0)
	return -1


func to_dict() -> Dictionary:
	return {
		"cap": cap, "count": count, "alive": alive, "caste": caste, "task": task, "state": state,
		"carry": carry, "nanitic": nanitic, "hdir": hdir, "dir8": dir8, "node": node, "target": target,
		"aux": aux, "px": px, "py": py, "speed": speed, "timer": timer, "task_timer": task_timer,
		"born_day": born_day, "anim": anim, "carry_amt": carry_amt, "dump_x": dump_x,
		"strength": strength, "thr": thr, "free_list": free_list, "task_count": task_count,
		"queen_index": queen_index,
	}


func from_dict(d: Dictionary) -> void:
	cap = int(d["cap"])
	count = int(d["count"])
	alive = d["alive"]; caste = d["caste"]; task = d["task"]; state = d["state"]
	carry = d["carry"]; nanitic = d["nanitic"]; hdir = d["hdir"]; dir8 = d["dir8"]
	node = d["node"]; target = d["target"]; aux = d["aux"]
	px = d["px"]; py = d["py"]; speed = d["speed"]; timer = d["timer"]; task_timer = d["task_timer"]
	born_day = d["born_day"]; anim = d["anim"]; carry_amt = d["carry_amt"]; dump_x = d["dump_x"]
	strength = d["strength"]; thr = d["thr"]; free_list = d["free_list"]; task_count = d["task_count"]
	queen_index = int(d["queen_index"])
	# Las semillas objetivo no se guardan: soltar referencias.
	for i in cap:
		if alive[i] == 1 and state[i] == St.TO_SEED:
			state[i] = St.SURFACE_SEARCH
			aux[i] = -1
