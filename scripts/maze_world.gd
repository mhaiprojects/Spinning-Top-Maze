class_name MazeWorld
extends Node2D
## Builds collision walls and draws the maze from MazeGen data.

const WALL_GROUP := "maze_wall"
const HAZARD_GROUP := "hazard_zone"
const WALL_THICK := 7.0

var maze_data: Dictionary = {}
var _play_rect := Rect2()
var _cell_size := Vector2.ONE
var _goal_pulse := 0.0


func build(data: Dictionary, play_rect: Rect2) -> void:
	_clear_maze_now()
	maze_data = data
	_play_rect = play_rect
	var cols: int = data.cols
	var rows: int = data.rows
	_cell_size = Vector2(play_rect.size.x / float(cols), play_rect.size.y / float(rows))
	for seg in data.walls:
		_add_wall_segment(seg)
	for h in data.get("hazards", []):
		_add_hazard(h)
	queue_redraw()


func clear_maze() -> void:
	call_deferred("_clear_maze_now")


func _clear_maze_now() -> void:
	for c in get_children():
		c.queue_free()
	maze_data = {}
	queue_redraw()


func _process(delta: float) -> void:
	_goal_pulse += delta * 2.2
	queue_redraw()


func cell_center(cell: Vector2i) -> Vector2:
	return _play_rect.position + Vector2(
		(float(cell.x) + 0.5) * _cell_size.x,
		(float(cell.y) + 0.5) * _cell_size.y
	)


func goal_area_rect() -> Rect2:
	var g: Vector2i = maze_data.goal_cell
	var c: Vector2 = cell_center(g)
	var sz: Vector2 = _cell_size * 0.72
	return Rect2(c - sz * 0.5, sz)


func start_area_rect() -> Rect2:
	var s: Vector2i = maze_data.start_cell
	var c: Vector2 = cell_center(s)
	var sz: Vector2 = _cell_size * 0.62
	return Rect2(c - sz * 0.5, sz)


func start_position() -> Vector2:
	return cell_center(maze_data.start_cell)


func _add_wall_segment(seg: Dictionary) -> void:
	var horiz: bool = seg.horiz
	var a: Vector2 = seg.a
	var b: Vector2 = seg.b
	var body := StaticBody2D.new()
	body.add_to_group(WALL_GROUP)
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	if horiz:
		var len: float = (b.x - a.x) * _cell_size.x
		rect.size = Vector2(len + WALL_THICK, WALL_THICK)
		body.position = _play_rect.position + Vector2(a.x * _cell_size.x, a.y * _cell_size.y) + Vector2(len * 0.5, 0)
	else:
		var len_v: float = (b.y - a.y) * _cell_size.y
		rect.size = Vector2(WALL_THICK, len_v + WALL_THICK)
		body.position = _play_rect.position + Vector2(a.x * _cell_size.x, a.y * _cell_size.y) + Vector2(0, len_v * 0.5)
	cs.shape = rect
	body.add_child(cs)
	add_child(body)


func _add_hazard(cell: Vector2i) -> void:
	var body := StaticBody2D.new()
	body.add_to_group(HAZARD_GROUP)
	body.collision_layer = 4
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = minf(_cell_size.x, _cell_size.y) * 0.2
	cs.shape = circle
	body.add_child(cs)
	body.position = cell_center(cell)
	add_child(body)


func _draw() -> void:
	if maze_data.is_empty():
		return
	_draw_background()
	_draw_walls()
	_draw_hazards()
	_draw_start_pad()
	_draw_goal_pad()


func _draw_background() -> void:
	var top_c := Color(0.08, 0.1, 0.16)
	var bot_c := Color(0.14, 0.12, 0.18)
	var steps := 12
	for i in steps:
		var t: float = float(i) / float(steps)
		var y0: float = lerpf(_play_rect.position.y, _play_rect.end.y, t)
		var y1: float = lerpf(_play_rect.position.y, _play_rect.end.y, float(i + 1) / float(steps))
		draw_rect(Rect2(_play_rect.position.x, y0, _play_rect.size.x, y1 - y0), top_c.lerp(bot_c, t))
	var dot_step: float = maxf(18.0, _cell_size.x * 0.35)
	var gx: float = _play_rect.position.x
	while gx < _play_rect.end.x:
		var gy: float = _play_rect.position.y
		while gy < _play_rect.end.y:
			draw_circle(Vector2(gx, gy), 1.2, Color(1, 1, 1, 0.03))
			gy += dot_step
		gx += dot_step
	var vignette := _play_rect.grow(20)
	draw_rect(vignette, Color(0, 0, 0, 0.08), false, 12.0)


func _draw_walls() -> void:
	var fill_col := Color(0.5, 0.54, 0.62)
	var shadow_col := Color(0.18, 0.2, 0.24)
	var hi_col := Color(0.75, 0.78, 0.85, 0.5)
	for seg in maze_data.walls:
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		var p0: Vector2 = _play_rect.position + Vector2(a.x * _cell_size.x, a.y * _cell_size.y)
		var r: Rect2
		if seg.horiz:
			var len: float = (b.x - a.x) * _cell_size.x
			r = Rect2(p0, Vector2(len, WALL_THICK))
		else:
			var len_v: float = (b.y - a.y) * _cell_size.y
			r = Rect2(p0, Vector2(WALL_THICK, len_v))
		draw_rect(Rect2(r.position + Vector2(2, 2), r.size), shadow_col)
		draw_rect(r, fill_col)
		draw_rect(r, hi_col, false, 1.0)


func _draw_hazards() -> void:
	for h in maze_data.get("hazards", []):
		var c: Vector2 = cell_center(h)
		draw_circle(c, minf(_cell_size.x, _cell_size.y) * 0.2, Color(0.85, 0.25, 0.2, 0.35))
		draw_arc(c, minf(_cell_size.x, _cell_size.y) * 0.22, _goal_pulse, _goal_pulse + TAU, 16, Color(1, 0.4, 0.25, 0.6), 2.0)


func _draw_start_pad() -> void:
	var start_r: Rect2 = start_area_rect()
	draw_rect(start_r, Color(0.22, 0.32, 0.55, 0.35))
	draw_rect(start_r, Color(0.5, 0.65, 0.95, 0.8), false, 2.0)


func _draw_goal_pad() -> void:
	var goal_r: Rect2 = goal_area_rect()
	var pulse: float = 0.5 + 0.5 * sin(_goal_pulse)
	var glow: float = minf(_cell_size.x, _cell_size.y) * (0.35 + pulse * 0.08)
	var gc: Vector2 = goal_r.get_center()
	draw_circle(gc, glow, Color(0.1, 0.8, 0.55, 0.12 + pulse * 0.1))
	draw_circle(gc, glow * 0.72, Color(0.15, 0.95, 0.62, 0.18 + pulse * 0.12))
	draw_rect(goal_r, Color(0.12, 0.55, 0.38, 0.55))
	draw_rect(goal_r, Color(0.2, 1.0, 0.7, 0.55 + pulse * 0.35), false, 3.0)