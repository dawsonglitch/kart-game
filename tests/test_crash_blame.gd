extends SceneTree
## Unit tests for the crash-attribution rules — who is on the hook for a given
## crash, which is the whole basis of the bumper arena's scoreboard. The rules
## live across kart_controller.gd, rocket.gd and hazard_oil.gd and the awkward
## cases (chain reactions, mutual head-ons, blocked hits, delayed causes) are
## easy to break by accident, so they are pinned down here.
##
## The collision maths is exercised by calling _resolve_kart_collision directly
## with a synthetic contact normal rather than by driving karts into each other,
## so the test is deterministic and takes no wall-clock time.
##
## Run it with:
##     godot --headless --path . --script tests/test_crash_blame.gd

var _log: Array = []
var _fails: int = 0

func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
	print(("PASS  " if ok else "FAIL  ") + name + ("   " + detail if detail != "" else ""))

func _mk(scene, id: int, nm: String, pos: Vector3, yaw: float) -> Node:
	var k = scene.instantiate()
	k.player_id = id
	k.display_name = nm
	k.is_ai = true
	root.add_child(k)
	k.global_position = pos
	k.rotation.y = yaw
	k.crashed.connect(func(by, cause): _log.append({"victim": k, "by": by, "cause": cause}))
	return k

var _done := false

# Tests run on the first frame, not in _initialize(): the scene tree root isn't
# usable yet at _initialize() time, and the karts need to be inside the tree for
# global_transform (and the AudioManager autoload) to work at all.
func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true

func _clear_blame(karts: Array) -> void:
	for k in karts:
		k._blame_source = null
		k._blame_timer = 0.0

func _run() -> void:
	var scene = load("res://scenes/kart.tscn")

	# --- 1. A drives into a stationary B: only B is crashed, blamed on A ------
	var a = _mk(scene, 1, "A", Vector3(0, 0, 0), 0.0)
	var b = _mk(scene, 2, "B", Vector3(0, 0, -3), 0.0)
	a.speed = 12.0
	b.speed = 0.0
	_log.clear()
	a._resolve_kart_collision(b, Vector3(0, 0, 1))
	_check("rammer is blamed, victim is the one crashed",
		_log.size() == 1 and _log[0]["victim"] == b and _log[0]["by"] == a
		and _log[0]["cause"] == CrashBlame.Cause.RAM,
		str(_log.size()) + " event(s)")

	# --- 2. Head-on, both driving hard: both are credited --------------------
	# Clear the blame test 1 just pinned on B, or B ramming A back reads as A's
	# own doing (which is correct, and is what test 5 covers deliberately).
	_clear_blame([a, b])
	a.speed = 12.0
	b.speed = 12.0
	b.rotation.y = PI          # facing back up the track at A
	a.crash_cooldown_timer = 0.0
	b.crash_cooldown_timer = 0.0
	_log.clear()
	a._resolve_kart_collision(b, Vector3(0, 0, 1))
	var by_set := {}
	for e in _log:
		by_set[e["by"]] = e["victim"]
	_check("head-on is both drivers' doing", _log.size() == 2 and by_set.get(a) == b and by_set.get(b) == a,
		str(_log.size()) + " event(s)")

	# --- 3. Rocket: the shooter owns it, not the target's driving -------------
	var c = _mk(scene, 3, "C", Vector3(6, 0, 0), 0.0)
	_log.clear()
	var landed: bool = c.apply_stun(1.1, Vector3(0, 0, -14), CrashBlame.Cause.ROCKET, a)
	_check("rocket hit is charged to whoever fired it",
		landed and _log.size() == 1 and _log[0]["victim"] == c and _log[0]["by"] == a
		and _log[0]["cause"] == CrashBlame.Cause.ROCKET)

	# --- 4. ...and it sticks: C, still reeling, is punted into a wall ---------
	_log.clear()
	c.apply_stun(0.25, Vector3(0, 0, 2), CrashBlame.Cause.WALL)
	_check("wall you were punted into still scores for the puncher",
		_log.size() == 1 and _log[0]["by"] == a and _log[0]["cause"] == CrashBlame.Cause.WALL)

	# --- 5. ...and through a third kart: A rocketed C, C bounces into D -------
	var d = _mk(scene, 4, "D", Vector3(6, 0, -3), 0.0)
	c.speed = 12.0
	d.speed = 0.0
	c.crash_cooldown_timer = 0.0
	_log.clear()
	c._resolve_kart_collision(d, Vector3(0, 0, 1))
	_check("blame chains through a shoved kart to the original instigator",
		_log.size() == 1 and _log[0]["victim"] == d and _log[0]["by"] == a,
		"by=" + str(_log[0]["by"].display_name if _log.size() > 0 and _log[0]["by"] else "null"))

	# --- 6. An unforced wall bonk is nobody's crash to bank ------------------
	var e = _mk(scene, 5, "E", Vector3(12, 0, 0), 0.0)
	_log.clear()
	e.apply_stun(0.25, Vector3(0, 0, 2), CrashBlame.Cause.WALL)
	_check("solo wall bonk is credited to nobody",
		_log.size() == 1 and _log[0]["by"] == null)

	# --- 7. A shield eats the hit entirely — no crash, no credit -------------
	e._raise_shield()
	_log.clear()
	var blocked: bool = e.apply_stun(1.1, Vector3(0, 0, -14), CrashBlame.Cause.ROCKET, a)
	_check("shielded hit scores nothing", (not blocked) and _log.size() == 0)

	# --- 8. Oil: the dropper owns whatever the slick causes ------------------
	# B is still carrying blame from the head-on, which is the point here: a
	# slick's culprit was settled when it was dropped, so it must NOT flatten
	# through whatever is happening to B at the moment F slides onto it.
	var f = _mk(scene, 6, "F", Vector3(18, 0, 0), 0.0)
	f.mark_blame(b, 1.2)                 # what hazard_oil.gd does on overlap
	_log.clear()
	f.apply_stun(0.25, Vector3(0, 0, 2), CrashBlame.Cause.WALL)
	_check("crash while sliding on someone's oil is charged to them",
		_log.size() == 1 and _log[0]["by"] == b)

	# --- 9. Blame expires: F recovers, then bins it on its own ---------------
	f._blame_timer = 0.0
	f._blame_source = null
	_log.clear()
	f.apply_stun(0.25, Vector3(0, 0, 2), CrashBlame.Cause.WALL)
	_check("blame expires — a later solo crash is your own", _log[0]["by"] == null)

	# --- 10. Firing a rocket is your own act, even mid-shunt -----------------
	# G has just been rammed by A, so A owns G's crashes. But G choosing to fire
	# is G's doing: the rocket must not be redirected to A.
	var g = _mk(scene, 7, "G", Vector3(24, 0, 0), 0.0)
	var h = _mk(scene, 8, "H", Vector3(30, 0, 0), 0.0)
	g.mark_blame(a, 0.25)                # A rammed G a moment ago
	_log.clear()
	h.apply_stun(1.1, Vector3(0, 0, -14), CrashBlame.Cause.ROCKET, g)
	_check("a rocket belongs to whoever fired it, not to whoever rammed them",
		_log.size() == 1 and _log[0]["by"] == g)
	_log.clear()
	h.apply_stun(0.25, Vector3(0, 0, 2), CrashBlame.Cause.WALL)
	_check("the shooter still owns the wall their target lands in",
		_log.size() == 1 and _log[0]["by"] == g)

	# --- 11. Scoreboard: credit the causer, tie-break on least taken ---------
	var mgr = load("res://scripts/arena_manager.gd").new()
	root.add_child(mgr)
	for k in [a, b, c]:
		mgr.register_kart(k)
	mgr.arena_active = true
	# A and B finish level on 2 caused apiece, but A wore one more than B did, so
	# the tie-break has to separate them. C's single hit keeps it off the tie.
	b.crashed.emit(a, CrashBlame.Cause.RAM)      # a scores, b wears one
	c.crashed.emit(a, CrashBlame.Cause.ROCKET)   # a scores, c wears one
	a.crashed.emit(b, CrashBlame.Cause.RAM)      # b scores, a wears one
	c.crashed.emit(b, CrashBlame.Cause.RAM)      # b scores, c wears one
	a.crashed.emit(c, CrashBlame.Cause.RAM)      # c scores, a wears a second
	a.crashed.emit(null, CrashBlame.Cause.WALL)  # nobody scores, nobody debited
	var standings: Array = mgr.get_standings()
	_check("crashes caused are what is scored",
		mgr.get_crash_count(a) == 2 and mgr.get_crash_count(b) == 2 and mgr.get_crash_count(c) == 1)
	_check("a solo wall bonk is charged to nobody, in either column",
		mgr.get_crashes_taken(a) == 2 and mgr.get_crash_count(a) == 2)
	_check("tie breaks toward whoever was picked on less",
		standings[0]["display_name"] == "B" and standings[1]["display_name"] == "A"
		and standings[2]["display_name"] == "C",
		str(standings))

	print("\n%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)

