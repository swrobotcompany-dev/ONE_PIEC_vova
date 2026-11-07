extends SceneTree

func _initialize() -> void:
	var game = load("res://scripts/network_session.gd").new()
	root.add_child(game)
	game._spawn_player(1)
	var island: Dictionary = game.world.islands[0]
	game._ensure_guards(island)
	if FruitCatalog.TYPES.size() != 14:
		_fail("Expected 14 combat-ready Devil Fruit schools")
		return
	for island_id in range(SeaWorld.ISLAND_COUNT):
		if not FruitCatalog.TYPES.has(game.fruit_power_for(island_id)):
			_fail("Island %d has no combat fruit" % island_id)
			return
	var home: Vector3 = game.guard_groups[0][0]["home"]
	for kind in FruitCatalog.TYPES:
		var player: Dictionary = game.players[1]
		player["mode"] = "land"
		player["hero"] = "luffy"
		player["world"] = home + Vector3(0, 0, 4.0 if kind == "barrier" else 8.0)
		player["abilities"] = [kind]
		player["selected_fruit"] = kind
		var ranks: Dictionary = {}
		ranks[kind] = 1
		player["fruit_ranks"] = ranks
		player["next_fruit"] = 0.0
		player["shield_until"] = 0.0
		game.players[1] = player
		var group: Array = game.guard_groups[0]
		for i in range(group.size()):
			var enemy: Dictionary = group[i]
			enemy = {"pos": enemy["home"], "home": enemy["home"],
				"hp": 80, "max_hp": 80, "kind": i, "next_hit": 0.0,
				"hit_number": 0, "respawn_at": 0.0}
			group[i] = enemy
		game.guard_groups[0] = group
		game.projectiles.clear()
		game.world_clock += 20.0
		game._server_cast_fruit(1, Vector2(0, -1))
		if float(game.players[1]["next_fruit"]) <= game.world_clock:
			_fail("No server cooldown for fruit: " + kind)
			return
		var before_count: int = game.projectiles.size()
		game._server_cast_fruit(1, Vector2(0, -1))
		if game.projectiles.size() != before_count:
			_fail("Fruit cooldown bypass: " + kind)
			return
		for frame in range(25):
			game._step_projectiles(0.07)
			game.world_clock += 0.07
		var target: Dictionary = game.guard_groups[0][0]
		if int(target["hp"]) >= 80:
			_fail("Fruit has no combat effect on target: " + kind)
			return
		if kind in ["fire", "magma", "poison"] and float(target.get("dot_until", 0.0)) <= game.world_clock:
			_fail("Damage-over-time fruit did not apply status: " + kind)
			return
		if kind in ["ice", "string"] and float(target.get("freeze_until", 0.0)) <= game.world_clock:
			_fail("Crowd-control fruit did not root/freeze: " + kind)
			return
		if kind == "barrier" and float(game.players[1]["shield_until"]) <= game.world_clock:
			_fail("Barrier did not grant defense")
			return

	# The server must reject unowned powers, swimming and invalid aim.
	var pirate: Dictionary = game.players[1]
	pirate["abilities"] = []
	pirate["selected_fruit"] = "magma"
	pirate["next_fruit"] = 0.0
	game.players[1] = pirate
	game.projectiles.clear()
	game._server_cast_fruit(1, Vector2(0, -1))
	if not game.projectiles.is_empty():
		_fail("Server accepted an unowned fruit")
		return
	pirate["abilities"] = ["magma"]
	pirate["mode"] = "swim"
	game.players[1] = pirate
	game._server_cast_fruit(1, Vector2(0, -1))
	if not game.projectiles.is_empty():
		_fail("Devil Fruit can be used while swimming")
		return
	pirate["mode"] = "land"
	game.players[1] = pirate
	game._server_cast_fruit(1, Vector2.ZERO)
	if not game.projectiles.is_empty():
		_fail("Zero aim bypassed fruit cast validation")
		return

	# Test the uninfused hero weapons: the preceding restriction tests left
	# magma selected, whose splash intentionally consumes a shot on impact.
	pirate["abilities"] = []
	pirate["selected_fruit"] = ""
	# Luffy and Zoro do not share one generic gun projectile.
	pirate["hero"] = "luffy"
	pirate["next_shot"] = 0.0
	pirate["world"] = home + Vector3(0, 0, 12.0)
	game.players[1] = pirate
	game._server_fire(1, Vector2(0, -1))
	var luffy: Dictionary = game.projectiles.values()[0]
	if str(luffy["kind"]) != "fist" or int(luffy["pierce"]) != 1:
		_fail("Luffy should fire a single elastic punch")
		return
	game.projectiles.clear()
	pirate = game.players[1]
	pirate["hero"] = "zoro"
	pirate["next_shot"] = 0.0
	game.players[1] = pirate
	var group: Array = game.guard_groups[0]
	for i in range(3):
		var enemy: Dictionary = group[i]
		enemy["hp"] = 9
		enemy["pos"] = home + Vector3(0, 0, -5.0 * float(i))
		group[i] = enemy
	game.guard_groups[0] = group
	game.world_clock += 20.0
	game._server_fire(1, Vector2(0, -1))
	var zoro: Dictionary = game.projectiles.values()[0]
	if str(zoro["kind"]) != "slash" or int(zoro["pierce"]) != 3:
		_fail("Zoro should fire a piercing sword wave")
		return
	for frame in range(12):
		game._step_projectiles(0.05)
	for i in range(3):
		if int(game.guard_groups[0][i]["hp"]) >= 9:
			_fail("Zoro slash did not pierce guard %d" % i)
			return
	print("FRUIT COMBAT PASS: 14 fruit attacks, status effects, cooldowns, ownership, water restriction, distinct hero fire.")
	quit(0)

func _fail(reason: String) -> void:
	push_error("FRUIT COMBAT FAIL: " + reason)
	quit(1)
