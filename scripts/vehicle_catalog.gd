class_name VehicleCatalog
extends RefCounted
## Stable IDs shared by the menu, session settings and kart visuals.

enum Kind { CLASSIC_KART, CODEX_JEEP }

const OPTIONS := [
	{"id": Kind.CLASSIC_KART, "name": "Classic Kart"},
	{"id": Kind.CODEX_JEEP, "name": "Codex Jeep"},
]
const CODEX_JEEP_SCENE := "res://assets/models/vehicles/codex_jeep.glb"


static func valid_id(id: int) -> int:
	return id if id == Kind.CODEX_JEEP else Kind.CLASSIC_KART
