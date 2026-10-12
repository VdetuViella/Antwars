class_name SaveSystem
extends RefCounted
## Guardado versionado, comprimido y atómico con copias de seguridad rotativas.
## Formato: cabecera de 8 bytes "ANTW" + versión (u32) y después el
## diccionario de la partida serializado con var_to_bytes y comprimido (zstd).

const MAGIC := "ANTW"
const DEFAULT_PATH := "user://antwars_save.dat"
const BACKUPS := 3


static func save(world: SimWorld, path: String = DEFAULT_PATH, real_unix: float = -1.0) -> Error:
	var d := world.to_dict()
	d["saved_at_real"] = real_unix if real_unix >= 0.0 else Time.get_unix_time_from_system()
	var payload := var_to_bytes(d)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(MAGIC.to_ascii_buffer())
	f.store_32(SimWorld.SAVE_VERSION)
	f.store_32(payload.size())
	var packed := payload.compress(FileAccess.COMPRESSION_ZSTD)
	f.store_32(packed.size())
	f.store_buffer(packed)
	f.store_32(hash(packed) & 0xFFFFFFFF)
	f.close()
	# Rotar copias: .bak2 → .bak3, .bak1 → .bak2, actual → .bak1
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return ERR_CANT_OPEN
	for k in range(BACKUPS - 1, 0, -1):
		var src := "%s.bak%d" % [path, k]
		if FileAccess.file_exists(src):
			dir.rename(src, "%s.bak%d" % [path, k + 1])
	if FileAccess.file_exists(path):
		dir.rename(path, path + ".bak1")
	return dir.rename(tmp, path)


## Lee una partida. Devuelve {} si no existe o está dañada (prueba las copias).
static func load_dict(path: String = DEFAULT_PATH) -> Dictionary:
	for candidate in [path, path + ".bak1", path + ".bak2", path + ".bak3"]:
		var d := _read(candidate)
		if not d.is_empty():
			if candidate != path:
				d["_recovered_from"] = candidate
			return migrate(d)
	return {}


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 20:
		return {}
	var magic := f.get_buffer(4).get_string_from_ascii()
	if magic != MAGIC:
		return {}
	var _version := f.get_32()
	var raw_size := f.get_32()
	var packed_size := f.get_32()
	if packed_size <= 0 or packed_size > f.get_length():
		return {}
	var packed := f.get_buffer(packed_size)
	var crc := f.get_32()
	if (hash(packed) & 0xFFFFFFFF) != crc:
		return {}
	var payload := packed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if payload.size() != raw_size:
		return {}
	var v: Variant = bytes_to_var(payload)
	return v if v is Dictionary else {}


## Migraciones de formato. Cada cambio de esquema añade un paso aquí + test.
static func migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 1))
	# if v < 2: d = _v1_to_v2(d); v = 2
	d["version"] = v
	return d


static func exists(path: String = DEFAULT_PATH) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak1")


static func delete_all(path: String = DEFAULT_PATH) -> void:
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return
	for p in [path, path + ".tmp", path + ".bak1", path + ".bak2", path + ".bak3"]:
		if FileAccess.file_exists(p):
			dir.remove(p.get_file())
