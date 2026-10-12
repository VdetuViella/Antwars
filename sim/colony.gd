class_name Colony
extends RefCounted
## Biología y economía de la colonia en tiempo biológico (cohortes de cría,
## población por castas, granero y pan de hormiga). El MISMO código avanza la
## colonia con el juego abierto y durante el progreso offline, así que ambos
## modos son coherentes por construcción.

const Caste := SimConst.Caste
enum Stage { EGG = 0, LARVA = 1, PUPA = 2 }
const STAGE_KEYS := ["egg", "larva", "pupa"]

var sp: SpeciesDef

# --- Reina ---
var queen_alive: bool = true
var queen_age_days: float = 0.0
var queen_reserves: float = 100.0
var founding: bool = true           ## fase claustral: la reina no come y vive de reservas
var founding_eggs_left: int = 16
var queen_lifespan_days: float = 7300.0

# --- Cría: cohortes {stage, n, p (progreso 0..1), fed (0..1)} ---
var brood: Array[Dictionary] = []

# --- Obreras ---
var workers: PackedInt32Array = PackedInt32Array([0, 0, 0])   ## por casta (menor, media, mayor)
var nanitics: int = 0                ## subconjunto de las menores (primera camada)
var workers_ever: int = 0

# --- Despensa ---
var granary: float = 0.0            ## semillas almacenadas
var bread: float = 0.0              ## pan de hormiga (semilla molida)
var husks: float = 0.0              ## cáscaras pendientes de sacar al basurero
var corpses: int = 0                ## cadáveres pendientes de retirar

# --- Estadísticas ---
var eggs_total: int = 0
var deaths_total: int = 0
var seeds_harvested_total: float = 0.0
var starving_days: float = 0.0
var mold_days: float = 0.0
var forage_rate_ema: float = 0.0    ## semillas por obrera forrajera y día (medido en juego)


func setup(species: SpeciesDef, rng: RandomNumberGenerator) -> void:
	sp = species
	var q := sp.section("queen")
	queen_reserves = float(q.get("founding_reserves", 100.0))
	founding_eggs_left = int(q.get("founding_batch_eggs", 16)) + rng.randi_range(-3, 3)
	var mean := sp.num("lifespan_days", "queen_mean", 7300.0)
	queen_lifespan_days = mean * rng.randf_range(0.75, 1.25)


func total_workers() -> int:
	return workers[0] + workers[1] + workers[2]


func brood_count(stage: int) -> int:
	var t := 0
	for c in brood:
		if int(c["stage"]) == stage:
			t += int(c["n"])
	return t


func brood_total() -> int:
	var t := 0
	for c in brood:
		t += int(c["n"])
	return t


## Consumo diario de semillas de la colonia (sin cría, que come pan).
func daily_consumption() -> float:
	var c := workers[0] * sp.consumption("minor") + workers[1] * sp.consumption("media") \
		+ workers[2] * sp.consumption("major")
	if queen_alive and not founding:
		c += sp.consumption("queen")
	return c + brood_count(Stage.LARVA) * sp.consumption("larva")


func food_days() -> float:
	return (granary + bread) / maxf(daily_consumption(), 0.05)


## Avanza la colonia `dt_days` días biológicos.
## ctx: {temp, hum_brood, hum_granary, hibernating}
## Devuelve eventos: {born: Array[{caste, nanitic}], died: PackedInt32Array(3), eggs, queen_died, mold, starving}
func step(dt_days: float, ctx: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var ev := {"born": [], "died": PackedInt32Array([0, 0, 0]), "eggs": 0, "queen_died": false,
		"mold": false, "starving": false, "brood_died": 0}
	var temp: float = ctx.get("temp", 24.0)
	var hib: bool = ctx.get("hibernating", false)
	var hum_b: float = ctx.get("hum_brood", 60.0)
	var hum_g: float = ctx.get("hum_granary", 40.0)
	var q := sp.section("queen")
	var climate := sp.section("climate")

	# --- Reina ---
	if queen_alive:
		queen_age_days += dt_days
		if founding:
			# Metabolismo basal: más lento con frío.
			var metab := clampf(0.35 + 0.65 * sp.dev_rate(temp), 0.35, 1.0)
			queen_reserves -= float(q.get("reserve_cost_per_day", 0.25)) * metab * dt_days
		if queen_age_days > queen_lifespan_days or queen_reserves <= 0.0:
			queen_alive = false
			ev["queen_died"] = true
			corpses += 1

	# --- Puesta ---
	var lay_temp_ok := temp >= float(climate.get("laying_min_temp_c", 18.0)) and not hib
	if queen_alive and lay_temp_ok:
		var eggs_f := 0.0
		if founding:
			if founding_eggs_left > 0:
				var per_day := float(q.get("founding_batch_eggs", 16)) / float(q.get("founding_lay_days", 6.0))
				eggs_f = minf(per_day * dt_days, float(founding_eggs_left))
		else:
			var w := float(total_workers())
			var rate := minf(float(q.get("max_eggs_per_day", 30.0)), 1.0 + 0.5 * pow(w, 0.7))
			var temp_f := clampf(sp.dev_rate(temp) / 0.8, 0.0, 1.0)
			var food_f := clampf(food_days() / 10.0, 0.05, 1.0)
			# Límite por capacidad de las nodrizas (≈ 6 larvas por obrera).
			var cap := float(q.get("nurse_capacity_larvae", 6.0)) * w + 8.0
			var load := float(brood_total())
			var nurse_f := clampf((cap - load) / cap, 0.0, 1.0)
			eggs_f = rate * temp_f * food_f * nurse_f * dt_days
		var eggs := _stoch_round(eggs_f, rng)
		if eggs > 0:
			if founding:
				founding_eggs_left -= eggs
			_add_brood(Stage.EGG, eggs)
			eggs_total += eggs
			ev["eggs"] = eggs

	var rate_t_pre := sp.dev_rate(temp)

	# --- Molienda: semillas → pan (capacidad según castas) ---
	var mill_cap := (0.6 * workers[0] + 1.5 * workers[1] + 4.0 * workers[2]) * dt_days
	if hib:
		mill_cap *= 0.2
	var larvae := brood_count(Stage.LARVA)
	var bread_target := larvae * sp.consumption("larva") * 3.0 + 1.0
	if bread < bread_target and granary > 0.0:
		var m := minf(mill_cap, minf(granary, bread_target - bread))
		granary -= m
		bread += m
		husks += m

	# --- Desarrollo de la cría ---
	var rate_t := rate_t_pre
	var larva_need := larvae * sp.consumption("larva") * dt_days
	var fed_frac := 1.0
	if larva_need > 0.0:
		if founding:
			# Cada larva consume `reserve_cost_per_larva` a lo largo de toda su etapa.
			var per_day := float(q.get("reserve_cost_per_larva", 2.2)) * rate_t_pre / sp.stage_days_at_opt("larva")
			var cost := larvae * per_day * dt_days
			if queen_reserves > cost:
				queen_reserves -= cost
			else:
				fed_frac = maxf(queen_reserves, 0.0) / maxf(cost, 0.0001)
				queen_reserves = maxf(queen_reserves - cost, 0.0)
		else:
			var from_bread := minf(bread, larva_need)
			bread -= from_bread
			var rest := larva_need - from_bread
			# Sin pan, las nodrizas mastican semilla directamente (peor rendimiento).
			var from_seed := minf(granary, rest * 1.5)
			granary -= from_seed
			fed_frac = clampf((from_bread + from_seed / 1.5) / larva_need, 0.0, 1.0)

	var hum_lo := float(climate.get("brood_humidity", [50, 70])[0])
	var hum_hi := float(climate.get("brood_humidity", [50, 70])[1])
	var dry_mort := 0.0
	if hum_b < hum_lo - 15.0:
		dry_mort = 0.04 * dt_days       # desecación
	var wet_mort := 0.0
	if hum_b > hum_hi + 18.0:
		wet_mort = 0.015 * dt_days      # hongos en los huevos

	var next: Array[Dictionary] = []
	for c in brood:
		var stage := int(c["stage"])
		var n := int(c["n"])
		var stage_days := sp.stage_days_at_opt(STAGE_KEYS[stage])
		var adv := rate_t / stage_days * dt_days
		var mort := 0.002 * dt_days + dry_mort
		if stage == Stage.EGG:
			mort += wet_mort
		if stage == Stage.LARVA:
			adv *= 0.25 + 0.75 * fed_frac
			if fed_frac < 0.6:
				mort += (0.6 - fed_frac) * 0.08 * dt_days
			c["fed"] = lerpf(float(c.get("fed", 1.0)), fed_frac, clampf(dt_days, 0.0, 1.0))
		var dead := _binomial(n, clampf(mort, 0.0, 1.0), rng)
		if dead > 0:
			n -= dead
			ev["brood_died"] = int(ev["brood_died"]) + dead
		if n <= 0:
			continue
		var p := float(c["p"]) + adv
		if p >= 1.0:
			if stage == Stage.PUPA:
				_eclose(n, float(c.get("fed", 1.0)), ev, rng)
				continue
			c["stage"] = stage + 1
			p = 0.0
		c["p"] = p
		c["n"] = n
		next.append(c)
	brood = next

	# --- Fin de la fundación claustral ---
	if founding and total_workers() > 0:
		founding = false

	# --- Consumo de las obreras ---
	var need := (workers[0] * sp.consumption("minor") + workers[1] * sp.consumption("media")
		+ workers[2] * sp.consumption("major")) * dt_days
	if queen_alive and not founding:
		need += sp.consumption("queen") * dt_days
	if hib:
		need *= 0.15
	var eat := minf(need, granary + bread)
	var from_g := minf(granary, eat)
	granary -= from_g
	bread -= (eat - from_g)
	var starving := need > 0.0 and eat < need * 0.999
	if starving:
		starving_days += dt_days
		ev["starving"] = true
	else:
		starving_days = maxf(0.0, starving_days - dt_days)

	# --- Mortalidad de las obreras ---
	var died: PackedInt32Array = ev["died"]
	var life_w := sp.num("lifespan_days", "worker_mean", 730.0)
	var life_n := sp.num("lifespan_days", "nanitic_mean", 240.0)
	var starve_h := 0.0
	if starving_days > 3.0:
		starve_h = 0.03 * dt_days * minf(starving_days / 10.0, 3.0)
	for k in 3:
		var n := workers[k]
		if n <= 0:
			continue
		var h := dt_days / life_w + starve_h
		var d := _binomial(n, clampf(h, 0.0, 1.0), rng)
		if k == Caste.MINOR and nanitics > 0:
			var dn := _binomial(nanitics, clampf(dt_days / life_n + starve_h, 0.0, 1.0), rng)
			dn = mini(dn, nanitics)
			nanitics -= dn
			d = mini(d + dn, n)
		if d > 0:
			workers[k] = n - d
			died[k] = d
			deaths_total += d
			corpses += d
	nanitics = mini(nanitics, workers[0])
	ev["died"] = died   # PackedInt32Array es de copia en escritura

	# Reina sin colonia y sin reservas: muere de hambre.
	if queen_alive and not founding and starving_days > 25.0:
		queen_alive = false
		ev["queen_died"] = true
		corpses += 1

	# --- Moho en el granero ---
	var g_max := float(climate.get("granary_humidity_max", 50))
	if hum_g > g_max + 10.0 and granary > 0.0:
		var lost := granary * 0.015 * dt_days
		granary -= lost
		mold_days += dt_days
		ev["mold"] = true
	else:
		mold_days = maxf(0.0, mold_days - dt_days * 0.5)

	return ev


func _add_brood(stage: int, n: int) -> void:
	if not brood.is_empty():
		var last: Dictionary = brood[brood.size() - 1]
		if int(last["stage"]) == stage and float(last["p"]) < 0.04:
			last["n"] = int(last["n"]) + n
			return
	brood.append({"stage": stage, "n": n, "p": 0.0, "fed": 1.0})


func _eclose(n: int, fed: float, ev: Dictionary, rng: RandomNumberGenerator) -> void:
	var born: Array = ev["born"]
	for _i in n:
		var is_nanitic := workers_ever < int(sp.section("queen").get("founding_batch_eggs", 16))
		var caste := Caste.MINOR
		if not is_nanitic:
			var ratios := sp.caste_ratios(total_workers())
			# Larvas mal alimentadas salen menores.
			var r := rng.randf()
			var p_major := float(ratios.get("major", 0.0)) * fed
			var p_media := float(ratios.get("media", 0.0)) * fed
			if r < p_major:
				caste = Caste.MAJOR
			elif r < p_major + p_media:
				caste = Caste.MEDIA
		workers[caste] += 1
		workers_ever += 1
		if is_nanitic:
			nanitics += 1
		born.append({"caste": caste, "nanitic": is_nanitic})


## Redondeo estocástico (valor esperado exacto, determinista con la semilla).
static func _stoch_round(x: float, rng: RandomNumberGenerator) -> int:
	if x <= 0.0:
		return 0
	var base := floori(x)
	return base + (1 if rng.randf() < x - base else 0)


## Muestra binomial: exacta para n pequeño, aproximación normal para n grande.
static func _binomial(n: int, p: float, rng: RandomNumberGenerator) -> int:
	if n <= 0 or p <= 0.0:
		return 0
	if p >= 1.0:
		return n
	if n <= 40:
		var k := 0
		for _i in n:
			if rng.randf() < p:
				k += 1
		return k
	var mean := n * p
	var sd := sqrt(n * p * (1.0 - p))
	return clampi(roundi(rng.randfn(mean, sd)), 0, n)


func to_dict() -> Dictionary:
	return {
		"queen_alive": queen_alive, "queen_age_days": queen_age_days, "queen_reserves": queen_reserves,
		"founding": founding, "founding_eggs_left": founding_eggs_left, "queen_lifespan_days": queen_lifespan_days,
		"brood": brood.duplicate(true), "workers": workers, "nanitics": nanitics, "workers_ever": workers_ever,
		"granary": granary, "bread": bread, "husks": husks, "corpses": corpses,
		"eggs_total": eggs_total, "deaths_total": deaths_total, "seeds_harvested_total": seeds_harvested_total,
		"starving_days": starving_days, "mold_days": mold_days, "forage_rate_ema": forage_rate_ema,
	}


func from_dict(d: Dictionary) -> void:
	queen_alive = bool(d.get("queen_alive", true))
	queen_age_days = float(d.get("queen_age_days", 0.0))
	queen_reserves = float(d.get("queen_reserves", 100.0))
	founding = bool(d.get("founding", true))
	founding_eggs_left = int(d.get("founding_eggs_left", 0))
	queen_lifespan_days = float(d.get("queen_lifespan_days", 7300.0))
	brood.clear()
	for c: Dictionary in d.get("brood", []):
		brood.append(c.duplicate())
	workers = d.get("workers", PackedInt32Array([0, 0, 0]))
	nanitics = int(d.get("nanitics", 0))
	workers_ever = int(d.get("workers_ever", 0))
	granary = float(d.get("granary", 0.0))
	bread = float(d.get("bread", 0.0))
	husks = float(d.get("husks", 0.0))
	corpses = int(d.get("corpses", 0))
	eggs_total = int(d.get("eggs_total", 0))
	deaths_total = int(d.get("deaths_total", 0))
	seeds_harvested_total = float(d.get("seeds_harvested_total", 0.0))
	starving_days = float(d.get("starving_days", 0.0))
	mold_days = float(d.get("mold_days", 0.0))
	forage_rate_ema = float(d.get("forage_rate_ema", 0.0))
