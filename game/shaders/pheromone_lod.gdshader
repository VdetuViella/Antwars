shader_type canvas_item;
// Feromonas por niveles (ADR-005). La rejilla de feromonas (4×4 mm por celda) se
// dibuja a resolución de pantalla: a ×1, bloques de 4×4 px como hoy; a ×2 y ×4,
// cada píxel se enciende según un umbral de ruido por hash (sin RNG ni TIME), así
// el rastro es un moteado fino en vez de bloques grandes.
uniform sampler2D pher_tex : filter_nearest;
uniform int zoom = 1;
uniform vec2 world_cells = vec2(640.0, 240.0);
uniform float pher_cell = 4.0;

uint hash2(uvec2 p) {
	uint h = p.x * 0x8da6b343u ^ p.y * 0xd8163841u ^ 0x2545f491u;
	h ^= h >> 13u;
	h *= 0x5bd1e995u;
	h ^= h >> 15u;
	return h;
}

void fragment() {
	ivec2 s = ivec2(floor(UV * world_cells * float(zoom)));
	ivec2 cell = s / zoom;
	vec4 c = texelFetch(pher_tex, ivec2(vec2(cell) / pher_cell), 0);
	if (zoom == 1) {
		COLOR = c;
	} else {
		float r = float(hash2(uvec2(s)) & 255u) / 255.0;
		COLOR = (r < c.a * 1.25) ? vec4(c.rgb, min(1.0, c.a + 0.2)) : vec4(0.0);
	}
}
