shader_type canvas_item;
// Hormigas por nivel (ADR-005): cada instancia del MultiMesh elige su celda del atlas.
// INSTANCE_CUSTOM = (dirección 0..15, columna 0..frames-1, vista 0 = cenital / 1 = perfil, reservado).
// Columnas: 0..7 marcha, 8..15 reposo animado (si el atlas las trae).
// El quad mide exactamente una celda en píxeles de pantalla: 1 texel = 1 píxel.
uniform float frames = 8.0;             // columnas del atlas (AntAtlas.columns())
uniform float rows = 32.0;              // 16 direcciones × 2 vistas
uniform bool subpixel = false;          // muestreo «fat pixel» (comparación de la Fase 1)
uniform bool use_outline = true;
uniform vec4 outline_color : source_color = vec4(0.62, 0.52, 0.40, 0.55);
uniform bool debug_texels = false;

varying vec2 cell_origin;
varying vec2 cell_size;

void vertex() {
	cell_size = vec2(1.0 / frames, 1.0 / rows);
	cell_origin = vec2(INSTANCE_CUSTOM.y, INSTANCE_CUSTOM.z * 16.0 + INSTANCE_CUSTOM.x) * cell_size;
	UV = cell_origin + UV * cell_size;
}

float alpha_at(sampler2D tex, vec2 uv) {
	if (uv.x < cell_origin.x || uv.y < cell_origin.y || uv.x >= cell_origin.x + cell_size.x || uv.y >= cell_origin.y + cell_size.y) {
		return 0.0;
	}
	return texture(tex, uv).a;
}

void fragment() {
	vec2 uv = UV;
	if (subpixel) {
		// Antialiasing analítico de pixel art: nítido dentro del texel, mezcla de un
		// píxel en las costuras (requiere filtro lineal en el nodo).
		vec2 tsize = 1.0 / TEXTURE_PIXEL_SIZE;
		vec2 px = uv * tsize;
		vec2 seam = floor(px + 0.5);
		vec2 d = fwidth(px);
		px = seam + clamp((px - seam) / max(d, vec2(1e-4)), -0.5, 0.5);
		uv = px / tsize;
	}
	vec4 c = texture(TEXTURE, uv);
	if (use_outline && !subpixel && c.a < 0.5) {
		vec2 p = TEXTURE_PIXEL_SIZE;
		float n = max(max(alpha_at(TEXTURE, uv + vec2(p.x, 0.0)), alpha_at(TEXTURE, uv - vec2(p.x, 0.0))),
			max(alpha_at(TEXTURE, uv + vec2(0.0, p.y)), alpha_at(TEXTURE, uv - vec2(0.0, p.y))));
		if (n > 0.5) { c = outline_color; }
	}
	if (debug_texels && c.a > 0.0) {
		ivec2 t = ivec2(floor(uv / TEXTURE_PIXEL_SIZE));
		bool odd = ((t.x + t.y) & 1) == 1;
		c.rgb = mix(c.rgb, odd ? vec3(1.0, 0.2, 0.2) : vec3(0.2, 0.4, 1.0), 0.5);
	}
	COLOR = c;
}
