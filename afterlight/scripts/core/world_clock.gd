class_name WorldClock
extends RefCounted
## Zentrale Weltzeit. Tag N beginnt um day_start_hour, die Nacht N beginnt um
## night_start_hour desselben Tages und endet am Morgen von Tag N+1.

var day: int = 1
var hour: float = 7.0
var elapsed: float = 0.0
var day_start: float = 6.0
var night_start: float = 20.0
var day_seconds: float = 480.0
var night_seconds: float = 240.0


func configure(cfg: Dictionary) -> void:
	day_start = float(cfg.get("day_start_hour", 6.0))
	night_start = float(cfg.get("night_start_hour", 20.0))
	day_seconds = float(cfg.get("day_seconds", 480.0))
	night_seconds = float(cfg.get("night_seconds", 240.0))
	hour = float(cfg.get("start_hour", 7.0))


func is_night() -> bool:
	return is_night_hour(hour)


func is_night_hour(h: float) -> bool:
	return h >= night_start or h < day_start


## Spielstunden pro Echtsekunde zur angegebenen Uhrzeit
func rate_at(h: float) -> float:
	if is_night_hour(h):
		return (24.0 - night_start + day_start) / night_seconds
	return (night_start - day_start) / day_seconds


## Rückgabe: Liste von Ereignissen wie {"type": "night_started", "day": 1}
func advance(dt: float) -> Array:
	var out: Array = []
	elapsed += dt
	var remaining := dt
	# in Abschnitten rechnen, damit Phasenwechsel exakt erkannt werden
	while remaining > 0.0:
		var boundary := _next_boundary(hour)
		var hours_to := fposmod(boundary - hour, 24.0)
		if hours_to <= 0.0:
			hours_to = 24.0
		var secs_to := hours_to / rate_at(hour)
		if remaining < secs_to:
			hour = fposmod(hour + remaining * rate_at(hour), 24.0)
			remaining = 0.0
		else:
			hour = boundary
			remaining -= secs_to
			if is_equal_approx(boundary, day_start):
				day += 1
				out.append({"type": "day_started", "day": day})
			else:
				out.append({"type": "night_started", "day": day})
			hour = fposmod(hour + 0.00001, 24.0)
	return out


func _next_boundary(h: float) -> float:
	if is_night_hour(h):
		return day_start
	return night_start


## Echtsekunden bis zum nächsten Nachtbeginn (0 wenn bereits Nacht)
func seconds_until_night() -> float:
	if is_night():
		return 0.0
	return (night_start - hour) / rate_at(hour)


## Echtsekunden bis zum nächsten Morgen (0 wenn bereits Tag)
func seconds_until_day() -> float:
	if not is_night():
		return 0.0
	return fposmod(day_start - hour, 24.0) / rate_at(hour)


func time_text() -> String:
	var hh := int(hour)
	var mm := int((hour - hh) * 60.0)
	return "%02d:%02d" % [hh, mm]


func to_dict() -> Dictionary:
	return {"day": day, "hour": hour, "elapsed": elapsed}


func load_dict(d: Dictionary) -> void:
	day = int(d.get("day", 1))
	hour = float(d.get("hour", 7.0))
	elapsed = float(d.get("elapsed", 0.0))
