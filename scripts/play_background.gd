class_name PlayBackground
extends RefCounted
## Procedural play-floor textures and wall palettes (cached ImageTextures).

enum Id { TABLETOP, CHOPPING, PLANKS, STONE }

const ORDER: Array[int] = [Id.TABLETOP, Id.CHOPPING, Id.PLANKS, Id.STONE]
const NAMES: PackedStringArray = ["Tabletop", "Chopping", "Planks", "Stone"]

static var _tex_cache: Dictionary = {}


static func default_id() -> int:
	return Id.TABLETOP


static func from_saved(v: Variant) -> int:
	var i: int = int(v)
	return i if ORDER.has(i) else Id.TABLETOP


static func next_id(id: int) -> int:
	var idx: int = ORDER.find(id)
	if idx < 0:
		return Id.TABLETOP
	return ORDER[(idx + 1) % ORDER.size()]


static func name_for(id: int) -> String:
	if id >= 0 and id < NAMES.size():
		return NAMES[id]
	return NAMES[0]


static func wall_style(id: int) -> Dictionary:
	match id:
		Id.CHOPPING:
			return {
				"fill_top": Color(0.82, 0.72, 0.58),
				"fill_bot": Color(0.48, 0.36, 0.28),
				"shadow": Color(0.08, 0.05, 0.04, 0.7),
				"hi": Color(1.0, 0.95, 0.88, 0.5),
				"cell_a": Color(1, 1, 1, 0.025),
				"cell_b": Color(0, 0, 0, 0.04),
				"vignette": Color(0, 0, 0, 0.12),
			}
		Id.PLANKS:
			return {
				"fill_top": Color(0.74, 0.7, 0.64),
				"fill_bot": Color(0.45, 0.42, 0.38),
				"shadow": Color(0.06, 0.06, 0.08, 0.65),
				"hi": Color(0.95, 0.96, 1.0, 0.55),
				"cell_a": Color(1, 1, 1, 0.02),
				"cell_b": Color(0, 0, 0, 0.035),
				"vignette": Color(0.02, 0.03, 0.06, 0.1),
			}
		Id.STONE:
			return {
				"fill_top": Color(0.72, 0.74, 0.76),
				"fill_bot": Color(0.42, 0.44, 0.48),
				"shadow": Color(0.05, 0.06, 0.08, 0.75),
				"hi": Color(1.0, 1.0, 1.0, 0.45),
				"cell_a": Color(1, 1, 1, 0.018),
				"cell_b": Color(0, 0, 0, 0.028),
				"vignette": Color(0, 0, 0, 0.14),
			}
		_:
			return {
				"fill_top": Color(0.88, 0.78, 0.62),
				"fill_bot": Color(0.52, 0.38, 0.26),
				"shadow": Color(0.12, 0.07, 0.04, 0.65),
				"hi": Color(1.0, 0.96, 0.88, 0.52),
				"cell_a": Color(1, 0.98, 0.92, 0.03),
				"cell_b": Color(0.2, 0.1, 0.05, 0.04),
				"vignette": Color(0.15, 0.08, 0.02, 0.1),
			}


static func pad_style(id: int) -> Dictionary:
	match id:
		Id.STONE:
			return {
				"start_fill": Color(0.18, 0.32, 0.55, 0.62),
				"start_border": Color(0.55, 0.75, 1.0, 0.9),
				"goal_fill": Color(0.12, 0.48, 0.38, 0.7),
				"goal_border": Color(0.35, 1.0, 0.72, 0.85),
			}
		Id.CHOPPING, Id.PLANKS:
			return {
				"start_fill": Color(0.14, 0.3, 0.52, 0.58),
				"start_border": Color(0.5, 0.7, 1.0, 0.88),
				"goal_fill": Color(0.1, 0.45, 0.34, 0.68),
				"goal_border": Color(0.3, 1.0, 0.7, 0.8),
			}
		_:
			return {
				"start_fill": Color(0.12, 0.28, 0.55, 0.55),
				"start_border": Color(0.45, 0.65, 1.0, 0.85),
				"goal_fill": Color(0.1, 0.42, 0.32, 0.65),
				"goal_border": Color(0.25, 1.0, 0.72, 0.35),
			}


static func texture_for_size(id: int, size: Vector2) -> ImageTexture:
	var w: int = clampi(maxi(256, int(size.x)), 256, 1024)
	var h: int = clampi(maxi(256, int(size.y)), 256, 1024)
	var key: String = "%d_%d_%d" % [id, w, h]
	if _tex_cache.has(key):
		return _tex_cache[key] as ImageTexture
	var img := _generate_image(id, w, h)
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


static func _generate_image(id: int, w: int, h: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) + (w << 12) + h
	match id:
		Id.CHOPPING:
			return _gen_chopping(w, h, rng)
		Id.PLANKS:
			return _gen_planks(w, h, rng)
		Id.STONE:
			return _gen_stone(w, h, rng)
		_:
			return _gen_tabletop(w, h, rng)


static func _gen_tabletop(w: int, h: int, rng: RandomNumberGenerator) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var base_lo := Color(0.42, 0.28, 0.16)
	var base_hi := Color(0.78, 0.58, 0.34)
	for y in h:
		var ty: float = float(y) / float(h)
		var row_c: Color = base_lo.lerp(base_hi, ty * 0.55 + 0.2)
		for x in w:
			var grain: float = sin(float(x) * 0.09 + float(y) * 0.03) * 0.04
			grain += rng.randf_range(-0.03, 0.03)
			var c: Color = row_c.lightened(grain)
			if y % 7 == 0:
				c = c.darkened(0.06 + rng.randf() * 0.04)
			img.set_pixel(x, y, c)
	for i in 24:
		var gy: int = rng.randi_range(8, h - 8)
		var shade: float = rng.randf_range(0.85, 1.0)
		for x in w:
			var p: Color = img.get_pixel(x, gy)
			img.set_pixel(x, gy, p.darkened(1.0 - shade))
	return img


static func _gen_chopping(w: int, h: int, rng: RandomNumberGenerator) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.55, 0.38, 0.24))
	var cell: int = clampi(mini(w, h) / 14, 28, 52)
	for y in range(0, h + cell, cell):
		for x in range(0, w + cell, cell):
			var cx: float = float(x) + cell * 0.5
			var cy: float = float(y) + cell * 0.5
			var r: float = cell * 0.46
			var tone: float = rng.randf_range(0.85, 1.12)
			for dy in range(-int(r) - 1, int(r) + 2):
				for dx in range(-int(r) - 1, int(r) + 2):
					var px: int = int(cx) + dx
					var py: int = int(cy) + dy
					if px < 0 or py < 0 or px >= w or py >= h:
						continue
					var d: float = Vector2(dx, dy).length() / r
					if d > 1.0:
						continue
					var ring: float = 0.06 * sin(d * 18.0 + float(px) * 0.2)
					var c := Color(0.62 * tone, 0.4 * tone, 0.26 * tone).darkened(d * 0.15 + ring)
					img.set_pixel(px, py, c)
	for i in 18:
		var scratch_x0: int = rng.randi_range(0, w - 1)
		var scratch_y0: int = rng.randi_range(0, h - 1)
		var len: int = rng.randi_range(40, 140)
		var ang: float = rng.randf_range(-0.4, 0.4)
		for s in len:
			var px: int = scratch_x0 + int(cos(ang) * float(s))
			var py: int = scratch_y0 + int(sin(ang) * float(s))
			if px < 0 or py < 0 or px >= w or py >= h:
				break
			var p: Color = img.get_pixel(px, py)
			img.set_pixel(px, py, p.lightened(0.08))
	return img


static func _gen_planks(w: int, h: int, rng: RandomNumberGenerator) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var plank_n: int = clampi(w / 90, 5, 12)
	var plank_w: float = float(w) / float(plank_n)
	for pi in plank_n:
		var tone: float = rng.randf_range(0.88, 1.08)
		var c0 := Color(0.5 * tone, 0.35 * tone, 0.22 * tone)
		var c1 := Color(0.68 * tone, 0.5 * tone, 0.34 * tone)
		var x0: int = int(pi * plank_w)
		var x1: int = int((pi + 1) * plank_w)
		for x in range(x0, mini(x1, w)):
			for y in h:
				var t: float = float(y) / float(h)
				var c: Color = c0.lerp(c1, t)
				if (x + y) % 11 == 0:
					c = c.darkened(0.04)
				img.set_pixel(x, y, c)
		if x1 < w:
			for y in h:
				var seam := img.get_pixel(x1, y)
				img.set_pixel(x1, y, seam.darkened(0.25))
		for nail_i in 2:
			var nx: int = clampi(x0 + int(plank_w * 0.35) + nail_i * int(plank_w * 0.35), x0 + 4, x1 - 4)
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if nx + dx < 0 or nx + dx >= w:
						continue
					var py: int = h / 4 + nail_i * h / 3 + dy
					if py < 0 or py >= h:
						continue
					img.set_pixel(nx + dx, py, Color(0.28, 0.24, 0.2))
	return img


static func _gen_stone(w: int, h: int, rng: RandomNumberGenerator) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var base := Color(0.58, 0.6, 0.62)
	for y in h:
		for x in w:
			var n: float = rng.randf_range(-0.06, 0.06)
			img.set_pixel(x, y, base.lightened(n))
	for i in 8:
		var cx: int = rng.randi_range(0, w - 1)
		var cy: int = rng.randi_range(0, h - 1)
		var rad: int = rng.randi_range(30, 90)
		for dy in range(-rad, rad):
			for dx in range(-rad, rad):
				var px: int = cx + dx
				var py: int = cy + dy
				if px < 0 or py < 0 or px >= w or py >= h:
					continue
				var d: float = Vector2(dx, dy).length() / float(rad)
				if d > 1.0:
					continue
				var p: Color = img.get_pixel(px, py)
				img.set_pixel(px, py, p.lightened(0.04 - d * 0.06))
	for c in 5:
		var x0: int = rng.randi_range(0, w - 1)
		var y0: int = rng.randi_range(0, h - 1)
		var seg_len: int = rng.randi_range(80, 220)
		var dir := Vector2(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.3)).normalized()
		for s in seg_len:
			var px: int = x0 + int(dir.x * float(s))
			var py: int = y0 + int(dir.y * float(s))
			if px < 0 or py < 0 or px >= w or py >= h:
				break
			var p: Color = img.get_pixel(px, py)
			img.set_pixel(px, py, p.darkened(0.18))
			if py + 1 < h:
				img.set_pixel(px, py + 1, p.darkened(0.12))
	return img