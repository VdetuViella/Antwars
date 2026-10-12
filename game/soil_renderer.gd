class_name SoilRenderer
extends Sprite2D
## Pinta la rejilla de suelo en una textura (1 texel = 1 celda). Solo repinta
## los bloques de 8×8 que han cambiado, como mucho 10 veces por segundo.
## Las galerías se ven claras (el sustrato del fondo iluminado tras el cristal)
## para que las hormigas, casi negras, se distingan bien.

const M := SimConst.Mat
const BLOCK := 8

var world: SimWorld
var img: Image
var tex: ImageTexture
var pix := PackedByteArray()
var _timer := 0.0
var _dirty_blocks := {}

# Rampas de color por material (4 tonos, elegidos con ruido determinista).
const RAMPS := {
	M.TOPSOIL: [Color8(62, 42, 28), Color8(69, 48, 31), Color8(75, 53, 34), Color8(83, 59, 38)],
	M.SOIL: [Color8(91, 63, 40), Color8(99, 69, 48), Color8(107, 75, 51), Color8(115, 79, 54)],
	M.CLAY: [Color8(125, 90, 60), Color8(134, 98, 68), Color8(142, 105, 72), Color8(151, 112, 78)],
	M.LOOSE: [Color8(138, 106, 76), Color8(147, 115, 82), Color8(156, 123, 88), Color8(165, 132, 95)],
	M.ROCK: [Color8(85, 86, 90), Color8(94, 95, 99), Color8(104, 105, 109), Color8(114, 115, 120)],
	M.MIDDEN: [Color8(155, 138, 90), Color8(168, 148, 95), Color8(141, 122, 76), Color8(179, 159, 106)],
	M.PLUG: [Color8(110, 83, 56), Color8(118, 90, 61), Color8(126, 96, 66), Color8(102, 77, 52)],
}
const CAVITY := [Color8(196, 170, 132), Color8(201, 175, 137), Color8(191, 164, 126), Color8(198, 172, 134)]


func setup(w: SimWorld) -> void:
	world = w
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	img = Image.create(w.soil.w, w.soil.h, false, Image.FORMAT_RGBA8)
	pix.resize(w.soil.w * w.soil.h * 4)
	_full_redraw()
	tex = ImageTexture.create_from_image(img)
	texture = tex


static func _noise(x: int, y: int) -> int:
	var n := (x * 73856093) ^ (y * 19349663)
	n = (n ^ (n >> 13)) * 1274126177
	return (n >> 8) & 0xFF


func _cell_color(x: int, y: int) -> Color:
	var soil := world.soil
	var w := soil.w
	var m := soil.mat[y * w + x]
	var nz := _noise(x, y)
	if m == M.AIR:
		if y < soil.surface_h[x]:
			return Color(0, 0, 0, 0)  # outworld: transparente
		# Cavidad del nido: más oscura junto a las paredes (oclusión ambiental).
		var n1 := 0
		for k in 8:
			var xx: int = x + NavGrid.NB_DX[k]
			var yy: int = y + NavGrid.NB_DY[k]
			if soil.is_solid(xx, yy):
				n1 += 1
		var n2 := 0
		if soil.is_solid(x + 2, y): n2 += 1
		if soil.is_solid(x - 2, y): n2 += 1
		if soil.is_solid(x, y + 2): n2 += 1
		if soil.is_solid(x, y - 2): n2 += 1
		var base: Color = CAVITY[nz & 3]
		var depth := float(y - soil.surface_h[x]) / float(soil.h)
		var f := 1.0 - 0.055 * n1 - 0.03 * n2 - 0.18 * depth
		return Color(base.r * f, base.g * f, base.b * f, 1.0)
	var ramp: Array = RAMPS.get(m, RAMPS[M.SOIL])
	var c: Color = ramp[nz & 3]
	if (nz >> 4) == 0:
		c = c.lightened(0.08)   # granos claros sueltos
	elif (nz >> 4) == 15:
		c = c.darkened(0.12)
	var depth2 := float(y - soil.surface_h[x]) / float(soil.h)
	var f2 := 1.0 - 0.12 * clampf(depth2, 0.0, 1.0)
	# Borde de las galerías: la pared cortada se ve algo más oscura.
	if soil.is_air(x + 1, y) or soil.is_air(x - 1, y) or soil.is_air(x, y + 1) or soil.is_air(x, y - 1):
		if y >= soil.surface_h[x] or m == M.LOOSE or m == M.MIDDEN:
			# La cara superior del suelo (la que da al cielo) recibe luz.
			f2 *= 1.12 if soil.is_air(x, y - 1) and y - 1 < soil.surface_h[x] else 0.82
	return Color(c.r * f2, c.g * f2, c.b * f2, 1.0)


func _write(x: int, y: int) -> void:
	var c := _cell_color(x, y)
	var o := (y * world.soil.w + x) * 4
	pix[o] = int(c.r * 255.0)
	pix[o + 1] = int(c.g * 255.0)
	pix[o + 2] = int(c.b * 255.0)
	pix[o + 3] = int(c.a * 255.0)


func _full_redraw() -> void:
	var soil := world.soil
	for y in soil.h:
		for x in soil.w:
			_write(x, y)
	img.set_data(soil.w, soil.h, false, Image.FORMAT_RGBA8, pix)
	soil.full_dirty = false
	soil.dirty.clear()


func _process(delta: float) -> void:
	if world == null:
		return
	var soil := world.soil
	if soil.full_dirty:
		_full_redraw()
		tex.update(img)
		_dirty_blocks.clear()
		return
	for i in soil.consume_dirty():
		var bx := (i % soil.w) / BLOCK
		var by := (i / soil.w) / BLOCK
		_dirty_blocks[by * 1000 + bx] = true
	_timer -= delta
	if _timer > 0.0 or _dirty_blocks.is_empty():
		return
	_timer = 0.1
	for key: int in _dirty_blocks:
		var bx := key % 1000
		var by := key / 1000
		var x0 := maxi(bx * BLOCK - 2, 0)
		var y0 := maxi(by * BLOCK - 2, 0)
		var x1 := mini((bx + 1) * BLOCK + 2, soil.w)
		var y1 := mini((by + 1) * BLOCK + 2, soil.h)
		for y in range(y0, y1):
			for x in range(x0, x1):
				_write(x, y)
	_dirty_blocks.clear()
	img.set_data(soil.w, soil.h, false, Image.FORMAT_RGBA8, pix)
	tex.update(img)
