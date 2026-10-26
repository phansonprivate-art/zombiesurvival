class_name PauseMenu
extends Control
## ESC-Menü. Im Einzelspieler hält die Pause die Weltzeit an (SceneTree.paused).
## Im Koop (Phase 5) darf nur der Host pausieren – die Regel liegt dann in der Session.

signal resume_requested
signal main_menu_requested

var _box: VBoxContainer
var _settings: SettingsDialog
var _confirm: PanelContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel(0.97))
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.custom_minimum_size = Vector2(340, 0)
	_box.add_theme_constant_override("separation", 10)
	panel.add_child(_box)
	_box.add_child(UiTheme.label("PAUSE", 28, UiTheme.ACCENT))
	_box.add_child(UiTheme.label("Die Weltzeit ist angehalten.", 14, UiTheme.MUTED))
	_box.add_child(UiTheme.button("Fortsetzen", func(): resume_requested.emit()))
	var save := UiTheme.button("Speichern (folgt in Phase 4)", func(): pass)
	save.disabled = true
	_box.add_child(save)
	_box.add_child(UiTheme.button("Einstellungen", _open_settings))
	_box.add_child(UiTheme.button("Zum Hauptmenü", _ask_main_menu))
	_box.add_child(UiTheme.button("Spiel beenden", func(): get_tree().quit()))
	_settings = SettingsDialog.new()
	_settings.visible = false
	_settings.closed.connect(func(): _settings.visible = false; panel.visible = true)
	center.add_child(_settings)
	_confirm = PanelContainer.new()
	_confirm.add_theme_stylebox_override("panel", UiTheme.panel(0.98))
	_confirm.visible = false
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	_confirm.add_child(cv)
	cv.add_child(UiTheme.label("Zum Hauptmenü zurückkehren?", 20))
	cv.add_child(UiTheme.label("Speichern gibt es erst ab Phase 4.\nDiese Welt geht dabei verloren.", 14, UiTheme.WARNING))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	cv.add_child(row)
	row.add_child(UiTheme.button("Ja, verlassen", func(): main_menu_requested.emit()))
	row.add_child(UiTheme.button("Abbrechen", func(): _confirm.visible = false; panel.visible = true))
	center.add_child(_confirm)
	_settings.set_meta("panel", panel)
	_confirm.set_meta("panel", panel)


func _open_settings() -> void:
	_settings.get_meta("panel").visible = false
	_settings.visible = true


func _ask_main_menu() -> void:
	_confirm.get_meta("panel").visible = false
	_confirm.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		if _settings.visible or _confirm.visible:
			_settings.visible = false
			_confirm.visible = false
			_settings.get_meta("panel").visible = true
		else:
			resume_requested.emit()
		get_viewport().set_input_as_handled()
