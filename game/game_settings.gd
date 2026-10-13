class_name GameSettings
extends RefCounted
## Preferencias del jugador (user://settings.cfg). No forman parte de la partida.

const PATH := "user://settings.cfg"

var window_mode: String = "ventana"     ## "ventana" | "franja"
var strip_height: int = 300
var always_on_top: bool = false
var time_scale_key: String = "acompanante"
var zoom: int = 2                       ## zoom manual (franja, o ventana sin ajuste automático)
var zoom_auto: bool = true              ## en modo ventana, el formicario crece con la ventana
var show_info: bool = true
var behaviour_speed: float = 1.0
var low_power_unfocused: bool = true
var window_pos: Vector2i = Vector2i(-1, -1)
## Detalle por niveles (ADR-005): zoom ×1/×2/×4 con detalle propio en cada paso.
## Apagado por defecto: con false el juego se ve y se comporta exactamente como antes.
var detail_levels_enabled: bool = false
var ant_px: int = 6                 ## largo de la obrera menor a ×1 en modo detalle (hay atlas de 5, 6, 7, 9 y 13)


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	window_mode = String(cf.get_value("ventana", "modo", window_mode))
	strip_height = int(cf.get_value("ventana", "alto_franja", strip_height))
	always_on_top = bool(cf.get_value("ventana", "siempre_encima", always_on_top))
	zoom = clampi(int(cf.get_value("ventana", "zoom", zoom)), 1, 8)
	zoom_auto = bool(cf.get_value("ventana", "zoom_auto", zoom_auto))
	window_pos = cf.get_value("ventana", "posicion", window_pos)
	time_scale_key = String(cf.get_value("juego", "escala_tiempo", time_scale_key))
	show_info = bool(cf.get_value("juego", "mostrar_info", show_info))
	behaviour_speed = float(cf.get_value("juego", "velocidad_hormigas", behaviour_speed))
	low_power_unfocused = bool(cf.get_value("rendimiento", "ahorro_sin_foco", low_power_unfocused))
	detail_levels_enabled = bool(cf.get_value("detalle", "niveles", detail_levels_enabled))
	ant_px = int(cf.get_value("detalle", "hormiga_px", ant_px))
	if not SimConst.TIME_SCALES.has(time_scale_key) and time_scale_key != "debug":
		time_scale_key = "acompanante"


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("ventana", "modo", window_mode)
	cf.set_value("ventana", "alto_franja", strip_height)
	cf.set_value("ventana", "siempre_encima", always_on_top)
	cf.set_value("ventana", "zoom", zoom)
	cf.set_value("ventana", "zoom_auto", zoom_auto)
	cf.set_value("ventana", "posicion", window_pos)
	cf.set_value("juego", "escala_tiempo", time_scale_key)
	cf.set_value("juego", "mostrar_info", show_info)
	cf.set_value("juego", "velocidad_hormigas", behaviour_speed)
	cf.set_value("rendimiento", "ahorro_sin_foco", low_power_unfocused)
	cf.set_value("detalle", "niveles", detail_levels_enabled)
	cf.set_value("detalle", "hormiga_px", ant_px)
	cf.save(PATH)


func time_scale() -> float:
	if time_scale_key == "debug":
		return 1000.0
	return float(SimConst.TIME_SCALES.get(time_scale_key, 24.0))
