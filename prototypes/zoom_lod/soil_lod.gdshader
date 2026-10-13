shader_type canvas_item;
// Suelo por niveles de detalle (ADR-005). Se dibuja sobre un rectángulo del tamaño
// del mundo en píxeles de PANTALLA (640·Z × 240·Z), así que cada fragmento es un
// píxel de pantalla y cae en una subcelda: celda = píxel / Z, subcelda = píxel mod Z.
//
//  · ×1: copia exacta de la textura que pinta hoy SoilRenderer (bit a bit).
//  · ×2 y ×4: cada subcelda toma un tono de la paleta de su material con un hash
//    de sus coordenadas enteras (sin RNG ni TIME: determinista). En los bordes
//    entre materiales, un hash decide si la subcelda cae de un lado o del otro:
//    el borde queda irregular pero duro (sin degradados ni escalones de Z px).
//    La oclusión de las galerías se calcula a resolución de subcelda.
//
// mat_tex (RG8): R = material (SimConst.Mat; 255 = cielo sobre la superficie),
//                G = profundidad relativa (como SoilRenderer).

uniform sampler2D mat_tex : filter_nearest;
uniform sampler2D base_tex : filter_nearest;
uniform sampler2D pal_tex : filter_nearest;     // 4 tonos × 8 filas (0 = galería, 1..7 materiales)
uniform int zoom = 1;
uniform vec2 world_cells = vec2(640.0, 240.0);
uniform bool debug_texels = false;

const int SKY = 255;
const int AIR = 0;
const ivec2 NB[8] = ivec2[8](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1),
	ivec2(1, 1), ivec2(1, -1), ivec2(-1, 1), ivec2(-1, -1));

int mat_at(ivec2 c) {
	if (c.x < 0 || c.y < 0 || c.x >= int(world_cells.x) || c.y >= int(world_cells.y)) {
		return -1;
	}
	return int(texelFetch(mat_tex, c, 0).r * 255.0 + 0.5);
}

bool is_solid(int m) {
	return m != AIR && m != SKY && m != -1;
}

uint hash2(uvec2 p, uint salt) {
	uint h = p.x * 0x8da6b343u ^ p.y * 0xd8163841u ^ salt * 0xcb1ab31fu;
	h ^= h >> 13u;
	h *= 0x5bd1e995u;
	h ^= h >> 15u;
	return h;
}

vec3 pal(int row, uint idx) {
	return texelFetch(pal_tex, ivec2(int(idx & 3u), row), 0).rgb;
}

void fragment() {
	float z = float(zoom);
	ivec2 s = ivec2(floor(UV * world_cells * z));           // píxel de pantalla = subcelda
	ivec2 cell = s / zoom;
	vec4 outc;
	if (zoom == 1) {
		outc = texelFetch(base_tex, cell, 0);
	} else {
		ivec2 sub = s - cell * zoom;
		vec2 u = (vec2(sub) + 0.5) / z;                       // posición dentro de la celda (0..1)
		int m = mat_at(cell);
		uint h = hash2(uvec2(s), 1u);
		// Borde irregular: si un vecino tiene otro material y esta subcelda está a
		// menos de t (aleatorio por subcelda, hasta media celda) de ese lado, toma
		// el material del vecino. Gana el lado más cercano.
		float t = float(h & 255u) / 255.0 * 0.55;
		float best = 9.0;
		int mm = m;
		int mr = mat_at(cell + ivec2(1, 0));
		int ml = mat_at(cell + ivec2(-1, 0));
		int md = mat_at(cell + ivec2(0, 1));
		int mu = mat_at(cell + ivec2(0, -1));
		if (mr != m && mr != -1 && 1.0 - u.x < t && 1.0 - u.x < best) { best = 1.0 - u.x; mm = mr; }
		if (ml != m && ml != -1 && u.x < t && u.x < best) { best = u.x; mm = ml; }
		if (md != m && md != -1 && 1.0 - u.y < t && 1.0 - u.y < best) { best = 1.0 - u.y; mm = md; }
		if (mu != m && mu != -1 && u.y < t && u.y < best) { best = u.y; mm = mu; }
		float depth = texelFetch(mat_tex, cell, 0).g;
		if (mm == SKY || mm == -1) {
			outc = vec4(0.0);
		} else if (mm == AIR) {
			// Galería: sustrato claro tras el cristal con oclusión junto a las paredes,
			// medida desde el centro de la subcelda (gradiente fino, sin bloques de Z px).
			vec2 q = (vec2(s) + 0.5) / z;
			float n1 = 0.0;
			float n2 = 0.0;
			for (int k = 0; k < 8; k++) {
				if (is_solid(mat_at(ivec2(floor(q + vec2(NB[k])))))) { n1 += 1.0; }
			}
			if (is_solid(mat_at(ivec2(floor(q + vec2(2.0, 0.0)))))) { n2 += 1.0; }
			if (is_solid(mat_at(ivec2(floor(q + vec2(-2.0, 0.0)))))) { n2 += 1.0; }
			if (is_solid(mat_at(ivec2(floor(q + vec2(0.0, 2.0)))))) { n2 += 1.0; }
			if (is_solid(mat_at(ivec2(floor(q + vec2(0.0, -2.0)))))) { n2 += 1.0; }
			float f = 1.0 - 0.055 * n1 - 0.03 * n2 - 0.18 * depth;
			outc = vec4(pal(0, h >> 8u) * f, 1.0);
		} else {
			vec3 c = pal(mm, h >> 8u);
			uint g = (h >> 16u) & 15u;
			if (g == 0u) { c = mix(c, vec3(1.0), 0.08); }        // granos claros sueltos
			else if (g == 15u) { c *= 0.88; }                     // y oscuros
			float f2 = 1.0 - 0.12 * clamp(depth, 0.0, 1.0);
			// Pared cortada (junto a galería): más oscura; cara que da al cielo: más clara.
			int up = mat_at((s + ivec2(0, -1)) / zoom);
			bool edge = !is_solid(mat_at((s + ivec2(1, 0)) / zoom)) || !is_solid(mat_at((s + ivec2(-1, 0)) / zoom))
				|| !is_solid(mat_at((s + ivec2(0, 1)) / zoom)) || !is_solid(up);
			if (edge) {
				f2 *= (up == SKY) ? 1.12 : 0.82;
			}
			outc = vec4(c * f2, 1.0);
		}
	}
	if (debug_texels && outc.a > 0.0) {
		// Vista de depuración: tablero de 1 px. Si cada subcelda ocupa exactamente
		// un píxel de pantalla, se ve un tablero perfecto en los tres niveles.
		bool odd = ((s.x + s.y) & 1) == 1;
		outc.rgb = mix(outc.rgb, odd ? vec3(1.0, 0.2, 0.2) : vec3(0.2, 0.4, 1.0), 0.45);
	}
	COLOR = outc;
}
