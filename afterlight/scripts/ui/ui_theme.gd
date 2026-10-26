class_name UiTheme
extends RefCounted
## Einheitliches Erscheinungsbild der Oberfläche: dunkles Marineblau/Anthrazit, warmer Bernstein-Akzent.

const BG := Color(0.065, 0.08, 0.115, 0.92)
const BG_SOFT := Color(0.1, 0.12, 0.165, 0.94)
const LINE := Color(1, 1, 1, 0.09)
const TEXT := Color("#e8e4d8")
const MUTED := Color("#99a0aa")
const ACCENT := Color("#f2a541")
const WARNING := Color("#e8833a")
const DANGER := Color("#e05a4f")
const SUCCESS := Color("#86c46f")
const INFO := Color("#7fb2e0")

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 17
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("panel", "Panel", panel())

	var normal := _box(Color(0.14, 0.17, 0.23, 0.95), LINE, 6)
	var hover := _box(Color(0.19, 0.22, 0.29, 0.98), ACCENT.darkened(0.3), 6)
	var pressed := _box(Color(0.24, 0.2, 0.14, 1.0), ACCENT, 6)
	var disabled := _box(Color(0.1, 0.11, 0.14, 0.8), Color(1, 1, 1, 0.04), 6)
	for s in [normal, hover, pressed, disabled]:
		s.content_margin_left = 14
		s.content_margin_right = 14
		s.content_margin_top = 8
		s.content_margin_bottom = 8
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT.lightened(0.3))
	t.set_color("font_disabled_color", "Button", MUTED.darkened(0.3))

	var field := _box(Color(0.04, 0.05, 0.08, 0.95), LINE, 5)
	field.content_margin_left = 10
	field.content_margin_right = 10
	field.content_margin_top = 6
	field.content_margin_bottom = 6
	t.set_stylebox("normal", "LineEdit", field)
	var field_focus := field.duplicate()
	field_focus.border_color = ACCENT
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_color("font_color", "LineEdit", TEXT)

	var bar_bg := _box(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.06), 4)
	var bar_fill := _box(SUCCESS, Color(0, 0, 0, 0), 4)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_font_size("font_size", "ProgressBar", 12)

	t.set_color("font_color", "CheckBox", TEXT)
	t.set_stylebox("normal", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("hover", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("panel", "TooltipPanel", _box(Color(0.05, 0.06, 0.09, 0.97), ACCENT.darkened(0.4), 5))
	t.set_color("font_color", "TooltipLabel", TEXT)
	_theme = t
	return t


static func panel(alpha := 0.92) -> StyleBoxFlat:
	var s := _box(Color(BG.r, BG.g, BG.b, alpha), LINE, 8)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 8
	return s


static func _box(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	return s


static func label(text: String, size := 17, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


static func bar_style(color: Color) -> StyleBoxFlat:
	return _box(color, Color(0, 0, 0, 0), 4)
