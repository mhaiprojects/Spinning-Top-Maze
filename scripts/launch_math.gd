class_name LaunchMath
extends RefCounted
## Pure launch mini-game math for unit tests.

const POWER_MIN := 25.0
const POWER_MAX := 100.0


static func power_for_offset(offset_norm: float) -> float:
	var o: float = clampf(absf(offset_norm), 0.0, 1.0)
	var t: float = 1.0 - o
	return lerpf(POWER_MIN, POWER_MAX, t * t)