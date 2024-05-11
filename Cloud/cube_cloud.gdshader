shader_type spatial;
render_mode unshaded, depth_test_disabled;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;

uniform vec3 BOUND_SIZE = vec3(5);
uniform vec3 BaseColor = vec3(0.0, 0.5, 0.5);
uniform float LightAbsorption = 1.0;

varying vec3 world_position;

vec2 get_cube_penetration_distance(vec3 ray_origin, vec3 ray_direction, vec3 bound_center) {
	vec3 min_bound = bound_center - BOUND_SIZE / 2.0;
	vec3 max_bound = bound_center + BOUND_SIZE / 2.0;
	
	vec3 penetration_min_bound = (min_bound - ray_origin) / ray_direction;
	vec3 penetration_max_bound = (max_bound - ray_origin) / ray_direction;
	
	vec3 penetration_min = min(penetration_max_bound, penetration_min_bound);
	vec3 penetration_max = max(penetration_max_bound, penetration_min_bound);
	
	float entry_time = max(max(penetration_min.x, penetration_min.y), penetration_min.z);
	float exit_time = min(min(penetration_max.x, penetration_max.y), penetration_max.z);

	return vec2(entry_time, exit_time);
}

vec3 get_linear_depth(float raw_depth, vec2 screen_uv, mat4 inv_projection_matrix) {
    vec3 ndc = vec3(screen_uv * 2.0 - 1.0, raw_depth);
    vec4 hom_position_view_space = inv_projection_matrix * vec4(ndc, 1.0);
    return hom_position_view_space.xyz / hom_position_view_space.w;
}

void vertex() {
	// Called for every vertex the material is visible on.
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	float real_linear_depth = length(get_linear_depth(depth, SCREEN_UV, INV_PROJECTION_MATRIX));

    vec3 object_position_worldspace = (MODEL_MATRIX * vec4(vec3(0.0), 1.0)).xyz;

	vec3 ray_origin = CAMERA_POSITION_WORLD;
	vec3 ray_direction = -(INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz;

    vec2 cube_peneration_times = get_cube_penetration_distance(
        ray_origin, ray_direction, object_position_worldspace);

    float enter_time = cube_peneration_times.x;
    float exit_time = min(cube_peneration_times.y, real_linear_depth);
	
    float distance_in_medium = exit_time - enter_time;
	float transmittance = exp(-distance_in_medium * LightAbsorption);

	ALBEDO = BaseColor;
	ALPHA = (1.0 - transmittance) * step(enter_time, real_linear_depth);
}
