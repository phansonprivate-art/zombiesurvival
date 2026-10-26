class_name Palette
extends RefCounted
## Zentrale Materialbibliothek des Art-Sets. Alle Modelle teilen sich diese Materialien,
## damit das Spiel einheitlich aussieht und Materialien nur einmal existieren.

const DEFS := {
	# Holz
	"bark": {"c": "#4a3628", "r": 0.95},
	"wood": {"c": "#7a5638", "r": 0.85},
	"wood_light": {"c": "#a07b55", "r": 0.8},
	"wood_dark": {"c": "#4b372a", "r": 0.9},
	"plank": {"c": "#8a6a49", "r": 0.85},
	# Stein und Beton
	"stone": {"c": "#8d897e", "r": 0.92},
	"stone_dark": {"c": "#5d5a54", "r": 0.95},
	"concrete": {"c": "#928f86", "r": 0.95},
	"concrete_dark": {"c": "#66645e", "r": 0.95},
	"brick": {"c": "#7f4f3c", "r": 0.9},
	"rock": {"c": "#7c786e", "r": 0.95},
	"rock_dark": {"c": "#57544e", "r": 0.95},
	# Metall
	"metal": {"c": "#6f777d", "r": 0.45, "m": 0.6},
	"metal_dark": {"c": "#3c4246", "r": 0.5, "m": 0.55},
	"rust": {"c": "#7a4529", "r": 0.85, "m": 0.25},
	"roof": {"c": "#39414d", "r": 0.8},
	"roof_metal": {"c": "#56616b", "r": 0.55, "m": 0.45},
	"rubber": {"c": "#1d1e20", "r": 0.9},
	# Stoff und Farben
	"tarp": {"c": "#5a6541", "r": 0.95},
	"cloth_red": {"c": "#8c3a2f", "r": 0.9},
	"canvas": {"c": "#b3a88a", "r": 0.95},
	"paint_blue": {"c": "#3d5870", "r": 0.7, "m": 0.2},
	"paint_green": {"c": "#4e6849", "r": 0.7, "m": 0.2},
	"paint_cream": {"c": "#b3a98e", "r": 0.7, "m": 0.2},
	"olive": {"c": "#4f5536", "r": 0.85},
	# Vegetation
	"leaf_pine": {"c": "#2c4a30", "r": 0.9},
	"leaf_pine2": {"c": "#365a3a", "r": 0.9},
	"leaf": {"c": "#4b6b35", "r": 0.9},
	"leaf2": {"c": "#5d7b3b", "r": 0.9},
	"leaf_dry": {"c": "#7d7a40", "r": 0.9},
	"ore": {"c": "#9a5a32", "r": 0.7, "m": 0.3},
	"ore_crystal": {"c": "#e08a3c", "r": 0.35, "e": "#ff8a2a", "ee": 0.6},
	# Figuren
	"skin": {"c": "#d1a07c", "r": 0.8},
	"pants": {"c": "#363c45", "r": 0.9},
	"boots": {"c": "#2a2420", "r": 0.85},
	"backpack": {"c": "#59583d", "r": 0.9},
	# Licht und Akzente
	"window": {"c": "#1b2230", "r": 0.2, "e": "#ffb35c", "ee": 0.0},
	"glass_dark": {"c": "#1a2028", "r": 0.15, "m": 0.3},
	"void": {"c": "#0c0d0f", "r": 1.0},
	"fire": {"c": "#ff7a2a", "r": 1.0, "e": "#ff6a1a", "ee": 3.0},
	"lamp": {"c": "#ffe0a0", "r": 0.4, "e": "#ffcf80", "ee": 0.0},
	"accent": {"c": "#f2a541", "r": 0.5, "e": "#f2a541", "ee": 1.2},
	"asphalt_line": {"c": "#c9b77a", "r": 0.9},
}

static var _cache := {}
static var _ghost := {}


static func mat(name: String) -> StandardMaterial3D:
	if _cache.has(name):
		return _cache[name]
	var d: Dictionary = DEFS.get(name, {"c": "#ff00ff"})
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.html(d.c)
	m.roughness = float(d.get("r", 0.9))
	m.metallic = float(d.get("m", 0.0))
	if d.has("e"):
		m.emission_enabled = true
		m.emission = Color.html(d.e)
		m.emission_energy_multiplier = float(d.get("ee", 1.0))
	_cache[name] = m
	return m


## Material für Spielerfarben (Jacke usw.)
static func color_mat(c: Color, roughness := 0.85) -> StandardMaterial3D:
	var key := "col_" + c.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = roughness
	_cache[key] = m
	return m


## Halbtransparentes Material für die Bauvorschau
static func ghost(valid: bool) -> StandardMaterial3D:
	if _ghost.has(valid):
		return _ghost[valid]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.45, 0.95, 0.55, 0.45) if valid else Color(1.0, 0.3, 0.25, 0.45)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost[valid] = m
	return m


## Nachtwert 0..1: Fenster und Lampen leuchten warm
static func set_night(f: float) -> void:
	mat("window").emission_energy_multiplier = lerpf(0.0, 2.2, f)
	mat("window").albedo_color = Color.html("#1b2230").lerp(Color.html("#5a4026"), f)
	mat("lamp").emission_energy_multiplier = lerpf(0.0, 4.0, f)
