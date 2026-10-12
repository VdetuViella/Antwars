shader_type canvas_item;
// Selecciona la celda del atlas para cada instancia del MultiMesh.
// INSTANCE_CUSTOM = (columna, fila, volteo horizontal, volteo vertical)
uniform vec2 cell_uv = vec2(0.05, 0.2);

void vertex() {
	vec2 uv = UV;
	if (INSTANCE_CUSTOM.z > 0.5) { uv.x = 1.0 - uv.x; }
	if (INSTANCE_CUSTOM.w > 0.5) { uv.y = 1.0 - uv.y; }
	UV = (INSTANCE_CUSTOM.xy + uv) * cell_uv;
}
