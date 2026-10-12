class_name TestCase
extends RefCounted
## Base mínima para tests headless (sin dependencias externas).
## Cada método que empieza por `test_` se ejecuta en una instancia nueva.

var failures: Array[String] = []
var current: String = ""


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append("%s: %s" % [current, msg])


func check_eq(a: Variant, b: Variant, msg: String = "") -> void:
	if a != b:
		failures.append("%s: %s (esperado %s, obtenido %s)" % [current, msg, str(b), str(a)])


func check_near(a: float, b: float, tol: float, msg: String = "") -> void:
	if absf(a - b) > tol:
		failures.append("%s: %s (esperado %.4f ± %.4f, obtenido %.4f)" % [current, msg, b, tol, a])


func check_range(a: float, lo: float, hi: float, msg: String = "") -> void:
	if a < lo or a > hi:
		failures.append("%s: %s (esperado en [%.3f, %.3f], obtenido %.3f)" % [current, msg, lo, hi, a])


## Partida nueva con fecha fija (12 de octubre de 2026) para tests reproducibles.
static func make_world(seed_v: int = 1234) -> SimWorld:
	var w := SimWorld.new()
	var start := float(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 10, "day": 12, "hour": 10, "minute": 0, "second": 0}))
	w.new_game(seed_v, start)
	return w
