class_name PhysicsMenu
extends CanvasLayer
## In-game physics tunables panel (pauses tree while open).

const VT := preload("res://scripts/visual_theme.gd")

var _open := false
var _prev_paused := false
var _root_panel: PanelContainer
var _scroll: ScrollContainer
var _vbox: VBoxContainer
var _rows: Dictionary = {}
var _syncing := false
var _settings_path := "user://settings.cfg"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 25
	visible = false
	_build_ui()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_root_panel = PanelContainer.new()
	_root_panel.custom_minimum_size = Vector2(640, 760)
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
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_root_panel.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)
	var title := Label.new()
	title.text = "Physics settings"
	title.add_theme_font_size_override("font_size", 26)
	outer.add_child(title)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0, 520)
	outer.add_child(_scroll)
	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 8)
	_scroll.add_child(_vbox)
	for def in PhysicsSettings.DEFS:
		_add_row(def)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	outer.add_child(btn_row)
	var reset_all := Button.new()
	reset_all.text = "Reset all"
	reset_all.custom_minimum_size = Vector2(140, 56)
	VT.apply_button_theme(reset_all)
	reset_all.pressed.connect(_on_reset_all)
	btn_row.add_child(reset_all)
	btn_row.add_child(Control.new())
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(140, 56)
	VT.apply_button_theme(close_btn)
	close_btn.pressed.connect(close)
	btn_row.add_child(close_btn)


func _add_row(def: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.name = "Row_%s" % def.key
	_vbox.add_child(row)
	var lbl := Label.new()
	lbl.text = str(def.label)
	lbl.custom_minimum_size = Vector2(200, 0)
	lbl.add_theme_font_size_override("font_size", 18)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = float(def.min)
	slider.max_value = float(def.max)
	slider.step = float(def.step)
	slider.value = PhysicsSettings.get_value(def.key)
	row.add_child(slider)
	var spin := SpinBox.new()
	spin.custom_minimum_size = Vector2(110, 0)
	spin.min_value = float(def.min)
	spin.max_value = float(def.max)
	spin.step = float(def.step)
	spin.value = slider.value
	spin.allow_greater = false
	spin.allow_lesser = false
	row.add_child(spin)
	var reset := Button.new()
	reset.text = "Reset"
	reset.custom_minimum_size = Vector2(72, 44)
	VT.apply_button_theme(reset)
	reset.pressed.connect(_on_row_reset.bind(def.key))
	row.add_child(reset)
	slider.value_changed.connect(_on_slider_changed.bind(def.key, spin))
	spin.value_changed.connect(_on_spin_changed.bind(def.key, slider))
	_rows[def.key] = {"slider": slider, "spin": spin}


func _on_slider_changed(v: float, key: String, spin: SpinBox) -> void:
	if _syncing:
		return
	_syncing = true
	spin.value = v
	_syncing = false
	PhysicsSettings.set_value(key, v)


func _on_spin_changed(v: float, key: String, slider: HSlider) -> void:
	if _syncing:
		return
	_syncing = true
	slider.value = v
	_syncing = false
	PhysicsSettings.set_value(key, v)


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
	_syncing = true
	var v: float = PhysicsSettings.get_value(key)
	var row: Dictionary = _rows[key]
	(row.slider as HSlider).value = v
	(row.spin as SpinBox).value = v
	_syncing = false


func is_open() -> bool:
	return _open


func spinbox_for_key(key: String) -> SpinBox:
	if not _rows.has(key):
		return null
	return _rows[key].spin as SpinBox


func slider_for_key(key: String) -> HSlider:
	if not _rows.has(key):
		return null
	return _rows[key].slider as HSlider


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
	for d in PhysicsSettings.DEFS:
		_refresh_row(d.key)


func close() -> void:
	if not _open:
		return
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