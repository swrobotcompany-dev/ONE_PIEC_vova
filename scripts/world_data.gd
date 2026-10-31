class_name SeaWorld
extends RefCounted

# The entire world manifest is small: no distant 3D objects are stored here.
const WORLD_RADIUS := 15000.0
const WORLD_SEED := 4272026
const ISLAND_COUNT := 56
const SEA_LEVEL := 0.0
# Radius of the vessel's collision footprint: half-length + safe clearance.
const SHIP_CLEARANCE := 15.0
const SHIP_SWEEP_STEP := 3.0

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

# Server-side ship clearance from all islands. Keeps the whole hull
# outside the visible shore, even when the vessel is turning or moving fast.
func ship_position_is_clear(position: Vector3) -> bool:
	if absf(position.x) > WORLD_RADIUS - 20.0 or absf(position.z) > WORLD_RADIUS - 20.0:
		return false
	for island in islands:
		var dx: float = position.x - float(island["x"])
		var dz: float = position.z - float(island["z"])
		var minimum: float = float(island["radius"]) + SHIP_CLEARANCE
		if dx * dx + dz * dz < minimum * minimum:
			return false
	return true

# Old server saves may contain a ship inside an island. Relocate on load
# without losing the rest of the save (heading and looted treasure).
func ensure_ship_clear(position: Vector3) -> Vector3:
	var corrected := Vector3(
		clampf(position.x, -WORLD_RADIUS + 20.0, WORLD_RADIUS - 20.0),
		0.0,
		clampf(position.z, -WORLD_RADIUS + 20.0, WORLD_RADIUS - 20.0)
	)
	for attempt in range(4):
		var changed := false
		for island in islands:
			var offset := Vector2(corrected.x - float(island["x"]),
				corrected.z - float(island["z"]))
			var minimum: float = float(island["radius"]) + SHIP_CLEARANCE + 0.5
			if offset.length_squared() < minimum * minimum:
				var direction := offset.normalized() if offset.length() > 0.01 					else Vector2(1.0, 0.0)
				corrected.x = float(island["x"]) + direction.x * minimum
				corrected.z = float(island["z"]) + direction.y * minimum
				changed = true
		corrected.x = clampf(corrected.x, -WORLD_RADIUS + 20.0, WORLD_RADIUS - 20.0)
		corrected.z = clampf(corrected.z, -WORLD_RADIUS + 20.0, WORLD_RADIUS - 20.0)
		if not changed:
			break
	return corrected

# Swept movement in <=3m steps prevents high-speed tunnelling into land.
# If the bow hits shore, slide along coast on the free axis rather than
# teleporting through the island. Caller can throttle on a blocked hit.
func move_ship_safely(position: Vector3, motion: Vector3) -> Dictionary:
	var current := ensure_ship_clear(position)
	var blocked := false
	var steps := maxi(1, ceili(motion.length() / SHIP_SWEEP_STEP))
	var step := Vector3(motion.x / float(steps), 0.0, motion.z / float(steps))
	for i in range(steps):
		var target := current + step
		if ship_position_is_clear(target):
			current = target
			continue
		blocked = true
		var along_x := current + Vector3(step.x, 0.0, 0.0)
		var along_z := current + Vector3(0.0, 0.0, step.z)
		# Keep the axis that actually remains navigable.
		if absf(step.x) >= absf(step.z):
			if ship_position_is_clear(along_x):
				current = along_x
			elif ship_position_is_clear(along_z):
				current = along_z
		else:
			if ship_position_is_clear(along_z):
				current = along_z
			elif ship_position_is_clear(along_x):
				current = along_x
	return {"position": current, "blocked": blocked}

# True over dry terrain, false on the sea shelf outside or under sea level.
func is_land_at(position: Vector3) -> bool:
	var island := closest_island(position)
	return ground_height(island, position) >= SEA_LEVEL + 0.65

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
