extends TestCase
## Comprobaciones básicas del núcleo: generación, especie y modelo térmico.


func test_world_generates() -> void:
	var w := make_world()
	check(w.soil.count_material(SimConst.Mat.AIR) > 0, "hay aire sobre el suelo")
	check(w.soil.count_material(SimConst.Mat.ROCK) > 0, "hay piedras")
	check_eq(w.ants.count, 1, "solo la reina al empezar")
	check(w.ants.queen_index >= 0, "la reina existe")
	check(w.colony.founding, "empieza en fundación claustral")


func test_dev_rate_calibration() -> void:
	var sp := SpeciesDef.load_by_id("messor_barbarus")
	var total_opt := sp.stage_days_at_opt("egg") + sp.stage_days_at_opt("larva") + sp.stage_days_at_opt("pupa")
	# [A] 42-56 días a 24 °C; 30-50 a 24-28 °C; 60-90 a 20 °C.
	check_range(total_opt / sp.dev_rate(24.0), 40.0, 50.0, "días huevo→obrera a 24 °C")
	check_range(total_opt / sp.dev_rate(20.0), 60.0, 95.0, "días huevo→obrera a 20 °C")
	check_range(total_opt / sp.dev_rate(27.0), 30.0, 42.0, "días huevo→obrera a 27 °C")
	check_eq(sp.dev_rate(15.0), 0.0, "sin desarrollo por debajo de 16 °C")


func test_packed_nested_write() -> void:
	# Garantía del lenguaje en la que se apoya PheromoneField: a[i][j] = v escribe de verdad.
	var p := PheromoneField.new()
	p.setup(64, 64)
	p.now = 0.0
	p.deposit(PheromoneField.Kind.FOOD, 10.0, 10.0, 5.0)
	check_near(p.read(PheromoneField.Kind.FOOD, 10.0, 10.0), 5.0, 0.001, "depósito leído")
	p.now = 420.0
	check_near(p.read(PheromoneField.Kind.FOOD, 10.0, 10.0), 5.0 * exp(-1.0), 0.01, "evaporación perezosa")


func test_room_temperature_model() -> void:
	check_range(FormicariumEnv.room_temp(205, 17.0), 26.0, 27.5, "verano")
	check_range(FormicariumEnv.room_temp(20, 5.0), 17.5, 19.5, "invierno")


func test_calendar_daylight() -> void:
	var c := SimCalendar.new()
	c.setup(float(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 6, "day": 21, "hour": 14, "minute": 0, "second": 0})))
	check(c.is_daylight(), "a las 14 h de junio es de día")
	check_range(c.day_length_hours(), 14.5, 15.2, "día más largo")
	c.elapsed = 12.0 * 3600.0
	check(not c.is_daylight(), "a las 2 h es de noche")
