class_name ToonMaterial
extends RefCounted
## Small factory for the cel-shaded ShaderMaterial (shaders/toon.gdshader), so runtime
## tinting (kart paint, scenery colors) reads the same as the StandardMaterial3D
## pattern it replaces: ToonMaterial.create(color) instead of
## `var m := StandardMaterial3D.new(); m.albedo_color = color`.

## Lazily load()'d on first use rather than preload()'d — see the note in
## track_builder.gd about preload() not playing well with threaded scene loading
## (the loading screen loads race.tscn's whole dependency tree on a background
## thread; this shader is pulled in by nearly everything in that tree).
static var _shader: Shader


static func create(color: Color, metallic: float = 0.0, emission_boost: float = 0.0) -> ShaderMaterial:
	if _shader == null:
		_shader = load("res://shaders/toon.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("albedo_color", color)
	if metallic > 0.0:
		mat.set_shader_parameter("metallic", metallic)
	if emission_boost > 0.0:
		mat.set_shader_parameter("emission_boost", emission_boost)
	return mat
