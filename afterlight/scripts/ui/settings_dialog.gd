class_name SettingsDialog
extends PanelContainer
## Lokale Einstellungen: Spielername, Vollbild, VSync, Schatten. Werden sofort angewendet und gespeichert.

signal closed

var _name: LineEdit
var _fullscreen: CheckBox
var _vsync: CheckBox
var _shadows: CheckBox


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.panel(0.97))
	custom_minimum_size = Vector2(420, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	add_child(v)
	v.add_child(UiTheme.label("Einstellungen", 24))
	v.add_child(UiTheme.label("Spielername", 13, UiTheme.MUTED))
	_name = LineEdit.new()
	_name.max_length = 20
	_name.text = Settings.player_name
	v.add_child(_name)
	_fullscreen = _check(v, "Vollbild", Settings.fullscreen)
	_vsync = _check(v, "VSync", Settings.vsync)
	_shadows = _check(v, "Schatten (wirkt ab der nächsten Welt)", Settings.shadows)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var save := UiTheme.button("Übernehmen", _apply)
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(save)
	var back := UiTheme.button("Zurück", func(): closed.emit())
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(back)


func _check(parent: Control, text: String, on: bool) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	parent.add_child(c)
	return c


func _apply() -> void:
	var n := _name.text.strip_edges()
	Settings.player_name = n if n != "" else "Überlebender"
	Settings.fullscreen = _fullscreen.button_pressed
	Settings.vsync = _vsync.button_pressed
	Settings.shadows = _shadows.button_pressed
	Settings.save_settings()
	Settings.apply()
	closed.emit()
