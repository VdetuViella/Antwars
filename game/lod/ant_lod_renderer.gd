class_name AntLodRenderer
extends Node2D
## Hormigas con detalle por niveles (ADR-005). Un MultiMesh por casta con el atlas
## del nivel activo (×1 → L0, ×2 → L1, ×4 → L2) y otro para lo que llevan en las
## mandíbulas. El nodo no se escala: cada quad mide una celda del atlas en píxeles
## de pantalla y su posición se ajusta al píxel entero (pixel art puro).

const ANT_BASE_PX := 6                    ## largo por defecto de la obrera menor a ×1 (mm = px)
const BASES := [5, 6, 7, 9, 13]              ## atlas generados en assets/ants_lod/base<N>
const VARIANTS := ["menor", "media", "mayor", "reina", "nanitic"]   ## = filas de AntViewState
const ITEM_DIR := "res://assets/items_lod"

var world: SimWorld
var base_px: int = ANT_BASE_PX           ## GameSettings.ant_px; si no hay atlas de ese tamaño, el por defecto
var state := AntViewState.new()
var alpha: float = 0.0                    ## fracción del paso de comportamiento (interpolación)
var zoom: int = 2
var view_rect := Rect2()                  ## zona visible en coordenadas locales (descarte)
var atlases: Array[AntAtlas] = []
var mmis: Array[MultiMeshInstance2D] = []
var items_mmi: MultiMeshInstance2D
var items_tex: Array[Texture2D] = []
var items_cell := PackedInt32Array()
var _bufs: Array[PackedFloat32Array] = []
var _ibuf := PackedFloat32Array()
var _dt := 0.0


func setup(w: SimWorld) -> void:
	world = w
	state.setup(w.ants.cap)
	if not BASES.has(base_px):
		base_px = ANT_BASE_PX
	var dir := "res://assets/ants_lod/base%d" % base_px
	for vi in VARIANTS.size():
		var at := AntAtlas.new()
		at.load_variant(dir, VARIANTS[vi])
		atlases.append(at)
		state.feet_mm[vi] = at.feet_mm()
		state.stride_mm[vi] = at.stride_mm()
		var mmi := _make_mmi(load("res://game/shaders/ant_lod.gdshader"), w.ants.cap)
		(mmi.material as ShaderMaterial).set_shader_parameter("frames", float(at.columns()))
		state.idle_frames = at.idle_frames()
		add_child(mmi)
		mmis.append(mmi)
		_bufs.append(PackedFloat32Array())
	var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ITEM_DIR.path_join("items.json")))
	for lv: Dictionary in man["levels"]:
		items_tex.append(load(ITEM_DIR.path_join(String(lv["file"]))) as Texture2D)
		items_cell.append(int(lv["cell_px"]))
	items_mmi = _make_mmi(load("res://game/shaders/ants.gdshader"), w.ants.cap)
	add_child(items_mmi)           # por encima de las hormigas
	set_zoom(zoom)


func _make_mmi(shader: Shader, count: int) -> MultiMeshInstance2D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance2D.new()
	mmi.multimesh = mm
	mmi.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mmi.material = mat
	return mmi


static func _quad(cell: int) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	var h := float(cell) * 0.5
	arr[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func set_zoom(z: int) -> void:
	zoom = z
	for vi in VARIANTS.size():
		var at := atlases[vi]
		mmis[vi].texture = at.texture_for_zoom(z)
		mmis[vi].multimesh.mesh = _quad(at.cell_for_zoom(z))
	var lv := AntAtlas.LEVEL_OF_ZOOM.get(z, 0) as int
	items_mmi.texture = items_tex[lv]
	items_mmi.multimesh.mesh = _quad(items_cell[lv])
	var im := items_mmi.material as ShaderMaterial
	im.set_shader_parameter("cell_uv", Vector2(float(items_cell[lv]) / items_tex[lv].get_width(), 1.0))


func _process(delta: float) -> void:
	if world == null:
		return
	_dt = delta
	state.update(world, alpha, delta)
	var a := world.ants
	var z := float(zoom)
	var lv := AntAtlas.LEVEL_OF_ZOOM.get(zoom, 0) as int
	var icell := items_cell[lv]
	var counts := PackedInt32Array([0, 0, 0, 0, 0])
	for vi in VARIANTS.size():
		if _bufs[vi].size() != a.cap * 12:
			_bufs[vi].resize(a.cap * 12)
	if _ibuf.size() != a.cap * 12:
		_ibuf.resize(a.cap * 12)
	var ni := 0
	var vr := view_rect.grow(64.0)
	for i in a.cap:
		if a.alive[i] == 0:
			continue
		var row := AntViewState.row_of(a.caste[i], a.nanitic[i])
		var at := atlases[row]
		var cell := at.cell_for_zoom(zoom)
		var sp := state.draw_pos[i] * z
		if not vr.has_point(sp):
			continue
		var half := 0.5 if (cell % 2) == 1 else 0.0
		var tx := floorf(sp.x) + half
		var ty := floorf(sp.y) + half
		var o := counts[row] * 12
		_bufs[row][o] = 1.0; _bufs[row][o + 1] = 0.0; _bufs[row][o + 2] = 0.0; _bufs[row][o + 3] = tx
		_bufs[row][o + 4] = 0.0; _bufs[row][o + 5] = 1.0; _bufs[row][o + 6] = 0.0; _bufs[row][o + 7] = ty
		_bufs[row][o + 8] = float(state.dir[i]); _bufs[row][o + 9] = float(state.frame[i])
		_bufs[row][o + 10] = float(state.view[i]); _bufs[row][o + 11] = 0.0
		counts[row] += 1
		var carry := a.carry[i]
		if carry != SimConst.Carry.NONE:
			# La carga va en las mandíbulas: a `head_reach` del tórax en la dirección de marcha.
			var ang := deg_to_rad(float(state.dir[i]) * 22.5)
			var reach := float(at.manifest["levels"][lv]["head_reach_px"])
			var ip := sp + Vector2(cos(ang), sin(ang)) * reach
			var ih := 0.5 if (icell % 2) == 1 else 0.0
			var oi := ni * 12
			_ibuf[oi] = 1.0; _ibuf[oi + 1] = 0.0; _ibuf[oi + 2] = 0.0; _ibuf[oi + 3] = floorf(ip.x) + ih
			_ibuf[oi + 4] = 0.0; _ibuf[oi + 5] = 1.0; _ibuf[oi + 6] = 0.0; _ibuf[oi + 7] = floorf(ip.y) + ih
			_ibuf[oi + 8] = float(carry - 1); _ibuf[oi + 9] = 0.0; _ibuf[oi + 10] = 0.0; _ibuf[oi + 11] = 0.0
			ni += 1
	for vi in VARIANTS.size():
		var mm := mmis[vi].multimesh
		mm.buffer = _bufs[vi]
		mm.visible_instance_count = counts[vi]
	var imm := items_mmi.multimesh
	imm.buffer = _ibuf
	imm.visible_instance_count = ni
