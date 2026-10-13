class_name PheromoneOverlay
extends Sprite2D
## Capa de feromonas (tecla F). Verde = rastro de comida, cian = rastro pintado
## por ti, naranja = excavación. Además del color, el rastro pintado usa un
## patrón punteado para que se distinga sin depender del color.

var world: SimWorld
var img: Image
var tex: ImageTexture
var _t := 0.0


func setup(w: SimWorld) -> void:
	world = w
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scale = Vector2(SimConst.PHER_CELL, SimConst.PHER_CELL)
	img = Image.create(w.pher.pw, w.pher.ph, false, Image.FORMAT_RGBA8)
	tex = ImageTexture.create_from_image(img)
	texture = tex
	visible = false


## Detalle por niveles (ADR-005): 0 = dibujo clásico; 1, 2 o 4 = shader a
## resolución de pantalla (moteado fino a ×2 y ×4, bloques de 4 px a ×1 como hoy).
func set_lod_zoom(z: int) -> void:
	if z <= 0:
		material = null
		scale = Vector2(SimConst.PHER_CELL, SimConst.PHER_CELL)
		return
	var m := ShaderMaterial.new()
	m.shader = load("res://game/shaders/pheromone_lod.gdshader")
	m.set_shader_parameter("pher_tex", tex)
	m.set_shader_parameter("zoom", z)
	m.set_shader_parameter("world_cells", Vector2(world.soil.w, world.soil.h))
	m.set_shader_parameter("pher_cell", float(SimConst.PHER_CELL))
	material = m
	scale = Vector2(SimConst.PHER_CELL * z, SimConst.PHER_CELL * z)


func _process(delta: float) -> void:
	if not visible or world == null:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.4
	var p := world.pher
	for y in p.ph:
		for x in p.pw:
			var c := y * p.pw + x
			var food := clampf(p.read_cell(PheromoneField.Kind.FOOD, c) / 6.0, 0.0, 1.0)
			var mine := clampf(p.read_cell(PheromoneField.Kind.PLAYER, c) / 6.0, 0.0, 1.0)
			var dig := clampf(p.read_cell(PheromoneField.Kind.DIG, c) / 3.0, 0.0, 1.0)
			if (x + y) % 2 == 1:
				mine *= 0.35
			var a := maxf(food, maxf(mine, dig))
			if a < 0.02:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var col := Color(0.2, 0.95, 0.35) * food + Color(0.2, 0.85, 1.0) * mine + Color(1.0, 0.6, 0.15) * dig
			col = col / maxf(food + mine + dig, 0.001)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, 0.25 + 0.55 * a))
	tex.update(img)
