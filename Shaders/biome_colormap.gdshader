shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

// Six layers: right, left, top, bottom, front, back (CubeSphereMath / baker EXR order).
uniform sampler2DArray u_biomes : repeat_disable, filter_nearest;
uniform sampler2DArray u_heights : repeat_disable, filter_nearest;
uniform sampler2DArray u_flow_accumulation : repeat_disable, filter_nearest;
uniform float u_sea_level_m = 0.0;
uniform float u_river_flow_threshold = 500.0;

varying vec3 v_model_pos;


void vertex() {
	v_model_pos = VERTEX;
}


void dir_to_cube_layer_uv(vec3 p, out vec2 uv, out float layer) {
	vec3 a = abs(p);
	float denom;

	if (a.x >= a.y && a.x >= a.z) {
		denom = max(abs(p.x), 1e-8);
		if (p.x > 0.0) {
			layer = 0.0;
			uv = vec2(p.z / (2.0 * denom) + 0.5, 0.5 - p.y / (2.0 * denom));
		} else {
			layer = 1.0;
			uv = vec2(0.5 - p.z / (2.0 * denom), 0.5 - p.y / (2.0 * denom));
		}
	} else if (a.y >= a.x && a.y >= a.z) {
		denom = max(abs(p.y), 1e-8);
		if (p.y > 0.0) {
			layer = 2.0;
			uv = vec2(p.x / (2.0 * denom) + 0.5, 0.5 - p.z / (2.0 * denom));
		} else {
			layer = 3.0;
			uv = vec2(0.5 - p.x / (2.0 * denom), 0.5 - p.z / (2.0 * denom));
		}
	} else {
		denom = max(abs(p.z), 1e-8);
		if (p.z > 0.0) {
			layer = 4.0;
			uv = vec2(0.5 + p.y / (2.0 * denom), 0.5 - p.x / (2.0 * denom));
		} else {
			layer = 5.0;
			uv = vec2(0.5 - p.y / (2.0 * denom), 0.5 - p.x / (2.0 * denom));
		}
	}
	uv = clamp(uv, vec2(0.0), vec2(1.0));
}


vec3 biome_id_to_color(float id_raw) {
	int id = int(floor(id_raw + 0.5));
	// Tabletop-style flat palette; ids match ClimateSimulator.BiomeID order.
	// UI legend: DebugSidePanel populates BiomeLegendBox from the same RGB values.
	if (id == 0) {
		return vec3(0.72, 0.78, 0.82);
	}
	if (id == 1) {
		return vec3(0.18, 0.38, 0.28);
	}
	if (id == 2) {
		return vec3(0.69, 0.42, 0.24);
	}
	if (id == 3) {
		return vec3(0.35, 0.55, 0.22);
	}
	if (id == 4) {
		return vec3(0.12, 0.48, 0.42);
	}
	if (id == 5) {
		return vec3(0.85, 0.72, 0.38);
	}
	if (id == 6) {
		return vec3(0.72, 0.62, 0.28);
	}
	if (id == 7) {
		return vec3(0.24, 0.58, 0.24);
	}
	if (id == 8) {
		return vec3(0.05, 0.42, 0.22);
	}
	if (id == 9) {
		return vec3(0.88, 0.92, 0.96);
	}
	if (id == 10) {
		return vec3(0.08, 0.22, 0.48);
	}
	return vec3(0.5, 0.5, 0.52);
}


void fragment() {
	vec3 dir = normalize(v_model_pos);
	vec2 uv;
	float layer;
	dir_to_cube_layer_uv(dir, uv, layer);
	vec3 cube_uv_layer = vec3(uv, layer);

	float flow = texture(u_flow_accumulation, cube_uv_layer).r;
	float b_id = texture(u_biomes, cube_uv_layer).r;
	int biome_id = int(floor(b_id + 0.5));
	vec3 biome_col = biome_id_to_color(b_id);

	// Ocean/land split should follow biome classification output exactly.
	// This avoids coastline drift from independent elevation sampling/filtering.
	if (biome_id == 10) {
		ALBEDO = vec3(0.06, 0.14, 0.38);
	} else if (flow > u_river_flow_threshold) {
		// Keep rivers visible while still letting biome shifts read through.
		ALBEDO = mix(biome_col, vec3(0.12, 0.42, 0.82), 0.55);
	} else {
		ALBEDO = biome_col;
	}
}
