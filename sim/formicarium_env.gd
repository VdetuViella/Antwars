class_name FormicariumEnv
extends RefCounted
## Condiciones del formicario doméstico: temperatura de la habitación, manta
## térmica, hibernación, humedad del sustrato, depósito de agua y comedero.
## Ver docs/adr/ADR-003-formicario-domestico.md.

# --- Temperatura ---
var heater_on: bool = true
var heater_delta_c: float = 3.0
var auto_hibernation: bool = true
var hibernation_start: Vector2i = Vector2i(12, 1)   ## (mes, día)
var hibernation_end: Vector2i = Vector2i(1, 31)
var hibernation_temp_c: float = 14.0

# --- Humedad (0-100 % HR del sustrato a media profundidad) ---
var humidity: float = 60.0
var evaporation_per_day: float = 3.0               ## [D] % HR/día a 24 °C
var water_ml: float = 80.0                          ## depósito de agua (tubo)
const WATER_MAX_ML := 120.0
var water_ml_per_point: float = 0.25                ## ml para subir 1 % HR
var target_humidity: float = 60.0

# --- Comedero de semillas ---
var feeder_seeds: float = 600.0                     ## semillas en el comedero
var feeder_x: int = 520                             ## posición en la superficie

# --- Mechones de hierba que sueltan semillas (sustrato naturalista) ---
var tuft_xs: PackedInt32Array = PackedInt32Array([90, 200, 400])


## Temperatura de la habitación (casa española sin climatizar): ~19 °C en
## invierno, ~26 °C en verano, ±1 °C de oscilación diaria.
static func room_temp(doy: int, hour: float) -> float:
	var base := 22.5 + 3.5 * cos(TAU * float(doy - 205) / 365.0)
	var daily := 1.0 * cos(TAU * (hour - 17.0) / 24.0)
	return base + daily


func is_hibernating(cal: SimCalendar) -> bool:
	if not auto_hibernation:
		return false
	var d := cal.date_dict()
	var md := Vector2i(int(d["month"]), int(d["day"]))
	var s := hibernation_start
	var e := hibernation_end
	var after_start := md.x > s.x or (md.x == s.x and md.y >= s.y)
	var before_end := md.x < e.x or (md.x == e.x and md.y <= e.y)
	if s.x > e.x:  # el periodo cruza el año
		return after_start or before_end
	return after_start and before_end


## Temperatura del nido (zona de cría).
func nest_temp(cal: SimCalendar) -> float:
	if is_hibernating(cal):
		return hibernation_temp_c
	var t := room_temp(cal.day_of_year(), cal.hour_float())
	if heater_on:
		t += heater_delta_c
	return t


## Temperatura en la superficie (outworld).
func surface_temp(cal: SimCalendar) -> float:
	if is_hibernating(cal):
		return hibernation_temp_c - 1.0
	return room_temp(cal.day_of_year(), cal.hour_float())


## Humedad relativa local según la profundidad (0 = superficie, 1 = fondo).
## Las zonas profundas conservan más humedad que las altas.
func humidity_at_depth(depth_frac: float) -> float:
	return clampf(humidity + (depth_frac - 0.45) * 30.0, 0.0, 100.0)


## Avanza la humedad y el depósito de agua un intervalo biológico.
func step(dt_days: float, temp_c: float) -> void:
	var evap := evaporation_per_day * maxf(0.3, (temp_c - 5.0) / 19.0) * dt_days
	humidity = maxf(0.0, humidity - evap)
	# El tubo de agua rehidrata el sustrato poco a poco mientras tenga agua.
	if humidity < target_humidity and water_ml > 0.0:
		var need := minf(target_humidity - humidity, 12.0 * dt_days)
		var ml := minf(need * water_ml_per_point, water_ml)
		water_ml -= ml
		humidity += ml / water_ml_per_point


func to_dict() -> Dictionary:
	return {
		"heater_on": heater_on, "auto_hibernation": auto_hibernation,
		"humidity": humidity, "water_ml": water_ml, "target_humidity": target_humidity,
		"feeder_seeds": feeder_seeds, "feeder_x": feeder_x,
	}


func from_dict(d: Dictionary) -> void:
	heater_on = bool(d.get("heater_on", true))
	auto_hibernation = bool(d.get("auto_hibernation", true))
	humidity = float(d.get("humidity", 60.0))
	water_ml = float(d.get("water_ml", 80.0))
	target_humidity = float(d.get("target_humidity", 60.0))
	feeder_seeds = float(d.get("feeder_seeds", 600.0))
	feeder_x = int(d.get("feeder_x", 520))
