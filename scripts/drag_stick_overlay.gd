class_name DragStickOverlay
extends CanvasLayer
## Virtual-stick indicator for drag steering mode.

const IM := preload("res://scripts/input_modes.gd")

var _origin := Vector2.ZERO
var _pointer := Vector2.ZERO
var _active := false
var _visible_stick := false


func show_stick(origin: Vector2, pointer: Vector2) -> void:
	_origin = origin
	_pointer = pointer
	_active = true
	_visible_stick = true
	visible = true
	queue_redraw()


func hide_stick() -> void:
	_active = false
	_visible_stick = false
	visible = false
	queue_redraw()


func _ready() -> void:
	visible = false
	layer = 5


func _draw() -> void:
	if not _visible_stick:
		return
	var outer_r: float = IM.DRAG_RADIUS * 0.42
	draw_circle(_origin, outer_r, Color(0.1, 0.11, 0.14, 0.55))
	draw_arc(_origin, outer_r, 0, TAU, 32, Color(0.85, 0.85, 0.8, 0.35), 2.0)
	var delta: Vector2 = _pointer - _origin
	if delta.length() > outer_r:
		delta = delta.normalized() * outer_r
	draw_line(_origin, _origin + delta, Color(0.95, 0.55, 0.2, 0.85), 3.0)
	draw_circle(_origin + delta, 10.0, Color(0.95, 0.55, 0.2))