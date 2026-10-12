shader_type canvas_item;
// Lupa: amplía la zona bajo el ratón muestreando la pantalla (píxeles nítidos).
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec2 center_uv = vec2(0.5);
uniform vec2 screen_px = vec2(1280.0, 560.0);
uniform float zoom = 3.0;
uniform float radius_px = 72.0;

void fragment() {
	vec2 d_px = (SCREEN_UV - center_uv) * screen_px;
	float r = length(d_px);
	if (r > radius_px + 3.0) {
		discard;
	}
	if (r > radius_px) {
		COLOR = vec4(0.93, 0.89, 0.78, 1.0);
	} else if (r > radius_px - 1.5) {
		COLOR = vec4(0.25, 0.2, 0.16, 1.0);
	} else {
		vec2 uv = center_uv + (SCREEN_UV - center_uv) / zoom;
		vec4 c = texture(screen_tex, uv);
		// leve viñeta para dar sensación de lente
		float v = 1.0 - 0.18 * smoothstep(radius_px * 0.6, radius_px, r);
		COLOR = vec4(c.rgb * v, 1.0);
	}
}
