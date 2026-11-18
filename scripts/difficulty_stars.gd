class_name DifficultyStars
extends Control
## Five tiny star glyphs drawn as polygons (web-safe; no Unicode stars).

const STAR_R := 8.0
const GAP := 6.0

var _filled := 1
var _label := "Easy"


func _ready() -> void:
	custom_minimum_size = Vector2(5 * (STAR_R * 2.0 + GAP) + 72, 26)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_rating(filled: int, label: String) -> void:
	_filled = clampi(filled, 0, 5)
	_label = label
	queue_redraw()


func _draw() -> void:
	var x: float = STAR_R
	for i in 5:
		var on: bool = i < _filled
		_draw_star(Vector2(x, 13), STAR_R, on)
		x += STAR_R * 2.0 + GAP
	var font: Font = ThemeDB.fallback_font
	var label_x: float = 5 * (STAR_R * 2.0 + GAP) + 4
	draw_string(
		font,
		Vector2(label_x, 18),
		_label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		22,
		Color(0.75, 0.85, 1.0)
	)


func _draw_star(center: Vector2, radius: float, filled: bool) -> void:
	var pts := PackedVector2Array()
	for i in 5:
		var outer: float = -PI * 0.5 + TAU * float(i) / 5.0
		pts.append(center + Vector2(cos(outer), sin(outer)) * radius)
		var inner: float = outer + TAU / 10.0
		pts.append(center + Vector2(cos(inner), sin(inner)) * radius * 0.42)
	if filled:
		draw_colored_polygon(pts, Color(1.0, 0.88, 0.35))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.85, 0.65, 0.15), 1.2)
	else:
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.55, 0.62, 0.78), 1.5)