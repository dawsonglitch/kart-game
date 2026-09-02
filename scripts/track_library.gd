class_name TrackLibrary
extends RefCounted
## Where saved tracks live: one JSON file per design under `user://tracks/`.
##
## `user://` is the per-user writeable directory Godot gives every exported game
## (~/Library/Application Support/Godot/app_userdata/RacingGameWithKids on this
## machine), which is what "stored locally" has to mean — res:// is read-only in
## an export, so saving into the project folder would work in the editor and
## silently fail for anyone playing the actual game.
##
## Files are named from a slug of the track's name plus a counter, so the folder
## is browsable ("my-oval.json") rather than a pile of UUIDs, and two tracks
## called the same thing don't overwrite each other.

const DIR := "user://tracks"
const EXTENSION := ".json"
## A saved design is a few kilobytes of JSON; anything past this is not one of
## ours and isn't worth parsing.
const MAX_FILE_BYTES := 512 * 1024


static func _ensure_dir() -> bool:
	if DirAccess.dir_exists_absolute(DIR):
		return true
	return DirAccess.make_dir_recursive_absolute(DIR) == OK


## Every saved design, newest first, as {"id", "name", "kind", "modified"}.
## The menu shows this list; it does not parse the full designs until one is
## actually picked.
static func list_designs() -> Array:
	var found: Array = []
	if not DirAccess.dir_exists_absolute(DIR):
		return found
	for file_name in DirAccess.get_files_at(DIR):
		if not file_name.ends_with(EXTENSION):
			continue
		var id := file_name.substr(0, file_name.length() - EXTENSION.length())
		var design := load_design(id)
		if design == null:
			continue
		found.append({
			"id": id,
			"name": design.design_name,
			"kind": design.kind,
			"modified": FileAccess.get_modified_time(_path_for(id)),
		})
	found.sort_custom(func(a, b): return int(a["modified"]) > int(b["modified"]))
	return found


static func load_design(id: String) -> TrackDesign:
	var path := _path_for(id)
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Track library: couldn't open %s" % path)
		return null
	if file.get_length() > MAX_FILE_BYTES:
		push_warning("Track library: %s is too big to be a saved track" % path)
		return null
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Track library: %s isn't valid track JSON" % path)
		return null
	return TrackDesign.from_dict(parsed)


## Writes `design` and returns the id it was stored under, or "" on failure.
## Pass the id an existing design was loaded from as `overwrite_id` to save over
## it; leave it empty to create a new file (so "Save As" and "Save" are the same
## call with one argument different).
static func save_design(design: TrackDesign, overwrite_id: String = "") -> String:
	if not _ensure_dir():
		push_warning("Track library: couldn't create %s" % DIR)
		return ""
	var id := overwrite_id if overwrite_id != "" else _unique_id(design.design_name)
	var file := FileAccess.open(_path_for(id), FileAccess.WRITE)
	if file == null:
		push_warning("Track library: couldn't write %s" % _path_for(id))
		return ""
	file.store_string(JSON.stringify(design.to_dict(), "\t"))
	file.close()
	return id


static func delete_design(id: String) -> bool:
	var path := _path_for(id)
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK


static func exists(id: String) -> bool:
	return id != "" and FileAccess.file_exists(_path_for(id))


static func _path_for(id: String) -> String:
	return "%s/%s%s" % [DIR, id, EXTENSION]


## "Dad's Big Loop!" -> "dads-big-loop", then "-2", "-3"... if that's taken.
## Only spaces (and characters already acting as separators) become dashes;
## apostrophes, punctuation and emoji are dropped, so "Dad's" stays one word
## rather than turning into "dad-s".
static func _unique_id(display_name: String) -> String:
	const SEPARATORS := [" ", "\t", "-", "_", "."]
	var base := ""
	for character in display_name.to_lower():
		if character.is_valid_identifier() or character.is_valid_int():
			base += character
		elif character in SEPARATORS and base.length() > 0 and not base.ends_with("-"):
			base += "-"
	base = base.trim_suffix("-").substr(0, 40)
	if base == "":
		base = "track"
	if not exists(base):
		return base
	var suffix := 2
	while exists("%s-%d" % [base, suffix]):
		suffix += 1
	return "%s-%d" % [base, suffix]
