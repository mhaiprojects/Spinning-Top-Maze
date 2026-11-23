class_name LaunchMinigame
extends Node2D
## Fishing-style power launch: marker ping-pongs on a bar.

signal released(power: float)

const SHOW_RESULT_SEC := 0.85
const Launch := preload("res://scripts/launch_math.gd")

var wave: int = 1
var active := false
var _pos := 0.0
var _dir := 1.0
var _speed := 1.6
var _sweet_frac := 0.14
var _result_power := -1.0
var _result_t := 0.0
var _bar_rect := Rect2()
var _marker_trail: Array[float] = []


func bar_screen_rect() -> Rect2:
	return _bar_rect


func setup(bar_rect: Rect2, wave_num: int) -> void:
	_bar_rect = bar_rect
	wave = wave_num
	active = true
	var p: Dictionary = Difficulty.params_for_wave(wave_num)
	_speed = float(p.marker_speed)
	_sweet_frac = float(p.sweet_spot_frac)
	_pos = 0.0
	_dir = 1.0
	_result_power = -1.0
	_result_t = 0.0
	_marker_trail.clear()
	visible = true
	z_index = 20
	set_process(true)
	queue_redraw()


func cancel() -> void:
	active = false
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	if _result_power >= 0.0:
		_result_t += delta
		if _result_t >= SHOW_RESULT_SEC:
			released.emit(_result_power)
			cancel()
		queue_redraw()
		return
	if not active:
		return
	_pos += _dir * _speed * delta
	if _pos > 1.0:
		_pos = 1.0
		_dir = -1.0
	elif _pos < -1.0:
		_pos = -1.0
		_dir = 1.0
	_marker_trail.push_back(_pos)
	while _marker_trail.size() > 8:
		_marker_trail.pop_front()
	queue_redraw()


func try_release() -> bool:
	if not active or _result_power >= 0.0:
		return false
	_result_power = Launch.power_for_offset(_pos)
	_result_t = 0.0
	if OS.has_feature("web"):
		var n: Node = get_tree().root.get_node_or_null("TiltInput")
		if n and n.has_method("request_web_permission"):
			n.call("request_web_permission")
	queue_redraw()
	return true


func _result_label() -> String:
	if _result_power >= 92.0:
		return "Perfect!"
	if _result_power >= 70.0:
		return "Good"
	return "Weak"


func _draw() -> void:
	if _bar_rect.size.x < 1.0:
		return
	var cx: float = _bar_rect.position.x + _bar_rect.size.x * 0.5
	var bar_y: float = _bar_rect.position.y + _bar_rect.size.y * 0.5
	var inner := _bar_rect.grow_individual(-3, -3, -3, -3)
	draw_rounded_rect(inner, Color(0.12, 0.13, 0.18), 10.0)
	var centre_zone: float = _bar_rect.size.x * _sweet_frac
	var sweet := Rect2(cx - centre_zone * 0.5, inner.position.y + 2, centre_zone, inner.size.y - 4)
	draw_rounded_rect(sweet, Color(0.2, 0.75, 0.48, 0.35), 6.0)
	draw_rounded_rect(sweet, Color(0.35, 1.0, 0.65, 0.25), 6.0)
	draw_line(Vector2(cx, inner.position.y), Vector2(cx, inner.end.y), Color(1, 1, 0.9, 0.7), 2.0)
	for tpos in _marker_trail:
		var tx: float = cx + tpos * (_bar_rect.size.x * 0.5 - 14.0)
		draw_circle(Vector2(tx, bar_y), 8.0, Color(1, 0.55, 0.15, 0.15))
	var marker_x: float = cx + _pos * (_bar_rect.size.x * 0.5 - 14.0)
	draw_circle(Vector2(marker_x, bar_y), 16.0, Color(0.2, 0.1, 0.05, 0.35))
	draw_circle(Vector2(marker_x, bar_y), 14.0, Color(1, 0.58, 0.18))
	draw_circle(Vector2(marker_x, bar_y), 14.0, Color(0.45, 0.22, 0.05), false, 2.0)
	if _result_power >= 0.0:
		var lbl := "%s  %d" % [_result_label(), int(round(_result_power))]
		draw_string(ThemeDB.fallback_font, Vector2(cx - 70, bar_y - 40), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1))


func draw_rounded_rect(r: Rect2, col: Color, radius: float) -> void:
	draw_rect(r, col)
	draw_circle(r.position + Vector2(radius, radius), radius, col)
	draw_circle(Vector2(r.end.x - radius, r.position.y + radius), radius, col)
	draw_circle(Vector2(r.end.x - radius, r.end.y - radius), radius, col)
	draw_circle(Vector2(r.position.x + radius, r.end.y - radius), radius, col)