extends SceneTree

func _initialize() -> void:
	print("DIAG stage: shader")
	var water := load("res://shaders/ocean.gdshader") as Shader
	if water == null or not ("land_masks" in water.code):
		push_error("Ocean shoreline mask shader missing")
		quit(1)
		return
	var data := SeaWorld.new()
	if data.islands.size() != SeaWorld.ISLAND_COUNT:
		push_error("World generation failed")
		quit(1)
		return
	if not ResourceLoader.exists("res://assets/characters/rogue.glb") or not ResourceLoader.exists("res://assets/characters/barbarian.glb"):
		push_error("Required 3D models missing")
		quit(1)
		return
	print("DIAG stage: create hero")
	var hero := HeroVisual.new()
	root.add_child(hero)
	print("DIAG stage: switch hero -> zoro")
	hero.set_hero("zoro")
	print("DIAG stage: switch hero -> luffy")
	hero.set_hero("luffy")
	print("DIAG stage: create guard")
	var guard := HeroVisual.new()
	root.add_child(guard)
	guard.set_hero("guard")
	print("DIAG stage: create ship")
	var vessel := PirateShip.new()
	root.add_child(vessel)
	print("DIAG stage: create island streamer")
	var stream := IslandStream.new()
	root.add_child(stream)
	stream.set_focus(Vector3.ZERO)
	print("DIAG stage: stream initial island")
	stream._refresh()
	if stream.detailed.is_empty():
		push_error("No initial island streamed")
		quit(1)
		return
	print("DIAG stage: HUD")
	var ui := PirateHud.new()
	root.add_child(ui)
	print("SMOKE PASS: %d islands, rigged characters, ship, terrain, vegetation, HUD." %
		data.islands.size())
	quit(0)
