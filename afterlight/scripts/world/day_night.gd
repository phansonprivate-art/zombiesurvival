class_name DayNight
extends Node
## Beleuchtung abhängig von der Weltzeit: Sonnenstand, warme Dämmerung, kalte Nacht, Nebel.

var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var night_factor := 0.0  ## 0 = Tag, 1 = tiefe Nacht

const SKY_DAY := Color("#5d86b5")
const SKY_DAY_HORIZON := Color("#b9c6cf")
const SKY_DUSK_HORIZON := Color("#d88a52")
const SKY_NIGHT := Color("#0b1220")
const SKY_NIGHT_HORIZON := Color("#1a2638")
const FOG_DAY := Color("#9fb0bd")
const FOG_DUSK := Color("#c79a72")
const FOG_NIGHT := Color("#121b2a")


func build(parent: Node3D) -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.ground_bottom_color = Color("#2a2f2a")
	sky_mat.ground_horizon_color = Color("#6d7a74")
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.fog_enabled = true
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.35
	env.fog_aerial_perspective = 0.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.9
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = Settings.shadows
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_blur = 1.5
	parent.add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color("#7f9ad0")
	moon.shadow_enabled = Settings.shadows
	moon.directional_shadow_max_distance = 60.0
	moon.basis = Basis.looking_at(Vector3(0.4, -0.75, -0.5).normalized(), Vector3.UP)
	parent.add_child(moon)


## hour 0..24, day_start/night_start aus der Weltzeit
func update(hour: float, day_start: float, night_start: float) -> void:
	# Sonnenhöhe: 0 bei Sonnenauf-/untergang, 1 zur Tagesmitte, negativ in der Nacht
	var day_len := night_start - day_start
	var t := (hour - day_start) / day_len
	var elev := sin(t * PI) if t >= 0.0 and t <= 1.0 else -0.3
	var daylight := smoothstep(-0.12, 0.2, elev)
	var dusk := clampf(1.0 - absf(elev) / 0.3, 0.0, 1.0) * (1.0 if elev > -0.1 else 0.0)
	night_factor = 1.0 - smoothstep(-0.08, 0.15, elev)

	var az := lerpf(-PI * 0.55, PI * 0.55, clampf(t, 0.0, 1.0))
	var e := deg_to_rad(maxf(6.0, elev * 62.0))
	var sun_dir := Vector3(sin(az) * cos(e), sin(e), -cos(az) * cos(e) * 0.6 + 0.4).normalized()
	sun.basis = Basis.looking_at(-sun_dir, Vector3.UP)
	sun.light_energy = lerpf(0.0, 1.25, daylight)
	sun.light_color = Color("#fff1dc").lerp(Color("#ff9550"), dusk * 0.85)
	sun.visible = sun.light_energy > 0.01
	moon.light_energy = lerpf(0.0, 0.32, night_factor)
	moon.visible = moon.light_energy > 0.01

	sky_mat.sky_top_color = SKY_NIGHT.lerp(SKY_DAY, daylight)
	var horizon := SKY_NIGHT_HORIZON.lerp(SKY_DAY_HORIZON, daylight).lerp(SKY_DUSK_HORIZON, dusk * 0.7)
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon.darkened(0.3)
	env.ambient_light_energy = lerpf(0.3, 0.7, daylight)
	env.fog_light_color = FOG_NIGHT.lerp(FOG_DAY, daylight).lerp(FOG_DUSK, dusk * 0.5)
	env.fog_density = lerpf(0.008, 0.0035, daylight)
	env.adjustment_saturation = lerpf(0.65, 0.92, daylight)
	Palette.set_night(night_factor)
