@tool
class_name WorleyNoise3D extends ImageTexture3D

## https://github.com/MAGGen-hub/Multi-Noise-Texture-Godot-Plugin/blob/master/addons/MultiNoiseTexture/MultiNoiseTexture3D.gd

const MAX_SIZE = 256;
const NUM_OCTAVES = 4;

@export_range(1, 256) var dimension := 16:
	set (value):
		value = clamp(1, value, MAX_SIZE)
		dimension = value

@export var density: Array[int] = [1, 4, 8, 16]:
	set (value):
		density = value

@export var regenerate_button: bool:
	set(value):
		on_variable_update()

@export var progress = "Finished"
		
func _validate_property(property):
	if property.name=="progress":
		property.usage = PROPERTY_USAGE_READ_ONLY | PROPERTY_USAGE_EDITOR

func on_variable_update():
	update_required = true
	start_drawing_threads()

signal drawing_thread_finished;

var thread: Thread
var thread_data := {}

var update_required = false;

func _init():
	connect("drawing_thread_finished", on_threads_finished)
	start_drawing_threads()

func start_drawing_threads():
	if thread:
		if thread.is_alive(): 
			return
		if thread.is_started():
			thread.wait_to_finish()

	thread_data = {
		dimension = dimension,
		density = density
	}

	thread = Thread.new()
	thread.start(generate_noise_texture)
	update_required = false

func generate_noise_texture():
	progress = "Noise Generation Start"
	var number_of_points : Array[int] = []; number_of_points.resize(NUM_OCTAVES)
	for octave in range(NUM_OCTAVES):
		number_of_points[octave] = thread_data.density[octave] * thread_data.density[octave] * thread_data.density[octave]

	var random = RandomNumberGenerator.new()
	random.randomize()

	var points : Array[Array] = []

	var dimension_size = thread_data.dimension
	progress = str("Generate Points for ", dimension_size)
	for octave in range(NUM_OCTAVES):
		var sample_density = thread_data.density[octave]

		points.append([])
		points[octave].resize(number_of_points[octave])
		points[octave].fill(Vector3(0.0, 0.0, 0.0))

		var get_index = func(x:int, y:int, z:int):
			return x * sample_density * sample_density + y * sample_density + z

		## generate noise points
		for i in range(sample_density):
			for j in range(sample_density):
				for k in range(sample_density):
					var index = get_index.call(i, j, k)
					points[octave][index] = Vector3(i + random.randf(), j + random.randf(), k + random.randf()) / float(sample_density)
		
	progress = "Generate Points Finished"
	var dataArray: Array[Image] = []; dataArray.resize(dimension_size)

	for k in range(dimension_size):
		var data: PackedByteArray = []; data.resize(dimension_size * dimension_size * NUM_OCTAVES)

		for i in range(dimension_size): 
			for j in range(dimension_size):
				for octave in range(NUM_OCTAVES):
					var sample_density = thread_data.density[octave]
					var position = Vector3(i,j,k) / dimension_size

					var sample_coord : Vector3i = Vector3i(position * sample_density)

					var bound_index = func(x:int):
						if x < 0:
							return x + sample_density
						if x >= sample_density:
							return x - sample_density
						return x

					var get_index = func(x:int, y:int, z:int):
						x = bound_index.call(x)
						y = bound_index.call(y)
						z = bound_index.call(z)
						return x * sample_density * sample_density + y * sample_density + z

					var get_distance_squared_to_sample = func(p:Vector3):
						var displacement = p - position
						displacement.x = min(displacement.x, 1 - displacement.x)
						displacement.y = min(displacement.y, 1 - displacement.y)
						displacement.z = min(displacement.z, 1 - displacement.z)
						return displacement.length_squared()

					var closest_distance_squared : float = 1.0

					for dx in range(-1, 2):
						for dy in range(-1, 2):
							for dz in range(-1, 2):
								var adjacent_sample_index = get_index.call(sample_coord.x + dx, sample_coord.y + dy, sample_coord.z + dz)
								var adjacent_sample = points[octave][adjacent_sample_index]
								var distance_squared : float = get_distance_squared_to_sample.call(adjacent_sample)

								if distance_squared < closest_distance_squared:
									closest_distance_squared = distance_squared
					
					var distance = sqrt(closest_distance_squared) * sample_density
					distance = max(1.0 - distance, 0.0) # makes it bright at the point and falls off at the edge
						
					# prevents overflowing a byte
					if distance == 1.0:
						distance = 0.9999999

					data[i * dimension_size * NUM_OCTAVES + j * NUM_OCTAVES + octave] = floor(256 * distance)

		progress=str("Gen:",k,"/",dataArray.size()," ", data.size())
		dataArray[k] = Image.create_from_data(dimension_size, dimension_size, false, Image.FORMAT_RGBA8, data)

	## Create the ImageTexture3D from individual slices
	call_deferred("create", Image.FORMAT_RGBA8, dimension_size, dimension_size, dimension_size, false, dataArray)
	progress = str("Finished ", dimension_size, ", ", dimension_size, ", ", dimension_size)
	call_deferred("emit_signal", "drawing_thread_finished")
	## Prevents regenerating too quickly
	OS.delay_msec(50)

func on_threads_finished():
	if thread.is_started():
		thread.wait_to_finish()
	emit_changed()
	if update_required:
		start_drawing_threads()
