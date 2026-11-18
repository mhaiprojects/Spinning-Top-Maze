class_name MazeGen
extends RefCounted
## Procedural maze via iterative recursive backtracker; start bottom-centre, goal top-centre.

const DIR4: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


static func grid_dims_for_wave(wave: int) -> Vector2i:
	var w: int = maxi(3, mini(3 + (wave - 1) / 2, 12))
	var h: int = maxi(4, mini(4 + (wave - 1) / 2, 16))
	if wave == 1:
		return Vector2i(3, 4)
	return Vector2i(w, h)


static func extra_wall_remove_chance(wave: int) -> float:
	return clampf(0.55 - float(wave - 1) * 0.04, 0.05, 0.55)


static func generate(wave: int, seed_val: int) -> Dictionary:
	var dims: Vector2i = grid_dims_for_wave(wave)
	var cols: int = dims.x
	var rows: int = dims.y
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var cells: Array = []
	for y in rows:
		var row: Array = []
		for x in cols:
			row.append(true)
		cells.append(row)

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
		var neighbours: Array[Vector2i] = []
		for d in DIR4:
			var nc: Vector2i = cur + d
			if nc.x < 0 or nc.y < 0 or nc.x >= cols or nc.y >= rows:
				continue
			if visited[nc.y][nc.x]:
				continue
			neighbours.append(nc)
		if neighbours.is_empty():
			stack.pop_back()
			continue
		var next: Vector2i = neighbours[rng.randi_range(0, neighbours.size() - 1)]
		var between: Vector2i = cur + (next - cur) / 2
		cells[between.y][between.x] = false
		cells[next.y][next.x] = false
		visited[next.y][next.x] = true
		stack.append(next)

	cells[start_cell.y][start_cell.x] = false
	cells[goal_cell.y][goal_cell.x] = false

	var remove_chance: float = extra_wall_remove_chance(wave)
	for y in rows:
		for x in cols:
			if not cells[y][x]:
				continue
			if Vector2i(x, y) == start_cell or Vector2i(x, y) == goal_cell:
				continue
			if rng.randf() < remove_chance:
				cells[y][x] = false

	var walls: Array = wall_segments_from_cells(cols, rows, cells)
	var data := {
		"cols": cols,
		"rows": rows,
		"cells": cells,
		"walls": walls,
		"start_cell": start_cell,
		"goal_cell": goal_cell,
		"wave": wave,
		"seed": seed_val,
	}
	assert(has_path(data), "MazeGen: generated maze must have start->goal path")
	return data


static func wall_segments_from_cells(cols: int, rows: int, cells: Array) -> Array:
	var segs: Array = []
	for y in rows:
		for x in cols:
			if not cells[y][x]:
				continue
			if y == 0 or not cells[y - 1][x]:
				segs.append({"a": Vector2(x, y), "b": Vector2(x + 1, y), "horiz": true})
			if y == rows - 1 or not cells[y + 1][x]:
				segs.append({"a": Vector2(x, y + 1), "b": Vector2(x + 1, y + 1), "horiz": true})
			if x == 0 or not cells[y][x - 1]:
				segs.append({"a": Vector2(x, y), "b": Vector2(x, y + 1), "horiz": false})
			if x == cols - 1 or not cells[y][x + 1]:
				segs.append({"a": Vector2(x + 1, y), "b": Vector2(x + 1, y + 1), "horiz": false})
	return segs


static func passable_cells(data: Dictionary) -> Array:
	var cols: int = data.cols
	var rows: int = data.rows
	var cells: Array = data.cells
	var out: Array = []
	for y in rows:
		for x in cols:
			if not cells[y][x]:
				out.append(Vector2i(x, y))
	return out


static func has_path(data: Dictionary) -> bool:
	var start: Vector2i = data.start_cell
	var goal: Vector2i = data.goal_cell
	var cols: int = data.cols
	var rows: int = data.rows
	var cells: Array = data.cells
	var q: Array[Vector2i] = [start]
	var seen: Dictionary = {start: true}
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c == goal:
			return true
		for d in DIR4:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= cols or n.y >= rows:
				continue
			if cells[n.y][n.x]:
				continue
			if seen.has(n):
				continue
			seen[n] = true
			q.append(n)
	return false


static func density(data: Dictionary) -> float:
	var cols: int = data.cols
	var rows: int = data.rows
	var area: float = float(cols * rows)
	var wall_cells: int = 0
	for y in rows:
		for x in cols:
			if data.cells[y][x]:
				wall_cells += 1
	return float(wall_cells) / maxf(area, 1.0)


static func wall_count(data: Dictionary) -> int:
	return data.walls.size()