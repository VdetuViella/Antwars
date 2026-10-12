class_name SpeciesDef
extends RefCounted
## Definición de especie cargada desde data/species/<id>.json.
## Todos los números biológicos viven en el JSON, no en el código.

var id: String = ""
var data: Dictionary = {}


static func load_from_file(path: String) -> SpeciesDef:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "No se puede abrir la especie: %s" % path)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "JSON de especie inválido: %s" % path)
	var s := SpeciesDef.new()
	s.data = parsed
	s.id = String(parsed.get("id", ""))
	return s


static func load_by_id(species_id: String) -> SpeciesDef:
	return load_from_file("res://data/species/%s.json" % species_id)


func section(key: String) -> Dictionary:
	return data.get(key, {})


func num(sect: String, key: String, fallback: float = 0.0) -> float:
	return float(section(sect).get(key, fallback))


## Tasa de desarrollo relativa (0..1) en función de la temperatura del nido.
## Modelo de grados-día con meseta. 1.0 = desarrollo a temperatura óptima.
func dev_rate(temp_c: float) -> float:
	var d := section("development")
	var t_min := float(d.get("t_min_c", 16.0))
	var t_opt := float(d.get("t_opt_c", 26.0))
	var t_pl := float(d.get("t_plateau_end_c", 30.0))
	var t_let := float(d.get("t_lethal_c", 36.0))
	if temp_c <= t_min or temp_c >= t_let:
		return 0.0
	if temp_c < t_opt:
		return (temp_c - t_min) / (t_opt - t_min)
	if temp_c <= t_pl:
		return 1.0
	return clampf(1.0 - (temp_c - t_pl) / (t_let - t_pl), 0.0, 1.0)


## Días de desarrollo de una etapa a la temperatura óptima.
func stage_days_at_opt(stage: String) -> float:
	return float(section("development").get("days_at_opt", {}).get(stage, 10.0))


func speed_for_caste(caste: int) -> float:
	var sp: Dictionary = section("behaviour").get("speed", {})
	return float(sp.get(SimConst.CASTE_KEYS[caste], 12.0))


func consumption(key: String) -> float:
	return float(section("consumption_seeds_per_day").get(key, 0.05))


## Proporciones de castas para una nueva obrera según el tamaño de la colonia.
func caste_ratios(workers: int) -> Dictionary:
	var c := section("castes")
	if workers >= int(c.get("unlock_major_workers", 100)):
		return c.get("ratios_large", {"minor": 1.0})
	if workers >= int(c.get("unlock_media_workers", 50)):
		return c.get("ratios_medium", {"minor": 1.0})
	return c.get("ratios_small", {"minor": 1.0})
