shader_type spatial;
render_mode unshaded, depth_test_disabled;

uniform int MAX_STEPS = 100;
uniform float MAX_DIST = 100.0;
uniform float SURF_DIST = 0.01;
uniform float SMOOTHNESS = 0.1;

float union_quadratic( float a, float b, float k ) {
    k *= 4.0;
    float h = max( k-abs(a-b), 0.0 )/k;
    return min(a,b) - h*h*k*(1.0/4.0);
}

float signed_distance_sphere(vec3 point, vec3 sphere_center, float radius) {
	return length(sphere_center - point) - radius;
}

float get_distance_to_world(vec3 point) {
	vec3 spheres_pos[3] = vec3[](
		vec3(0.5, 0.7, 1.0),
		vec3(0.5, 0.2, -0.5),
		vec3(1, 1.1, 0.5)
	);
	float spheres_radius[3] = float[](.5, 1.0, 0.6);
	
	float dist = MAX_DIST;

	for (int i = 0; i < 3; i++) {
		vec3 noisy_movement = vec3(
			sin(0.5 + TIME * 0.2 * (float(i)+1.0)),
			cos(0.5 + TIME * 0.5 * (float(i)+1.0)),
			sin(0.5 + TIME * 1.0 * (float(i)+1.0))	
		);
		
		vec3 sphere_pos_with_movement = spheres_pos[i] + noisy_movement;
		float distance_to_i_sphere = signed_distance_sphere(point, sphere_pos_with_movement, spheres_radius[i]);
		dist = union_quadratic(dist, distance_to_i_sphere, SMOOTHNESS);
	}
		
	return dist;
}

vec3 get_normal(vec3 point) {
	float distance_to_world = get_distance_to_world(point);
	vec2 error = vec2(0.01, 0.0);
	vec3 normal = distance_to_world - vec3(
		get_distance_to_world(point - error.xyy),
		get_distance_to_world(point - error.yxy),
		get_distance_to_world(point - error.yyx)
	);
	return normalize(normal);
}

float ray_march(vec3 ray_origin, vec3 ray_direction) {
	float marching_distance = 0.0;
	
	for (int i = 0; i < MAX_STEPS; i++) {
		vec3 current_position = ray_origin + ray_direction * marching_distance;
		float distance_to_closest_object = get_distance_to_world(current_position);
		
		marching_distance += distance_to_closest_object;
		
		bool is_far_from_origin = marching_distance >= MAX_DIST;
		bool is_step_too_small = distance_to_closest_object <= SURF_DIST;
		if (is_far_from_origin || is_step_too_small) break;
	}
	
	return marching_distance;
}

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	// Called for every pixel the material is visible on.
	vec3 position_worldspace = ((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vec3 ray_origin = CAMERA_POSITION_WORLD;
	vec3 ray_direction = normalize(position_worldspace - ray_origin);
	
	float ray_distance = ray_march(ray_origin, ray_direction);
	
	ALPHA = step(ray_distance, MAX_DIST);
	
	vec3 normal = get_normal(ray_origin + ray_direction * ray_distance);
	ALBEDO = (normal + 1.0) / 2.0;
}
