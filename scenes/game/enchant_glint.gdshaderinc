// Minecraft-style enchantment glint: two layers of soft purple bands
// sliding diagonally at different angles and speeds, added on top.
uniform vec4 glint_color : source_color = vec4(0.62, 0.36, 1.0, 1.0);
uniform float glint_strength = 1.1;
uniform float glint_speed = 0.35;

float glint_layer(vec2 p, float angle, float t) {
	vec2 d = vec2(cos(angle), sin(angle));
	float x = dot(p, d) - t;
	float wide = pow(0.5 + 0.5 * sin(x * 6.2831), 6.0);
	float thin = pow(0.5 + 0.5 * sin(x * 17.0 + 1.3), 12.0);
	return wide * 0.8 + thin * 0.45;
}

// p: surface coordinates (roughly 0..3 across the item).
float glint(vec2 p, float time) {
	float t = time * glint_speed;
	return glint_layer(p, 0.65, t) + glint_layer(p * 1.35, 2.3, t * 0.7) * 0.7;
}
