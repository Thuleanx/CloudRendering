@tool
class_name PerlinWorleyNoise3D extends ImageTexture3D

## https://github.com/MAGGen-hub/Multi-Noise-Texture-Godot-Plugin/blob/master/addons/MultiNoiseTexture/MultiNoiseTexture3D.gd

const MAX_SIZE = 256
const MAX_DENSITY = 128
const NUM_OCTAVES = 4

@export_range(1, 256) var dimension := 16:
    set (value):
        value = clamp(1, value, MAX_SIZE)
        dimension = value

@export var worley_density: Array[int] = [16, 32, 56]
@export var worley_noise_contribution : Array[float] = [0.625, 0.25, 0.125]

@export var worley_density_extras: Array[int] = [8,16,32,64]
@export var g_worley_contribution: Array[float] = [0.625, 0.25, 0.125, 0.0]
@export var b_worley_contribution: Array[float] = [0.0, 0.625, 0.25, 0.125]
@export var a_worley_contribution: Array[float] = [0.0, 0.0, 0.75, 0.25]

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

var random: RandomNumberGenerator
var worley_points : Array[Vector3]
var perlin_vectors: Array[Vector3]
var thread: Thread
var thread_data := {}

var update_required = false;

func interpolate(a: float, b: float, t : float):
    ## return (b - a) * t + a
    return (b - a) * (3.0 - t * 2.0) * t * t + a # cubic interpolation

func remap(t: float, a : float, b: float, c : float, d : float) -> float:
    return (t - a) / (b - a) * (d - c) + c

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
        worley_density = worley_density,
        worley_noise_contribution = worley_noise_contribution,
        worley_density_extras = worley_density_extras,
        g_worley_contribution = g_worley_contribution,
        b_worley_contribution = b_worley_contribution,
        a_worley_contribution = a_worley_contribution,
    }

    thread = Thread.new()
    thread.start(generate_noise_texture)
    update_required = false

func generate_worley_points():
    progress = str("Generate Worley Points for ", MAX_DENSITY)

    var number_of_points = MAX_DENSITY * MAX_DENSITY * MAX_DENSITY

    worley_points = []
    worley_points.resize(number_of_points)

    var get_index = func(x:int, y:int, z:int):
        return x * MAX_DENSITY * MAX_DENSITY + y * MAX_DENSITY + z

    ## generate noise points
    for i in range(MAX_DENSITY):
        for j in range(MAX_DENSITY):
            for k in range(MAX_DENSITY):
                var index = get_index.call(i, j, k)
                worley_points[index] = Vector3(i + random.randf(), j + random.randf(), k + random.randf())

    progress = str("Finished generating Worley Points for ", MAX_DENSITY)

func generate_perlin_vectors():
    progress = str("Generate Perlin Vectors for ", MAX_DENSITY)

    var number_of_points = MAX_DENSITY * MAX_DENSITY * MAX_DENSITY

    perlin_vectors = []
    perlin_vectors.resize(number_of_points)

    for index in range(number_of_points):
        ## since the number of dimensions is low, the method of 
        ## sampling and discarding results outside of the unit sphere 
        ## works pretty well
        var random_unit_vector = Vector3(1.0, 0.0, 0.0)
        for iter in range(40):
            random_unit_vector = 2.0 * Vector3(random.randf(), random.randf(), random.randf()) - Vector3.ONE
            ## reject samples outside of sphere
            var length_squared = random_unit_vector.length_squared()
            if length_squared > 0 && length_squared <= 1:
                random_unit_vector = random_unit_vector.normalized()
                break

        perlin_vectors[index] = random_unit_vector

    progress = str("Finished generating Perlin vectors for ", MAX_DENSITY)


func sample_worley(position: Vector3, density: int):
    var sample_coord : Vector3i = Vector3i(floor(position * density))

    var closest_distance_squared: float = 1.0

    for dx in range(-1, 2):
        for dy in range(-1, 2):
            for dz in range(-1, 2):
                # possible to optimize these modulos
                # by keeping sample_coord within [0,density)^3
                var shifted_sample_coord = sample_coord + Vector3i(dx, dy, dz)
                for k in range(0, 2):
                    shifted_sample_coord[k] = (shifted_sample_coord[k] + 2 * density) % density

                var sample_index: int = shifted_sample_coord.x * MAX_DENSITY * MAX_DENSITY + shifted_sample_coord.y * MAX_DENSITY + shifted_sample_coord.z

                var sample : Vector3 = worley_points[sample_index]

                var displacement = sample - (position * density)
                for k in range(0, 2):
                    displacement[k] = min(
                            abs(displacement[k]), 
                            min(abs(displacement[k] + density),abs(displacement[k] - density)))

                closest_distance_squared = min(closest_distance_squared, displacement.length_squared())
    
    return closest_distance_squared

func sample_perlin(position: Vector3, density: int):
    var sample_coord : Vector3i = Vector3i(floor(position * density))
    var sample_coord_fractional : Vector3 = position * density - Vector3(sample_coord)

    var interpolants : Array[float] = []; interpolants.resize(16)

    for dx in range(0, 2):
        for dy in range(0, 2):
            for dz in range(0, 2):
                var shifted_sample_coord = sample_coord + Vector3i(dx, dy, dz)
                for k in range(0, 2):
                    shifted_sample_coord[k] = (shifted_sample_coord[k] + density) % density

                var sample_index: int = shifted_sample_coord.x * MAX_DENSITY * MAX_DENSITY + shifted_sample_coord.y * MAX_DENSITY + shifted_sample_coord.z

                var displacement = sample_coord_fractional - Vector3(dx, dy, dz)
                var sample : Vector3 = perlin_vectors[sample_index]
                interpolants[8 + dx * 4 + dy * 2 + dz] = sample.dot(displacement)
    
    var log_highest_bit = 2;
    var highest_bit = 4;

    for index in range(7, 0, -1):
        if index < highest_bit:
            log_highest_bit -= 1
            highest_bit /= 2

        var t = sample_coord_fractional[log_highest_bit]
        interpolants[index] = interpolate(
                interpolants[index << 1], 
                interpolants[index << 1 | 1], t)
    
    return clamp((interpolants[1] + 1.0) / 2.0, 0.0, 1.0)

func sample_perlin_fbm(position: Vector3, density: int, number_of_octaves: int) -> float:
    const OCTAVE_DOUBLING_FACTOR = 2.0

    var fbm = 0.0
    var noise_contribution : float = 1.0
    var noise_contribution_scale_factor: float = 0.5
    var total_noise_normalizer : float = 0.0
    
    for i in range(number_of_octaves):
        fbm += noise_contribution * sample_perlin(position, density)

        total_noise_normalizer += noise_contribution

        noise_contribution *= noise_contribution_scale_factor
        density *= OCTAVE_DOUBLING_FACTOR

    fbm = fbm / total_noise_normalizer
    return clampf(fbm, 0.0, 1.0)

func generate_noise_texture():
    progress = "Noise Generation Start"

    random = RandomNumberGenerator.new()
    random.randomize()

    var dimension_size = thread_data.dimension

    generate_worley_points()
    generate_perlin_vectors()

    progress = "Generate Points Finished"
    var dataArray: Array[Image] = []; dataArray.resize(dimension_size)

    for k in range(dimension_size):
        var data: PackedByteArray = []; data.resize(dimension_size * dimension_size * NUM_OCTAVES)

        ## R channel -> Perlin-Worley noise 
        for i in range(dimension_size): 
            for j in range(dimension_size):
                var position = Vector3(i,j,k) / float(dimension_size)

                var worley_fbm : float = 0.0

                var perlin_fbm : float = sample_perlin_fbm(position, 8, 5)

                var worley_sample_displacement : Vector3 = Vector3.ONE * (perlin_fbm * 2.0 - 1.0) / float(dimension_size)

                for z in range(thread_data.worley_density.size()):
                    var worley_sample: float = (1.0 - sample_worley(position + worley_sample_displacement, thread_data.worley_density[z]))
                    worley_fbm += worley_sample * thread_data.worley_noise_contribution[z]


                var perlin_worley_noise : float = worley_fbm
                # clamp(remap(perlin_fbm, 0.0, 1.0, worley_fbm, 1.0), 0.0, 1.0)

                data[i * dimension_size * NUM_OCTAVES + j * NUM_OCTAVES + 0] = float_to_color(perlin_worley_noise)
                
        ## GBA -> multiple octaves of worley_fbms
        for i in range(dimension_size): 
            for j in range(dimension_size):
                var position = Vector3(i,j,k) / float(dimension_size)

                var g = 0.0
                var b = 0.0
                var a = 0.0

                for z in range(thread_data.worley_density_extras.size()):
                    var worley_sample : float =  1.0 - sample_worley(position, thread_data.worley_density_extras[z])
                    g += thread_data.g_worley_contribution[z] * worley_sample
                    b += thread_data.b_worley_contribution[z] * worley_sample
                    a += thread_data.a_worley_contribution[z] * worley_sample

                data[i * dimension_size * NUM_OCTAVES + j * NUM_OCTAVES + 1] = float_to_color(g)
                data[i * dimension_size * NUM_OCTAVES + j * NUM_OCTAVES + 2] = float_to_color(b)
                data[i * dimension_size * NUM_OCTAVES + j * NUM_OCTAVES + 3] = float_to_color(a)


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
