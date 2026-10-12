class_name SimCalendar
extends RefCounted
## Reloj biológico de la colonia. Avanza a la escala de tiempo elegida
## (realista ×1, acompañante ×24, acelerado ×96). Nunca lee el reloj del sistema:
## la hora real entra solo por world.apply_offline() / el host.

const LATITUDE_DEG := 40.0      ## España peninsular (aprox.)
const SOLAR_NOON_H := 13.3      ## mediodía solar medio en hora oficial española (aprox.)

var start_unix: float = 0.0     ## fecha de inicio de la partida (hora local tratada como UTC)
var elapsed: float = 0.0        ## segundos biológicos transcurridos


func setup(start_unix_time: float) -> void:
	start_unix = start_unix_time
	elapsed = 0.0


func unix() -> float:
	return start_unix + elapsed


func days_elapsed() -> float:
	return elapsed / SimConst.SECONDS_PER_DAY


func date_dict() -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(int(unix()))


func month() -> int:
	return int(date_dict()["month"])


func day_of_year() -> int:
	var d := date_dict()
	var jan1 := Time.get_unix_time_from_datetime_dict({"year": d["year"], "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0})
	return int((unix() - float(jan1)) / SimConst.SECONDS_PER_DAY) + 1


func hour_float() -> float:
	var t := fposmod(unix(), SimConst.SECONDS_PER_DAY)
	return t / 3600.0


## Horas de luz para el día del año (aproximación sinusoidal a 40° N: ~9,3 h a ~15 h).
func day_length_hours(doy: int = -1) -> float:
	if doy < 0:
		doy = day_of_year()
	return 12.15 + 2.85 * sin(TAU * float(doy - 80) / 365.0)


func sunrise_hour() -> float:
	return SOLAR_NOON_H - day_length_hours() * 0.5


func sunset_hour() -> float:
	return SOLAR_NOON_H + day_length_hours() * 0.5


func is_daylight() -> bool:
	var h := hour_float()
	return h >= sunrise_hour() and h <= sunset_hour()


## Nivel de luz 0..1 con amanecer y anochecer suaves (≈ 1 h).
func light_level() -> float:
	var h := hour_float()
	var rise := sunrise_hour()
	var sset := sunset_hour()
	var a := clampf((h - (rise - 0.5)) / 1.0, 0.0, 1.0)
	var b := clampf(((sset + 0.5) - h) / 1.0, 0.0, 1.0)
	return minf(a, b)


func format_date_es() -> String:
	const MESES := ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
		"agosto", "septiembre", "octubre", "noviembre", "diciembre"]
	var d := date_dict()
	return "%d de %s de %d, %02d:%02d" % [d["day"], MESES[int(d["month"]) - 1], d["year"], d["hour"], d["minute"]]


func to_dict() -> Dictionary:
	return {"start_unix": start_unix, "elapsed": elapsed}


func from_dict(d: Dictionary) -> void:
	start_unix = float(d.get("start_unix", 0.0))
	elapsed = float(d.get("elapsed", 0.0))
