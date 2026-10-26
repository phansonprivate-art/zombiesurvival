extends Node
## Lokale Einstellungen (pro Spieler, nicht Teil der Welt). Gespeichert in user://settings.cfg.

const PATH := "user://settings.cfg"

var fullscreen := false
var vsync := true
var shadows := true
var player_name := "Überlebender"


func _ready() -> void:
	InputSetup.register()
	load_settings()
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	vsync = bool(cfg.get_value("video", "vsync", vsync))
	shadows = bool(cfg.get_value("video", "shadows", shadows))
	player_name = String(cfg.get_value("player", "name", player_name))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "shadows", shadows)
	cfg.set_value("player", "name", player_name)
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("Einstellungen konnten nicht gespeichert werden: %s" % error_string(err))


func apply() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Session.local_player_name = player_name
