@tool
class_name PerlinNoise3D extends ImageTexture3D

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

func interpolate(a: float, b: float, t : float):
	## return (b - a) * t + a
	return (b - a) * (3.0 - t * 2.0) * t * t + a # cubic interpolation

func float_to_color(a: float):
	var r = int(a * 256)
	if r == 256:
		return 255
	return r

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
	## random.seed = 0

	var perlin_vectors : Array[Array] = []

	var dimension_size = thread_data.dimension
	progress = str("Generate Points for ", dimension_size)
	for octave in range(NUM_OCTAVES):
		var sample_density = thread_data.density[octave]

		perlin_vectors.append([])
		perlin_vectors[octave].resize(number_of_points[octave])
		perlin_vectors[octave].fill(Vector3(0.0, 0.0, 0.0))

		var get_index = func(x:int, y:int, z:int):
			return x * sample_density * sample_density + y * sample_density + z

		## generate noise points
		for i in range(sample_density):
			for j in range(sample_density):
				for k in range(sample_density):
					var index = get_index.call(i, j, k)

					## since the number of dimensions is low, the method of 
					## sampling and discarding results outside of the unit sphere 
					## works pretty well
					var random_unit_vector = Vector3(1.0, 0.0, 0.0)
					for iter in range(40):
						random_unit_vector = Vector3(random.randf(), random.randf(), random.randf())
						## reject samples outside of sphere
						var length_squared = random_unit_vector.length_squared()
						if length_squared > 0 && length_squared <= 1:
							random_unit_vector = random_unit_vector.normalized()
							break

					perlin_vectors[octave][index] = random_unit_vector
		
	progress = "Generate Points Finished"
	var dataArray: Array[Image] = []; dataArray.resize(dimension_size)

	for k in range(dimension_size):
		var data: PackedByteArray = []; data.resize(dimension_size * dimension_size * NUM_OCTAVES)

		for i in range(dimension_size): 
			for j in range(dimension_size):
				for octave in range(NUM_OCTAVES):
					var sample_density = thread_data.density[octave]
					var position = Vector3(i,j,k) / float(dimension_size)

					var sample_coord : Vector3i = Vector3i(floor(position * sample_density))
					var sample_coord_fractional : Vector3 = position * sample_density - Vector3(sample_coord)

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
					
					var interpolants : Array[float] = []; interpolants.resize(16)

					for dx in range(0, 2):
						for dy in range(0, 2):
							for dz in range(0, 2):
								var index = get_index.call(sample_coord.x + dx, sample_coord.y + dy, sample_coord.z + dz)
								var displacement = sample_coord_fractional - Vector3(dx, dy, dz)
								interpolants[8 + dx * 4 + dy * 2 + dz] = perlin_vectors[octave][index].dot(displacement)

					var log_highest_bit = 2;
					var highest_bit = 4;

					for index in range(7, 0, -1):
						if index < highest_bit:
							log_highest_bit -= 1
							highest_bit /= 2

						var t = sample_coord_fractional[log_highest_bit]
						interpolants[index] = interpolate(interpolants[index * 2], interpolants[index * 2 + 1], t)
					
					data[i * dimension_size * NUM_OCTAVES + j * NUM_OCTAVES + octave] = float_to_color((interpolants[1] + 1.0) / 2.0)

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
