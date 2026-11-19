class_name TopPhysics
extends RefCounted
## Pure helpers for tier shaping, lean, and precession (unit-testable).


static func tier_scale(magnitude: float) -> float:
	var thr: float = PhysicsSettings.get_value("tier_threshold")
	var blend: float = PhysicsSettings.get_value("tier_blend")
	var low_s: float = PhysicsSettings.get_value("low_scale")
	var high_s: float = PhysicsSettings.get_value("high_scale")
	var m: float = clampf(magnitude, 0.0, 1.0)
	var t: float = smoothstep(thr - blend, thr + blend, m)
	return m * lerpf(low_s, high_s, t)


static func shape_input(v: Vector2) -> Vector2:
	var m: float = v.length()
	if m < 0.0001:
		return Vector2.ZERO
	var scaled: float = tier_scale(m)
	return v.normalized() * scaled


static func spring_lean(lean: Vector2, target: Vector2, stiffness: float, delta: float) -> Vector2:
	var t: float = clampf(delta, 0.0, 0.05)
	var rate: float = clampf(stiffness / 25.0, 0.04, 1.0)
	var alpha: float = 1.0 - pow(1.0 - rate, t * 60.0)
	return lean.lerp(target, alpha)


static func apply_precession(
	lean: Vector2,
	spin_norm: float,
	rate: float,
	delta: float,
	spin_sign: float = 1.0
) -> Vector2:
	if rate <= 0.0001 or lean.length_squared() < 0.000001:
		return lean
	var sn: float = maxf(spin_norm, 0.15)
	var sg: float = signf(spin_sign) if absf(spin_sign) > 0.001 else 1.0
	var omega: float = rate * lean.length() / sn * delta * sg
	return Vector2(
		lean.x * cos(omega) - lean.y * sin(omega),
		lean.x * sin(omega) + lean.y * cos(omega)
	)