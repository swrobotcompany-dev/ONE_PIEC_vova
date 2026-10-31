extends SceneTree

func _initialize() -> void:
	var data := SeaWorld.new()
	if data.islands.size() != SeaWorld.ISLAND_COUNT:
		push_error("World generation failed")
		quit(1)
		return
	var vessel := PirateShip.new()
	root.add_child(vessel)
	var stream := IslandStream.new()
	root.add_child(stream)
	stream.set_focus(Vector3.ZERO)
	stream._refresh()
	if stream.detailed.is_empty():
		push_error("No initial island streamed")
		quit(1)
		return
	var ui := PirateHud.new()
	root.add_child(ui)
	print("SMOKE PASS: %d islands, ship meshes, terrain, vegetation, HUD." %
		data.islands.size())
	quit(0)
