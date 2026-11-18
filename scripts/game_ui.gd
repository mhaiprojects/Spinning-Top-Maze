extends CanvasLayer
## HUD top band (does not cover the maze).

const BTN_H := 64.0
const FONT_SZ := 22
const VT := preload("res://scripts/visual_theme.gd")

var _vp_size := Vector2(720, 1280)
var _play_rect := Rect2()
var _hud_band: PanelContainer
var _hud_height := 228.0
var _power_bar: ProgressBar
var _lbl_power: Label
var _lbl_wave: Label
var _lbl_diff: Label
var _lbl_tilt: Label
var _lbl_msg: Label
var _btn_cal: Button
var _btn_mode: Button
var _btn_pause: Button
var _btn_retry: Button
var _overlay: Control
var _overlay_card: PanelContainer
var _overlay_lbl: Label
var _overlay_btn: Button
var _overlay_mode := ""
var _power_display := 100.0
var _overlay_action_armed := true
var _confetti: CPUParticles2D


func _ready() -> void:
	_build_hud()
	_build_overlay()
	process_mode = Node.PROCESS_MODE_ALWAYS
	var tin: Node = get_node_or_null("/root/TiltInput")
	if tin:
		if tin.has_signal("mode_changed"):
			tin.mode_changed.connect(_on_mode_changed)
		if tin.has_signal("fallback_message"):
			tin.fallback_message.connect(_on_fallback_message)
		_refresh_mode_button()
	call_deferred("_refresh_mode_button")


func set_layout_rects(vp: Vector2, play: Rect2, top_h: float, _bot_h: float) -> void:
	_vp_size = vp
	_play_rect = play
	_hud_height = top_h
	if _hud_band:
		_hud_band.offset_bottom = top_h


func overlay_visible() -> bool:
	return _overlay.visible


func overlay_button_rect() -> Rect2:
	if _overlay_btn == null:
		return Rect2()
	return _overlay_btn.get_global_rect()


func overlay_card_rect() -> Rect2:
	if _overlay_card == null:
		return Rect2()
	return _overlay_card.get_global_rect()


func hud_screen_rect() -> Rect2:
	if _hud_band == null:
		return Rect2()
	return _hud_band.get_global_rect()


func consumes_steering_at(screen_pos: Vector2) -> bool:
	if _overlay.visible:
		return _overlay_btn.get_global_rect().has_point(screen_pos) or _overlay_card.get_global_rect().has_point(screen_pos)
	return hud_screen_rect().has_point(screen_pos)


func handle_overlay_input(event: InputEvent) -> bool:
	if not _overlay.visible:
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_activate_overlay_action()
			get_viewport().set_input_as_handled()
			return true
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _overlay_btn.get_global_rect().has_point(event.position):
			_activate_overlay_action()
			get_viewport().set_input_as_handled()
			return true
	return false


func _build_hud() -> void:
	_hud_band = PanelContainer.new()
	_hud_band.name = "HudBand"
	_hud_band.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hud_band.offset_bottom = _hud_height
	_hud_band.mouse_filter = Control.MOUSE_FILTER_STOP
	var hud_box := StyleBoxFlat.new()
	hud_box.bg_color = Color(0.09, 0.1, 0.15, 0.94)
	hud_box.border_color = Color(0.35, 0.38, 0.5, 0.35)
	hud_box.set_border_width_all(1)
	hud_box.corner_radius_bottom_left = 14
	hud_box.corner_radius_bottom_right = 14
	hud_box.shadow_size = 6
	hud_box.shadow_color = Color(0, 0, 0, 0.4)
	_hud_band.add_theme_stylebox_override("panel", hud_box)
	add_child(_hud_band)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_hud_band.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	margin.add_child(v)
	_lbl_wave = _label("Wave 1")
	v.add_child(_lbl_wave)
	_lbl_diff = _label("★☆☆☆☆ Easy")
	_lbl_diff.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	v.add_child(_lbl_diff)
	_lbl_tilt = _label("Input: Mouse")
	v.add_child(_lbl_tilt)
	_lbl_msg = _label("")
	_lbl_msg.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
	v.add_child(_lbl_msg)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 8)
	v.add_child(prow)
	_power_bar = ProgressBar.new()
	_power_bar.min_value = 0
	_power_bar.max_value = 100
	_power_bar.custom_minimum_size = Vector2(280, 34)
	_power_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.35, 0.9, 0.45)
	fill.corner_radius_top_left = 8
	fill.corner_radius_top_right = 8
	fill.corner_radius_bottom_left = 8
	fill.corner_radius_bottom_right = 8
	_power_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.16, 0.2)
	bg.corner_radius_top_left = 8
	bg.corner_radius_top_right = 8
	bg.corner_radius_bottom_left = 8
	bg.corner_radius_bottom_right = 8
	_power_bar.add_theme_stylebox_override("background", bg)
	prow.add_child(_power_bar)
	_lbl_power = _label("100%")
	prow.add_child(_lbl_power)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	_btn_mode = _btn("Input: Mouse [M]", _on_cycle_mode)
	_btn_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_btn_mode)
	_btn_cal = _btn("Calibrate", _on_calibrate)
	row.add_child(_btn_cal)
	_btn_pause = _btn("Pause", _on_pause)
	row.add_child(_btn_pause)
	_btn_retry = _btn("Retry", _on_retry)
	row.add_child(_btn_retry)


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.62)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(panel)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)
	_overlay_card = PanelContainer.new()
	_overlay_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_card.custom_minimum_size = Vector2(320, 180)
	var card_box := StyleBoxFlat.new()
	card_box.bg_color = Color(0.16, 0.18, 0.24, 0.95)
	card_box.corner_radius_top_left = 16
	card_box.corner_radius_top_right = 16
	card_box.corner_radius_bottom_left = 16
	card_box.corner_radius_bottom_right = 16
	card_box.shadow_size = 8
	_overlay_card.add_theme_stylebox_override("panel", card_box)
	center.add_child(_overlay_card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	_overlay_card.add_child(vb)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	vb.add_child(pad)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 16)
	pad.add_child(inner)
	_overlay_lbl = _label("")
	_overlay_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_lbl.add_theme_font_size_override("font_size", 26)
	inner.add_child(_overlay_lbl)
	_overlay_btn = Button.new()
	_overlay_btn.custom_minimum_size = Vector2(280, 72)
	_overlay_btn.add_theme_font_size_override("font_size", 24)
	_overlay_btn.add_theme_stylebox_override("normal", VT.overlay_button_style())
	_overlay_btn.add_theme_stylebox_override("hover", VT.overlay_button_style())
	_overlay_btn.add_theme_stylebox_override("pressed", VT.overlay_button_style())
	_overlay_btn.pressed.connect(_activate_overlay_action)
	inner.add_child(_overlay_btn)
	_confetti = CPUParticles2D.new()
	_confetti.emitting = false
	_confetti.one_shot = true
	_confetti.amount = 28
	_confetti.lifetime = 1.1
	_confetti.explosiveness = 0.85
	_confetti.direction = Vector2(0, -1)
	_confetti.spread = 55.0
	_confetti.gravity = Vector2(0, 180)
	_confetti.initial_velocity_min = 90.0
	_confetti.initial_velocity_max = 220.0
	_confetti.color = Color(1, 0.9, 0.4)
	_confetti.position = Vector2(0, 40)
	_overlay_card.add_child(_confetti)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT_SZ)
	return l


func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(100, BTN_H)
	b.add_theme_font_size_override("font_size", FONT_SZ)
	VT.apply_button_theme(b)
	b.pressed.connect(cb)
	return b


func _process(delta: float) -> void:
	var tin: Node = get_node_or_null("/root/TiltInput")
	if tin and tin.has_method("status_text"):
		_lbl_tilt.text = tin.call("status_text")
	for c in get_parent().get_children():
		if c is SpinningTop:
			var v: float = (c as SpinningTop).spin_power
			_power_display = lerpf(_power_display, v, clampf(delta * 8.0, 0.0, 1.0))
			_power_bar.value = _power_display
			_lbl_power.text = "%d%%" % int(round(_power_display))
			var ratio: float = _power_display / 100.0
			var fill := _power_bar.get_theme_stylebox("fill") as StyleBoxFlat
			if fill:
				fill.bg_color = VT.power_colour(ratio)
			break


func _unhandled_input(event: InputEvent) -> void:
	if handle_overlay_input(event):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M or event.keycode == KEY_TAB:
			_cycle_mode()
			get_viewport().set_input_as_handled()


func _wave_header(w: int) -> void:
	var p: Dictionary = Difficulty.params_for_wave(w)
	var stars := ""
	for i in 5:
		stars += "★" if i < int(p.stars) else "☆"
	_lbl_diff.text = "%s %s" % [stars, p.difficulty_label]


func on_phase_launch(w: int) -> void:
	_lbl_wave.text = "Wave %d — Launch! (Space / tap bar)" % w
	_wave_header(w)
	_hide_overlay()


func on_phase_run(w: int) -> void:
	_lbl_wave.text = "Wave %d — Go!" % w
	_wave_header(w)
	_hide_overlay()


func on_fell_over() -> void:
	_show_overlay("Fell over", "retry", "Retry")


func on_wave_cleared(w: int) -> void:
	_show_overlay("Wave %d cleared!" % w, "next", "Next Wave")


func _show_overlay(msg: String, mode: String, btn: String) -> void:
	_overlay_mode = mode
	_overlay_lbl.text = msg
	_overlay_btn.text = btn
	_overlay.visible = true
	_overlay_action_armed = true
	_overlay_card.scale = Vector2(0.85, 0.85)
	_overlay_card.modulate = Color(1, 1, 1, 0.0)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_overlay_card, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK)
	tw.parallel().tween_property(_overlay_card, "modulate", Color.WHITE, 0.18)
	if mode == "next" and _confetti:
		_confetti.emitting = true


func _hide_overlay() -> void:
	_overlay.visible = false
	_overlay_mode = ""


func _activate_overlay_action() -> void:
	if not _overlay.visible or not _overlay_action_armed:
		return
	_overlay_action_armed = false
	var mode := _overlay_mode
	var main = get_parent()
	_hide_overlay()
	if mode == "retry" and main.has_method("request_retry_same_wave"):
		main.request_retry_same_wave()
	elif mode == "next" and main.has_method("advance_wave"):
		main.advance_wave()


func _on_cycle_mode() -> void:
	_cycle_mode()


func _cycle_mode() -> void:
	var tin: Node = get_node_or_null("/root/TiltInput")
	if tin and tin.has_method("cycle_mode"):
		tin.call("cycle_mode")
	_refresh_mode_button()


func _on_mode_changed(_selected: int, _effective: int) -> void:
	_refresh_mode_button()


func _on_fallback_message(text: String) -> void:
	_lbl_msg.text = text


func _refresh_mode_button() -> void:
	var tin: Node = get_node_or_null("/root/TiltInput")
	if tin == null:
		return
	var name: String = "Mouse"
	if tin.has_method("status_text"):
		var st: String = tin.call("status_text")
		if st.begins_with("Input: "):
			name = st.split(" ")[1].trim_suffix("(on)").trim_suffix("(denied)")
	var mode_word: String = name.split("(")[0].strip_edges()
	_btn_mode.text = "Input: %s [M]" % mode_word
	_btn_cal.visible = tin.has_method("selected_mode") and int(tin.call("selected_mode")) == InputModes.Mode.TILT


func _on_calibrate() -> void:
	var t: Node = get_node_or_null("/root/TiltInput")
	if t and t.has_method("calibrate_zero"):
		t.call("calibrate_zero")


func _on_pause() -> void:
	var main = get_parent()
	if main.has_method("toggle_pause"):
		main.toggle_pause()
		_btn_pause.text = "Resume" if get_tree().paused else "Pause"


func _on_retry() -> void:
	var main = get_parent()
	if main.has_method("force_retry_wave"):
		main.call("force_retry_wave")