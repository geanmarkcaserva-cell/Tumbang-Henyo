shader_type spatial;
// One cloud on the sky dome (SkyBodies). The cloud pictures are plain white
// shapes; this lights them like a sunset: a dark body with a glowing rim on
// the edges facing the sun (or the moon), brighter on the clouds near it.
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 body_color : source_color = vec4(0.86, 0.82, 0.86, 1.0); // the cloud's shaded bulk
uniform vec4 lit_color : source_color = vec4(1.0, 0.9, 0.7, 1.0); // the sunlit edges
uniform float opacity = 0.9;
uniform float sun_near = 0.0; // 1 = the sun is right behind this cloud, 0 = opposite side of the sky
uniform float sun_side = 0.0; // -1 = the sun is off to its left, 1 = to its right
uniform float rim_width = 0.03; // how deep the lit edge reaches into the cloud (in picture widths)

void fragment() {
	float a = texture(tex, UV).a;
	// Toward the light: down (the sun is low) and a little toward its side.
	vec2 to_light = normalize(vec2(sun_side * 0.8, 1.0));
	// How much cloud sits between this point and the light.
	float cover = 0.0;
	for (int i = 1; i <= 5; i++) {
		cover += texture(tex, UV + to_light * rim_width * float(i)).a;
	}
	cover /= 5.0;
	float rim = clamp((a - cover) * 1.8 + 0.08, 0.0, 1.0);
	// Clouds near the sun glow all over; away from it only their edges catch light.
	float lit = clamp(rim * (0.35 + 0.65 * sun_near) + sun_near * sun_near * 0.35, 0.0, 1.0);
	ALBEDO = mix(body_color.rgb, lit_color.rgb, lit);
	ALPHA = a * opacity;
}
