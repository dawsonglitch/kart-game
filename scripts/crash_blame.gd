class_name CrashBlame
extends RefCounted
## How a crash happened, and the wording for it. Every crash in the game reports
## a cause plus the kart on the hook for it (or null when nobody is), so the
## arena's scoreboard can credit whoever actually started it rather than just
## counting bonks. Same one-table-instead-of-three-switch-statements idea as
## item_kind.gd.

enum Cause {
	RAM,      # kart drove into another kart
	ROCKET,   # a fired ROCKET item connected
	OIL,      # slid off a dropped OIL slick into something
	HAZARD,   # a swinging log or a crate
	WALL,     # a wall, curb, or the rink boundary
	FALL,     # drove off the world and respawned
}

## `verb` completes "<attacker> ___ <victim>" in the HUD's hit feed; `solo`
## covers the same crash when nobody is to blame for it.
const DATA := {
	Cause.RAM:    {"icon": "💥", "verb": "bumped",   "solo": "Crashed!"},
	Cause.ROCKET: {"icon": "🚀", "verb": "rocketed", "solo": "Rocketed!"},
	Cause.OIL:    {"icon": "🛢", "verb": "oiled",    "solo": "Spun out!"},
	Cause.HAZARD: {"icon": "🪵", "verb": "shoved",   "solo": "Bonked!"},
	Cause.WALL:   {"icon": "🧱", "verb": "walled",   "solo": "Off track!"},
	Cause.FALL:   {"icon": "🕳", "verb": "dunked",   "solo": "Fell off!"},
}


static func icon(cause: int) -> String:
	return DATA.get(cause, DATA[Cause.RAM])["icon"]


static func verb(cause: int) -> String:
	return DATA.get(cause, DATA[Cause.RAM])["verb"]


static func solo_label(cause: int) -> String:
	return DATA.get(cause, DATA[Cause.RAM])["solo"]
