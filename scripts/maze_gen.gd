class_name MazeGen
extends RefCounted
## Room-based iterative backtracker; bottom-centre start, goal on the top row
## in a different column. Candidates are regenerated (derived seeds) until the
## goal is NOT reachable in a straight line: start and goal never share an
## unobstructed row/column and every route needs at least min_turns_for() turns.

const DIR4: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const W_N := 0
const W_E := 1
const W_S := 2
const W_W := 3
const MAX_ATTEMPTS := 600


static func grid_dims_for_wave(wave: int) -> Vector2i:
	var p: Dictionary = Difficulty.params_for_wave(wave)
	return Vector2i(p.cols, p.rows)


static func extra_wall_remove_chance(wave: int) -> float:
	return float(Difficulty.params_for_wave(wave).extra_wall_remove)


## Fewest direction changes any start->goal route must make (grows with size).
static func min_turns_for(wave: int) -> int:
	var dims: Vector2i = grid_dims_for_wave(wave)
	return clampi(1 + dims.y / 2, 3, 9)


static func generate(wave: int, seed_val: int) -> Dictionary:
	var need: int = min_turns_for(wave)
	var best: Dictionary = {}
	var best_turns := -1
	for attempt in MAX_ATTEMPTS:
		var sub_seed: int = seed_val if attempt == 0 else hash([seed_val, attempt])
		var cand: Dictionary = _generate_candidate(wave, sub_seed)
		var turns: int = min_turns(cand)
		cand["min_turns"] = turns
		cand["attempts"] = attempt + 1
		cand["seed"] = seed_val
		if turns >= need and not has_straight_line(cand):
			return cand
		if turns > best_turns and not has_straight_line(cand):
			best = cand
			best_turns = turns
	assert(not best.is_empty(), "MazeGen: no non-straight maze found")
	return best


static func _generate_candidate(wave: int, seed_val: int) -> Dictionary:
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
	var goal_cols: Array[int] = []
	for gx in cols:
		if gx != start_cell.x:
			goal_cols.append(gx)
	var goal_cell := Vector2i(goal_cols[rng.randi_range(0, goal_cols.size() - 1)], 0)

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
				if _is_perimeter_wall(x, y, dir_i, cols, rows):
					continue
				if rng.randf() < remove_chance:
					_remove_wall_between_dir(room_walls, x, y, dir_i, cols, rows)

	_force_perimeter_walls(room_walls, cols, rows)
	_ensure_start_opening(room_walls, cols, rows, start_cell)

	var cells: Array = []
	for y in rows:
		var row: Array = []
		for x in cols:
			row.append(false)
		cells.append(row)

	var segments: Array = wall_segments_from_rooms(cols, rows, room_walls)
	var hazards: Array = _place_hazards(cols, rows, start_cell, goal_cell, room_walls, rng, wave)
	var data := {
		"cols": cols,
		"rows": rows,
		"cells": cells,
		"room_walls": room_walls,
		"walls": segments,
		"hazards": hazards,
		"start_cell": start_cell,
		"goal_cell": goal_cell,
		"wave": wave,
		"seed": seed_val,
	}
	assert(has_path(data), "MazeGen: generated maze must have start->goal path")
	return data


static func _opposite(dir_i: int) -> int:
	return (dir_i + 2) % 4


static func _is_perimeter_wall(x: int, y: int, dir_i: int, cols: int, rows: int) -> bool:
	if dir_i == W_N and y == 0:
		return true
	if dir_i == W_S and y == rows - 1:
		return true
	if dir_i == W_W and x == 0:
		return true
	if dir_i == W_E and x == cols - 1:
		return true
	return false


static func _ensure_start_opening(room_walls: Array, _cols: int, rows: int, start: Vector2i) -> void:
	if start.y <= 0:
		return
	var north: Vector2i = start + Vector2i(0, -1)
	if room_walls[start.y][start.x][W_N]:
		_remove_wall_between(room_walls, start, north, W_N)


static func _force_perimeter_walls(room_walls: Array, cols: int, rows: int) -> void:
	for x in cols:
		room_walls[0][x][W_N] = true
		room_walls[rows - 1][x][W_S] = true
	for y in rows:
		room_walls[y][0][W_W] = true
		room_walls[y][cols - 1][W_E] = true


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


## True when start and goal share a row or column with no wall between them.
static func has_straight_line(data: Dictionary) -> bool:
	var a: Vector2i = data.start_cell
	var b: Vector2i = data.goal_cell
	var walls: Array = data.room_walls
	if a.x == b.x:
		var y0: int = mini(a.y, b.y)
		var y1: int = maxi(a.y, b.y)
		for y in range(y0, y1):
			if walls[y][a.x][W_S]:
				return false
		return true
	if a.y == b.y:
		var x0: int = mini(a.x, b.x)
		var x1: int = maxi(a.x, b.x)
		for x in range(x0, x1):
			if walls[a.y][x][W_E]:
				return false
		return true
	return false


## Fewest direction changes over ALL open routes start->goal (0-1 BFS on
## cell+heading). -1 when unreachable.
static func min_turns(data: Dictionary) -> int:
	var start: Vector2i = data.start_cell
	var goal: Vector2i = data.goal_cell
	var cols: int = data.cols
	var rows: int = data.rows
	var walls: Array = data.room_walls
	var inf := 1 << 30
	var dist: Dictionary = {}
	var dq: Array = []
	for d in 4:
		var n: Vector2i = start + DIR4[d]
		if walls[start.y][start.x][d] or n.x < 0 or n.y < 0 or n.x >= cols or n.y >= rows:
			continue
		dist[[n, d]] = 0
		dq.append([n, d, 0])
	if start == goal:
		return 0
	while not dq.is_empty():
		var cur: Array = dq.pop_front()
		var c: Vector2i = cur[0]
		var hd: int = cur[1]
		var t: int = cur[2]
		if int(dist.get([c, hd], inf)) < t:
			continue
		if c == goal:
			return t
		for d in 4:
			if walls[c.y][c.x][d]:
				continue
			var n2: Vector2i = c + DIR4[d]
			if n2.x < 0 or n2.y < 0 or n2.x >= cols or n2.y >= rows:
				continue
			var nt: int = t + (0 if d == hd else 1)
			if nt < int(dist.get([n2, d], inf)):
				dist[[n2, d]] = nt
				if d == hd:
					dq.push_front([n2, d, nt])
				else:
					dq.append([n2, d, nt])
	return -1


static func shortest_path_len(data: Dictionary) -> int:
	var start: Vector2i = data.start_cell
	var goal: Vector2i = data.goal_cell
	var walls: Array = data.room_walls
	var q: Array[Vector2i] = [start]
	var dist: Dictionary = {start: 0}
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c == goal:
			return int(dist[c])
		for i in 4:
			if walls[c.y][c.x][i]:
				continue
			var n: Vector2i = c + DIR4[i]
			if n.x < 0 or n.y < 0 or n.x >= data.cols or n.y >= data.rows or dist.has(n):
				continue
			dist[n] = int(dist[c]) + 1
			q.append(n)
	return -1


static func density(data: Dictionary) -> float:
	var area: float = float(data.cols * data.rows)
	return float(wall_count(data)) / maxf(area, 1.0)


static func wall_count(data: Dictionary) -> int:
	return data.walls.size()


static func _place_hazards(
	cols: int,
	rows: int,
	start_cell: Vector2i,
	goal_cell: Vector2i,
	room_walls: Array,
	rng: RandomNumberGenerator,
	wave: int
) -> Array:
	var count: int = int(Difficulty.params_for_wave(wave).hazards)
	if count <= 0:
		return []
	var out: Array = []
	var tries := 0
	while out.size() < count and tries < count * 40:
		tries += 1
		var c := Vector2i(rng.randi_range(0, cols - 1), rng.randi_range(0, rows - 1))
		if c == start_cell or c == goal_cell:
			continue
		if (c - start_cell).length() < 2 or (c - goal_cell).length() < 2:
			continue
		if out.has(c):
			continue
		out.append(c)
	return out