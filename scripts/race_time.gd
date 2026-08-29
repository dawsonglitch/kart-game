class_name RaceTime
extends RefCounted
## The two ways a duration is written on screen, in one place so the HUD and the
## end-of-race standings can't drift apart on how a lap time looks.

## "1:02.47" — the race clock and every finishing time. Hundredths matter here:
## they're usually the whole margin between two karts.
static func stamp(t: float) -> String:
	@warning_ignore("integer_division") # intentional — minutes as a whole number
	var minutes := int(t) / 60
	var seconds := int(t) % 60
	var ms := int((t - int(t)) * 100)
	return "%d:%02d.%02d" % [minutes, seconds, ms]


## "1:02" — whole seconds only, for a clock counting *down*. Hundredths flickering
## past on a countdown are just noise next to the karts.
static func clock(t: float) -> String:
	var whole := int(ceil(t))
	@warning_ignore("integer_division") # intentional — minutes as a whole number
	var minutes := whole / 60
	return "%d:%02d" % [minutes, whole % 60]
