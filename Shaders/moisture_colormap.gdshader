shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

// Six layers: right, left, top, bottom, front, back (CubeSphereMath / baker EXR order).
uniform sampler2DArray u_moistures : repeat_disable, filter_linear;
uniform float u_m_min = 0.0;
uniform float u_m_max = 450.0;

varying vec3 v_model_pos;


void vertex() {
	v_model_pos = VERTEX;
}


vec4 sample_moisture_cube(vec3 p) {
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

	return texture(u_moistures, vec3(clamp(uv, vec2(0.0), vec2(1.0)), layer));
}


vec3 moisture_to_color(float moisture_norm) {
	float t = clamp(moisture_norm, 0.0, 1.0);
	vec3 dry = vec3(0.82, 0.64, 0.38);
	vec3 mid = vec3(0.22, 0.62, 0.42);
	vec3 wet = vec3(0.08, 0.22, 0.72);
	if (t < 0.5) {
		return mix(dry, mid, t * 2.0);
	}
	return mix(mid, wet, (t - 0.5) * 2.0);
}


void fragment() {
	vec3 dir = normalize(v_model_pos);
	float m = sample_moisture_cube(dir).r;
	float span = max(u_m_max - u_m_min, 1e-6);
	float n = clamp((m - u_m_min) / span, 0.0, 1.0);
	ALBEDO = moisture_to_color(n);
}
