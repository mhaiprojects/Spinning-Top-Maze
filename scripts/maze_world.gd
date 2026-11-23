class_name MazeWorld
extends Node2D
## Builds collision walls and draws the maze from MazeGen data.

const WALL_GROUP := "maze_wall"
const ViewportLayout := preload("res://scripts/viewport_layout.gd")
const HAZARD_GROUP := "hazard_zone"
const PlayBg := preload("res://scripts/play_background.gd")

var maze_data: Dictionary = {}
var _play_rect := Rect2()
var _cell_size := Vector2.ONE
var _goal_pulse := 0.0
var _wall_thick := 16.0
var play_background_id: int = PlayBg.Id.TABLETOP
var _floor_tex: ImageTexture


func set_play_background(id: int) -> void:
	play_background_id = PlayBg.from_saved(id)
	_floor_tex = null
	queue_redraw()


func screen_play_rect() -> Rect2:
	return Rect2(global_position + _play_rect.position, _play_rect.size)


func play_area_rect() -> Rect2:
	return _play_rect


func build(data: Dictionary, play_rect: Rect2) -> void:
	_clear_maze_now()
	maze_data = data
	_play_rect = play_rect
	_floor_tex = null
	var cols: int = data.cols
	var rows: int = data.rows
	_cell_size = Vector2(play_rect.size.x / float(cols), play_rect.size.y / float(rows))
	var layout_w: float = play_rect.size.x / ViewportLayout.DESIGN_SIZE.x
	_wall_thick = clampf(layout_w * 16.0, 10.0, 24.0)
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


## The winning tile: exactly the goal cell, nothing larger.
func goal_area_rect() -> Rect2:
	var g: Vector2i = maze_data.goal_cell
	return Rect2(
		_play_rect.position + Vector2(float(g.x) * _cell_size.x, float(g.y) * _cell_size.y),
		_cell_size
	)


## True only when the point (the top's centre) is on the goal tile itself.
func is_on_goal_tile(p: Vector2) -> bool:
	if maze_data.is_empty():
		return false
	return goal_area_rect().has_point(p)


## Goal pad art: the goal tile minus the wall band, so it stays inside 1 tile.
func goal_pad_rect() -> Rect2:
	var t: Rect2 = goal_area_rect()
	return Rect2(t.position + Vector2(_wall_thick, _wall_thick), t.size - Vector2(_wall_thick, _wall_thick))


func start_area_rect() -> Rect2:
	var s: Vector2i = maze_data.start_cell
	var c: Vector2 = cell_center(s)
	var sz: Vector2 = _cell_size * 0.7
	return Rect2(c - sz * 0.5, sz)


func start_position() -> Vector2:
	return cell_center(maze_data.start_cell)


func run_spawn_position() -> Vector2:
	return start_position() + Vector2(0, -_cell_size.y * 0.22)


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


func _floor_texture() -> ImageTexture:
	if _floor_tex == null:
		_floor_tex = PlayBg.texture_for_size(play_background_id, _play_rect.size)
	return _floor_tex


func _draw_background() -> void:
	var tex: ImageTexture = _floor_texture()
	draw_texture_rect(tex, _play_rect, false)
	var style: Dictionary = PlayBg.wall_style(play_background_id)
	var vig: Color = style.vignette
	if vig.a > 0.001:
		draw_rect(_play_rect, vig)


func _draw_cell_shading() -> void:
	if play_background_id == PlayBg.Id.CHOPPING:
		return
	var cols: int = maze_data.cols
	var rows: int = maze_data.rows
	var style: Dictionary = PlayBg.wall_style(play_background_id)
	for y in rows:
		for x in cols:
			var r := Rect2(
				_play_rect.position.x + float(x) * _cell_size.x,
				_play_rect.position.y + float(y) * _cell_size.y,
				_cell_size.x,
				_cell_size.y
			)
			var tint: Color = style.cell_a if (x + y) % 2 == 0 else style.cell_b
			draw_rect(r, tint)


func _draw_walls() -> void:
	var wt: float = _wall_thick
	var style: Dictionary = PlayBg.wall_style(play_background_id)
	var fill_top: Color = style.fill_top
	var fill_bot: Color = style.fill_bot
	var shadow_col: Color = style.shadow
	var hi_col: Color = style.hi
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
	var pads: Dictionary = PlayBg.pad_style(play_background_id)
	var start_r: Rect2 = start_area_rect()
	var c: Vector2 = start_r.get_center()
	draw_circle(c + Vector2(3, 4), start_r.size.x * 0.42, Color(0, 0, 0, 0.25))
	draw_rect(start_r, pads.start_fill)
	draw_rect(start_r, pads.start_border, false, 3.0)
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
	var goal_r: Rect2 = goal_pad_rect()
	var gc: Vector2 = goal_r.get_center()
	var pulse: float = 0.5 + 0.5 * sin(_goal_pulse)
	var max_r: float = minf(goal_r.size.x, goal_r.size.y) * 0.5
	for ring_i in 3:
		var rr: float = max_r * (0.55 + float(ring_i) * 0.15 + pulse * 0.08)
		var alpha: float = 0.22 - float(ring_i) * 0.05
		draw_arc(gc, rr, 0, TAU, 32, Color(0.15, 0.95, 0.55, alpha + pulse * 0.08), 3.0, true)
	draw_circle(gc + Vector2(0, 4), max_r * 0.6, Color(0, 0, 0, 0.2))
	var pads: Dictionary = PlayBg.pad_style(play_background_id)
	draw_rect(goal_r, pads.goal_fill)
	draw_rect(goal_r, Color(pads.goal_border.r, pads.goal_border.g, pads.goal_border.b, pads.goal_border.a + pulse * 0.45), false, 3.0)
	var flag_h: float = goal_r.size.y * 0.55
	draw_line(gc + Vector2(0, -goal_r.size.y * 0.35), gc + Vector2(0, -goal_r.size.y * 0.35 + flag_h), Color(0.95, 0.95, 1.0), 3.0)
	var tip := gc + Vector2(3, -goal_r.size.y * 0.35 + 2)
	var fl: float = clampf(max_r * 0.45, 8.0, 24.0)
	draw_colored_polygon(
		PackedVector2Array([tip, tip + Vector2(fl, fl * 0.42), tip + Vector2(0, fl * 0.84)]),
		Color(1.0, 0.35, 0.32, 0.9)
	)