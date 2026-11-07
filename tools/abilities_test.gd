extends SceneTree

func _initialize() -> void:
	var net = load("res://scripts/network_session.gd").new()
	root.add_child(net)
	var world := SeaWorld.new()
	if world.islands.size() != SeaWorld.ISLAND_COUNT:
		_fail("Island generation count has changed")
		return
	var dawn: Dictionary = world.islands[0]
	var early: Dictionary = world.islands[2]
	var distance := Vector2(float(dawn["x"]), float(dawn["z"])).distance_to(
		Vector2(float(early["x"]), float(early["z"])))
	if distance > 950.0:
		_fail("First other island is still too far away")
		return
	net._spawn_player(1)
	for island in world.islands:
		net._ensure_guards(island)
	if net.guard_groups.size() != world.islands.size():
		_fail("Not every island has permanent pirates")
		return
	for island in world.islands:
		if net.guard_groups[int(island["id"])].size() != net.GUARD_COUNT:
			_fail("Missing pirates on island " + str(island["id"]))
			return
	if net.fruit_power_for(0) != "rubber" or net.fruit_power_for(1) != "fire" or net.fruit_power_for(2) != "ice":
		_fail("Fruit ability table is incomplete")
		return

	# Verify obtaining a fruit only when guards have been defeated.
	var player: Dictionary = net.players[1]
	player["mode"] = "land"
	player["world"] = Vector3(float(dawn["x"]), world.ground_height(dawn,
		Vector3(float(dawn["x"]), 0.0, float(dawn["z"]))), float(dawn["z"]))
	net.players[1] = player
	net._collect(1)
	if int(net.players[1]["fruits"]) != 0:
		_fail("Fruit pickup bypassed living pirates")
		return
	var group: Array = net.guard_groups[0]
	for index in range(group.size()):
		var guard: Dictionary = group[index]
		guard["hp"] = 0
		guard["respawn_at"] = 91.0
		group[index] = guard
	net.guard_groups[0] = group
	net._collect(1)
	player = net.players[1]
	if int(player["fruits"]) != 1 or not player["abilities"].has("rubber") or str(player["selected_fruit"]) != "rubber":
		_fail("First Devil Fruit was not equipped for combat")
		return
	player["abilities"] = ["lightning"]
	net.players[1] = player
	net.inputs[1] = {"forward": 1.0, "strafe": 0.0,
		"yaw": 0.0, "sprint": false}
	net._step_players(0.6)
	player = net.players[1]
	if (player["move_velocity"] as Vector3).length() < net.WALK_SPEED * 1.2:
		_fail("Lightning fruit movement bonus is missing")
		return

	# The first jump is available without a fruit; the second requires
	# flower and a third mid-air request must be rejected.
	player["abilities"] = ["flower"]
	player["jump_count"] = 0
	player["jump_height"] = 0.0
	player["jump_speed"] = 0.0
	player["move_velocity"] = Vector3.ZERO
	net.players[1] = player
	net._server_jump(1)
	if int(net.players[1]["jump_count"]) != 1:
		_fail("First jump not registered")
		return
	net._server_jump(1)
	if int(net.players[1]["jump_count"]) != 2:
		_fail("Double jump is not available")
		return
	net._server_jump(1)
	if int(net.players[1]["jump_count"]) != 2:
		_fail("Illegal third jump allowed")
		return
	net._step_players(0.1)
	if float(net.players[1]["jump_height"]) <= 0.0:
		_fail("Jump has no vertical movement")
		return

	# Killed pirates respawn and continue guarding already-looted islands.
	net.world_clock = 100.0
	net._step_guards(0.05)
	if int(net.guard_groups[0][0]["hp"]) <= 0:
		_fail("Pirates do not respawn on looted islands")
		return
	var abilities_now: Array = net.players[1]["abilities"]
	if abilities_now.size() != 1 or not abilities_now.has("flower"):
		_fail("Powers changed while enemies respawned")
		return

	# A on forward sailing should rotate the bow to the LEFT (-X).
	net.helmsman_id = 1
	net.ship_heading = 0.0
	net.ship_speed = 7.0
	net.inputs[1] = {"forward": 1.0, "strafe": -1.0}
	net._step_ship(0.1)
	if net.ship_heading <= 0.0:
		_fail("Ship steering A/D is still inverted")
		return
	net.ship_heading = 0.0
	net.inputs[1]["strafe"] = 1.0
	net._step_ship(0.1)
	if net.ship_heading >= 0.0:
		_fail("Ship steering D should turn right")
		return
	print("ABILITY PASS: pirates on every island, fruit combat unlock, flower double jump, guard respawn, helm steering.")
	quit(0)

func _fail(message: String) -> void:
	push_error("ABILITY FAIL: " + message)
	quit(1)
