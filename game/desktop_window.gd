class_name DesktopWindow
extends RefCounted
## Gestión de la ventana de escritorio: modo ventana normal y modo «franja»
## (sin bordes, transparente, pegada al borde inferior del área útil de la
## pantalla y con click-through en las zonas vacías).
## Limitaciones conocidas: en Wayland el click-through puede no funcionar
## (ver docs/adr/ADR-004-ventana-escritorio.md).

const WINDOW_SIZE := Vector2i(1280, 560)


static func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


static func apply_window_mode(on_top: bool, pos: Vector2i) -> void:
	if is_headless():
		return
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, on_top)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(WINDOW_SIZE)
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var p := pos
	if p.x < 0 or not usable.has_point(p):
		p = usable.position + (usable.size - WINDOW_SIZE) / 2
	DisplayServer.window_set_position(p)


## Coloca la ventana como franja en la parte inferior. Devuelve su tamaño.
static func apply_strip_mode(height: int, on_top: bool) -> Vector2i:
	if is_headless():
		return Vector2i(1920, height)
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var size := Vector2i(usable.size.x, clampi(height, 160, usable.size.y / 2))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, on_top)
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(Vector2i(usable.position.x, usable.position.y + usable.size.y - size.y))
	return size


static func set_click_region(poly: PackedVector2Array) -> void:
	if is_headless():
		return
	DisplayServer.window_set_mouse_passthrough(poly)


static func set_on_top(on_top: bool) -> void:
	if is_headless():
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, on_top)
