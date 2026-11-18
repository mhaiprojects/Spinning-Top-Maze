class_name MazeGen
extends RefCounted
## Room-based iterative backtracker; bottom-centre start, top-centre goal.

const DIR4: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const W_N := 0
const W_E := 1
const W_S := 2
const W_W := 3


static func grid_dims_for_wave(wave: int) -> Vector2i:
	if wave == 1:
		return Vector2i(3, 4)
	var w: int = clampi(2 + wave, 3, 12)
	var h: int = clampi(3 + wave, 4, 16)
	return Vector2i(w, h)


static func extra_wall_remove_chance(wave: int) -> float:
	return clampf(0.48 - float(wave) * 0.038, 0.0, 0.48)


static func generate(wave: int, seed_val: int) -> Dictionary:
	var dims: Vector2i = grid_dims_for_wave(wave)
	var cols: int = dims.x
	var rows: int = dims.y
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var room_walls: Array = []
	for y in rows:
		var row: Array = []
		for x in cols:
			row.append([true, true, true, true])
		room_walls.append(row)

	var visited: Array = []
	for y in rows:
		var row: Array = []
		for x in cols:
			row.append(false)
		visited.append(row)

	var start_cell := Vector2i(cols / 2, rows - 1)
	var goal_cell := Vector2i(cols / 2, 0)

	var stack: Array[Vector2i] = [start_cell]
	visited[start_cell.y][start_cell.x] = true

	while not stack.is_empty():
		var cur: Vector2i = stack.back()
		var options: Array = []
		for i in DIR4.size():
			var d: Vector2i = DIR4[i]
			var nc: Vector2i = cur + d
			if nc.x < 0 or nc.y < 0 or nc.x >= cols or nc.y >= rows:
				continue
			if visited[nc.y][nc.x]:
				continue
			options.append({"cell": nc, "dir": i})
		if options.is_empty():
			stack.pop_back()
			continue
		var pick: Dictionary = options[rng.randi_range(0, options.size() - 1)]
		var next: Vector2i = pick.cell
		var dir_i: int = pick.dir
		_remove_wall_between(room_walls, cur, next, dir_i)
		visited[next.y][next.x] = true
		stack.append(next)

	var remove_chance: float = extra_wall_remove_chance(wave)
	for y in rows:
		for x in cols:
			for dir_i in 4:
				if not room_walls[y][x][dir_i]:
					continue
				if rng.randf() < remove_chance:
					_remove_wall_between_dir(room_walls, x, y, dir_i, cols, rows)

	var cells: Array = []
	for y in rows:
		var row: Array = []
		for x in cols:
			row.append(false)
		cells.append(row)

	var segments: Array = wall_segments_from_rooms(cols, rows, room_walls)
	var data := {
		"cols": cols,
		"rows": rows,
		"cells": cells,
		"room_walls": room_walls,
		"walls": segments,
		"start_cell": start_cell,
		"goal_cell": goal_cell,
		"wave": wave,
		"seed": seed_val,
	}
	assert(has_path(data), "MazeGen: generated maze must have start->goal path")
	return data


static func _opposite(dir_i: int) -> int:
	return (dir_i + 2) % 4


static func _remove_wall_between(walls: Array, a: Vector2i, b: Vector2i, dir_from_a: int) -> void:
	walls[a.y][a.x][dir_from_a] = false
	walls[b.y][b.x][_opposite(dir_from_a)] = false


static func _remove_wall_between_dir(walls: Array, x: int, y: int, dir_i: int, cols: int, rows: int) -> void:
	walls[y][x][dir_i] = false
	var d: Vector2i = DIR4[dir_i]
	var nx: int = x + d.x
	var ny: int = y + d.y
	if dir_i == W_N and y == 0:
		return
	if dir_i == W_S and y == rows - 1:
		return
	if dir_i == W_W and x == 0:
		return
	if dir_i == W_E and x == cols - 1:
		return
	if nx >= 0 and ny >= 0 and nx < cols and ny < rows:
		walls[ny][nx][_opposite(dir_i)] = false


static func wall_segments_from_rooms(cols: int, rows: int, room_walls: Array) -> Array:
	var segs: Array = []
	for y in rows:
		for x in cols:
			if room_walls[y][x][W_N]:
				segs.append({"a": Vector2(x, y), "b": Vector2(x + 1, y), "horiz": true})
			if room_walls[y][x][W_W]:
				segs.append({"a": Vector2(x, y), "b": Vector2(x, y + 1), "horiz": false})
			if y == rows - 1 and room_walls[y][x][W_S]:
				segs.append({"a": Vector2(x, y + 1), "b": Vector2(x + 1, y + 1), "horiz": true})
			if x == cols - 1 and room_walls[y][x][W_E]:
				segs.append({"a": Vector2(x + 1, y), "b": Vector2(x + 1, y + 1), "horiz": false})
	return segs


static func has_path(data: Dictionary) -> bool:
	var start: Vector2i = data.start_cell
	var goal: Vector2i = data.goal_cell
	var cols: int = data.cols
	var rows: int = data.rows
	var walls: Array = data.room_walls
	var q: Array[Vector2i] = [start]
	var seen: Dictionary = {start: true}
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c == goal:
			return true
		for i in DIR4.size():
			if walls[c.y][c.x][i]:
				continue
			var n: Vector2i = c + DIR4[i]
			if n.x < 0 or n.y < 0 or n.x >= cols or n.y >= rows:
				continue
			if seen.has(n):
				continue
			seen[n] = true
			q.append(n)
	return false


static func density(data: Dictionary) -> float:
	var area: float = float(data.cols * data.rows)
	return float(wall_count(data)) / maxf(area, 1.0)


static func wall_count(data: Dictionary) -> int:
	return data.walls.size()