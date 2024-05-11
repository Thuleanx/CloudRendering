#[compute]
#version 450

layout(local_size_x = 2, local_size_y = 2, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer RandomNoiseBuffer {
    float noise_buffer[];
} random_noise_buffer;

void main() {

}
