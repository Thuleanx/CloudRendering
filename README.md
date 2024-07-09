# GodotCloud

http://thuleanx.github.io/graphics/shader/2024/05/25/realtime-cloud-rendering for a write up of the project.
 
cube_cloud.gdshader contains the shader for rendering the cloud

perlin_worley_noise_generator.gd contains the code for generating perlin-worley and worley noises, used to shape the clouds. Ideally this should be a compute shader but I wanted to use learn godot so gdscript it is.
