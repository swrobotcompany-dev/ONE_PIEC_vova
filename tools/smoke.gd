extends SceneTree

func _initialize() -> void:
	var data := SeaWorld.new()
	if data.islands.size() != SeaWorld.ISLAND_COUNT:
		_fail("World generation failed")
		return
	var island: Dictionary = data.islands[0]
	var center := Vector3(float(island["x"]), 0.0, float(island["z"]))
	if data.ship_position_is_clear(center):
		_fail("Ship can occupy the island interior")
		return
	if not data.ship_position_is_clear(Vector3.ZERO):
		_fail("Starter ship spawn is blocked")
		return
	if not data.is_land_at(center) or data.is_land_at(Vector3.ZERO):
		_fail("Land/water detection is inverted")
		return

	# Simulate a fast ship heading straight through an island in one tick.
	var approach := center + Vector3(0.0, 0.0,
		-float(island["radius"]) - SeaWorld.SHIP_CLEARANCE - 45.0)
	var move := data.move_ship_safely(approach, Vector3(0.0, 0.0, 120.0))
	if not bool(move["blocked"]):
		_fail("High-speed ship did not detect the coastline")
		return
	var result_position: Vector3 = move["position"]
	if not data.ship_position_is_clear(result_position):
		_fail("Ship tunnelling / penetrated the island")
		return
	var repaired := data.ensure_ship_clear(center)
	if not data.ship_position_is_clear(repaired):
		_fail("Loaded ship save inside island was not repaired")
		return

	var vessel := PirateShip.new()
	root.add_child(vessel)
	if vessel.get_child_count() < 40:
		_fail("Improved ship details were not created")
		return

	var stream := IslandStream.new()
	root.add_child(stream)
	stream.set_focus(Vector3.ZERO)
	stream._refresh()
	if stream.detailed.is_empty():
		_fail("No initial island streamed")
		return

	var found_foam := false
	var found_rocks := false
	for island_node in stream.detailed.values():
		for piece in island_node.get_children():
			if piece is MeshInstance3D and piece.mesh is TorusMesh:
				found_foam = true
			if piece is MultiMeshInstance3D:
				found_rocks = true
	if not found_foam or not found_rocks:
		_fail("Island shore foam or instanced rocks missing")
		return

	# This creates the ocean / wake shader without starting the game server.
	var main_script = load("res://scripts/main.gd")
	var view: Node3D = main_script.new()
	view._setup_ocean()
	if view.ocean == null or view.wake == null:
		_fail("Ocean shader or ship wake not constructed")
		return
	if view.ocean.mesh.subdivide_width < 100:
		_fail("Ocean mesh still uses coarse original geometry")
		return

	var ui := PirateHud.new()
	root.add_child(ui)
	ui.update_details(0.0, "Dawn Island", 2, 10000.0,
		false, 0, false, "SWIMMING")
	if not "SWIMMING" in ui.details.text:
		_fail("Swimming status not displayed")
		return

	print("SMOKE PASS: %d islands, swept ship collision, water/land, " % [
		data.islands.size()] +
		"enhanced ship, shoreline foam, ocean shader, swimming HUD.")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
