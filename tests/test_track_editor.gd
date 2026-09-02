extends SceneTree
## Drives the track designer's UI headlessly. Run:
##
##     godot --headless --path . --script tests/test_track_editor.gd
##
## The editor is the one part of this feature with no other way to check it: the
## builders have tests/test_track_design.gd, but the editor's own wiring — the
## palette it generates from TrackDesign's tables, the panel that has to follow
## the selection, the buttons that rebuild a whole world on every press — is only
## exercised by someone clicking it.
##
## So this clicks it. Everything below goes through the real controls
## (`button.pressed.emit()`, `slider.value = x`) rather than calling the handlers
## directly, which is what makes it a check on the wiring and not just on the
## functions.
##
## What it CANNOT check is the part that needs a mouse and a camera: picking a
## handle out of the 3D view, dragging it, and how any of it looks. Those need a
## real windowed session.

var _done := false
var _fails := 0

var editor: Node3D


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	print("\n%s  (%d failures)" % ["FAILED" if _fails > 0 else "ALL PASSED", _fails])
	return true


func _check(check_name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
	print(("PASS  " if ok else "FAIL  ") + check_name + ("   " + detail if detail != "" else ""))


func _panel(path: String) -> Node:
	return editor.get_node("UI/Root/Panel/Scroll/VBox/%s" % path)


func _run() -> void:
	# A clean library, since the editor's Open dialog reads the real one.
	for entry in TrackLibrary.list_designs():
		TrackLibrary.delete_design(String(entry["id"]))

	editor = load("res://scenes/track_editor.tscn").instantiate()
	root.add_child(editor)
	_check("editor opens", editor.design != null)

	_test_generated_panel()
	_test_templates()
	_test_placing_and_removing()
	_test_colors()
	_test_saving_and_opening()

	editor.queue_free()


func _test_generated_panel() -> void:
	print("\n--- the panel builds itself from TrackDesign's tables ---")
	var palette: GridContainer = _panel("FeatureGrid")
	_check(
		"one palette button per feature type",
		palette.get_child_count() == TrackDesign.FEATURE_ORDER.size(),
		"%d buttons for %d types" % [palette.get_child_count(), TrackDesign.FEATURE_ORDER.size()]
	)
	var colors: GridContainer = _panel("ColorGrid")
	_check(
		"one picker per customisable color",
		colors.get_child_count() == TrackDesign.COLOR_DEFAULTS.size(),
		"%d pickers for %d colors" % [colors.get_child_count(), TrackDesign.COLOR_DEFAULTS.size()]
	)
	var templates: OptionButton = _panel("TemplateRow/TemplateOption")
	_check("every template is offered", templates.item_count == TrackDesign.TEMPLATES.size())

	_check("a road was built", editor.get_node("Preview/Road").get_child_count() > 0)
	_check(
		"a handle per road node",
		editor.get_node("Handles").get_child_count() == editor.design.nodes.size(),
		"%d handles" % editor.get_node("Handles").get_child_count()
	)


func _test_templates() -> void:
	print("\n--- starting from a template ---")
	var option: OptionButton = _panel("TemplateRow/TemplateOption")
	for i in range(TrackDesign.TEMPLATES.size()):
		var template: Dictionary = TrackDesign.TEMPLATES[i]
		option.select(i)
		_panel("TemplateRow/NewButton").pressed.emit()
		var id := String(template["id"])
		_check("%s loads into the editor" % id, editor.design.kind == int(template["kind"]))
		# The arena has no road nodes, so its handles are only its features; the
		# race templates get one per node plus one per feature. Either way the
		# handle count has to track the design, or there are points on screen
		# that move nothing.
		var expected: int = editor.design.features.size()
		if editor.design.kind == TrackDesign.Kind.RACE:
			expected += editor.design.nodes.size()
		_check(
			"%s draws a handle for everything" % id,
			editor.get_node("Handles").get_child_count() == expected,
			"%d of %d" % [editor.get_node("Handles").get_child_count(), expected]
		)
		# Switching between a race and an arena swaps what the preview even is.
		var road: Node3D = editor.get_node("Preview/Road")
		_check("%s previews something" % id, road.get_child_count() > 0)


func _test_placing_and_removing() -> void:
	print("\n--- adding and removing things ---")
	var option: OptionButton = _panel("TemplateRow/TemplateOption")
	option.select(0) # the oval
	_panel("TemplateRow/NewButton").pressed.emit()

	var before: int = editor.design.features.size()
	# Picking a palette button and dropping one is two separate acts in the UI;
	# only the first is reachable without a mouse, so the drop goes through the
	# design directly and the rebuild is triggered the way the click would.
	(_panel("FeatureGrid").get_child(1) as Button).pressed.emit() # rock
	_check("picking a palette item selects the Add tool", (_panel("ToolRow/AddToolButton") as Button).button_pressed)

	editor.design.add_feature("rock", Vector3(40.0, 0.0, 40.0))
	editor.design.add_feature("water", Vector3(-60.0, 0.0, 0.0))
	_panel("TemplateRow/NewButton").pressed.emit() # any rebuild path
	_check("a new template clears the previous edits", editor.design.features.size() != before + 2)

	# Road points: the panel's own buttons, on a selected node.
	var nodes_before: int = editor.design.nodes.size()
	editor._select(1, 0) # SelectionKind.NODE, first node
	_panel("NodeRow/SplitButton").pressed.emit()
	_check("Add point lengthens the lap", editor.design.nodes.size() == nodes_before + 1)
	_panel("NodeRow/DeleteButton").pressed.emit()
	_check("Delete removes it again", editor.design.nodes.size() == nodes_before)

	# ...and can't take the lap below the minimum, however many times it's pressed.
	for _i in range(nodes_before + 4):
		editor._select(1, 0)
		_panel("NodeRow/DeleteButton").pressed.emit()
	_check(
		"a lap can't be deleted away",
		editor.design.nodes.size() >= TrackDesign.MIN_NODES,
		"%d nodes left" % editor.design.nodes.size()
	)
	_check("the road survived it", editor.get_node("Preview/Road").get_child_count() > 0)


func _test_colors() -> void:
	print("\n--- colors ---")
	var option: OptionButton = _panel("TemplateRow/TemplateOption")
	option.select(0)
	_panel("TemplateRow/NewButton").pressed.emit()

	var picker: ColorPickerButton = _panel("ColorGrid").get_child(0).get_child(1)
	var chosen := Color(0.11, 0.72, 0.33)
	picker.color = chosen
	picker.color_changed.emit(chosen)
	var key: String = (_panel("ColorGrid").get_child(0).get_child(0) as Label).text.to_lower()
	_check("the picker writes into the design", editor.design.color_of(key).is_equal_approx(chosen))

	# Loading a different design has to push its colors back into the pickers, or
	# the panel is showing one track's palette over another track's road.
	option.select(1)
	_panel("TemplateRow/NewButton").pressed.emit()
	_check(
		"opening another track resets the pickers",
		picker.color.is_equal_approx(TrackDesign.COLOR_DEFAULTS[key])
	)


func _test_saving_and_opening() -> void:
	print("\n--- saving and reopening ---")
	var name_field: LineEdit = _panel("NameField")
	name_field.text = "Test Track"
	name_field.text_changed.emit("Test Track")
	_panel("SaveButton").pressed.emit()
	_check("saved to the library", TrackLibrary.list_designs().size() == 1)
	_check("saved under the typed name", editor.saved_id != "" and TrackLibrary.load_design(editor.saved_id).design_name == "Test Track")

	# Saving again overwrites rather than piling up a second copy every press.
	_panel("SaveButton").pressed.emit()
	_panel("SaveButton").pressed.emit()
	_check("saving again overwrites", TrackLibrary.list_designs().size() == 1)

	# An empty name still has to produce a file rather than a track called "".
	name_field.text = "   "
	name_field.text_changed.emit("   ")
	_panel("SaveButton").pressed.emit()
	_check("a blank name gets a default", editor.design.design_name != "")

	var list: ItemList = editor.get_node("UI/Root/OpenPanel/VBox/List")
	_panel("BottomRow/OpenButton").pressed.emit()
	_check("Open lists the saved track", list.item_count == 1)
	list.select(0)
	editor.get_node("UI/Root/OpenPanel/VBox/Row/LoadButton").pressed.emit()
	_check("opening it loads it", editor.design.design_name != "")
	_check("and the id comes with it", editor.saved_id != "")

	# Deleting the open track leaves it on screen but unsaved, so the next save
	# writes a new file instead of quietly resurrecting the deleted one.
	var open_id: String = editor.saved_id
	_panel("BottomRow/OpenButton").pressed.emit()
	list.select(0)
	editor.get_node("UI/Root/OpenPanel/VBox/Row/DeleteButton").pressed.emit()
	_check("deleting removes the file", not TrackLibrary.exists(open_id))
	_check("the open design forgets its file", editor.saved_id == "")
	_check("but is still being edited", editor.design != null and editor.get_node("Preview/Road").get_child_count() > 0)

	for entry in TrackLibrary.list_designs():
		TrackLibrary.delete_design(String(entry["id"]))
