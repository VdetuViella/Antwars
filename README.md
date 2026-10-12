# AntWars

Un formicario de *Messor barbarus* que vive en tu escritorio. Las hormigas deciden solas —excavan, forrajean, crían, muelen semillas— y tú eres el cuidador: rellenas el comedero y el agua, regulas el calor y empujas a la colonia con prioridades y rastros de feromona. Puedes dejarlo en una franja al pie de la pantalla mientras trabajas; con el juego cerrado la colonia sigue viviendo y al volver te cuenta qué ha pasado.

Biología real: fundación claustral, nanitics, castas por tamaño de colonia, desarrollo según la temperatura, diapausa invernal, granero y molienda (ver `docs/BIOLOGIA.md`).

## Jugar
- **Ejecutable:** abre `AntWars.exe` (Windows). La partida se guarda sola en `%APPDATA%\Godot\app_userdata\AntWars\`.
- **Desde el código:** abre la carpeta con [Godot 4.7](https://godotengine.org/download) (versión estándar, no hace falta .NET) y pulsa F5.

| Tecla | Acción |
|---|---|
| 1 / 2 / 3 | Tiempo real ×1 · acompañante ×24 (un día por hora) · acelerado ×96 |
| F · L · I · J · H | Feromonas · lupa · información · diario · ayuda |
| F11 | Alternar ventana y franja |
| Rueda / botón derecho | Desplazarse |
| + / − · 0 | Zoom manual · zoom automático (se ajusta a la ventana) |

## Estado
Vertical slice de *Messor barbarus* en curso (ver `docs/ROADMAP.md`). Lo siguiente: vuelo nupcial y prestigio con los dos linajes genéticos de *M. barbarus*.

## Documentación
`docs/GDD.md` · `docs/SIMULACION.md` · `docs/BIOLOGIA.md` · `docs/ARQUITECTURA.md` · `docs/ARTE_Y_AUDIO.md` · `docs/MERCADO.md` · `docs/ROADMAP.md` · `docs/GLOSARIO.md` · `docs/adr/` · `CLAUDE.md` (guía para el agente programador).
