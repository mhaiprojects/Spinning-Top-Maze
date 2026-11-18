class_name VisualTheme
extends RefCounted
## Shared colours and StyleBox helpers for HUD (created in code).


static func hud_button_style(base: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = base
	s.corner_radius_top_left = 10
	s.corner_radius_top_right = 10
	s.corner_radius_bottom_left = 10
	s.corner_radius_bottom_right = 10
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 3
	s.shadow_offset = Vector2(0, 2)
	return s


static func apply_button_theme(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal", hud_button_style(Color(0.28, 0.32, 0.4)))
	btn.add_theme_stylebox_override("hover", hud_button_style(Color(0.34, 0.4, 0.5)))
	btn.add_theme_stylebox_override("pressed", hud_button_style(Color(0.22, 0.26, 0.34)))
	btn.add_theme_color_override("font_color", Color(0.95, 0.96, 0.98))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))


static func overlay_button_style() -> StyleBoxFlat:
	var s := hud_button_style(Color(0.15, 0.62, 0.42))
	s.corner_radius_top_left = 14
	s.corner_radius_top_right = 14
	s.corner_radius_bottom_left = 14
	s.corner_radius_bottom_right = 14
	s.bg_color = Color(0.18, 0.55, 0.38)
	return s


static func power_colour(ratio: float) -> Color:
	if ratio > 0.55:
		return Color(0.35, 0.9, 0.45).lerp(Color(0.95, 0.9, 0.2), 1.0 - (ratio - 0.55) / 0.45)
	return Color(0.95, 0.35, 0.25).lerp(Color(0.95, 0.9, 0.2), ratio / 0.55)