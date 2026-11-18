extends CanvasLayer
## HUD, overlays, input-mode selector, and touch-friendly controls.

const BTN_H := 52.0
const FONT_SZ := 20

var _vp_size := Vector2(720, 1280)
var _play_rect := Rect2()
var _hud_root: MarginContainer
var _power_bar: ProgressBar
var _lbl_wave: Label
var _lbl_tilt: Label
var _lbl_msg: Label
var _btn_cal: Button
var _btn_mode: Button
var _btn_pause: Button
var _btn_retry: Button
var _overlay: Control
var _overlay_lbl: Label
var _overlay_btn: Button
var _overlay_mode := ""


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


func set_layout_rects(vp: Vector2, play: Rect2) -> void:
	_vp_size = vp
	_play_rect = play


func overlay_visible() -> bool:
	return _overlay.visible


func consumes_steering_at(screen_pos: Vector2) -> bool:
	if _overlay.visible:
		return true
	if _hud_root == null:
		return false
	return _hud_root.get_global_rect().has_point(screen_pos)


func _build_hud() -> void:
	_hud_root = MarginContainer.new()
	_hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_root.add_theme_constant_override("margin_left", 12)
	_hud_root.add_theme_constant_override("margin_right", 12)
	_hud_root.add_theme_constant_override("margin_top", 8)
	add_child(_hud_root)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_root.add_child(v)
	_lbl_wave = _label("Wave 1")
	v.add_child(_lbl_wave)
	_lbl_tilt = _label("Input: Mouse")
	v.add_child(_lbl_tilt)
	_lbl_msg = _label("")
	_lbl_msg.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
	v.add_child(_lbl_msg)
	_power_bar = ProgressBar.new()
	_power_bar.min_value = 0
	_power_bar.max_value = 100
	_power_bar.custom_minimum_size = Vector2(200, 22)
	_power_bar.show_percentage = false
	v.add_child(_power_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_btn_mode = _btn("Input: Mouse [M]", _on_cycle_mode)
	_btn_mode.custom_minimum_size = Vector2(200, BTN_H)
	row.add_child(_btn_mode)
	_btn_cal = _btn("Calibrate", _on_calibrate)
	row.add_child(_btn_cal)
	_btn_pause = _btn("Pause", _on_pause)
	row.add_child(_btn_pause)
	_btn_retry = _btn("Retry", _on_retry)
	row.add_child(_btn_retry)
	var row2 := HBoxContainer.new()
	v.add_child(row2)


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.65)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(panel)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	center.add_child(vb)
	_overlay_lbl = _label("")
	_overlay_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_overlay_lbl)
	_overlay_btn = _btn("Continue", _on_overlay_btn)
	vb.add_child(_overlay_btn)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT_SZ)
	return l


func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(120, BTN_H)
	b.add_theme_font_size_override("font_size", FONT_SZ)
	b.pressed.connect(cb)
	return b


func _process(_delta: float) -> void:
	var tin: Node = get_node_or_null("/root/TiltInput")
	if tin and tin.has_method("status_text"):
		_lbl_tilt.text = tin.call("status_text")
	for c in get_parent().get_children():
		if c is SpinningTop:
			_power_bar.value = (c as SpinningTop).spin_power
			break


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M or event.keycode == KEY_TAB:
			_cycle_mode()
			get_viewport().set_input_as_handled()


func on_phase_launch(w: int) -> void:
	_lbl_wave.text = "Wave %d — Launch!" % w
	_hide_overlay()


func on_phase_run() -> void:
	_hide_overlay()


func on_fell_over() -> void:
	_show_overlay("Fell over — Retry", "retry")


func on_wave_cleared(w: int) -> void:
	_show_overlay("Wave %d cleared!" % w, "next")


func _show_overlay(msg: String, mode: String) -> void:
	_overlay_mode = mode
	_overlay_lbl.text = msg
	_overlay_btn.text = "Retry" if mode == "retry" else "Next wave"
	_overlay.visible = true


func _hide_overlay() -> void:
	_overlay.visible = false
	_overlay_mode = ""


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
	if main.has_method("request_retry_same_wave"):
		main.request_retry_same_wave()


func _on_overlay_btn() -> void:
	var main = get_parent()
	_hide_overlay()
	if _overlay_mode == "retry":
		if main.has_method("request_retry_same_wave"):
			main.request_retry_same_wave()
	elif _overlay_mode == "next":
		if main.has_method("advance_wave"):
			main.advance_wave()


func forward_input(event: InputEvent) -> void:
	if _overlay.visible:
		return