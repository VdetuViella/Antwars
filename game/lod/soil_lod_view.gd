class_name SoilLodView
extends Node2D
## Suelo con detalle por niveles (ADR-005), con CACHÉ: el shader `soil_lod` pinta el
## mundo a ×Z dentro de un SubViewport que conserva lo dibujado. Al cambiar el zoom
## se repinta entero; cuando cambia el suelo, solo los rectángulos afectados
## (ampliados por la oclusión y los bordes). Cada fotograma solo se dibuja la
## textura, así que sin foco no hay trabajo extra (regla dura 7). A ×1 la imagen es
## la de SoilRenderer, que sigue siendo la fuente de la textura base y de los cambios.

const MAX_PATCHES := 8
const PATCH_MARGIN := 3                ## celdas: la oclusión y los bordes miran hasta 2 celdas

var world: SimWorld
var soil_ref: SoilRenderer
var zoom: int = 2
var mat_img: Image
var mat_tex: ImageTexture
var vp: SubViewport
var rect: ColorRect
var sprite: Sprite2D
var shader_mat: ShaderMaterial
var renders := 0                       ## repintados completos de la caché (pruebas)
var patch_renders := 0                 ## repintados parciales (pruebas)
var patches: Array[ColorRect] = []
var _pending: Array[Rect2i] = []
var _hide_patches := false
var _full_pending := false             ## repintado completo pedido; se hace en _process


func setup(w: SimWorld, soil_renderer: SoilRenderer) -> void:
	world = w
	soil_ref = soil_renderer
	soil_ref.visible = false
	soil_ref.redrawn.connect(_on_redrawn)
	mat_img = Image.create(w.soil.w, w.soil.h, false, Image.FORMAT_RG8)
	_write_mat(Rect2i(0, 0, w.soil.w, w.soil.h))
	mat_tex = ImageTexture.create_from_image(mat_img)
	shader_mat = ShaderMaterial.new()
	shader_mat.shader = load("res://game/shaders/soil_lod.gdshader")
	shader_mat.set_shader_parameter("mat_tex", mat_tex)
	shader_mat.set_shader_parameter("base_tex", soil_ref.tex)
	shader_mat.set_shader_parameter("pal_tex", palette_texture())
	shader_mat.set_shader_parameter("world_cells", Vector2(w.soil.w, w.soil.h))
	vp = SubViewport.new()
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	rect = ColorRect.new()
	rect.material = shader_mat
	vp.add_child(rect)
	for _k in MAX_PATCHES:
		var pr := ColorRect.new()
		pr.material = shader_mat.duplicate()
		pr.visible = false
		vp.add_child(pr)
		patches.append(pr)
	sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture = vp.get_texture()
	add_child(sprite)
	set_zoom(zoom)


func set_zoom(z: int) -> void:
	zoom = z
	var size := Vector2i(world.soil.w * z, world.soil.h * z)
	vp.size = size
	rect.position = Vector2.ZERO
	rect.size = Vector2(size)
	shader_mat.set_shader_parameter("zoom", z)
	for pr in patches:
		(pr.material as ShaderMaterial).set_shader_parameter("zoom", z)
	_request_full()


## Repintado completo (al crear la caché, cambiar de zoom o cambiar todo el suelo).
## Se aplaza a _process: si en el mismo fotograma llegaban parches, ocultaban la
## pantalla completa antes de que el SubViewport la pintara y la caché se quedaba
## con solo los parches (el suelo desaparecía tras la resolución offline).
func _request_full() -> void:
	_full_pending = true
	_pending.clear()


func _do_full() -> void:
	_full_pending = false
	_pending.clear()
	_hide_patches = false
	rect.visible = true
	for pr in patches:
		pr.visible = false
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	renders += 1


func _on_redrawn(rects: Array[Rect2i]) -> void:
	if rects.is_empty():
		_write_mat(Rect2i(0, 0, world.soil.w, world.soil.h))
		mat_tex.update(mat_img)
		_request_full()
		return
	for r in rects:
		_write_mat(r)
		if _full_pending:
			continue                   # el repintado completo ya lo cubre
		_pending.append(r.grow(PATCH_MARGIN).intersection(Rect2i(0, 0, world.soil.w, world.soil.h)))
	mat_tex.update(mat_img)


func _process(_delta: float) -> void:
	if _full_pending:
		_do_full()
		return
	if _hide_patches:
		# El repintado parcial ya se hizo en el fotograma anterior.
		_hide_patches = false
		for pr in patches:
			pr.visible = false
	if _pending.is_empty():
		return
	# Si hay demasiados trozos, se juntan en su rectángulo envolvente.
	var list := _pending
	_pending = []
	if list.size() > MAX_PATCHES:
		var u := list[0]
		for r in list:
			u = u.merge(r)
		list = [u]
	rect.visible = false
	var z := float(zoom)
	for k in patches.size():
		var pr := patches[k]
		if k >= list.size():
			pr.visible = false
			continue
		var r := list[k]
		pr.position = Vector2(r.position) * z
		pr.size = Vector2(r.size) * z
		var m := pr.material as ShaderMaterial
		m.set_shader_parameter("region_origin_px", Vector2(r.position) * z)
		m.set_shader_parameter("region_size_px", Vector2(r.size) * z)
		pr.visible = true
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	patch_renders += 1
	_hide_patches = true


## R = material (255 = cielo sobre la superficie), G = profundidad relativa.
func _write_mat(r: Rect2i) -> void:
	var soil := world.soil
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var m := soil.mat[y * soil.w + x]
			var sky := m == SimConst.Mat.AIR and y < soil.surface_h[x]
			var d := clampf(float(y - soil.surface_h[x]) / float(soil.h), 0.0, 1.0)
			mat_img.set_pixel(x, y, Color(1.0 if sky else float(m) / 255.0, d, 0.0))


static func palette_texture() -> ImageTexture:
	var pal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/palette.json"))
	var img := Image.create(4, 8, false, Image.FORMAT_RGBA8)
	var rows: Array = [pal["cavity"]]
	for m in range(1, 8):
		rows.append(pal["soil"][str(m)])
	for r in rows.size():
		for i in 4:
			var c: Array = rows[r][i]
			img.set_pixel(i, r, Color8(int(c[0]), int(c[1]), int(c[2])))
	return ImageTexture.create_from_image(img)
