shader_type spatial;
render_mode unshaded, depth_test_disabled;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;
uniform sampler3D NOISE_TEXTURE : source_color, repeat_enable, filter_linear;
uniform sampler3D HIGH_FREQUENCY_NOISE_TEXTURE: source_color, repeat_enable, filter_linear;

uniform sampler2D CLOUD_TEXTURE : source_color, repeat_enable, filter_linear;

uniform vec3 BOUND_SIZE = vec3(10);
uniform float NoiseScale = 5.0;

// Used for Henyey-Greenstein phase function
// -1 is strong backwards propagation
// 1 is strong forward propagation
uniform float LightingAsymmetry : hint_range(-1.0, 1.0) = 1.0;

uniform vec3 VolumeColor : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 AmbientColor : source_color = vec3(0.0, 0.5, 0.5);
uniform vec3 LightColor : source_color = vec3(0.0, 0.5, 0.5);

uniform float AmbientAbsorption = 1.0;
uniform float LightAbsorption = 1.0;

uniform float CloudType : hint_range(0.0, 1.0) = 0.0;
uniform float GlobalCoverage : hint_range(0.0, 1.0) = 0.0;
uniform float HighFrequencyNoiseScale : hint_range(1.0, 10.0) = 1.0;
uniform float HighFrequencyNoiseScaleErosure : hint_range(0.0, 1.0) = 0.2;

uniform vec3 WindVelocity = vec3(0.0, 0.0, 0.0);
uniform float WindHeightSkew : hint_range(0.0, 10.0) = 0.0;
uniform float AnvilBias : hint_range(0.0, 1.0) = 0.0;

uniform vec3 LightDirection;

varying vec3 world_position;

const int NUM_SAMPLES = 128;
const int NUM_LIGHT_SAMPLES = 5;

const vec3 STRATUS_GRADIENT = vec3(0.1, 0.2, 0.3);
const vec3 STRATOCUMULUS_GRADIENT = vec3(0.4, 0.4, 0.6);
const vec3 CUMULUS_GRADIENT = vec3(0.2, 0.6, 1.0);

float remap(float t, float a, float b, float c, float d) { return c + (d - c) * (t - a) / (b - a); }
float saturate(float t) { return clamp(t, 0.0, 1.0); }
float evaluate_cloud(float height, vec3 gradient) { return remap(height, 0.0, gradient.x, 0.0, 1.0) * remap(height, gradient.y, gradient.z, 1.0, 0.0); }

float get_density_multiplier_by_cloud_type(vec3 uv, float cloud_type) {
    float stratus = 1.0 - saturate(cloud_type * 2.0);
	float stratocumulus = 1.0f - abs(cloud_type - 0.5) * 2.0;
	float cumulus = saturate(cloud_type - 0.5) * 2.0;

    float stratus_value = evaluate_cloud(uv.y, STRATUS_GRADIENT);
    float stratocumulus_value = evaluate_cloud(uv.y, STRATOCUMULUS_GRADIENT);
    float cumulus_value = evaluate_cloud(uv.y, CUMULUS_GRADIENT);

    float unbound_density_scale =   stratus_value * stratus + 
                                    stratocumulus_value * stratocumulus +
                                    cumulus_value * cumulus;

    return saturate(unbound_density_scale);
}

float get_absorption(float density, float absorption_coef) { 
    // Beer's Law
    float beer = exp(-density * absorption_coef); 
    float powder_sugar = 1.0 - exp(-density * density * absorption_coef * absorption_coef);
	
	return beer;
}


float erode(float x, float e) {
	return saturate(remap(x, e, 1.0, 0.0, 1.0));
	//return x * e;
    //return max(1.0 - (1.0 - x) / e, 0.0);
}

// Henyey-Greenstein anisotropic scattering
float get_phase_function(float cosTheta) {
    float g = LightingAsymmetry;

    float normalizing_factor = 1.0 / (PI * 4.0); // can be precomputed on the CPU
    float denominator = 1.0 + g * g + 2.0 * g * cosTheta;
    float numerator = (1.0 - g * g);

	return normalizing_factor * numerator / pow(denominator, 1.5);
}

vec3 get_linear_depth(float raw_depth, vec2 screen_uv, mat4 inv_projection_matrix) {
    vec3 ndc = vec3(screen_uv * 2.0 - 1.0, raw_depth);
    vec4 hom_position_view_space = inv_projection_matrix * vec4(ndc, 1.0);
    return hom_position_view_space.xyz / hom_position_view_space.w;
}

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


float get_density(vec3 position, vec3 bound_center) {
	vec3 uv = (position - bound_center) / vec3(NoiseScale) + 0.5;
    vec3 model_uv = (position - bound_center) / BOUND_SIZE + 0.5;
    float height_fraction = model_uv.y;

    vec3 wind_uv_displacement = WindVelocity * TIME;
    wind_uv_displacement += height_fraction * WindVelocity * WindHeightSkew;

    float actual_cloud = texture(CLOUD_TEXTURE, uv.xz).r;

	vec4 sample_perlinworley = texture(NOISE_TEXTURE, uv + wind_uv_displacement);

    float cloud_type_density_scale = get_density_multiplier_by_cloud_type(model_uv, CloudType);

    float low_frequency_fbm = dot(sample_perlinworley, vec4(0.0, 0.625, 0.25, 0.125));

    float base_cloud = sample_perlinworley.r;
    base_cloud = erode(base_cloud, low_frequency_fbm);

    vec4 sample_highfrequency = texture(HIGH_FREQUENCY_NOISE_TEXTURE, uv * HighFrequencyNoiseScale - wind_uv_displacement);
    float high_frequency_fbm = dot(sample_highfrequency, vec4(0.0, .625, 0.25, 0.125));

    base_cloud = erode(base_cloud, high_frequency_fbm * HighFrequencyNoiseScaleErosure);
    base_cloud *= cloud_type_density_scale;

    float anvil_pow = remap(height_fraction, 0.7, 0.8, 1.0, mix(1.0, 0.5, AnvilBias));
    float local_coverage = pow(GlobalCoverage, anvil_pow);

    float coverage_erosure = (1.0 - local_coverage) / 3.0;
    //float coverage_erosure = (1.0 - local_coverage) * (1.0 - local_coverage) / 3.0;
    float cloud_with_coverage = saturate(erode(base_cloud, coverage_erosure));
    cloud_with_coverage *= local_coverage;
    //cloud_with_coverage *= local_coverage * local_coverage * local_coverage;

    return cloud_with_coverage;
}

float get_light_absorption(vec3 position, vec3 bound_center, vec3 eye_direction) {
	vec3 ray_origin = position;
	vec3 ray_direction = LightDirection;
	
    vec2 cube_penetration_distance = get_cube_penetration_distance(
        ray_origin, ray_direction, bound_center);

	float enter_distance = max(cube_penetration_distance.x, 0.0); // should be 0.0
	float exit_distance = max(cube_penetration_distance.y, 0.0);

	float total_density = 0.0;
	float total_distance = (exit_distance - enter_distance);
	float segment_length = total_distance / float(NUM_LIGHT_SAMPLES);

	for (int sample = 0; sample < NUM_LIGHT_SAMPLES; sample++) {
		float segment_progress = ((float(sample) + 0.5) / float(NUM_LIGHT_SAMPLES));
		float segment_midpoint_time = mix(enter_distance, exit_distance, segment_progress);

		vec3 midpoint_position = ray_origin + ray_direction * segment_midpoint_time;
		float segment_density = get_density(midpoint_position, bound_center);
		total_density += segment_density * segment_length;
	}

    float cosLightTheta = dot(ray_direction, eye_direction);
    float phase_function = get_phase_function(cosLightTheta);

	return get_absorption(total_density, LightAbsorption) * phase_function;
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

    vec2 cube_penetration_distance = get_cube_penetration_distance(
        ray_origin, ray_direction, object_position_worldspace);

    float enter_distance = max(cube_penetration_distance.x, 0.0);
    float exit_distance = clamp(cube_penetration_distance.y, 0.0, real_linear_depth);

	float total_distance = (exit_distance - enter_distance);
	float segment_length = total_distance / float(NUM_SAMPLES);

	vec3 volumetricLightColor = vec3(0.0);

	float volume_absorption_from_march = 1.0;

	for (int sample = 0; sample < NUM_SAMPLES; sample++) {
		float segment_progress = (float(sample) + 0.5) / float(NUM_SAMPLES);
		float segment_midpoint_time = mix(enter_distance, exit_distance, segment_progress);
		vec3 midpoint_position = ray_origin + ray_direction * segment_midpoint_time;

		float segment_density = get_density(midpoint_position, object_position_worldspace);
		float light_absorption = get_light_absorption(midpoint_position, object_position_worldspace, ray_direction);

		float previous_absorption = volume_absorption_from_march;
		volume_absorption_from_march *= get_absorption(segment_density * segment_length, AmbientAbsorption);

		float segment_absorption = previous_absorption - volume_absorption_from_march;
        
		volumetricLightColor += VolumeColor * LightColor * previous_absorption * light_absorption 
              * segment_length;
		volumetricLightColor += VolumeColor * AmbientColor * segment_absorption;
	}

	float transmittance = 1.0 - volume_absorption_from_march;

	ALBEDO = volumetricLightColor;
	ALPHA = transmittance * step(enter_distance, real_linear_depth);
}
