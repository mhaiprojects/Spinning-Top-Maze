class_name TopPhysics
extends RefCounted
## Pure helpers for tier shaping, lean, and precession (unit-testable).


static func tier_scale(magnitude: float) -> float:
	if not is_finite(magnitude):
		return 0.0
	var thr: float = PhysicsSettings.get_value("tier_threshold")
	var blend: float = PhysicsSettings.get_value("tier_blend")
	var low_s: float = PhysicsSettings.get_value("low_scale")
	var high_s: float = PhysicsSettings.get_value("high_scale")
	if not is_finite(thr) or not is_finite(blend) or not is_finite(low_s) or not is_finite(high_s):
		return 0.0
	var m: float = clampf(magnitude, 0.0, 1.0)
	var t: float = smoothstep(thr - blend, thr + blend, m)
	var out: float = m * lerpf(low_s, high_s, t)
	return out if is_finite(out) else 0.0


static func shape_input(v: Vector2) -> Vector2:
	if not v.is_finite():
		return Vector2.ZERO
	var m: float = v.length()
	if m < 0.0001:
		return Vector2.ZERO
	var scaled: float = tier_scale(m)
	var out: Vector2 = v.normalized() * scaled
	return out if out.is_finite() else Vector2.ZERO


static func spring_lean(lean: Vector2, target: Vector2, stiffness: float, delta: float) -> Vector2:
	if not lean.is_finite():
		lean = Vector2.ZERO
	if not target.is_finite():
		target = Vector2.ZERO
	var t: float = clampf(delta, 0.0, 0.05)
	var rate: float = stiffness / 25.0
	if not is_finite(rate) or rate <= 0.0:
		return lean
	var r: float = minf(rate, 1.0)
	var alpha: float = 1.0 - pow(1.0 - r, t * 60.0)
	if rate >= 1.0:
		alpha = 1.0
	var out: Vector2 = lean.lerp(target, alpha)
	return out if out.is_finite() else lean


static func apply_precession(
	lean: Vector2,
	spin_norm: float,
	rate: float,
	delta: float,
	spin_sign: float = 1.0
) -> Vector2:
	if not lean.is_finite():
		return Vector2.ZERO
	if rate <= 0.0001 or lean.length_squared() < 0.000001:
		return lean
	var sn: float = maxf(spin_norm, 0.15)
	if not is_finite(sn):
		sn = 0.15
	var sg: float = signf(spin_sign) if absf(spin_sign) > 0.001 else 1.0
	var omega: float = rate * lean.length() / sn * delta * sg
	if not is_finite(omega):
		return lean
	omega = clampf(omega, -TAU * 4.0, TAU * 4.0)
	var out := Vector2(
		lean.x * cos(omega) - lean.y * sin(omega),
		lean.x * sin(omega) + lean.y * cos(omega)
	)
	return out if out.is_finite() else lean