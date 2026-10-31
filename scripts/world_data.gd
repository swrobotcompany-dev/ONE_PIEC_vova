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
	var biomes := ["tropical", "tropical", "desert", "rocky", "jungle", "snow", "volcanic", "mesa", "lagoon"]
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

# Shared mathematical terrain: renderer, collisions, AI and ocean use
# exactly the same coastline, including coves and uneven shorelines.
func coast_radius(island: Dictionary, angle: float) -> float:
	var base: float = float(island["radius"])
	var seed: float = float(island["id"]) * 1.73
	var biome := str(island["biome"])
	var amplitude := 0.09
	if biome == "lagoon":
		amplitude = 0.15
	elif biome == "volcanic" or biome == "rocky":
		amplitude = 0.13
	elif biome == "mesa" or biome == "desert":
		amplitude = 0.06
	var coves := sin(3.0 * angle + seed) * 0.53
	coves += cos(5.0 * angle + seed * 0.63) * 0.29
	coves += sin(8.0 * angle + seed * 1.4) * 0.18
	return base * (0.96 + amplitude * coves)

func ground_height(island: Dictionary, point: Vector3) -> float:
	var dx: float = point.x - float(island["x"])
	var dz: float = point.z - float(island["z"])
	var r := sqrt(dx * dx + dz * dz)
	var angle := atan2(dz, dx)
	var shoreline := coast_radius(island, angle)
	if r >= shoreline:
		return -3.0
	var t := clampf(1.0 - r / shoreline, 0.0, 1.0)
	var elevation: float = float(island["height"])
	var biome := str(island["biome"])
	var id := float(island["id"])
	var ridge := absf(sin(dx * 0.041 + id * 2.31) * cos(dz * 0.038 - id))
	var swell := sin(dx * 0.024 + id * 1.7) * cos(dz * 0.029 - id)
	var base := elevation * pow(t, 0.82)
	match biome:
		"desert":
			base = elevation * pow(t, 1.32)
			base += 3.3 * sin(dx * 0.065 + id) * cos(dz * 0.036) * pow(t, 0.42)
		"mesa":
			var plateau := smoothstep(0.26, 0.41, t)
			base = elevation * plateau
			base += 1.9 * ridge * t
		"snow":
			base = elevation * pow(t, 0.43)
			base += elevation * 0.38 * ridge * pow(t, 1.6)
		"rocky":
			base = elevation * pow(t, 0.66)
			base += elevation * 0.43 * ridge * pow(t, 1.5)
		"volcanic":
			base = elevation * pow(t, 0.59)
			base += elevation * 0.46 * ridge * pow(t, 1.8)
			var crater := exp(-pow(r / (shoreline * 0.15), 2.0))
			base -= elevation * 0.33 * crater
		"lagoon":
			base = elevation * pow(t, 1.62)
			base += 4.5 * ridge * t
		"jungle":
			base = elevation * pow(t, 0.70)
			base += elevation * 0.31 * swell * pow(t, 1.25)
		"legend":
			base = elevation * pow(t, 0.49)
			base += elevation * 0.38 * ridge * pow(t, 1.8)
		_:
			base += elevation * 0.16 * swell * pow(t, 1.1)
	# Keep the coastline continuous and never place terrain below sea
	# level. The first strip of beach always begins at elevation zero.
	return maxf(0.0, base)

func terrain_zone(island: Dictionary, world_point: Vector3) -> float:
	var delta := Vector2(world_point.x - float(island["x"]), world_point.z - float(island["z"]))
	var coastline := coast_radius(island, atan2(delta.y, delta.x))
	return clampf(delta.length() / coastline, 0.0, 1.0)

func coast_point(island: Dictionary, ship_position: Vector3) -> Vector3:
	var center := Vector3(float(island["x"]), 0.0, float(island["z"]))
	var towards_ship := ship_position - center
	towards_ship.y = 0.0
	if towards_ship.length_squared() < 1.0:
		towards_ship = Vector3.FORWARD
	var direction := towards_ship.normalized()
	var shoreline := coast_radius(island, atan2(direction.z, direction.x))
	var land := center + direction * shoreline * 0.78
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
