shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;

// Grasbüschel: Farbverlauf von der Wurzel zur Spitze und Wind
uniform vec3 base_color : source_color = vec3(0.16, 0.24, 0.11);
uniform vec3 tip_color : source_color = vec3(0.46, 0.56, 0.26);
uniform vec3 dry_color : source_color = vec3(0.55, 0.52, 0.28);
uniform float wind_strength = 0.12;
uniform float night = 0.0;

varying float tip;
varying float dry;

void vertex() {
	tip = UV.y;
	dry = INSTANCE_CUSTOM.r;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * 1.7 + wp.x * 0.21 + wp.z * 0.17;
	float bend = tip * tip;
	VERTEX.x += sin(t) * wind_strength * bend;
	VERTEX.z += cos(t * 0.83) * wind_strength * 0.6 * bend;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec3 tipc = mix(tip_color, dry_color, dry);
	ALBEDO = mix(base_color, tipc, tip);
	ROUGHNESS = 0.95;
	BACKLIGHT = vec3(0.15) * tip;
}
