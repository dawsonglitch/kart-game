class_name ItemKind
extends RefCounted
## The power-up catalog: one enum plus the per-item presentation data (label,
## icon, HUD color) that the item box, the HUD, and the kart all need to agree
## on. Kept in one place so adding an item means touching one table rather than
## three switch statements.

enum Kind {
	NONE,
	TURBO,   # instant big speed burst
	ROCKET,  # fires forward, bonks the first kart it reaches
	OIL,     # drops a slick behind you
	SHIELD,  # absorbs the next hit
}

## Icons are emoji rather than sprite assets deliberately — the HUD is already
## all-Label based (no atlas, no theme icons), and these render at any size
## without a new import pipeline for four tiny textures.
const DATA := {
	Kind.NONE: {"label": "", "icon": "", "color": Color(1, 1, 1, 0.4)},
	Kind.TURBO: {"label": "Turbo!", "icon": "🔥", "color": Color(1, 0.6, 0.1)},
	Kind.ROCKET: {"label": "Rocket!", "icon": "🚀", "color": Color(1, 0.3, 0.25)},
	Kind.OIL: {"label": "Oil Slick!", "icon": "🛢", "color": Color(0.45, 0.35, 0.7)},
	Kind.SHIELD: {"label": "Shield!", "icon": "🛡", "color": Color(0.3, 0.8, 1)},
}


static func label(kind: int) -> String:
	return DATA.get(kind, DATA[Kind.NONE])["label"]


static func icon(kind: int) -> String:
	return DATA.get(kind, DATA[Kind.NONE])["icon"]


static func color(kind: int) -> Color:
	return DATA.get(kind, DATA[Kind.NONE])["color"]


## Weighted draw. Karts further back get the more disruptive items (rocket) more
## often and the defensive one less — the standard kart-racer rubber band, so a
## kid who's behind has a real shot at catching up. `rank_fraction` is 0.0 for
## the leader and 1.0 for last place.
static func roll(rng: RandomNumberGenerator, rank_fraction: float = 0.5) -> int:
	var behind: float = clamp(rank_fraction, 0.0, 1.0)
	var weights := {
		Kind.TURBO: 3.0 + behind * 2.0,
		Kind.ROCKET: 1.5 + behind * 3.0,
		Kind.OIL: 2.5 - behind * 1.0,
		Kind.SHIELD: 2.5 - behind * 1.5,
	}
	var total := 0.0
	for kind in weights:
		total += weights[kind]
	var pick := rng.randf() * total
	for kind in weights:
		pick -= weights[kind]
		if pick <= 0.0:
			return kind
	return Kind.TURBO
