extends Node3D
## Three chevron arrows that pulse forward in sequence — a "this way, something fun
## ahead!" indicator reused by both boost_pad.tscn and jump_pad.tscn with different
## colors. Children are expected to be MeshInstance3D cones, in order.

@export var pulse_color: Color = Color(1, 0.75, 0.05)
@export var pulse_speed: float = 2.2

var _time: float = 0.0
var _materials: Array[StandardMaterial3D] = []


func _ready() -> void:
	for child in get_children():
		var arrow := child as MeshInstance3D
		if not arrow:
			continue
		var mat := StandardMaterial3D.new()
		mat.albedo_color = pulse_color
		mat.emission_enabled = true
		mat.emission = pulse_color
		arrow.material_override = mat
		_materials.append(mat)


func _process(delta: float) -> void:
	_time += delta
	for i in range(_materials.size()):
		var phase := fmod(_time * pulse_speed - i * 0.28, 1.0)
		if phase < 0.0:
			phase += 1.0
		var pulse := 1.0 - phase
		_materials[i].emission_energy_multiplier = 0.6 + pulse * 2.4
		var arrow := get_child(i) as Node3D
		if arrow:
			arrow.scale = Vector3.ONE * (0.8 + pulse * 0.35)
