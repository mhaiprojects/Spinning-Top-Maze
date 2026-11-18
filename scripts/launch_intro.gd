class_name LaunchIntro
extends Control
## Skippable hand winding the top onto the start pad (~2.5 s).

signal finished

const DURATION := 2.6
const HOLD_AFTER := 0.15

var _t := 0.0
var _top_pos := Vector2.ZERO
var _active := false
var _done := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func start_at(top_global: Vector2) -> void:
	_top_pos = top_global
	_t = 0.0
	_active = true
	_done = false
	visible = true
	queue_redraw()


func skip() -> void:
	if not _active or _done:
		return
	_t = DURATION
	_finish()


func is_active() -> bool:
	return _active and not _done


func _process(delta: float) -> void:
	if not _active or _done:
		return
	_t += delta
	queue_redraw()
	if _t >= DURATION:
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	_active = false
	visible = false
	finished.emit()


func _draw() -> void:
	if not _active:
		return
	var vp: Transform2D = get_viewport().get_canvas_transform()
	var local_top: Vector2 = vp.affine_inverse() * _top_pos
	var wind: float = clampf(_t / 0.55, 0.0, 1.0)
	var place: float = clampf((_t - 0.55) / 0.55, 0.0, 1.0)
	var spin_t: float = clampf((_t - 1.1) / 1.2, 0.0, 1.0)
	var hand_base: Vector2 = local_top + Vector2(-90, -120 - wind * 40.0)
	var fingers: Vector2 = local_top + Vector2(0, -30 - place * 70.0)
	var palm: Vector2 = hand_base.lerp(fingers, 0.45 + wind * 0.25)
	draw_line(hand_base, palm, Color(1, 0.82, 0.68), 14.0, true)
	draw_circle(palm, 16.0, Color(1, 0.78, 0.62))
	draw_circle(fingers, 12.0, Color(1, 0.85, 0.7))
	for i in 4:
		var a: float = -PI * 0.35 + float(i) * 0.22 + wind * PI * 1.4
		draw_line(fingers, fingers + Vector2(cos(a), sin(a)) * 22.0, Color(1, 0.9, 0.75), 4.0)
	var top_r: float = 22.0 + spin_t * 8.0
	var top_p: Vector2 = local_top.lerp(local_top + Vector2(0, -6), place)
	if spin_t > 0.01:
		for s in 6:
			var ang: float = _t * 10.0 + float(s) * TAU / 6.0
			draw_arc(top_p, top_r * 1.2, ang, ang + 0.6, 8, Color(1, 0.7, 0.2, 0.35), 3.0)
	draw_circle(top_p, top_r, Color(0.95, 0.55, 0.15))
	draw_circle(top_p + Vector2(2, 3), top_r * 0.95, Color(0, 0, 0, 0.18))