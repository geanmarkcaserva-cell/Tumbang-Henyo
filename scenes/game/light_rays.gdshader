shader_type canvas_item;
render_mode blend_add, unshaded;
// Light rays (High quality): streams light out from the sun or moon across
// the screen. Each pixel walks toward the light's spot on screen and adds up
// the bright sky it passes; houses, posts and trees in between are dark, so
// they cut the light into shafts. See sky_bodies.gd.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 light_pos = vec2(0.5, 0.3); // the sun/moon on screen (0..1, may be off-screen)
uniform float aspect = 1.777;
uniform vec3 ray_color : source_color = vec3(1.0, 0.85, 0.6);
uniform float intensity = 0.8;
uniform float threshold = 0.6; // only brighter than this shines
uniform float decay = 0.965;
uniform float reach = 0.9; // how far toward the light each pixel looks (0..1)

const int SAMPLES = 40;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 step_uv = (uv - light_pos) * reach / float(SAMPLES);
	vec2 p = uv;
	float weight = 1.0;
	float acc = 0.0;
	for (int i = 0; i < SAMPLES; i++) {
		p -= step_uv;
		if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0) {
			weight *= decay;
			continue;
		}
		vec3 c = texture(screen_tex, p).rgb;
		float lum = dot(c, vec3(0.299, 0.587, 0.114));
		float bright = smoothstep(threshold, threshold + 0.25, lum);
		// Mostly from close around the light, not the whole sky.
		vec2 d = (p - light_pos) * vec2(aspect, 1.0);
		float near_light = 1.0 / (1.0 + dot(d, d) * 18.0);
		acc += bright * near_light * weight;
		weight *= decay;
	}
	acc = acc / float(SAMPLES) * 2.2;
	COLOR = vec4(ray_color * acc * intensity, 1.0);
}
