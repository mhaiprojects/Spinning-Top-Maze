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


static func input_picker_size(vp: Vector2) -> float:
	return maxf(48.0, 52.0 * ui_scale(vp))


## Horizontal space for the bottom-left picker; used for launch bar placement only (not maze inset).
static func launch_bar_left_clearance(vp: Vector2) -> float:
	var sz: float = input_picker_size(vp)
	return edge_margin(vp, 8.0) + sz + edge_margin(vp, 4.0)


static func scaled_heights(vp: Vector2) -> Dictionary:
	var s: float = ui_scale(vp)
	var picker_sz: float = input_picker_size(vp)
	var bottom_pad: float = maxf(140.0 * s, picker_sz + edge_margin(vp, 10.0) * 2.0)
	return {
		"scale": s,
		"top": 152.0 * s,
		"bottom": bottom_pad,
		"margin": edge_margin(vp, 10.0),
	}