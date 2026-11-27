class_name InputPickerMenu
extends CanvasLayer
## Bottom-left input mode picker (explicit + Auto).

const VT := preload("res://scripts/visual_theme.gd")
const ViewportLayout := preload("res://scripts/viewport_layout.gd")

signal closed

var _open := false
var _prev_paused := false
var _ui_host: Node
var _chrome: Control
var _btn: Button
var _backdrop: ColorRect
var _popup: PanelContainer
var _bot_h := 140.0
var _option_vbox: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 24
	_build_ui()
	visible = true


func set_ui_host(host: Node) -> void:
	_ui_host = host


func is_open() -> bool:
	return _open


func button() -> Button:
	return _btn


func button_screen_rect() -> Rect2:
	if _btn == null:
		return Rect2()
	return _btn.get_global_rect()


func popup_screen_rect() -> Rect2:
	if _popup == null or not _open:
		return Rect2()
	return _popup.get_global_rect()


func consumes_point(screen_pos: Vector2) -> bool:
	if _btn and _btn.get_global_rect().has_point(screen_pos):
		return true
	if _open and _backdrop and _backdrop.get_global_rect().has_point(screen_pos):
		return true
	if _open and _popup and _popup.get_global_rect().has_point(screen_pos):
		return true
	return false


func layout_chrome(vp: Vector2, bot_h: float) -> void:
	_bot_h = bot_h
	var sz: float = ViewportLayout.input_picker_size(vp)
	var m: float = ViewportLayout.edge_margin(vp, 8.0)
	_btn.custom_minimum_size = Vector2(sz, sz)
	_btn.position = Vector2(m, vp.y - bot_h + maxf(4.0, (bot_h - sz) * 0.5))
	_btn.size = Vector2(sz, sz)
	if _open:
		_center_popup(vp)


func _build_ui() -> void:
	_chrome = Control.new()
	_chrome.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chrome)
	_btn = Button.new()
	_btn.name = "InputPickerButton"
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_btn.pressed.connect(_on_toggle_popup)
	VT.apply_button_theme(_btn)
	_btn.add_theme_font_size_override("font_size", 16)
	_chrome.add_child(_btn)
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0, 0, 0, 0.45)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.visible = false
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_input)
	_chrome.add_child(_backdrop)
	_popup = PanelContainer.new()
	_popup.visible = false
	_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_box := StyleBoxFlat.new()
	panel_box.bg_color = Color(0.13, 0.14, 0.2, 0.97)
	panel_box.border_color = Color(0.4, 0.44, 0.58)
	panel_box.set_border_width_all(1)
	panel_box.corner_radius_top_left = 14
	panel_box.corner_radius_top_right = 14
	panel_box.corner_radius_bottom_left = 14
	panel_box.corner_radius_bottom_right = 14
	_popup.add_theme_stylebox_override("panel", panel_box)
	_chrome.add_child(_popup)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_popup.add_child(margin)
	_option_vbox = VBoxContainer.new()
	_option_vbox.add_theme_constant_override("separation", 6)
	margin.add_child(_option_vbox)
	var v := _option_vbox
	var title := Label.new()
	title.text = "Input"
	title.add_theme_font_size_override("font_size", 20)
	v.add_child(title)
	v.add_child(_make_row("Mouse", InputModes.Mode.MOUSE, false))
	v.add_child(_make_row("Keyboard", InputModes.Mode.KEYBOARD, false))
	v.add_child(_make_row("Finger drag", InputModes.Mode.DRAG, false))
	v.add_child(_make_row("Tilt", InputModes.Mode.TILT, true))
	v.add_child(_make_row("Auto", -1, false))
	_refresh_button_label()


func _make_row(label: String, mode: int, tilt_row: bool) -> Button:
	var b := Button.new()
	b.text = label
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(200, 48)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	VT.apply_button_theme(b)
	b.pressed.connect(_on_pick.bind(mode, tilt_row))
	b.set_meta("picker_mode", mode)
	b.set_meta("tilt_row", tilt_row)
	return b


func _on_pick(mode: int, tilt_row: bool) -> void:
	var tin: Node = get_node_or_null("/root/TiltInput")
	if tin == null:
		close()
		return
	if mode < 0:
		if tin.has_method("apply_auto_detect"):
			tin.call("apply_auto_detect")
	else:
		if tilt_row and tin.has_method("tilt_picker_enabled") and not tin.call("tilt_picker_enabled"):
			return
		if tin.has_method("pick_mode_from_ui"):
			tin.call("pick_mode_from_ui", mode)
		elif tin.has_method("set_mode"):
			tin.call("set_mode", mode)
	_refresh_button_label()
	if _ui_host and _ui_host.has_method("_refresh_settings_menu"):
		_ui_host.call("_refresh_settings_menu")
	close()


func _on_toggle_popup() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	if _open:
		return
	var tree := get_tree()
	_prev_paused = tree.paused
	tree.paused = true
	_open = true
	_backdrop.visible = true
	_popup.visible = true
	var tin: Node = get_node_or_null("/root/TiltInput")
	if tin and tin.has_method("set_steer_blocked"):
		tin.call("set_steer_blocked", true)
	_refresh_popup_rows()
	_refresh_button_label()
	var vp: Rect2 = get_viewport().get_visible_rect()
	_center_popup(vp.size)


func close() -> void:
	if not _open:
		return
	_open = false
	_backdrop.visible = false
	_popup.visible = false
	var tree := get_tree()
	if tree:
		tree.paused = _prev_paused
	var tin: Node = get_node_or_null("/root/TiltInput")
	if tin:
		if tin.has_method("set_steer_blocked"):
			tin.call("set_steer_blocked", false)
		if tin.has_method("release_menu_drag"):
			tin.call("release_menu_drag")
	closed.emit()


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _center_popup(vp: Vector2) -> void:
	var sz: Vector2 = _popup.get_combined_minimum_size()
	if sz.x < 180.0:
		sz.x = 220.0
	var btn_c: Vector2 = _btn.get_global_rect().get_center()
	var x: float = clampf(btn_c.x, 8.0, vp.x - sz.x - 8.0)
	var y: float = btn_c.y - sz.y - 12.0
	if y < 8.0:
		y = minf(_btn.global_position.y + _btn.size.y + 8.0, vp.y - sz.y - 8.0)
	_popup.position = Vector2(x, y)
	_popup.size = sz


func _refresh_popup_rows() -> void:
	var tin: Node = get_node_or_null("/root/TiltInput")
	var tilt_ok: bool = tin and tin.has_method("tilt_picker_enabled") and bool(tin.call("tilt_picker_enabled"))
	for c in _option_vbox.get_children():
		if c is Button and bool(c.get_meta("tilt_row", false)):
			var b := c as Button
			if tilt_ok:
				b.disabled = false
				b.text = "Tilt"
				b.modulate = Color.WHITE
			else:
				b.disabled = true
				b.text = "Tilt (unavailable)"
				b.modulate = Color(0.75, 0.75, 0.75)


func _refresh_button_label() -> void:
	var tin: Node = get_node_or_null("/root/TiltInput")
	if tin == null:
		_btn.text = "In"
		return
	var eff: int = int(tin.call("effective_mode"))
	var short: String = InputModes.mode_short_label(eff)
	var explicit: bool = tin.has_method("mode_explicit") and bool(tin.call("mode_explicit"))
	if not explicit:
		short += "·A"
	_btn.text = short
	_btn.tooltip_text = "Input: %s%s" % [
		InputModes.mode_name(eff),
		" (Auto)" if not explicit else " (manual)",
	]


func refresh_chrome() -> void:
	_refresh_button_label()