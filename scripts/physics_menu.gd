class_name PhysicsMenu
extends CanvasLayer
## Settings overlay: game controls + physics tunables (pauses tree while open).

const VT := preload("res://scripts/visual_theme.gd")
const ViewportLayout := preload("res://scripts/viewport_layout.gd")

var _open := false
var _prev_paused := false
var _ui_host: Node
var _root_panel: PanelContainer
var _scroll: ScrollContainer
var _game_vbox: VBoxContainer
var _physics_vbox: VBoxContainer
var _rows: Dictionary = {}
var _settings_path := "user://settings.cfg"
var _btn_mode: Button
var _btn_board: Button
var _btn_calibrate: Button
var _btn_retry: Button
var _btn_resume: Button
var _frame_margin: MarginContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 25
	visible = false
	_build_ui()


func set_ui_host(host: Node) -> void:
	_ui_host = host


func apply_viewport_layout(vp: Vector2) -> void:
	if _frame_margin == null or _root_panel == null:
		return
	var s: float = ViewportLayout.ui_scale(vp)
	var m: float = maxf(8.0, 12.0 * s)
	var top_m: float = maxf(8.0, minf(48.0 * s, vp.y * 0.1))
	_frame_margin.add_theme_constant_override("margin_left", int(m))
	_frame_margin.add_theme_constant_override("margin_right", int(m))
	_frame_margin.add_theme_constant_override("margin_top", int(top_m))
	_frame_margin.add_theme_constant_override("margin_bottom", int(m))
	var max_h: float = maxf(160.0, vp.y - top_m - m * 2.0)
	var max_w: float = maxf(220.0, vp.x - m * 2.0)
	_root_panel.custom_minimum_size = Vector2(
		minf(maxf(260.0, 300.0 * s), max_w),
		minf(maxf(220.0, 400.0 * s), max_h)
	)


func settings_panel_rect() -> Rect2:
	if _root_panel == null:
		return Rect2()
	return _root_panel.get_global_rect()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_frame_margin = MarginContainer.new()
	_frame_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame_margin.add_theme_constant_override("margin_left", 12)
	_frame_margin.add_theme_constant_override("margin_right", 12)
	_frame_margin.add_theme_constant_override("margin_top", 48)
	_frame_margin.add_theme_constant_override("margin_bottom", 48)
	add_child(_frame_margin)
	var center := _frame_margin
	_root_panel = PanelContainer.new()
	_root_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root_panel.custom_minimum_size = Vector2(320, 480)
	var panel_box := StyleBoxFlat.new()
	panel_box.bg_color = Color(0.12, 0.13, 0.18, 0.97)
	panel_box.corner_radius_top_left = 16
	panel_box.corner_radius_top_right = 16
	panel_box.corner_radius_bottom_left = 16
	panel_box.corner_radius_bottom_right = 16
	panel_box.border_color = Color(0.38, 0.42, 0.55)
	panel_box.set_border_width_all(1)
	_root_panel.add_theme_stylebox_override("panel", panel_box)
	center.add_child(_root_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_root_panel.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(outer)
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 26)
	outer.add_child(title)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	outer.add_child(_scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 10)
	_scroll.add_child(inner)
	var game_title := Label.new()
	game_title.text = "Game"
	game_title.add_theme_font_size_override("font_size", 20)
	inner.add_child(game_title)
	_game_vbox = VBoxContainer.new()
	_game_vbox.add_theme_constant_override("separation", 8)
	inner.add_child(_game_vbox)
	_btn_mode = _menu_btn("Input: Mouse [M]", _on_cycle_mode)
	_game_vbox.add_child(_btn_mode)
	_btn_board = _menu_btn("Board: Tabletop [B]", _on_cycle_board)
	_game_vbox.add_child(_btn_board)
	_btn_calibrate = _menu_btn("Calibrate tilt", _on_calibrate)
	_game_vbox.add_child(_btn_calibrate)
	_btn_retry = _menu_btn("Retry wave", _on_retry_wave)
	_game_vbox.add_child(_btn_retry)
	var phys_title := Label.new()
	phys_title.text = "Physics"
	phys_title.add_theme_font_size_override("font_size", 20)
	inner.add_child(phys_title)
	_physics_vbox = VBoxContainer.new()
	_physics_vbox.add_theme_constant_override("separation", 8)
	inner.add_child(_physics_vbox)
	for def in PhysicsSettings.DEFS:
		_add_row(def)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	outer.add_child(btn_row)
	var reset_all := Button.new()
	reset_all.text = "Reset all"
	reset_all.custom_minimum_size = Vector2(120, 52)
	VT.apply_button_theme(reset_all)
	reset_all.pressed.connect(_on_reset_all)
	btn_row.add_child(reset_all)
	btn_row.add_child(Control.new())
	_btn_resume = Button.new()
	_btn_resume.text = "Resume"
	_btn_resume.custom_minimum_size = Vector2(140, 52)
	VT.apply_button_theme(_btn_resume)
	_btn_resume.pressed.connect(close)
	btn_row.add_child(_btn_resume)


func _menu_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 52)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 18)
	VT.apply_button_theme(b)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _suggested_range_label(def: Dictionary) -> String:
	var s: String = str(def.label)
	if def.has("min") and def.has("max"):
		s += " (suggest %s–%s)" % [
			PhysicsSettings.format_number(float(def.min)),
			PhysicsSettings.format_number(float(def.max)),
		]
	return s


func _add_row(def: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.name = "Row_%s" % def.key
	_physics_vbox.add_child(row)
	var lbl := Label.new()
	lbl.text = _suggested_range_label(def)
	lbl.custom_minimum_size = Vector2(140, 0)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 15)
	row.add_child(lbl)
	var edit := LineEdit.new()
	edit.custom_minimum_size = Vector2(112, 40)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text = PhysicsSettings.display_value(def.key)
	edit.clear_button_enabled = false
	edit.text_submitted.connect(_on_line_submitted.bind(def.key, edit))
	edit.focus_exited.connect(_on_line_focus_exited.bind(def.key, edit))
	if _use_web_prompt():
		edit.gui_input.connect(_on_line_gui.bind(def.key, edit))
		edit.focus_mode = Control.FOCUS_CLICK
	row.add_child(edit)
	var reset := Button.new()
	reset.text = "Reset"
	reset.custom_minimum_size = Vector2(64, 40)
	VT.apply_button_theme(reset)
	reset.pressed.connect(_on_row_reset.bind(def.key))
	row.add_child(reset)
	_rows[def.key] = {"edit": edit}


func _use_web_prompt() -> bool:
	return OS.has_feature("web") and InputModes.is_touch_device()


func _on_line_gui(event: InputEvent, key: String, edit: LineEdit) -> void:
	if not _use_web_prompt():
		return
	if event is InputEventScreenTouch and event.pressed:
		_open_web_prompt(key, edit)
		edit.accept_event()


func _open_web_prompt(key: String, edit: LineEdit) -> void:
	var cur_json: String = JSON.stringify(edit.text)
	var js: String = (
		"(function(){var v=prompt('Enter value',%s);if(v===null)return '';return v;})();" % cur_json
	)
	var res: Variant = JavaScriptBridge.eval(js, true)
	if res == null:
		return
	var s: String = str(res)
	if s.is_empty():
		return
	_commit_field(key, s, edit)


func _on_line_submitted(text: String, key: String, edit: LineEdit) -> void:
	_commit_field(key, text, edit)


func _on_line_focus_exited(key: String, edit: LineEdit) -> void:
	_commit_field(key, edit.text, edit)


func _commit_field(key: String, text: String, edit: LineEdit) -> void:
	var parsed: Variant = PhysicsSettings.parse_finite_number(text)
	if parsed == null:
		_flash_invalid(edit)
		edit.text = PhysicsSettings.display_value(key)
		return
	if not PhysicsSettings.set_value(key, float(parsed)):
		_flash_invalid(edit)
		edit.text = PhysicsSettings.display_value(key)
		return
	edit.text = PhysicsSettings.display_value(key)


func _flash_invalid(edit: LineEdit) -> void:
	var base: Color = edit.modulate
	edit.modulate = Color(1.0, 0.45, 0.45)
	var tw := create_tween()
	tw.tween_property(edit, "modulate", base, 0.35)


func _commit_all_fields() -> void:
	for key in _rows:
		var edit: LineEdit = _rows[key].edit as LineEdit
		_commit_field(key, edit.text, edit)


func refresh_game_rows() -> void:
	var tin: Node = get_node_or_null("/root/TiltInput")
	if tin == null:
		return
	var mode_name := "Mouse"
	if tin.has_method("status_text"):
		var st: String = str(tin.call("status_text"))
		if st.begins_with("Input: "):
			mode_name = st.split(" ")[1].trim_suffix("(on)").trim_suffix("(denied)")
	mode_name = mode_name.split("(")[0].strip_edges()
	_btn_mode.text = "Input: %s [M]" % mode_name
	var bg_name := "Tabletop"
	if tin.has_method("background_name"):
		bg_name = str(tin.call("background_name"))
	_btn_board.text = "Board: %s [B]" % bg_name
	var tilt: bool = tin.has_method("selected_mode") and int(tin.call("selected_mode")) == InputModes.Mode.TILT
	_btn_calibrate.visible = tilt


func _on_cycle_mode() -> void:
	if _ui_host and _ui_host.has_method("_cycle_mode"):
		_ui_host.call("_cycle_mode")
	refresh_game_rows()


func _on_cycle_board() -> void:
	if _ui_host and _ui_host.has_method("_cycle_board"):
		_ui_host.call("_cycle_board")
	refresh_game_rows()


func _on_calibrate() -> void:
	var t: Node = get_node_or_null("/root/TiltInput")
	if t and t.has_method("calibrate_zero"):
		t.call("calibrate_zero")


func _on_retry_wave() -> void:
	if _ui_host and _ui_host.has_method("menu_retry_wave"):
		_ui_host.call("menu_retry_wave")


func _on_row_reset(key: String) -> void:
	PhysicsSettings.reset(key)
	_refresh_row(key)


func _on_reset_all() -> void:
	PhysicsSettings.reset_all()
	for d in PhysicsSettings.DEFS:
		_refresh_row(d.key)


func _refresh_row(key: String) -> void:
	if not _rows.has(key):
		return
	var edit: LineEdit = _rows[key].edit as LineEdit
	edit.text = PhysicsSettings.display_value(key)


func is_open() -> bool:
	return _open


func btn_board() -> Button:
	return _btn_board


func btn_mode() -> Button:
	return _btn_mode


func btn_calibrate() -> Button:
	return _btn_calibrate


func btn_retry() -> Button:
	return _btn_retry


func lineedit_for_key(key: String) -> LineEdit:
	if not _rows.has(key):
		return null
	return _rows[key].edit as LineEdit


func physics_vbox() -> VBoxContainer:
	return _physics_vbox


func set_settings_path(path: String) -> void:
	_settings_path = path


func open() -> void:
	if _open:
		return
	var tree := get_tree()
	_prev_paused = tree.paused
	tree.paused = true
	_open = true
	visible = true
	var tin: Node = get_node_or_null("/root/TiltInput")
	if tin and tin.has_method("set_steer_blocked"):
		tin.call("set_steer_blocked", true)
	var vp: Rect2 = get_viewport().get_visible_rect()
	apply_viewport_layout(vp.size)
	refresh_game_rows()
	for d in PhysicsSettings.DEFS:
		_refresh_row(d.key)


func close() -> void:
	if not _open:
		return
	_commit_all_fields()
	_open = false
	visible = false
	var vp := get_viewport()
	if vp:
		var fo := vp.gui_get_focus_owner()
		if fo is LineEdit:
			fo.release_focus()
	PhysicsSettings.save_to_path(_settings_path)
	var tree := get_tree()
	if tree:
		tree.paused = _prev_paused
	var tin: Node = get_node_or_null("/root/TiltInput")
	if tin:
		if tin.has_method("set_steer_blocked"):
			tin.call("set_steer_blocked", false)
		if tin.has_method("release_menu_drag"):
			tin.call("release_menu_drag")


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()