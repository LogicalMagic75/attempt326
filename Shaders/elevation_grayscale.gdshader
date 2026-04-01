shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

// Six layers: right, left, top, bottom, front, back (CubeSphereMath / baker face order).
uniform sampler2DArray u_heights : repeat_disable, filter_linear;
uniform float u_h_min = -11000.0;
uniform float u_h_max = 8850.0;

varying vec3 v_model_pos;


void vertex() {
	v_model_pos = VERTEX;
}


// Inverse of face_uv01_to_unit_direction (planet / baker); matches CubeSphereMath.unit_direction_to_face_uv01.
vec4 sample_height_cube(vec3 p) {
	vec3 a = abs(p);
	vec2 uv;
	float layer;
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
			// Matches face_uv01 FRONT: cube (-2*(v-0.5), 2*(u-0.5), 1).
			uv = vec2(0.5 + p.y / (2.0 * denom), 0.5 - p.x / (2.0 * denom));
		} else {
			layer = 5.0;
			uv = vec2(0.5 - p.y / (2.0 * denom), 0.5 - p.x / (2.0 * denom));
		}
	}

	return texture(u_heights, vec3(clamp(uv, vec2(0.0), vec2(1.0)), layer));
}


void fragment() {
	vec3 dir = normalize(v_model_pos);
	float h = sample_height_cube(dir).r;

	// Elevation split at sea level:
	// <= 0 m: ocean ramp (black -> blue), > 0 m: land ramp (orange -> white).
	if (h <= 0.0) {
		float denom_lo = max(0.0 - u_h_min, 1.0);
		float t_lo = clamp((h - u_h_min) / denom_lo, 0.0, 1.0);
		vec3 ocean_low = vec3(0.0, 0.0, 0.0);
		vec3 ocean_high = vec3(0.0, 0.0, 1.0);
		ALBEDO = mix(ocean_low, ocean_high, t_lo);
	} else {
		float denom_hi = max(u_h_max - 0.0, 1.0);
		float t_hi = clamp(h / denom_hi, 0.0, 1.0);
		vec3 land_low = vec3(1.0, 0.5, 0.0);
		vec3 land_high = vec3(1.0, 1.0, 1.0);
		ALBEDO = mix(land_low, land_high, t_hi);
	}
}
