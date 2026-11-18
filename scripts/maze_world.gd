class_name MazeWorld
extends Node2D
## Builds collision walls and draws the maze from MazeGen data.

const WALL_GROUP := "maze_wall"
const WALL_THICK := 6.0

var maze_data: Dictionary = {}
var _play_rect := Rect2()
var _cell_size := Vector2.ONE


func build(data: Dictionary, play_rect: Rect2) -> void:
	_clear_maze_now()
	maze_data = data
	_play_rect = play_rect
	var cols: int = data.cols
	var rows: int = data.rows
	_cell_size = Vector2(play_rect.size.x / float(cols), play_rect.size.y / float(rows))
	for seg in data.walls:
		_add_wall_segment(seg)
	queue_redraw()


func clear_maze() -> void:
	call_deferred("_clear_maze_now")


func _clear_maze_now() -> void:
	for c in get_children():
		c.queue_free()
	maze_data = {}
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


func _draw() -> void:
	if maze_data.is_empty():
		return
	draw_rect(_play_rect, Color(0.16, 0.17, 0.2))
	var wall_col := Color(0.4, 0.44, 0.52)
	for seg in maze_data.walls:
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		var p0: Vector2 = _play_rect.position + Vector2(a.x * _cell_size.x, a.y * _cell_size.y)
		if seg.horiz:
			var len: float = (b.x - a.x) * _cell_size.x
			draw_rect(Rect2(p0, Vector2(len, WALL_THICK)), wall_col)
		else:
			var len_v: float = (b.y - a.y) * _cell_size.y
			draw_rect(Rect2(p0, Vector2(WALL_THICK, len_v)), wall_col)
	var goal_r: Rect2 = goal_area_rect()
	draw_rect(goal_r, Color(0.12, 0.55, 0.38, 0.55))
	draw_rect(goal_r, Color(0.1, 0.85, 0.55), false, 3.0)
	draw_string(
		ThemeDB.fallback_font,
		goal_r.position + Vector2(4, goal_r.size.y * 0.55),
		"GOAL",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		mini(18, int(goal_r.size.x * 0.22)),
		Color(0.85, 1.0, 0.9)
	)
	var start_r: Rect2 = start_area_rect()
	draw_rect(start_r, Color(0.25, 0.35, 0.55, 0.35))
	draw_rect(start_r, Color(0.45, 0.6, 0.95), false, 2.0)
	draw_string(
		ThemeDB.fallback_font,
		start_r.position + Vector2(4, start_r.size.y * 0.55),
		"START",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		mini(16, int(start_r.size.x * 0.2)),
		Color(0.75, 0.85, 1.0)
	)