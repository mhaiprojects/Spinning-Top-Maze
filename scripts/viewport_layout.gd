class_name ViewportLayout
extends RefCounted
## Scale chrome (HUD, launch bar, menu) for varying aspect ratios (portrait / landscape).

const DESIGN_SIZE := Vector2(720, 1280)


static func ui_scale(vp: Vector2) -> float:
	var fit: float = minf(vp.x / DESIGN_SIZE.x, vp.y / DESIGN_SIZE.y)
	var short_side: float = minf(vp.x, vp.y)
	var boosted: float = short_side / DESIGN_SIZE.x * 0.88
	return clampf(maxf(fit, boosted), 0.42, 1.4)


static func edge_margin(vp: Vector2, base: float = 10.0) -> float:
	return maxf(4.0, base * ui_scale(vp))


static func hud_base_height() -> float:
	return 152.0 * ui_scale(DESIGN_SIZE)


static func bottom_base_height() -> float:
	return 140.0 * ui_scale(DESIGN_SIZE)


static func scaled_heights(vp: Vector2) -> Dictionary:
	var s: float = ui_scale(vp)
	return {
		"scale": s,
		"top": 152.0 * s,
		"bottom": 140.0 * s,
		"margin": edge_margin(vp, 10.0),
	}