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
