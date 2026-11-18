class_name LaunchMinigame
extends Node2D
## Fishing-style power launch: marker ping-pongs on a bar.

signal released(power: float)

const SHOW_RESULT_SEC := 0.9

var wave: int = 1
var active := false
var _pos := 0.0
var _dir := 1.0
var _speed := 1.6
var _result_power := -1.0
var _result_t := 0.0
var _bar_rect := Rect2()


func setup(bar_rect: Rect2, wave_num: int) -> void:
	_bar_rect = bar_rect
	wave = wave_num
	active = true
	_pos = 0.0
	_dir = 1.0
	_speed = 1.6 + float(wave - 1) * 0.06
	_result_power = -1.0
	_result_t = 0.0
	visible = true
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
	var span: float = _bar_rect.size.x * 0.5
	_pos += _dir * _speed * delta
	if _pos > 1.0:
		_pos = 1.0
		_dir = -1.0
	elif _pos < -1.0:
		_pos = -1.0
		_dir = 1.0
	queue_redraw()


func try_release() -> bool:
	if not active or _result_power >= 0.0:
		return false
	_result_power = LaunchMath.power_for_offset(_pos)
	_result_t = 0.0
	if OS.has_feature("web"):
		var n: Node = get_tree().root.get_node_or_null("TiltInput")
		if n and n.has_method("request_web_permission"):
			n.call("request_web_permission")
	queue_redraw()
	return true


func _draw() -> void:
	if _bar_rect.size.x < 1.0:
		return
	var centre_zone := _bar_rect.size.x * 0.14
	var cx: float = _bar_rect.position.x + _bar_rect.size.x * 0.5
	var bar_y: float = _bar_rect.position.y + _bar_rect.size.y * 0.5
	draw_rect(_bar_rect, Color(0.15, 0.16, 0.2))
	draw_rect(Rect2(cx - centre_zone * 0.5, _bar_rect.position.y + 4, centre_zone, _bar_rect.size.y - 8), Color(0.25, 0.55, 0.4, 0.45))
	draw_line(Vector2(cx, _bar_rect.position.y), Vector2(cx, _bar_rect.end.y), Color(0.9, 0.9, 0.85), 2.0)
	var marker_x: float = cx + _pos * (_bar_rect.size.x * 0.5 - 12.0)
	draw_circle(Vector2(marker_x, bar_y), 14.0, Color(0.95, 0.55, 0.2))
	draw_circle(Vector2(marker_x, bar_y), 14.0, Color(0.4, 0.22, 0.08), false, 2.0)
	if _result_power >= 0.0:
		var lbl := "Power: %d" % int(round(_result_power))
		draw_string(ThemeDB.fallback_font, Vector2(cx - 48, bar_y - 36), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1))