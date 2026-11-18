class_name MazeWorld
extends Node2D
## Builds collision walls and draws the maze from MazeGen data.

const WALL_GROUP := "maze_wall"
const HAZARD_GROUP := "hazard_zone"

var maze_data: Dictionary = {}
var _play_rect := Rect2()
var _cell_size := Vector2.ONE
var _goal_pulse := 0.0
var _wall_thick := 16.0


func build(data: Dictionary, play_rect: Rect2) -> void:
	_clear_maze_now()
	maze_data = data
	_play_rect = play_rect
	var cols: int = data.cols
	var rows: int = data.rows
	_cell_size = Vector2(play_rect.size.x / float(cols), play_rect.size.y / float(rows))
	_wall_thick = clampf(play_rect.size.x / 720.0 * 16.0, 12.0, 22.0)
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
	var sz: Vector2 = _cell_size * 0.78
	return Rect2(c - sz * 0.5, sz)


func start_area_rect() -> Rect2:
	var s: Vector2i = maze_data.start_cell
	var c: Vector2 = cell_center(s)
	var sz: Vector2 = _cell_size * 0.7
	return Rect2(c - sz * 0.5, sz)


func start_position() -> Vector2:
	return cell_center(maze_data.start_cell)


func first_wall_body() -> StaticBody2D:
	for c in get_children():
		if c is StaticBody2D and c.is_in_group(WALL_GROUP):
			return c as StaticBody2D
	return null


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
	var wt: float = _wall_thick
	if horiz:
		var len: float = (b.x - a.x) * _cell_size.x
		rect.size = Vector2(len + wt, wt)
		body.position = (
			_play_rect.position
			+ Vector2(a.x * _cell_size.x, a.y * _cell_size.y)
			+ Vector2(len * 0.5, wt * 0.5)
		)
	else:
		var len_v: float = (b.y - a.y) * _cell_size.y
		rect.size = Vector2(wt, len_v + wt)
		body.position = (
			_play_rect.position
			+ Vector2(a.x * _cell_size.x, a.y * _cell_size.y)
			+ Vector2(wt * 0.5, len_v * 0.5)
		)
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
	_draw_cell_shading()
	_draw_walls()
	_draw_hazards()
	_draw_start_pad()
	_draw_goal_pad()


func _draw_background() -> void:
	var top_c := Color(0.04, 0.07, 0.2)
	var bot_c := Color(0.22, 0.08, 0.26)
	var steps := 24
	for i in steps:
		var t: float = float(i) / float(steps)
		var y0: float = lerpf(_play_rect.position.y, _play_rect.end.y, t)
		var y1: float = lerpf(_play_rect.position.y, _play_rect.end.y, float(i + 1) / float(steps))
		draw_rect(Rect2(_play_rect.position.x, y0, _play_rect.size.x, y1 - y0 + 1.0), top_c.lerp(bot_c, t))
	var dot_step: float = maxf(16.0, _cell_size.x * 0.28)
	var gx: float = _play_rect.position.x + dot_step * 0.5
	while gx < _play_rect.end.x:
		var gy: float = _play_rect.position.y + dot_step * 0.5
		while gy < _play_rect.end.y:
			draw_circle(Vector2(gx, gy), 1.4, Color(0.85, 0.75, 1.0, 0.045))
			gy += dot_step
		gx += dot_step
	var cx: float = _play_rect.get_center().x
	var cy: float = _play_rect.get_center().y
	var max_r: float = _play_rect.size.length() * 0.55
	for ring in 6:
		var t: float = float(ring) / 6.0
		var r: float = lerpf(max_r * 0.35, max_r, t)
		var alpha: float = lerpf(0.16, 0.0, t)
		draw_arc(Vector2(cx, cy), r, 0, TAU, 48, Color(0, 0, 0, alpha), 18.0, true)


func _draw_cell_shading() -> void:
	var cols: int = maze_data.cols
	var rows: int = maze_data.rows
	for y in rows:
		for x in cols:
			var r := Rect2(
				_play_rect.position.x + float(x) * _cell_size.x,
				_play_rect.position.y + float(y) * _cell_size.y,
				_cell_size.x,
				_cell_size.y
			)
			var tint := Color(1, 1, 1, 0.03 if (x + y) % 2 == 0 else 0.06)
			draw_rect(r, tint)
			draw_rect(r, Color(0.7, 0.65, 0.95, 0.035), false, 1.0)


func _draw_walls() -> void:
	var wt: float = _wall_thick
	var fill_top := Color(0.62, 0.66, 0.78)
	var fill_bot := Color(0.38, 0.4, 0.5)
	var shadow_col := Color(0.05, 0.06, 0.1, 0.65)
	var hi_col := Color(0.92, 0.94, 1.0, 0.55)
	var cap_r: float = wt * 0.5 + 1.0
	for seg in maze_data.walls:
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		var p0: Vector2 = _play_rect.position + Vector2(a.x * _cell_size.x, a.y * _cell_size.y)
		var r: Rect2
		if seg.horiz:
			var len: float = (b.x - a.x) * _cell_size.x
			r = Rect2(p0.x, p0.y, len, wt)
			draw_rect(Rect2(r.position + Vector2(3, 4), r.size), shadow_col)
			draw_rect(r, fill_bot)
			var hi := Rect2(r.position.x, r.position.y, r.size.x, wt * 0.35)
			draw_rect(hi, fill_top)
			draw_rect(r, hi_col, false, 1.5)
			draw_circle(r.position, cap_r, fill_bot)
			draw_circle(Vector2(r.end.x, r.position.y), cap_r, fill_bot)
		else:
			var len_v: float = (b.y - a.y) * _cell_size.y
			r = Rect2(p0.x, p0.y, wt, len_v)
			draw_rect(Rect2(r.position + Vector2(4, 3), r.size), shadow_col)
			draw_rect(r, fill_bot)
			var hi_v := Rect2(r.position.x, r.position.y, wt * 0.32, r.size.y)
			draw_rect(hi_v, fill_top)
			draw_rect(r, hi_col, false, 1.5)
			draw_circle(r.position, cap_r, fill_bot)
			draw_circle(Vector2(r.position.x, r.end.y), cap_r, fill_bot)


func _draw_hazards() -> void:
	for h in maze_data.get("hazards", []):
		var c: Vector2 = cell_center(h)
		var rad: float = minf(_cell_size.x, _cell_size.y) * 0.22
		draw_circle(c, rad, Color(0.85, 0.25, 0.2, 0.4))
		draw_arc(c, rad * 1.1, _goal_pulse, _goal_pulse + TAU, 18, Color(1, 0.4, 0.25, 0.65), 2.5)


func _draw_start_pad() -> void:
	var start_r: Rect2 = start_area_rect()
	var c: Vector2 = start_r.get_center()
	draw_circle(c + Vector2(3, 4), start_r.size.x * 0.42, Color(0, 0, 0, 0.25))
	draw_rect(start_r, Color(0.12, 0.28, 0.55, 0.55))
	draw_rect(start_r, Color(0.45, 0.65, 1.0, 0.85), false, 3.0)
	draw_string(
		ThemeDB.fallback_font,
		c + Vector2(-22, 8),
		"START",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14,
		Color(0.75, 0.88, 1.0, 0.9)
	)


func _draw_goal_pad() -> void:
	var goal_r: Rect2 = goal_area_rect()
	var gc: Vector2 = goal_r.get_center()
	var pulse: float = 0.5 + 0.5 * sin(_goal_pulse)
	for ring_i in 3:
		var rr: float = goal_r.size.x * (0.55 + float(ring_i) * 0.18 + pulse * 0.06)
		var alpha: float = 0.22 - float(ring_i) * 0.05
		draw_arc(gc, rr, 0, TAU, 32, Color(0.15, 0.95, 0.55, alpha + pulse * 0.08), 4.0, true)
	draw_circle(gc + Vector2(0, 4), goal_r.size.x * 0.38, Color(0, 0, 0, 0.2))
	draw_rect(goal_r, Color(0.1, 0.42, 0.32, 0.65))
	draw_rect(goal_r, Color(0.25, 1.0, 0.72, 0.35 + pulse * 0.45), false, 3.0)
	var flag_h: float = goal_r.size.y * 0.55
	draw_line(gc + Vector2(0, -goal_r.size.y * 0.35), gc + Vector2(0, -goal_r.size.y * 0.35 + flag_h), Color(0.95, 0.95, 1.0), 3.0)
	var tip := gc + Vector2(6, -goal_r.size.y * 0.35 + 4)
	draw_colored_polygon(
		PackedVector2Array([tip, tip + Vector2(24, 10), tip + Vector2(0, 20)]),
		Color(1.0, 0.35, 0.32, 0.9)
	)