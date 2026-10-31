extends SceneTree

func _initialize() -> void:
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
	var hero := HeroVisual.new()
	root.add_child(hero)
	hero.set_hero("zoro")
	hero.set_hero("luffy")
	var guard := HeroVisual.new()
	root.add_child(guard)
	guard.set_hero("guard")
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
	print("SMOKE PASS: %d islands, rigged characters, ship, terrain, vegetation, HUD." %
		data.islands.size())
	quit(0)
