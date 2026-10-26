class_name WorldMap
extends RefCounted
## Unveränderliche Geländedaten einer Welt. Wird bei jedem Laden aus dem Seed
## neu erzeugt und deshalb nicht gespeichert.

var seed: int = 0
var cells: int = 72            ## Kacheln pro Kante
var cell_size: float = 2.0     ## Meter pro Kachel
var res: int = 145             ## Höhenpunkte pro Kante (1 m Abstand)
var heights := PackedFloat32Array()
var road_cells := {}           ## Vector2i -> true
var roads: Array = []          ## Array[PackedVector2Array] in Metern
var ruins: Array = []          ## [{cell: Vector2i, size: Vector2i, kind: int, rot: float}]
var node_spawns: Array = []    ## [{type, cell, offset: Vector2, scale, rot, variant}]
var start_cell := Vector2i(36, 36)
var base_radius: float = 26.0


func size_m() -> float:
	return cells * cell_size


func center() -> Vector3:
	var c := cell_center(start_cell)
	return c


## Höhe an einer Weltposition (bilinear interpoliert)
func height_at(x: float, z: float) -> float:
	var fx := clampf(x, 0.0, float(res - 1))
	var fz := clampf(z, 0.0, float(res - 1))
	var ix := mini(int(fx), res - 2)
	var iz := mini(int(fz), res - 2)
	var tx := fx - ix
	var tz := fz - iz
	var h00 := heights[iz * res + ix]
	var h10 := heights[iz * res + ix + 1]
	var h01 := heights[(iz + 1) * res + ix]
	var h11 := heights[(iz + 1) * res + ix + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func cell_center(cell: Vector2i) -> Vector3:
	var x := (cell.x + 0.5) * cell_size
	var z := (cell.y + 0.5) * cell_size
	return Vector3(x, height_at(x, z), z)


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / cell_size), floori(p.z / cell_size))


func in_bounds(cell: Vector2i, margin: int = 0) -> bool:
	return cell.x >= margin and cell.y >= margin and cell.x < cells - margin and cell.y < cells - margin


## Min/Max-Höhe über einer Fläche aus Kacheln
func height_range(cell_list: Array) -> Vector2:
	var lo := INF
	var hi := -INF
	for c in cell_list:
		for k in 3:
			for l in 3:
				var h := height_at((c.x + k * 0.5) * cell_size, (c.y + l * 0.5) * cell_size)
				lo = minf(lo, h)
				hi = maxf(hi, h)
	return Vector2(lo, hi)


## Prüfsumme für Reproduzierbarkeitstests
func checksum() -> int:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(heights.to_byte_array())
	ctx.update(var_to_bytes([node_spawns, ruins, road_cells.keys()]))
	var digest := ctx.finish()
	return digest.decode_s64(0)
