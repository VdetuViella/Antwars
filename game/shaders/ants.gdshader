shader_type canvas_item;
// Selecciona la celda del atlas para cada instancia del MultiMesh y dibuja un
// contorno sutil de 1 px: cuando dos hormigas se solapan, el contorno de la de
// encima las separa y siguen leyéndose como individuos (pilar «pequeño pero nítido»).
// INSTANCE_CUSTOM = (columna, fila, volteo horizontal, volteo vertical)
uniform vec2 cell_uv = vec2(0.05, 0.2);
uniform vec4 outline_color : source_color = vec4(0.62, 0.52, 0.40, 0.55);
uniform bool use_outline = false;

varying vec2 cell_origin;

void vertex() {
	vec2 uv = UV;
	if (INSTANCE_CUSTOM.z > 0.5) { uv.x = 1.0 - uv.x; }
	if (INSTANCE_CUSTOM.w > 0.5) { uv.y = 1.0 - uv.y; }
	cell_origin = INSTANCE_CUSTOM.xy * cell_uv;
	UV = (INSTANCE_CUSTOM.xy + uv) * cell_uv;
}

float alpha_at(sampler2D tex, vec2 uv) {
	// Fuera de la celda propia no hay nada (evita leer la hormiga vecina del atlas).
	vec2 lo = cell_origin;
	vec2 hi = cell_origin + cell_uv;
	if (uv.x < lo.x || uv.y < lo.y || uv.x >= hi.x || uv.y >= hi.y) { return 0.0; }
	return texture(tex, uv).a;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (use_outline && c.a < 0.5) {
		vec2 px = TEXTURE_PIXEL_SIZE;
		float n = max(max(alpha_at(TEXTURE, UV + vec2(px.x, 0.0)), alpha_at(TEXTURE, UV - vec2(px.x, 0.0))),
			max(alpha_at(TEXTURE, UV + vec2(0.0, px.y)), alpha_at(TEXTURE, UV - vec2(0.0, px.y))));
		if (n > 0.5) { c = outline_color; }
	}
	COLOR = c;
}
