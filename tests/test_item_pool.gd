extends SceneTree
## Unit tests for which power-ups a box can hand out in which mode. The race
## pool is all four items; the bumper arena's is the two attack weapons plus the
## shield, no turbo (issue #13). The pool lives in item_kind.gd and is applied by
## item_box.gd, so both halves are checked here: the draw itself, and that a real
## box in a real arena session actually draws from the smaller list.
##
## `GameSettings` is fetched from the tree instead of by its autoload name: a
## `--script` SceneTree is compiled before the autoloads are registered, so the
## bare identifier doesn't resolve here (it does in every script loaded later,
## which is why item_kind.gd can use it directly).
##
## Rolls are sampled rather than reasoned about — the draw is weighted and
## random, so "never turbo" is only meaningful over a lot of tries. The RNG is
## seeded so a failure reproduces.
##
## Run it with:
##     godot --headless --path . --script tests/test_item_pool.gd

const SAMPLES := 4000

var _fails: int = 0

func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
	print(("PASS  " if ok else "FAIL  ") + name + ("   " + detail if detail != "" else ""))

var _done := false

# Tests run on the first frame, not in _initialize(): the box has to be inside
# the tree before body_entered handling (and the AudioManager autoload) works.
func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true


## Every kind `roll()` produced over SAMPLES draws, as a kind -> count table.
func _sample(rng: RandomNumberGenerator, pool: Array, rank_fraction: float) -> Dictionary:
	var seen := {}
	for i in SAMPLES:
		var kind: int = ItemKind.roll(rng, rank_fraction, pool)
		seen[kind] = seen.get(kind, 0) + 1
	return seen


func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260830
	var settings := root.get_node("/root/GameSettings")
	var mode_race: int = settings.GameMode["RACE"]
	var mode_arena: int = settings.GameMode["ARENA"]

	# --- 1. The mode -> pool mapping -----------------------------------------
	_check("race mode draws from the full pool",
		ItemKind.pool_for_mode(mode_race) == ItemKind.RACE_POOL)
	_check("arena mode draws from the weapons-and-shield pool",
		ItemKind.pool_for_mode(mode_arena) == ItemKind.ARENA_POOL)
	_check("arena pool is exactly rocket, oil, shield",
		ItemKind.ARENA_POOL.size() == 3
		and ItemKind.ARENA_POOL.has(ItemKind.Kind.ROCKET)
		and ItemKind.ARENA_POOL.has(ItemKind.Kind.OIL)
		and ItemKind.ARENA_POOL.has(ItemKind.Kind.SHIELD),
		str(ItemKind.ARENA_POOL))

	# --- 2. The arena draw never turns up a turbo, at either end of the field -
	# Both rank fractions, because the leader/last weighting is what shifts the
	# odds around: a filter that only held for the middling case would be a bug
	# waiting for a kid in first place.
	for rank in [0.0, 1.0]:
		var arena := _sample(rng, ItemKind.ARENA_POOL, rank)
		_check("no turbo in the arena at rank_fraction %.1f" % rank,
			not arena.has(ItemKind.Kind.TURBO), str(arena.get(ItemKind.Kind.TURBO, 0)) + " drawn")
		_check("all three arena items come up at rank_fraction %.1f" % rank,
			arena.size() == 3, str(arena.size()) + " distinct kind(s)")
		_check("no empty draws in the arena at rank_fraction %.1f" % rank,
			not arena.has(ItemKind.Kind.NONE))

	# --- 3. A race is untouched: all four still appear ------------------------
	var race := _sample(rng, ItemKind.RACE_POOL, 0.5)
	_check("a race still hands out all four items", race.size() == 4,
		str(race.size()) + " distinct kind(s)")
	_check("roll() defaults to the race pool",
		_sample(rng, ItemKind.RACE_POOL, 0.5).has(ItemKind.Kind.TURBO))

	# --- 4. A real box in an arena session honours the pool -------------------
	# Drives the actual pickup path (item_box's body_entered handler against a
	# kart) rather than calling roll() again, so a box that forgot to ask for the
	# arena pool fails here even though section 2 passes.
	settings.game_mode = mode_arena
	var kart_scene := load("res://scenes/kart.tscn")
	var box_scene := load("res://scenes/item_box.tscn")
	var granted := {}
	for i in 400:
		var box = box_scene.instantiate()
		root.add_child(box)
		var kart = kart_scene.instantiate()
		kart.player_id = 1
		kart.is_ai = true
		root.add_child(kart)
		box._on_body_entered(kart)
		granted[kart.held_item] = granted.get(kart.held_item, 0) + 1
		kart.free()
		box.free()
	_check("boxes in an arena session never grant a turbo",
		not granted.has(ItemKind.Kind.TURBO), str(granted.get(ItemKind.Kind.TURBO, 0)) + " granted")
	_check("boxes in an arena session grant all three arena items",
		granted.size() == 3, str(granted.size()) + " distinct kind(s)")
	_check("every arena pickup grants something",
		not granted.has(ItemKind.Kind.NONE))

	print("")
	print("%d check(s) failed" % _fails)
	quit(1 if _fails > 0 else 0)
