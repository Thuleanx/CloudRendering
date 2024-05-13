@tool
extends Node3D

@export var cloud : MeshInstance3D

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	cloud.mesh.material.set("shader_parameter/LightPosition", global_position)
