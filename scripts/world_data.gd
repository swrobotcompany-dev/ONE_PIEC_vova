class_name SeaWorld
extends RefCounted

# The entire world manifest is small: no distant 3D objects are stored here.
const WORLD_RADIUS := 15000.0
const WORLD_SEED := 4272026
const ISLAND_COUNT := 56

var islands: Array[Dictionary] = []

func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = WORLD_SEED
	islands.append(_make(0, "Dawn Island", Vector2(0.0, -380.0), 175.0, 22.0, "tropical"))
	islands.append(_make(1, "Laugh Tale / ONE PIECE", Vector2(12600.0, -12800.0), 340.0, 65.0, "legend"))
	var names := ["Shells Town", "Orange Town", "Syrup Village", "Baratie Reef",
		"Loguetown", "Reverse Cape", "Whiskey Peak", "Little Garden", "Drum Island",
		"Sandy Kingdom", "Skyward Atoll", "Water City", "Thriller Shoal",
		"Marine Outpost", "Turtle Bay", "Coral Haven", "Stormwatch",
		"Mango Cay", "Pirate's Rest", "Whispering Palms", "Skull Rock"]
	var biomes := ["tropical", "tropical", "desert", "rocky", "jungle", "snow"]
	for i in range(2, ISLAND_COUNT):
		var radius := rng.randf_range(90.0, 260.0)
		for attempt in range(350):
			var p := Vector2(rng.randf_range(-WORLD_RADIUS, WORLD_RADIUS),
				rng.randf_range(-WORLD_RADIUS, WORLD_RADIUS))
			if p.length() < 1200.0:
				continue
			var valid := true
			for existing in islands:
				var q := Vector2(float(existing["x"]), float(existing["z"]))
				if p.distance_to(q) < radius + float(existing["radius"]) + 380.0:
					valid = false
					break
			if valid:
				var biome: String = biomes[rng.randi_range(0, biomes.size() - 1)]
				var name: String = names[(i - 2) % names.size()]
				islands.append(_make(i, name + " " + str(i), p, radius,
					rng.randf_range(11.0, 45.0), biome))
				break

func _make(id: int, name: String, center: Vector2, radius: float,
		height: float, biome: String) -> Dictionary:
	return {"id": id, "name": name, "x": center.x, "z": center.y,
		"radius": radius, "height": height, "biome": biome}

func closest_island(world_position: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var distance := INF
	for island in islands:
		var center := Vector2(float(island["x"]), float(island["z"]))
		var d := Vector2(world_position.x, world_position.z).distance_to(center)
		if d < distance:
			distance = d
			best = island
	return best

func ground_height(island: Dictionary, point: Vector3) -> float:
	var dx: float = point.x - float(island["x"])
	var dz: float = point.z - float(island["z"])
	var r := sqrt(dx * dx + dz * dz)
	var radius: float = float(island["radius"])
	if r >= radius:
		return -3.0
	var t := clampf(1.0 - r / radius, 0.0, 1.0)
	var base := pow(t, 0.67) * float(island["height"])
	var ripple := (sin(dx * 0.045 + float(island["id"])) +
		cos(dz * 0.039)) * 0.9 * t
	return base + ripple

func coast_point(island: Dictionary, ship_position: Vector3) -> Vector3:
	var center := Vector3(float(island["x"]), 0.0, float(island["z"]))
	var towards_ship := ship_position - center
	towards_ship.y = 0.0
	if towards_ship.length_squared() < 1.0:
		towards_ship = Vector3.FORWARD
	var land := center + towards_ship.normalized() * float(island["radius"]) * 0.80
	land.y = ground_height(island, land) + 2.0
	return land


# Shared visual/server footprints: never permit a client to walk through a
# building merely because the server has no rendered scene.
func buildings_for(island: Dictionary) -> Array[Dictionary]:
	var id := int(island["id"])
	var specs: Array[Dictionary] = []
	if id == 0:
		specs = [{"kind": "hut", "offset": Vector2(-48, -34)},
			{"kind": "hut", "offset": Vector2(44, 20)},
			{"kind": "tower", "offset": Vector2(-18, 52)}]
	elif id == 1:
		specs = [{"kind": "tower", "offset": Vector2(-33, 56)},
			{"kind": "hut", "offset": Vector2(42, -25)}]
	elif id % 4 == 0:
		specs = [{"kind": "hut", "offset": Vector2(-20, 29)},
			{"kind": "tower", "offset": Vector2(30, 19)}]
	var out: Array[Dictionary] = []
	for spec in specs:
		var ofs: Vector2 = spec["offset"]
		out.append({"kind": spec["kind"], "offset": ofs,
			"center": Vector2(float(island["x"]), float(island["z"])) + ofs,
			"half": Vector2(6, 5) if spec["kind"] == "hut" else Vector2(4, 4)})
	return out

func blocked_by_building(island: Dictionary, world_point: Vector3, radius: float = 0.68) -> bool:
	var point := Vector2(world_point.x, world_point.z)
	for building in buildings_for(island):
		var center: Vector2 = building["center"]
		var half: Vector2 = building["half"]
		var nearest := Vector2(clampf(point.x, center.x - half.x, center.x + half.x),
			clampf(point.y, center.y - half.y, center.y + half.y))
		if point.distance_squared_to(nearest) <= radius * radius:
			return true
	return false

func segment_hits_building(island: Dictionary, start: Vector3, finish: Vector3) -> bool:
	var origin := Vector2(start.x, start.z)
	var delta := Vector2(finish.x - start.x, finish.z - start.z)
	for building in buildings_for(island):
		var center: Vector2 = building["center"]
		var half: Vector2 = building["half"]
		var tmin := 0.0
		var tmax := 1.0
		var intersects := true
		for axis in range(2):
			var p := origin.x if axis == 0 else origin.y
			var d := delta.x if axis == 0 else delta.y
			var lo := center.x - half.x if axis == 0 else center.y - half.y
			var hi := center.x + half.x if axis == 0 else center.y + half.y
			if absf(d) < 0.000001:
				if p < lo or p > hi:
					intersects = false
					break
			else:
				var t1 := (lo - p) / d
				var t2 := (hi - p) / d
				tmin = maxf(tmin, minf(t1, t2))
				tmax = minf(tmax, maxf(t1, t2))
				if tmin > tmax:
					intersects = false
					break
		if intersects:
			return true
	return false
