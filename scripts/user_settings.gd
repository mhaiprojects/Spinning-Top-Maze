class_name UserSettings
extends RefCounted
## Merged load/save for user://settings.cfg (input mode + visual background).

const PlayBg := preload("res://scripts/play_background.gd")

const DEFAULT_PATH := "user://settings.cfg"


static func load_config(path: String) -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(path)
	return cfg


static func save_config(path: String, cfg: ConfigFile) -> bool:
	if OS.get_environment("STM_HEADLESS_TEST") == "1" and path == DEFAULT_PATH:
		return false
	return cfg.save(path) == OK


static func save_input_mode(path: String, mode: int) -> bool:
	var cfg := load_config(path)
	cfg.set_value("input", "mode", mode)
	return save_config(path, cfg)


static func load_input_mode(path: String) -> int:
	var cfg := load_config(path)
	return int(cfg.get_value("input", "mode", -1))


static func save_background(path: String, bg: int) -> bool:
	var cfg := load_config(path)
	cfg.set_value("visual", "background", bg)
	return save_config(path, cfg)


static func load_background(path: String) -> int:
	var cfg := load_config(path)
	var v: Variant = cfg.get_value("visual", "background", PlayBg.default_id())
	return PlayBg.from_saved(v)