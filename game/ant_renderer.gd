class_name AntRenderer
extends Node2D
## Dibuja todas las hormigas con un único MultiMesh (una llamada de dibujo) y
## lo que llevan en las mandíbulas con otro. Posiciones interpoladas entre
## pasos de comportamiento y ajustadas al píxel.

const CELL := 20
const ITEM := 8
const ROW_OF_CASTE := [0, 1, 2, 3]   # menor, media, mayor, reina (nanitic = fila 4)
# dir8 → (orientación base, volteo H, volteo V)
const DIR_MAP := [[0, 0, 0], [1, 0, 0], [2, 0, 0], [1, 1, 0], [0, 1, 0], [1, 1, 1], [2, 0, 1], [1, 0, 1]]
const DIR_VEC := [Vector2(1, 0), Vector2(0.7, -0.7), Vector2(0, -1), Vector2(-0.7, -0.7),
	Vector2(-1, 0), Vector2(-0.7, 0.7), Vector2(0, 1), Vector2(0.7, 0.7)]
const HEAD_REACH := [5.0, 6.0, 7.5, 9.0]   # distancia del centro a las mandíbulas por casta
const FEET := [3.0, 3.0, 3.0, 5.0]         # del centro del sprite a la base de las patas

var world: SimWorld
var ants_mmi: MultiMeshInstance2D
var items_mmi: MultiMeshInstance2D
var alpha: float = 0.0   ## fracción del paso de comportamiento (interpolación)
var _buf := PackedFloat32Array()
var _ibuf := PackedFloat32Array()


func setup(w: SimWorld) -> void:
	world = w
	var atlas: Texture2D = load("res://assets/sprites/ants.png")
	var items: Texture2D = load("res://assets/sprites/items.png")
	ants_mmi = _make_mmi(atlas, CELL, Vector2(float(CELL) / atlas.get_width(), float(CELL) / atlas.get_height()), w.ants.cap)
	items_mmi = _make_mmi(items, ITEM, Vector2(float(ITEM) / items.get_width(), float(ITEM) / items.get_height()), w.ants.cap)
	add_child(items_mmi)
	add_child(ants_mmi)
	move_child(items_mmi, 1)   # los objetos por encima de las hormigas


func _make_mmi(tex: Texture2D, cell: int, cell_uv: Vector2, count: int) -> MultiMeshInstance2D:
	var mesh := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	var h := float(cell) * 0.5
	arr[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance2D.new()
	mmi.multimesh = mm
	mmi.texture = tex
	mmi.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new()
	mat.shader = load("res://game/shaders/ants.gdshader")
	mat.set_shader_parameter("cell_uv", cell_uv)
	mmi.material = mat
	return mmi


func _process(_delta: float) -> void:
	if world == null:
		return
	var a := world.ants
	var nav := world.nav
	var n := 0
	var ni := 0
	# 12 floats por instancia: transform 2D (8) + custom (4)
	if _buf.size() != a.cap * 12:
		_buf.resize(a.cap * 12)
		_ibuf.resize(a.cap * 12)
	for i in a.cap:
		if a.alive[i] == 0:
			continue
		var x := lerpf(a.prev_px[i], a.px[i], alpha)
		var y := lerpf(a.prev_py[i], a.py[i], alpha)
		var c := a.caste[i]
		var row: int = 4 if (c == SimConst.Caste.MINOR and a.nanitic[i] == 1) else ROW_OF_CASTE[c]
		var dk := a.dir8[i]
		if nav.is_outworld(a.node[i]):
			# En la superficie: patas sobre el suelo (o la pila de tierra) y de perfil.
			var cx := clampi(int(x), 0, world.soil.w - 1)
			y = float(world.soil.col_top[cx]) - FEET[c]
			if dk == 1 or dk == 7:
				dk = 0
			elif dk == 3 or dk == 5:
				dk = 4
			elif dk == 2 or dk == 6:
				dk = 0 if a.hdir[i] == 1 else 4
		var d: Array = DIR_MAP[dk]
		var frame := int(a.anim[i]) & 3
		if a.state[i] == Ants.St.RESTING:
			frame = 1
		var o := n * 12
		_buf[o] = 1.0; _buf[o + 1] = 0.0; _buf[o + 2] = 0.0; _buf[o + 3] = floorf(x) + 0.5
		_buf[o + 4] = 0.0; _buf[o + 5] = 1.0; _buf[o + 6] = 0.0; _buf[o + 7] = floorf(y) + 0.5
		_buf[o + 8] = float(int(d[0]) * 4 + frame)
		_buf[o + 9] = float(row)
		_buf[o + 10] = float(d[1])
		_buf[o + 11] = float(d[2])
		n += 1
		var carry := a.carry[i]
		if carry != SimConst.Carry.NONE:
			var v: Vector2 = DIR_VEC[dk]
			var reach: float = HEAD_REACH[mini(c, 3)]
			var ix := floorf(x + v.x * reach) + 0.5
			var iy := floorf(y + v.y * reach + 1.0) + 0.5
			var oi := ni * 12
			_ibuf[oi] = 1.0; _ibuf[oi + 1] = 0.0; _ibuf[oi + 2] = 0.0; _ibuf[oi + 3] = ix
			_ibuf[oi + 4] = 0.0; _ibuf[oi + 5] = 1.0; _ibuf[oi + 6] = 0.0; _ibuf[oi + 7] = iy
			_ibuf[oi + 8] = float(carry - 1)
			_ibuf[oi + 9] = 0.0
			_ibuf[oi + 10] = 0.0
			_ibuf[oi + 11] = 0.0
			ni += 1
	var mm := ants_mmi.multimesh
	mm.buffer = _buf
	mm.visible_instance_count = n
	var im := items_mmi.multimesh
	im.buffer = _ibuf
	im.visible_instance_count = ni
