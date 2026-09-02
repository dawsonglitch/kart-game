extends Node3D
## The track designer: a live 3D view of a TrackDesign you can drag around, plus
## a panel of everything you can change about it.
##
## It shows the design by *building* it — the same RoadRibbon, the same
## TrackGround, the same CustomFeatures the game uses — rather than by drawing a
## schematic of it. That's the whole reason the design is plain data: what you
## drag here is what you drive later, and there is no second renderer that can
## disagree with the real one.
##
## What it deliberately does NOT build is the Terrain3D heightmap. That takes
## seconds and is regenerated wholesale on every edit, which would make dragging
## a handle unusable; the editor draws its own coarse mesh of the same height
## field instead. Everything else — road surface, banking, width, water, props —
## is the real thing.
##
## Rebuild cost is why edits are split in two: dragging a handle rebuilds only
## the road (cheap, and the only thing that visibly moves), and letting go
## rebuilds the ground and the props.

enum Tool { MOVE, ADD, ERASE }
enum SelectionKind { NONE, NODE, FEATURE }

## Screen-space radius, in pixels, within which a click counts as grabbing a
## handle. Generous on purpose — the people using this are eight.
const PICK_RADIUS := 26.0

## Handles are drawn at a constant *screen* size rather than a constant world
## size, so they stay grabbable whether you're zoomed into one corner or looking
## at the whole track.
const HANDLE_SCREEN_SCALE := 0.014

const CAM_MIN_DISTANCE := 30.0
const CAM_MAX_DISTANCE := 900.0
const CAM_MIN_PITCH := deg_to_rad(-88.0)
const CAM_MAX_PITCH := deg_to_rad(-8.0)
const CAM_ZOOM_STEP := 1.12
const CAM_ORBIT_SPEED := 0.007
## Panning moves the focus point across the ground; the further out you are, the
## further one pixel of mouse travel has to move it to feel the same.
const CAM_PAN_SPEED := 0.0016

## The editor's own ground mesh: one vertex every this many metres, adjusted so a
## big track doesn't cost more than a small one.
const GROUND_TARGET_SPAN := 140
const GROUND_MIN_STEP := 3.0
const GROUND_MAX_STEP := 9.0

## How far the mouse may wander between press and release and still count as a
## click rather than an orbit. A few pixels: nobody holds a mouse perfectly still.
const CLICK_SLOP := 6.0

const TOAST_SECONDS := 2.0

@onready var camera: Camera3D = $Camera
@onready var preview: Node3D = $Preview
@onready var handle_root: Node3D = $Handles

@onready var _panel_box: VBoxContainer = $UI/Root/Panel/Scroll/VBox
@onready var name_field: LineEdit = _panel_box.get_node("NameField")
@onready var template_option: OptionButton = _panel_box.get_node("TemplateRow/TemplateOption")
@onready var new_button: Button = _panel_box.get_node("TemplateRow/NewButton")
@onready var feature_grid: GridContainer = _panel_box.get_node("FeatureGrid")
@onready var color_grid: GridContainer = _panel_box.get_node("ColorGrid")
@onready var stats_label: Label = _panel_box.get_node("StatsLabel")
@onready var undo_button: Button = _panel_box.get_node("UndoButton")
@onready var jump_button: Button = _panel_box.get_node("JumpButton")
@onready var selection_label: Label = _panel_box.get_node("SelectionLabel")
@onready var size_row: HBoxContainer = _panel_box.get_node("SizeRow")
@onready var size_label: Label = _panel_box.get_node("SizeRow/SizeLabel")
@onready var size_slider: HSlider = _panel_box.get_node("SizeRow/SizeSlider")
@onready var height_row: HBoxContainer = _panel_box.get_node("HeightRow")
@onready var height_slider: HSlider = _panel_box.get_node("HeightRow/HeightSlider")
@onready var rotate_row: HBoxContainer = _panel_box.get_node("RotateRow")
@onready var rotate_slider: HSlider = _panel_box.get_node("RotateRow/RotateSlider")
@onready var node_row: HBoxContainer = _panel_box.get_node("NodeRow")
@onready var split_button: Button = _panel_box.get_node("NodeRow/SplitButton")
@onready var delete_button: Button = _panel_box.get_node("NodeRow/DeleteButton")
@onready var test_button: Button = _panel_box.get_node("TestButton")
@onready var save_button: Button = _panel_box.get_node("SaveButton")
@onready var open_button: Button = _panel_box.get_node("BottomRow/OpenButton")
@onready var back_button: Button = _panel_box.get_node("BottomRow/BackButton")

@onready var hint_label: Label = $UI/Root/Hint/HintLabel
@onready var warn_panel: PanelContainer = $UI/Root/Warn
@onready var warn_label: Label = $UI/Root/Warn/WarnLabel
@onready var confirm_panel: PanelContainer = $UI/Root/ConfirmPanel
@onready var confirm_message: Label = $UI/Root/ConfirmPanel/VBox/Message
@onready var confirm_save_button: Button = $UI/Root/ConfirmPanel/VBox/Row/SaveButton
@onready var confirm_discard_button: Button = $UI/Root/ConfirmPanel/VBox/Row/DiscardButton
@onready var confirm_cancel_button: Button = $UI/Root/ConfirmPanel/VBox/Row/CancelButton
@onready var toast_label: Label = $UI/Root/Toast
@onready var open_panel: PanelContainer = $UI/Root/OpenPanel
@onready var open_list: ItemList = $UI/Root/OpenPanel/VBox/List
@onready var open_load_button: Button = $UI/Root/OpenPanel/VBox/Row/LoadButton
@onready var open_delete_button: Button = $UI/Root/OpenPanel/VBox/Row/DeleteButton
@onready var open_cancel_button: Button = $UI/Root/OpenPanel/VBox/Row/CancelButton

var design: TrackDesign
## The library id this design was last saved under, or "" if it has never been
## saved. Saving with an id overwrites; saving without one makes a new file.
var saved_id: String = ""

var _tool: int = Tool.MOVE
var _tool_buttons: Array[Button] = []
var _add_type: String = "tree"
var _feature_buttons: Dictionary = {}

var _selection_kind: int = SelectionKind.NONE
var _selection_index: int = -1

## [{kind, index, pos}] for every draggable point on screen, rebuilt whenever the
## design's structure changes. Both the drawn handles and click-picking read this
## one list, so what you see is exactly what you can grab.
var _handles: Array = []

var _ribbon: RoadRibbon
var _ground: TrackGround

var _cam_focus: Vector3 = Vector3.ZERO
var _cam_yaw: float = 0.0
var _cam_pitch: float = deg_to_rad(-52.0)
var _cam_distance: float = 300.0

var _dragging: bool = false
var _drag_vertical: bool = false
var _orbiting: bool = false
var _panning: bool = false
## Where the left button went down and how far the mouse has travelled since —
## what separates "clicked here" from "spun the view around".
var _press_position: Vector2 = Vector2.ZERO
var _press_travel: float = 0.0
## Set while a slider is being moved by _refresh_panel(), so writing a value into
## a slider doesn't come straight back as an edit to the design.
var _syncing_panel: bool = false

var _toast_left: float = 0.0

## Built on first use and reused: red for a road point, blue for a feature,
## yellow for whichever is selected.
var _handle_materials: Dictionary = {}

## Snapshots for Undo, oldest first, each {"design": Dictionary, "saved_id": String}.
## Whole-design snapshots rather than a list of reversible operations: a design is
## a few kilobytes of dictionary, and the alternative is an undo implementation
## with its own bugs sitting under a tool aimed at eight-year-olds.
var _history: Array = []
const MAX_UNDO := 40

## True when there are edits that aren't in the library yet. Everything that
## would throw them away asks first.
var _unsaved: bool = false

## What to do if the confirm dialog is answered "save" or "don't save".
var _pending_action: Callable = Callable()

## Patches of road wound inside out in the current build, if any — see
## _count_folded_faces(). Non-zero means part of the road is invisible and not
## solid, which the player needs telling about rather than discovering at speed.
var _road_folds: int = 0


func _ready() -> void:
	design = _initial_design()
	saved_id = GameSettings.editor_design_id
	# Consumed: coming back here from a test drive resumes the session, but
	# opening the editor fresh from the menu shouldn't silently reopen an old one.
	GameSettings.editor_design = null

	_build_template_options()
	_build_feature_palette()
	_build_color_pickers()
	_wire_panel()

	name_field.text = design.design_name
	_frame_design()
	_rebuild_all()
	_refresh_panel()


func _initial_design() -> TrackDesign:
	if GameSettings.editor_design != null:
		return GameSettings.editor_design
	return TrackDesign.from_template("oval")


# ---------------------------------------------------------------------------
# Panel construction — the palette and the color pickers are generated from
# TrackDesign's own tables, so adding a feature type or a color there is the
# only edit needed to make it appear here.
# ---------------------------------------------------------------------------

func _build_template_options() -> void:
	for i in range(TrackDesign.TEMPLATES.size()):
		var template: Dictionary = TrackDesign.TEMPLATES[i]
		template_option.add_item(String(template["label"]), i)
		template_option.set_item_tooltip(i, String(template["hint"]))


func _build_feature_palette() -> void:
	for type in TrackDesign.FEATURE_ORDER:
		var spec: Dictionary = TrackDesign.FEATURES[type]
		var button := Button.new()
		button.text = String(spec["label"])
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(0, 38)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = "Pick this, then click the ground to place one"
		button.pressed.connect(_on_feature_type_picked.bind(type))
		feature_grid.add_child(button)
		_feature_buttons[type] = button


func _build_color_pickers() -> void:
	for key in TrackDesign.COLOR_DEFAULTS:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label := Label.new()
		label.text = String(key).capitalize()
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
		column.add_child(label)
		var picker := ColorPickerButton.new()
		picker.custom_minimum_size = Vector2(0, 32)
		picker.edit_alpha = false
		picker.color = design.color_of(key)
		picker.get_picker().picker_shape = ColorPicker.SHAPE_HSV_WHEEL
		picker.color_changed.connect(_on_color_changed.bind(String(key)))
		column.add_child(picker)
		color_grid.add_child(column)


func _wire_panel() -> void:
	name_field.text_changed.connect(func(text: String) -> void:
		design.design_name = text.strip_edges()
	)
	new_button.pressed.connect(_on_new_pressed)

	for button_name in ["MoveToolButton", "AddToolButton", "EraseToolButton"]:
		var button: Button = _panel_box.get_node("ToolRow/%s" % button_name)
		var tool_id: int = _tool_buttons.size()
		_tool_buttons.append(button)
		button.pressed.connect(_select_tool.bind(tool_id))

	size_slider.value_changed.connect(_on_size_changed)
	height_slider.value_changed.connect(_on_height_changed)
	rotate_slider.value_changed.connect(_on_rotate_changed)
	split_button.pressed.connect(_on_split_pressed)
	delete_button.pressed.connect(_on_delete_pressed)
	jump_button.pressed.connect(_on_jump_pressed)
	undo_button.pressed.connect(_undo)

	confirm_save_button.pressed.connect(_on_confirm_save)
	confirm_discard_button.pressed.connect(_on_confirm_discard)
	confirm_cancel_button.pressed.connect(_on_confirm_cancel)

	test_button.pressed.connect(_on_test_drive_pressed)
	save_button.pressed.connect(_on_save_pressed)
	open_button.pressed.connect(_on_open_pressed)
	back_button.pressed.connect(_on_back_pressed)

	# Sliders push one undo step per drag, not one per pixel of travel.
	for slider: HSlider in [size_slider, height_slider, rotate_slider]:
		slider.drag_started.connect(_push_undo)

	open_load_button.pressed.connect(_on_open_load_pressed)
	open_delete_button.pressed.connect(_on_open_delete_pressed)
	open_cancel_button.pressed.connect(func() -> void: open_panel.hide())
	open_list.item_activated.connect(func(_index: int) -> void: _on_open_load_pressed())

	_feature_buttons[_add_type].button_pressed = true


# ---------------------------------------------------------------------------
# Undo, and not losing anyone's track
# ---------------------------------------------------------------------------

## Call BEFORE changing anything. Every edit is undoable, which for this audience
## matters more than any single feature in the panel: the way a child explores a
## tool is by doing something drastic and seeing what happens, and that is only
## safe if it can be taken back.
func _push_undo() -> void:
	_history.append({"design": design.to_dict(), "saved_id": saved_id})
	if _history.size() > MAX_UNDO:
		_history.pop_front()
	_unsaved = true
	_refresh_history_button()


func _undo() -> void:
	if _history.is_empty():
		return
	var entry: Dictionary = _history.pop_back()
	var restored := TrackDesign.from_dict(entry["design"])
	if restored == null:
		return
	# Keeps the camera where it is: undoing an edit should put the track back,
	# not move the view as well.
	_adopt_design(restored, String(entry["saved_id"]), false)
	AudioManager.play("ui_click", -10.0)
	_refresh_history_button()


func _refresh_history_button() -> void:
	undo_button.disabled = _history.is_empty()


## Runs `action` now if there is nothing to lose, or asks first if there is.
func _guard_unsaved(action: Callable, what: String) -> void:
	if not _unsaved:
		action.call()
		return
	_pending_action = action
	confirm_message.text = "\"%s\" has changes you haven't saved.\n%s" % [
		design.design_name if design.design_name != "" else "Your track", what
	]
	confirm_panel.show()


func _on_confirm_save() -> void:
	confirm_panel.hide()
	_on_save_pressed()
	_run_pending()


func _on_confirm_discard() -> void:
	confirm_panel.hide()
	_run_pending()


func _on_confirm_cancel() -> void:
	confirm_panel.hide()
	_pending_action = Callable()


func _run_pending() -> void:
	var action := _pending_action
	_pending_action = Callable()
	if action.is_valid():
		action.call()


# ---------------------------------------------------------------------------
# Building the preview
# ---------------------------------------------------------------------------

func _rebuild_all() -> void:
	_rebuild_road()
	_rebuild_props()
	_rebuild_handles()


## The road surface (or the arena's wall ring). Cheap enough to run every frame
## of a drag, which is what makes dragging a corner feel like bending a road
## rather than like editing a list of numbers.
func _rebuild_road() -> void:
	_clear_group("Road")
	var road := Node3D.new()
	road.name = "Road"
	preview.add_child(road)

	if design.kind == TrackDesign.Kind.ARENA:
		_ribbon = null
		_build_arena_wall_preview(road)
		return

	# The same two calls custom_track_builder.gd makes, which is the point: the
	# road you bend here and the road you drive later come out of one function.
	var curve := design.build_curve()
	_ribbon = RoadRibbon.build(curve, design.width_profile(curve), [])
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _ribbon.mesh
	mesh_instance.material_override = TrackProps.road_material(design.color_of("road"))
	road.add_child(mesh_instance)

	var finish := Node3D.new()
	finish.name = "Finish"
	road.add_child(finish)
	TrackProps.build_finish_line(finish, _ribbon)


## The rink's wall, drawn from custom_arena_builder.gd's own numbers so the ring
## you size here is the ring you bounce off later. Drawn as one MultiMesh rather
## than 64 bodies: the preview only has to be looked at.
func _build_arena_wall_preview(road: Node3D) -> void:
	var segments: int = CustomArenaBuilder.WALL_SEGMENT_COUNT
	var radius: float = design.arena_radius
	var mesh := BoxMesh.new()
	mesh.size = Vector3(
		2.0 * radius * sin(TAU / float(segments) * 0.5) * CustomArenaBuilder.WALL_SEGMENT_OVERLAP,
		CustomArenaBuilder.WALL_HEIGHT,
		CustomArenaBuilder.WALL_THICKNESS
	)
	var lift: float = CustomArenaBuilder.WALL_HEIGHT * 0.5 - CustomArenaBuilder.WALL_SINK
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		var x := cos(angle) * radius
		var z := sin(angle) * radius
		transforms.append(Transform3D(
			Basis(Vector3.UP, angle + PI * 0.5), Vector3(x, _height_at(x, z) + lift, z)
		))
		colors.append(Color(0.9, 0.15, 0.15) if i % 2 == 0 else Color(0.95, 0.95, 0.95))
	TrackProps._multimesh(road, "WallPreview", transforms, mesh, Color.WHITE, colors)


## The ground, the water and every placed feature. Slower than the road, so it
## only runs when a drag ends rather than while one is happening.
func _rebuild_props() -> void:
	_clear_group("Props")
	var props := Node3D.new()
	props.name = "Props"
	preview.add_child(props)

	var canyons: Array = CustomFeatures.water_canyons(design)
	var noise_height: float = (
		TrackDesign.ARENA_GROUND_NOISE if design.kind == TrackDesign.Kind.ARENA
		else TrackGround.NOISE_HEIGHT
	)
	_ground = TrackGround.create(
		_ribbon if _ribbon != null else RoadRibbon.new(), [], canyons, noise_height
	)

	_build_ground_mesh(props)
	TrackProps.build_water(props, canyons)
	CustomFeatures.build(props, design, _ground, _ribbon, true)
	if design.kind == TrackDesign.Kind.RACE and _ribbon != null:
		# The crowd and the stands the real track builds around its start line,
		# so the preview is not missing something the finished track has.
		TrackProps.build_grandstands(
			props, _ribbon, _ground,
			_ribbon.length - CustomTrackBuilder.GRANDSTAND_BEFORE_LINE,
			_ribbon.length + CustomTrackBuilder.GRANDSTAND_AFTER_LINE
		)

	_road_folds = _count_folded_faces(_ribbon)
	_refresh_warning()
	_refresh_stats()


## A plain grid mesh of the height field. Not Terrain3D — see the note at the top
## of the file — but sampled from exactly the same TrackGround the real terrain
## is stamped from, so hills, hillsides and water pools all show up where they
## will actually be.
func _build_ground_mesh(parent: Node3D) -> void:
	var half: float = design.extent()
	var step: float = clampf(half * 2.0 / float(GROUND_TARGET_SPAN), GROUND_MIN_STEP, GROUND_MAX_STEP)
	var span: int = int(ceil(half * 2.0 / step)) + 1

	# Heights are sampled once into a grid and the normals are then differenced
	# from their neighbours, rather than each vertex re-sampling the field four
	# more times — the field lookup is the expensive part of a rebuild.
	var heights := PackedFloat32Array()
	heights.resize(span * span)
	for iz in range(span):
		for ix in range(span):
			heights[iz * span + ix] = _height_at(-half + ix * step, -half + iz * step)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	vertices.resize(span * span)
	normals.resize(span * span)
	for iz in range(span):
		for ix in range(span):
			var i: int = iz * span + ix
			vertices[i] = Vector3(-half + ix * step, heights[i], -half + iz * step)
			var dx: float = (
				heights[iz * span + mini(ix + 1, span - 1)] - heights[iz * span + maxi(ix - 1, 0)]
			)
			var dz: float = (
				heights[mini(iz + 1, span - 1) * span + ix] - heights[maxi(iz - 1, 0) * span + ix]
			)
			normals[i] = Vector3(-dx, 2.0 * step, -dz).normalized()

	var indices := PackedInt32Array()
	for iz in range(span - 1):
		for ix in range(span - 1):
			var a: int = iz * span + ix
			var b: int = a + 1
			var c: int = a + span
			var d: int = c + 1
			indices.append_array([a, c, b, b, c, d])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var instance := MeshInstance3D.new()
	instance.name = "Ground"
	instance.mesh = mesh
	instance.material_override = ToonMaterial.create(design.color_of("ground") * 0.75)
	parent.add_child(instance)


## Triangles wound the wrong way round in the road surface. Godot's front face is
## the one (c - a) x (b - a) points out of; a face that disagrees with its own
## normal is inside out, which means that patch of road is invisible from above
## AND, since Jolt back-face culls a one-sided trimesh, not solid — a kart drops
## straight through it.
##
## It happens where a corner is tighter than the road is wide: the inner edge
## laps over the stretch behind it. That is a shape a player can absolutely draw,
## so the editor measures it on every full rebuild and says so, rather than
## letting it be discovered at speed.
func _count_folded_faces(ribbon: RoadRibbon) -> int:
	if ribbon == null or ribbon.mesh == null or ribbon.mesh.get_surface_count() == 0:
		return 0
	var arrays: Array = ribbon.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var folded := 0
	for face in range(vertices.size() / 3):
		var a: Vector3 = vertices[face * 3]
		var b: Vector3 = vertices[face * 3 + 1]
		var c: Vector3 = vertices[face * 3 + 2]
		var geometric: Vector3 = (c - a).cross(b - a)
		if geometric.length() > 0.0001 and geometric.normalized().dot(normals[face * 3]) < -0.2:
			folded += 1
	return folded


func _refresh_warning() -> void:
	if _road_folds > 0:
		warn_label.text = (
			"⚠ A corner is too tight for how wide the road is, so the road folds over "
			+ "itself there. Karts can fall through it. Move that point further out, or "
			+ "make the road narrower."
		)
		warn_panel.show()
	else:
		warn_panel.hide()


func _height_at(x: float, z: float) -> float:
	return _ground.height_at(x, z) if _ground != null else 0.0


func _clear_group(node_name: String) -> void:
	var existing := preview.get_node_or_null(node_name)
	if existing:
		# Detached before freeing so the replacement can take the same name in
		# this same frame — queue_free() leaves the old node in the tree until
		# the end of the frame, and Godot would rename the new one to "Road2".
		preview.remove_child(existing)
		existing.queue_free()


# ---------------------------------------------------------------------------
# Handles
# ---------------------------------------------------------------------------

func _rebuild_handles() -> void:
	for child in handle_root.get_children():
		handle_root.remove_child(child)
		child.queue_free()
	_handles.clear()

	if design.kind == TrackDesign.Kind.RACE:
		for i in range(design.nodes.size()):
			_handles.append({
				"kind": SelectionKind.NODE, "index": i, "pos": design.nodes[i]["pos"],
			})
	for i in range(design.features.size()):
		var feature: Dictionary = design.features[i]
		var pos: Vector3 = feature["pos"]
		# Lifted to the ground so the marker sits on top of the thing it marks
		# rather than inside a hill.
		_handles.append({
			"kind": SelectionKind.FEATURE, "index": i,
			"pos": Vector3(pos.x, _height_at(pos.x, pos.z) + 3.0, pos.z),
		})

	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	for i in range(_handles.size()):
		var marker := MeshInstance3D.new()
		marker.mesh = sphere
		marker.position = _handles[i]["pos"]
		handle_root.add_child(marker)
	_refresh_handle_look()


## Handle color and size. Runs on every camera move (size follows distance) and
## on every mouse-move of a drag, so the three materials are made once and shared
## rather than built per handle per call.
func _refresh_handle_look() -> void:
	if _handle_materials.is_empty():
		_handle_materials = {
			"selected": ToonMaterial.create(Color(1.0, 0.95, 0.2), 0.0, 0.6),
			"node": ToonMaterial.create(Color(0.95, 0.35, 0.35)),
			"feature": ToonMaterial.create(Color(0.35, 0.75, 1.0)),
		}
	var handle_scale: float = maxf(_cam_distance * HANDLE_SCREEN_SCALE, 0.6)
	for i in range(mini(_handles.size(), handle_root.get_child_count())):
		var marker: MeshInstance3D = handle_root.get_child(i)
		var entry: Dictionary = _handles[i]
		marker.position = entry["pos"]
		marker.scale = Vector3.ONE * handle_scale
		var selected: bool = (
			int(entry["kind"]) == _selection_kind and int(entry["index"]) == _selection_index
		)
		var key: String
		if selected:
			key = "selected"
		elif int(entry["kind"]) == SelectionKind.NODE:
			key = "node"
		else:
			key = "feature"
		marker.material_override = _handle_materials[key]


## Nearest handle to a screen position, or -1. Screen-space rather than a physics
## ray: the handles have no collision shapes, and "closest to the cursor" is what
## a person actually means by clicking one.
func _pick_handle(screen_pos: Vector2) -> int:
	var best := -1
	var best_distance := PICK_RADIUS
	for i in range(_handles.size()):
		var world: Vector3 = _handles[i]["pos"]
		if camera.is_position_behind(world):
			continue
		var distance: float = camera.unproject_position(world).distance_to(screen_pos)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


# ---------------------------------------------------------------------------
# Input — the 3D view. Anything over the panel is consumed by the panel before
# it gets here, which is why this can assume every event it sees is aimed at the
# track.
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if confirm_panel.visible:
		# The dialog is a question; nothing behind it should act until it is
		# answered, including Escape, which is what put it up.
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Z and (event.ctrl_pressed or event.meta_pressed):
			_undo()
			return
	if open_panel.visible:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event.is_action_pressed("pause"):
		_on_back_pressed()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_zoom(1.0 / CAM_ZOOM_STEP)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_zoom(CAM_ZOOM_STEP)
		MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
			_panning = event.pressed
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_left_press(event)
			else:
				_end_left_press(event.position)


func _begin_left_press(event: InputEventMouseButton) -> void:
	var hit := _pick_handle(event.position)
	if hit >= 0:
		var entry: Dictionary = _handles[hit]
		_select(int(entry["kind"]), int(entry["index"]))
		if _tool == Tool.ERASE:
			_on_delete_pressed()
			return
		_push_undo()
		_dragging = true
		# Shift turns the drag vertical. Two separate gestures rather than a mode
		# you can forget you're in: you can't accidentally launch a corner into
		# the sky while trying to slide it sideways.
		_drag_vertical = event.shift_pressed
		return

	# Empty space always starts an orbit, even with the Add tool selected —
	# otherwise there is no way to turn the view around while placing things.
	# Whether it was an orbit or a click to drop something is decided on release,
	# by whether the mouse actually went anywhere.
	_orbiting = true
	_press_position = event.position
	_press_travel = 0.0


func _end_left_press(position: Vector2) -> void:
	if _orbiting and _tool == Tool.ADD and _press_travel <= CLICK_SLOP:
		var point = _ray_to_ground(position)
		if point != null:
			_add_feature_at(point)
	_orbiting = false
	if _dragging:
		_dragging = false
		# The cheap half of the rebuild ran on every motion event; the expensive
		# half runs once, here.
		_rebuild_props()
		_rebuild_handles()
	_refresh_panel()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _dragging:
		_drag_selection(event)
	elif _orbiting:
		_press_travel += event.relative.length()
		_cam_yaw -= event.relative.x * CAM_ORBIT_SPEED
		_cam_pitch = clampf(
			_cam_pitch - event.relative.y * CAM_ORBIT_SPEED, CAM_MIN_PITCH, CAM_MAX_PITCH
		)
		_update_camera()
	elif _panning:
		var pan: float = _cam_distance * CAM_PAN_SPEED
		var right := Vector3(cos(_cam_yaw), 0.0, -sin(_cam_yaw))
		var forward := Vector3(sin(_cam_yaw), 0.0, cos(_cam_yaw))
		_cam_focus -= right * event.relative.x * pan + forward * event.relative.y * pan
		_update_camera()


func _drag_selection(event: InputEventMouseMotion) -> void:
	var current = _selected_position()
	if current == null:
		return
	var anchor: Vector3 = current
	var target
	if _drag_vertical:
		# A plane standing up through the handle, facing the camera, so vertical
		# mouse travel maps to height at whatever angle you happen to be viewing
		# from.
		var facing := Vector3(sin(_cam_yaw), 0.0, cos(_cam_yaw))
		target = Plane(facing, anchor).intersects_ray(
			camera.project_ray_origin(event.position), camera.project_ray_normal(event.position)
		)
		if target == null:
			return
		anchor.y = (target as Vector3).y
	else:
		target = Plane(Vector3.UP, anchor.y).intersects_ray(
			camera.project_ray_origin(event.position), camera.project_ray_normal(event.position)
		)
		if target == null:
			return
		anchor.x = (target as Vector3).x
		anchor.z = (target as Vector3).z

	_set_selected_position(anchor)
	if _selection_kind == SelectionKind.NODE:
		_rebuild_road()
	_sync_handle_positions()
	_refresh_panel()


## Keeps the drawn handles on the design while a drag is in flight, without the
## full _rebuild_handles() (which re-creates every node).
func _sync_handle_positions() -> void:
	for i in range(_handles.size()):
		var entry: Dictionary = _handles[i]
		if int(entry["kind"]) == SelectionKind.NODE:
			entry["pos"] = design.nodes[int(entry["index"])]["pos"]
		else:
			var pos: Vector3 = design.features[int(entry["index"])]["pos"]
			entry["pos"] = Vector3(pos.x, _height_at(pos.x, pos.z) + 3.0, pos.z)
	_refresh_handle_look()


## Where a click lands on the ground. The height field isn't a surface anything
## can raycast against, so this walks the ray forward until it drops below the
## ground and then bisects — accurate to a few centimetres and, unlike
## intersecting a flat y=0 plane, correct on a track with hills in it.
func _ray_to_ground(screen_pos: Vector2):
	var origin: Vector3 = camera.project_ray_origin(screen_pos)
	var direction: Vector3 = camera.project_ray_normal(screen_pos)
	var reach: float = _cam_distance * 4.0
	var previous: float = 0.0
	var t: float = 0.0
	while t < reach:
		t += 4.0
		var point: Vector3 = origin + direction * t
		if point.y <= _height_at(point.x, point.z):
			var low := previous
			var high := t
			for _step in range(12):
				var mid: float = (low + high) * 0.5
				var probe: Vector3 = origin + direction * mid
				if probe.y <= _height_at(probe.x, probe.z):
					high = mid
				else:
					low = mid
			return origin + direction * high
		previous = t
	return null


func _zoom(factor: float) -> void:
	_cam_distance = clampf(_cam_distance * factor, CAM_MIN_DISTANCE, CAM_MAX_DISTANCE)
	_update_camera()
	_refresh_handle_look()


func _update_camera() -> void:
	var offset := Vector3(
		cos(_cam_pitch) * sin(_cam_yaw), sin(-_cam_pitch), cos(_cam_pitch) * cos(_cam_yaw)
	)
	camera.position = _cam_focus + offset * _cam_distance
	camera.look_at(_cam_focus, Vector3.UP)


## Puts the whole design on screen, used when the editor opens and whenever a new
## template or saved track is loaded.
func _frame_design() -> void:
	_cam_focus = Vector3.ZERO
	_cam_distance = clampf(design.extent() * 2.2, CAM_MIN_DISTANCE, CAM_MAX_DISTANCE)
	_update_camera()


# ---------------------------------------------------------------------------
# Selection and the panel
# ---------------------------------------------------------------------------

func _select(kind: int, index: int) -> void:
	_selection_kind = kind
	_selection_index = index
	_refresh_handle_look()
	_refresh_panel()


func _selected_position():
	match _selection_kind:
		SelectionKind.NODE:
			if _selection_index < design.nodes.size():
				return design.nodes[_selection_index]["pos"] as Vector3
		SelectionKind.FEATURE:
			if _selection_index < design.features.size():
				return design.features[_selection_index]["pos"] as Vector3
	return null


func _set_selected_position(pos: Vector3) -> void:
	match _selection_kind:
		SelectionKind.NODE:
			design.set_node_position(_selection_index, pos)
		SelectionKind.FEATURE:
			design.features[_selection_index]["pos"] = TrackDesign.clamp_position(pos)


func _select_tool(tool_id: int, silent: bool = false) -> void:
	_tool = tool_id
	for i in range(_tool_buttons.size()):
		_tool_buttons[i].button_pressed = (i == tool_id)
	if not silent:
		AudioManager.play("ui_click", -10.0)
	_refresh_panel()


func _on_feature_type_picked(type: String) -> void:
	_add_type = type
	for key in _feature_buttons:
		(_feature_buttons[key] as Button).button_pressed = (key == type)
	# Picking something to place is the same intent as choosing the Add tool, so
	# it switches for you rather than leaving a palette selection that does
	# nothing until you also press Add.
	_select_tool(Tool.ADD, true)


func _add_feature_at(point: Vector3) -> void:
	_push_undo()
	design.add_feature(_add_type, Vector3(point.x, 0.0, point.z))
	AudioManager.play("ui_click", -10.0)
	_rebuild_props()
	_rebuild_handles()
	# add_feature() appends, so the new one is the last — asking the array to
	# find it back would compare dictionaries by content and could match an
	# identical feature placed earlier.
	_select(SelectionKind.FEATURE, design.features.size() - 1)


func _on_color_changed(color: Color, key: String) -> void:
	_push_undo()
	design.colors[key] = color
	_rebuild_all()


func _on_size_changed(value: float) -> void:
	if _syncing_panel:
		return
	match _selection_kind:
		SelectionKind.NODE:
			design.set_node_half_width(_selection_index, value)
			_rebuild_road()
		SelectionKind.FEATURE:
			design.features[_selection_index]["size"] = value
			_rebuild_props()
		_:
			if design.kind == TrackDesign.Kind.ARENA:
				design.arena_radius = value
				_rebuild_road()
	_rebuild_handles()


func _on_height_changed(value: float) -> void:
	if _syncing_panel:
		return
	var pos = _selected_position()
	if pos == null:
		return
	_set_selected_position(Vector3((pos as Vector3).x, value, (pos as Vector3).z))
	if _selection_kind == SelectionKind.NODE:
		_rebuild_road()
	_rebuild_props()
	_rebuild_handles()


func _on_rotate_changed(value: float) -> void:
	if _syncing_panel or _selection_kind != SelectionKind.FEATURE:
		return
	design.features[_selection_index]["yaw"] = deg_to_rad(value)
	_rebuild_props()


func _on_split_pressed() -> void:
	if _selection_kind != SelectionKind.NODE:
		return
	_push_undo()
	var inserted := design.split_node(_selection_index)
	if inserted < 0:
		_history.pop_back()
		_toast("That's as many points as a track can have")
		return
	_rebuild_all()
	_select(SelectionKind.NODE, inserted)


func _on_delete_pressed() -> void:
	_push_undo()
	match _selection_kind:
		SelectionKind.NODE:
			if not design.remove_node(_selection_index):
				_history.pop_back()
				_toast("A track needs at least %d points" % TrackDesign.MIN_NODES)
				return
		SelectionKind.FEATURE:
			design.features.remove_at(_selection_index)
		_:
			_history.pop_back()
			return
	_selection_kind = SelectionKind.NONE
	_selection_index = -1
	_rebuild_all()
	_refresh_panel()


## One press builds the whole jump — see TrackDesign.make_jump() for why a lip
## on its own does nothing — and then checks the result before keeping it.
##
## The check is the interesting half. A jump needs a short, steep drop, and asking
## for one on a corner already near the limit of what a road that wide can turn
## tips it into folding over itself. Rather than guess a threshold, this builds
## the road and looks: if the jump wrecked it, the whole thing is taken back and
## the player is told where a jump will work instead.
func _on_jump_pressed() -> void:
	if _selection_kind != SelectionKind.NODE:
		return
	_push_undo()
	var folds_before := _road_folds
	if not design.make_jump(_selection_index):
		_history.pop_back()
		_toast("There isn't a long enough stretch of road here for a jump")
		return
	_rebuild_road()
	if _count_folded_faces(_ribbon) > folds_before:
		_undo()
		_toast("This corner is too tight for a jump — try a straighter part of the track")
		return
	_rebuild_props()
	_rebuild_handles()
	AudioManager.play("ui_click", -6.0)
	_toast("Jump built! Drag its point up or down to change how big it is")


## The numbers a person actually wants: how long a lap is, and how much is on it.
func _refresh_stats() -> void:
	if design.kind == TrackDesign.Kind.ARENA:
		stats_label.text = "Rink %d m across · %d things" % [
			int(round(design.arena_radius * 2.0)), design.features.size()
		]
		return
	var lap: float = _ribbon.length if _ribbon != null else 0.0
	stats_label.text = "Lap %d m · %d points · %d things" % [
		int(round(lap)), design.nodes.size(), design.features.size()
	]


func _refresh_panel() -> void:
	_syncing_panel = true
	var is_race: bool = design.kind == TrackDesign.Kind.RACE
	match _selection_kind:
		SelectionKind.NODE:
			var node: Dictionary = design.nodes[_selection_index]
			selection_label.text = "Track point %d of %d" % [
				_selection_index + 1, design.nodes.size()
			]
			size_row.show()
			size_label.text = "Width"
			size_slider.min_value = TrackDesign.MIN_HALF_WIDTH * 2.0
			size_slider.max_value = TrackDesign.MAX_HALF_WIDTH * 2.0
			# Shown as full road width, which is the number a person can picture;
			# the design stores half-widths because that's what RoadRibbon wants.
			size_slider.value = float(node["half_width"]) * 2.0
			height_row.show()
			rotate_row.hide()
			node_row.show()
			split_button.disabled = false
			jump_button.show()
			jump_button.disabled = design.nodes.size() >= TrackDesign.MAX_NODES
		SelectionKind.FEATURE:
			var feature: Dictionary = design.features[_selection_index]
			var spec: Dictionary = TrackDesign.FEATURES[String(feature["type"])]
			selection_label.text = String(spec["label"])
			size_row.show()
			size_label.text = "Size"
			size_slider.min_value = float(spec["min"])
			size_slider.max_value = float(spec["max"])
			size_slider.value = float(feature["size"])
			height_row.show()
			rotate_row.show()
			rotate_slider.value = rad_to_deg(float(feature["yaw"]))
			node_row.show()
			split_button.disabled = true
			jump_button.hide()
		_:
			selection_label.text = (
				"Click a red handle to bend the track"
				if is_race else "Click a blue handle to move something"
			)
			height_row.hide()
			rotate_row.hide()
			node_row.hide()
			jump_button.hide()
			if is_race:
				size_row.hide()
			else:
				size_row.show()
				size_label.text = "Rink size"
				size_slider.min_value = TrackDesign.MIN_ARENA_RADIUS
				size_slider.max_value = TrackDesign.MAX_ARENA_RADIUS
				size_slider.value = design.arena_radius

	var pos = _selected_position()
	if pos != null:
		height_slider.min_value = TrackDesign.MIN_HEIGHT
		height_slider.max_value = TrackDesign.MAX_HEIGHT
		height_slider.value = (pos as Vector3).y

	# Track points only exist on a race track; an arena has a rink instead.
	split_button.visible = is_race
	hint_label.text = _hint_text()
	_syncing_panel = false


func _hint_text() -> String:
	match _tool:
		Tool.ADD:
			return "Click the ground to drop a %s.   Drag empty space to spin the view, wheel to zoom." % (
				String(TrackDesign.FEATURES[_add_type]["label"]).substr(2)
			)
		Tool.ERASE:
			return "Click a handle to delete it.   Drag empty space to spin the view, wheel to zoom."
		_:
			return "Drag a handle to move it, hold Shift to raise or lower it.   Right-drag to pan, wheel to zoom."


# ---------------------------------------------------------------------------
# Templates, saving, loading, leaving
# ---------------------------------------------------------------------------

func _on_new_pressed() -> void:
	_guard_unsaved(_start_new_template, "Starting a new track will replace it.")


func _start_new_template() -> void:
	var template: Dictionary = TrackDesign.TEMPLATES[maxi(template_option.selected, 0)]
	_load_design(TrackDesign.from_template(String(template["id"])), "")
	_toast("Started a new %s" % String(template["label"]).substr(2))


## Opening a different track: forget the history (it belongs to the old one),
## and put the whole thing on screen.
func _load_design(new_design: TrackDesign, id: String) -> void:
	_history.clear()
	_unsaved = false
	_refresh_history_button()
	_adopt_design(new_design, id, true)


## Swap in `new_design`. `reframe` moves the camera to fit it, which is right when
## opening a track and wrong when undoing an edit to the one already on screen.
func _adopt_design(new_design: TrackDesign, id: String, reframe: bool) -> void:
	design = new_design
	saved_id = id
	_selection_kind = SelectionKind.NONE
	_selection_index = -1
	name_field.text = design.design_name
	_sync_color_pickers()
	if reframe:
		_frame_design()
	_rebuild_all()
	_refresh_panel()


func _sync_color_pickers() -> void:
	for column in color_grid.get_children():
		var label: Label = column.get_child(0)
		var picker: ColorPickerButton = column.get_child(1)
		# capitalize() is what put the label there; lowering it back is the
		# reverse, and every color key is a single lowercase word.
		picker.color = design.color_of(label.text.to_lower())


func _on_save_pressed() -> void:
	design.design_name = name_field.text.strip_edges()
	if design.design_name == "":
		design.design_name = "My Track"
		name_field.text = design.design_name
	var id := TrackLibrary.save_design(design, saved_id)
	if id == "":
		_toast("Couldn't save — check there's room on disk")
		return
	saved_id = id
	_unsaved = false
	AudioManager.play("ui_click", -4.0)
	_toast("Saved \"%s\"" % design.design_name)


func _on_open_pressed() -> void:
	open_list.clear()
	for entry in TrackLibrary.list_designs():
		var badge: String = "💥" if int(entry["kind"]) == TrackDesign.Kind.ARENA else "🏁"
		open_list.add_item("%s  %s" % [badge, String(entry["name"])])
		open_list.set_item_metadata(open_list.item_count - 1, String(entry["id"]))
	if open_list.item_count == 0:
		open_list.add_item("(nothing saved yet)")
		open_list.set_item_disabled(0, true)
	open_panel.show()


func _selected_library_id() -> String:
	var selected := open_list.get_selected_items()
	if selected.is_empty():
		return ""
	var meta = open_list.get_item_metadata(selected[0])
	return String(meta) if meta != null else ""


func _on_open_load_pressed() -> void:
	_guard_unsaved(_open_selected, "Opening another track will replace it.")


func _open_selected() -> void:
	var id := _selected_library_id()
	if id == "":
		return
	var loaded := TrackLibrary.load_design(id)
	if loaded == null:
		_toast("That track file couldn't be read")
		return
	open_panel.hide()
	_load_design(loaded, id)
	_toast("Opened \"%s\"" % loaded.design_name)


func _on_open_delete_pressed() -> void:
	var id := _selected_library_id()
	if id == "":
		return
	if TrackLibrary.delete_design(id):
		if saved_id == id:
			# The design stays open and editable; it just isn't saved anywhere
			# any more, so the next save writes a new file rather than silently
			# recreating the one that was just deleted.
			saved_id = ""
		_on_open_pressed()


## Drives the design you're looking at, unsaved edits included, and comes back
## here afterwards rather than to the main menu — the point of a test drive is
## the next edit.
func _on_test_drive_pressed() -> void:
	design.design_name = name_field.text.strip_edges()
	GameSettings.editor_design = design
	GameSettings.editor_design_id = saved_id
	GameSettings.exit_scene_path = "res://scenes/track_editor.tscn"
	GameSettings.exit_label = "← Back to Editor"
	# One player: a test drive is you checking your own track, and a split screen
	# with nobody in the bottom half isn't that.
	GameSettings.player_count = 1
	GameSettings.select_design(design)
	AudioManager.play("ui_click", -4.0)
	get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")


## Ctrl+Z as well as the button — and Escape asks about unsaved work rather than
## walking out with it.


func _on_back_pressed() -> void:
	_guard_unsaved(_leave_for_menu, "Going back to the menu will lose them.")


func _leave_for_menu() -> void:
	GameSettings.exit_scene_path = "res://scenes/main_menu.tscn"
	GameSettings.exit_label = "Main Menu"
	GameSettings.editor_design = null
	AudioManager.play("ui_click", -4.0)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _toast(message: String) -> void:
	toast_label.text = message
	toast_label.modulate.a = 1.0
	_toast_left = TOAST_SECONDS


func _process(delta: float) -> void:
	if _toast_left <= 0.0:
		return
	_toast_left -= delta
	if _toast_left <= 0.0:
		toast_label.text = ""
	else:
		toast_label.modulate.a = clampf(_toast_left / 0.6, 0.0, 1.0)
