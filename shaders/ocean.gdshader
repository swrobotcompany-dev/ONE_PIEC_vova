shader_type spatial;
render_mode cull_disabled, diffuse_burley;

// Only the nearest eight islands are tested. This keeps Compatibility fast.
uniform vec4 deep_blue : source_color = vec4(0.025, 0.17, 0.29, 1.0);
uniform vec4 turquoise : source_color = vec4(0.07, 0.48, 0.55, 1.0);
uniform vec4 land_masks[8];
varying vec3 ocean_world;
varying float shore_factor;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave_scale = 1.0;
	for (int i = 0; i < 8; i++) {
		if (land_masks[i].z < 1.0) { continue; }
		float d = length(w.xz - land_masks[i].xy);
		float edge = land_masks[i].z;
		wave_scale = min(wave_scale, smoothstep(edge - 8.0, edge + 12.0, d));
	}
	float wave = sin(w.x * 0.023 + TIME * 1.2) * 0.42
		+ cos(w.z * 0.031 + TIME * 1.7) * 0.28
		+ sin((w.x + w.z) * 0.058 + TIME * 2.2) * 0.11;
	VERTEX.y += wave * wave_scale;
	ocean_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	shore_factor = wave_scale;
}

void fragment() {
	// Land surface is above sea level. Remove the water pixels entirely
	// rather than drawing transparent water over beaches and buildings.
	for (int i = 0; i < 8; i++) {
		if (land_masks[i].z < 1.0) { continue; }
		float d = length(ocean_world.xz - land_masks[i].xy);
		if (d < land_masks[i].z) {
			float hill = pow(max(0.0, 1.0 - d / land_masks[i].z), 0.67) * land_masks[i].w;
			if (hill > 0.38) { discard; }
		}
	}
	float bands = sin(ocean_world.x * 0.048 + TIME * 1.1)
		* cos(ocean_world.z * 0.042 + TIME * 1.4);
	float ripples = sin(ocean_world.x * 0.23 + TIME * 3.2)
		* cos(ocean_world.z * 0.17 + TIME * 2.6);
	float foam = smoothstep(0.67, 1.0, bands * 0.28 + ripples * 0.72)
		* mix(0.2, 0.56, 1.0 - shore_factor);
	ALBEDO = mix(mix(deep_blue.rgb, turquoise.rgb, 0.49 + bands * 0.20),
		vec3(0.67, 0.91, 0.91), foam);
	ROUGHNESS = 0.33;
	METALLIC = 0.03;
	SPECULAR = 0.7;
}