# Prototipo ADR-005 · Detalle por zoom (Fase 1)

Escena independiente: **no toca `sim/` ni la escena principal**. Usa `SoilGrid` y `SoilRenderer` solo como datos y referencia.

```bash
godot --path . res://prototypes/zoom_lod/zoom_lod.tscn                       # interactivo
godot --path . res://prototypes/zoom_lod/zoom_lod.tscn -- --zoom=4 --base=13 --captura=/tmp/x.png
```

| Tecla | Acción |
|---|---|
| + / − (o rueda) | Zoom ×1 · ×2 · ×4 (tope en los extremos, cambio instantáneo) |
| Flechas / botón derecho | Desplazar |
| B | Hormiga base de 9 px o de 13 px |
| S | Posición en píxel entero o subpíxel («fat pixel») |
| T | Tablero de depuración: 1 texel = 1 píxel |
| O | Contorno de las hormigas |
| V | Vista automática / siempre cenital / siempre perfil |
| P | Pausa |

**Argumentos** (detrás de `--`): `--zoom=1|2|4`, `--base=9|13`, `--subpixel`, `--debug`, `--view=auto|top|side`, `--centro=x,y`, `--tam=AnchoxAlto`, `--captura=ruta.png`, `--serie=N`.

**Piezas:**
- `soil_lod.gdshader`: suelo a resolución de pantalla. A ×1 copia exacta de `SoilRenderer`; a ×2 y ×4 usa subceldas con hash y bordes irregulares duros.
- `ant_lod.gdshader` y `ant_atlas.gd`: atlas según el contrato del ADR-005.
- `tools/gen_ant_atlas_3d.py`: renderizador 3D propio que genera los atlas en `assets/ants_lod/base9|13/`.
