# ADR-004 — Ventana de escritorio: modo ventana y modo franja

- **Estado:** aceptada
- **Fecha:** 2026-10-12

## Decisión

Hay dos modos (tecla F11 o el botón *Franja*/*Ventana*):

- **Ventana:** ventana normal de 1280×560 con bordes y la pared de la habitación de fondo. La posición se recuerda entre sesiones. Al redimensionarla (señal `size_changed` del viewport) el formicario usa el mayor zoom entero que cabe y queda centrado sobre una balda.
- **Franja:** ventana sin bordes, con fondo transparente por píxel, del ancho del área útil del monitor y unos 300 px de alto, pegada al borde inferior (respeta la barra de tareas mediante `screen_get_usable_rect`). Las zonas vacías dejan pasar los clics a las aplicaciones de debajo con `DisplayServer.window_set_mouse_passthrough(polígono)`. El polígono (formicario y barra de herramientas) se recalcula una vez por segundo.

«Siempre encima» es opcional y está **desactivado por defecto**, para no tapar ventanas a pantalla completa.

## Bajo consumo

Cuando la ventana pierde el foco (`NOTIFICATION_APPLICATION_FOCUS_OUT`): `Engine.max_fps = 10`, `OS.low_processor_usage_mode = true` y la simulación pasa a pasos de comportamiento de 0,5 s. La biología no se ve afectada porque va por su propio reloj. Al recuperar el foco se restaura todo. Los proyectos exportados de Godot no limitan los FPS sin foco por sí solos, así que hay que hacerlo a mano.

## Limitaciones conocidas

- **Wayland:** el click-through y la posición de la ventana pueden no funcionar; en ese caso se usa el modo ventana.
- **macOS:** pendiente de probar el click-through con transparencia.
- **Windows:** el `per_pixel_transparency` necesita el renderizador de compatibilidad (OpenGL), que es el que usa el proyecto.
