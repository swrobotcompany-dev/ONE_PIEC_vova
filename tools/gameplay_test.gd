extends SceneTree

func _initialize() -> void:
	var server := load("res://scripts/network_session.gd").new()
	root.add_child(server)
	if not server.ship_can_occupy(Vector3(0, 0, -160)):
		_fail("Safe sea spawn rejected")
		return
	if server.ship_can_occupy(Vector3(0, 0, -380)):
		_fail("Ship may clip through island centre")
		return
	server.ship_position = Vector3(0, 0, -160)
	server.ship_heading = 0.0
	server.ship_speed = 23.0
	server.helmsman_id = 1
	server.inputs[1] = {"forward": 1.0, "strafe": 0.0}
	server._step_ship(5.0)
	if not server.ship_can_occupy(server.ship_position):
		_fail("Swept ship collision failed")
		return
	var swimmer := {"mode": "land", "world": Vector3(0, 0, -150)}
	server._snap_to_surface(swimmer)
	if swimmer["mode"] != "swim":
		_fail("Open sea must be swim mode")
		return
	swimmer["world"] = Vector3(0, 0, -310)
	server._snap_to_surface(swimmer)
	if swimmer["mode"] != "land":
		_fail("Island terrain must be land mode")
		return
	server._ensure_guards(server.world.islands[0])
	if server.guard_groups[0].size() != server.GUARD_COUNT:
		_fail("Initial pirate guards absent")
		return
	print("GAMEPLAY PASS: shoreline collision, swimming/land state, island guards.")
	quit(0)

func _fail(message: String) -> void:
	push_error("GAMEPLAY FAIL: " + message)
	quit(1)
