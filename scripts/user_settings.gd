class_name UserSettings
extends RefCounted
## Merged load/save for user://settings.cfg (input mode + visual background).

const PlayBg := preload("res://scripts/play_background.gd")

const DEFAULT_PATH := "user://settings.cfg"
const LS_INPUT_KEY := "stm_input"
const INPUT_SECTION := "input"
const MODE_KEY := "mode"
const MODE_EXPLICIT_KEY := "mode_explicit"


static func load_config(path: String) -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(path)
	return cfg


static func save_config(path: String, cfg: ConfigFile) -> bool:
	if OS.get_environment("STM_HEADLESS_TEST") == "1" and path == DEFAULT_PATH:
		return false
	return cfg.save(path) == OK


static func save_input_mode(path: String, mode: int) -> bool:
	return save_input_mode_full(path, mode, true)


static func save_input_mode_full(path: String, mode: int, explicit: bool) -> bool:
	var cfg := load_config(path)
	cfg.set_value(INPUT_SECTION, MODE_KEY, mode)
	cfg.set_value(INPUT_SECTION, MODE_EXPLICIT_KEY, explicit)
	if OS.has_feature("web"):
		_mirror_input_local_storage(mode, explicit)
	return save_config(path, cfg)


static func load_input_mode(path: String) -> int:
	var cfg := load_config(path)
	if OS.has_feature("web"):
		var ls: Dictionary = _load_input_local_storage()
		if ls.has(MODE_KEY):
			return int(ls[MODE_KEY])
	return int(cfg.get_value(INPUT_SECTION, MODE_KEY, -1))


static func load_mode_explicit(path: String) -> bool:
	var cfg := load_config(path)
	if OS.has_feature("web"):
		var ls: Dictionary = _load_input_local_storage()
		if ls.has(MODE_EXPLICIT_KEY):
			return bool(ls[MODE_EXPLICIT_KEY])
	if cfg.has_section_key(INPUT_SECTION, MODE_EXPLICIT_KEY):
		return bool(cfg.get_value(INPUT_SECTION, MODE_EXPLICIT_KEY, false))
	# Migration: legacy saves only stored `mode` after the user picked M / Settings.
	if cfg.has_section_key(INPUT_SECTION, MODE_KEY):
		return true
	return false


static func _mirror_input_local_storage(mode: int, explicit: bool) -> void:
	var json := JSON.stringify({MODE_KEY: mode, MODE_EXPLICIT_KEY: explicit})
	JavaScriptBridge.eval(
		"(function(){try{localStorage.setItem('%s',%s);}catch(e){}})();" % [LS_INPUT_KEY, json],
		true
	)


static func _load_input_local_storage() -> Dictionary:
	var s: String = JavaScriptBridge.eval(
		"(function(){try{return localStorage.getItem('%s')||'';}catch(e){return '';}})();" % LS_INPUT_KEY,
		true
	)
	if s.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(s)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


static func save_background(path: String, bg: int) -> bool:
	var cfg := load_config(path)
	cfg.set_value("visual", "background", bg)
	return save_config(path, cfg)


static func load_background(path: String) -> int:
	var cfg := load_config(path)
	var v: Variant = cfg.get_value("visual", "background", PlayBg.default_id())
	return PlayBg.from_saved(v)