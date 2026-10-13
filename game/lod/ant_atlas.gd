class_name AntAtlas
extends RefCounted
## Carga una variante de hormiga según el contrato del atlas del ADR-005:
## manifiesto JSON + un PNG por nivel (filas = 16 direcciones cenitales y 16 de
## perfil; columnas = 8 fotogramas; fotograma 0 = reposo). El dibujo no sabe de
## dónde sale el arte (script, Blender o a mano).
##
## Los PNG se cargan como recursos importados (sin pérdida y sin mipmaps, como el
## resto de sprites; regla dura 5), lo que funciona igual en el editor y exportado.

const LEVEL_OF_ZOOM := {1: 0, 2: 1, 4: 2}

var manifest: Dictionary = {}
var textures: Array[Texture2D] = []      ## por nivel (0, 1, 2)
var cells: PackedInt32Array = PackedInt32Array()


func load_variant(dir: String, variant: String) -> bool:
	var path := dir.path_join("ant_%s.json" % variant)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("No se encuentra el manifiesto %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		push_error("Manifiesto inválido: %s" % path)
		return false
	manifest = parsed
	textures.clear()
	cells.clear()
	for lv: Dictionary in manifest["levels"]:
		textures.append(load(dir.path_join(String(lv["file"]))) as Texture2D)
		cells.append(int(lv["cell_px"][0]))
	return true


func level_for_zoom(zoom: int) -> int:
	return int(LEVEL_OF_ZOOM.get(zoom, 0))


func texture_for_zoom(zoom: int) -> Texture2D:
	return textures[level_for_zoom(zoom)]


func cell_for_zoom(zoom: int) -> int:
	return cells[level_for_zoom(zoom)]


## Del pivote (centro del tórax) al suelo, en mm de mundo (igual en todos los niveles).
func feet_mm() -> float:
	var lv: Dictionary = manifest["levels"][0]
	return float(lv["feet_px"]) / float(lv["zoom"])


func stride_mm() -> float:
	return float(manifest.get("stride_mm", 9.0))
