shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

// Six layers: right, left, top, bottom, front, back (CubeSphereMath / baker EXR order).
uniform sampler2DArray u_temperatures : repeat_disable, filter_linear;
uniform float u_t_min = -50.0;
uniform float u_t_max = 40.0;

varying vec3 v_model_pos;


void vertex() {
	v_model_pos = VERTEX;
}


// Same cube-sphere sampling as elevation_grayscale.gdshader.
vec4 sample_temperature_cube(vec3 p) {
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
			uv = vec2(0.5 + p.y / (2.0 * denom), 0.5 - p.x / (2.0 * denom));
		} else {
			layer = 5.0;
			uv = vec2(0.5 - p.y / (2.0 * denom), 0.5 - p.x / (2.0 * denom));
		}
	}

	return texture(u_temperatures, vec3(clamp(uv, vec2(0.0), vec2(1.0)), layer));
}


vec3 temperature_to_color(float temp_norm) {
	float t = clamp(temp_norm, 0.0, 1.0);
	vec3 cold = vec3(0.06, 0.12, 0.85);
	vec3 mid = vec3(0.2, 0.85, 0.35);
	vec3 hot = vec3(0.95, 0.18, 0.08);
	if (t < 0.5) {
		return mix(cold, mid, t * 2.0);
	}
	return mix(mid, hot, (t - 0.5) * 2.0);
}


void fragment() {
	vec3 dir = normalize(v_model_pos);
	float temp = sample_temperature_cube(dir).r;
	float span = max(u_t_max - u_t_min, 0.001);
	float n = clamp((temp - u_t_min) / span, 0.0, 1.0);
	ALBEDO = temperature_to_color(n);
}
