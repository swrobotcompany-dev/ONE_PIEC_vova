extends SceneTree

func _initialize() -> void:
	var world := SeaWorld.new()
	var island: Dictionary = world.islands[0]
	var buildings := world.buildings_for(island)
	if buildings.size() != 3:
		_fail("Server/renderer building manifest mismatch")
		return
	var house: Dictionary = buildings[0]
	var center: Vector2 = house["center"]
	if not world.blocked_by_building(island, Vector3(center.x, 3, center.y)):
		_fail("House center is not solid")
		return
	if world.blocked_by_building(island, Vector3(center.x - 12, 3, center.y)):
		_fail("Player is blocked while outside house")
		return
	if not world.segment_hits_building(island,
			Vector3(center.x - 14, 3, center.y), Vector3(center.x + 14, 3, center.y)):
		_fail("Server-side projectile sees no house")
		return

	var game = load("res://scripts/network_session.gd").new()
	root.add_child(game)
	game._spawn_player(1)
	var pirate: Dictionary = game.players[1]
	pirate["mode"] = "land"
	pirate["world"] = Vector3(center.x - 10, 0, center.y)
	game.players[1] = pirate
	game.inputs[1] = {"forward": 0.0, "strafe": 1.0, "yaw": 0.0, "sprint": false}
	game._step_players(1.0)
	pirate = game.players[1]
	if float((pirate["world"] as Vector3).x) > center.x - 8.0:
		_fail("Player crossed the house footprint")
		return
	# Camera relative movement: W and yaw zero points to world -Z.
	pirate["world"] = Vector3(0, 0, -380)
	pirate["move_velocity"] = Vector3.ZERO
	game.players[1] = pirate
	game.inputs[1] = {"forward": 1.0, "strafe": 0.0, "yaw": 0.0, "sprint": false}
	game._step_players(0.15)
	pirate = game.players[1]
	if float(pirate["facing"]) > 0.04 or (pirate["world"] as Vector3).z >= -380.0:
		_fail("Forward movement/facing is reversed")
		return

	# Projectile stops at opaque building.
	pirate["world"] = Vector3(center.x - 10, 0, center.y)
	pirate["next_shot"] = 0.0
	game.players[1] = pirate
	game.world_clock = 2.0
	game._server_fire(1, Vector2(1, 0))
	if game.projectiles.size() != 1:
		_fail("Ranged attack was not spawned")
		return
	game._step_projectiles(0.15)
	if game.projectiles.size() != 0:
		_fail("Shot went through house wall")
		return

	# Projectile hits a pirate when there is clear line of sight.
	game._ensure_guards(island)
	var pirate_guard: Dictionary = game.guard_groups[0][0]
	var goal: Vector3 = pirate_guard["pos"]
	pirate["world"] = goal + Vector3(0, 0, 15.0)
	pirate["next_shot"] = 0.0
	game.players[1] = pirate
	game.world_clock = 3.0
	game._server_fire(1, Vector2(0, -1))
	var first_hp: int = int(pirate_guard["hp"])
	for i in range(7):
		game._step_projectiles(0.08)
	if int(game.guard_groups[0][0]["hp"]) >= first_hp:
		_fail("Unobstructed shot did not hit pirate")
		return

	var ocean := OceanSurface.new()
	root.add_child(ocean)
	ocean.rebuild_at(Vector2(0.0, -380.0))
	if ocean.mesh == null:
		_fail("Ocean mesh missing")
		return
	var positions: PackedVector3Array = ocean.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex in positions:
		var distance := Vector2(vertex.x + ocean.position.x,
			vertex.z + ocean.position.z).distance_to(Vector2(0, -380))
		if distance < float(island["radius"]) - 9.0:
			_fail("Ocean vertex penetrated island")
			return

	var hero := HeroVisual.new()
	root.add_child(hero)
	hero.set_hero("luffy")
	if absf(hero.avatar_model.rotation.y - PI) > 0.001:
		_fail("Rig visual +Z orientation not corrected to Godot -Z")
		return
	print("WORLD PASS: land water cutout, house collision, projectile wall/hit, hero forward.")
	quit(0)

func _fail(reason: String) -> void:
	push_error("WORLD FAIL: " + reason)
	quit(1)
