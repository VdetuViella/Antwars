class_name Journal
extends RefCounted
## Diario de la colonia («cuaderno de campo»). Guarda hitos y avisos con la
## fecha biológica en la que ocurrieron.

enum Level { INFO = 0, WARN = 1, CRITICAL = 2, MILESTONE = 3 }
const MAX_ENTRIES := 400

var entries: Array[Dictionary] = []     ## {day: float, date: String, text: String, level: int}
var flags: Dictionary = {}              ## hitos ya anunciados (no repetir)
var unread: int = 0


func add(day: float, date_text: String, text: String, level: int = Level.INFO) -> void:
	entries.append({"day": day, "date": date_text, "text": text, "level": level})
	if entries.size() > MAX_ENTRIES:
		entries.pop_front()
	unread += 1


## Añade la entrada solo la primera vez que ocurre el hito `flag`.
func once(flag: String, day: float, date_text: String, text: String, level: int = Level.MILESTONE) -> bool:
	if flags.has(flag):
		return false
	flags[flag] = true
	add(day, date_text, text, level)
	return true


## Avisos que pueden repetirse, pero no más de una vez cada `cooldown_days`.
func throttled(flag: String, cooldown_days: float, day: float, date_text: String, text: String, level: int = Level.WARN) -> bool:
	var last := float(flags.get(flag, -1.0e9))
	if day - last < cooldown_days:
		return false
	flags[flag] = day
	add(day, date_text, text, level)
	return true


func latest(n: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var start := maxi(0, entries.size() - n)
	for i in range(start, entries.size()):
		out.append(entries[i])
	return out


func to_dict() -> Dictionary:
	return {"entries": entries.duplicate(true), "flags": flags.duplicate(), "unread": unread}


func from_dict(d: Dictionary) -> void:
	entries.clear()
	for e: Dictionary in d.get("entries", []):
		entries.append(e.duplicate())
	flags = d.get("flags", {}).duplicate()
	unread = int(d.get("unread", 0))
