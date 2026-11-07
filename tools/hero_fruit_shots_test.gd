extends SceneTree

# Each of the 14 unlocked fruits must alter BOTH heroes' normal LMB attacks.
# Verify actual guard damage, LAN projectile data, server ownership and combos.
func _initialize() -> void:
	var game = load("res://scripts/network_session.gd").new()
	root.add_child(game)
	game._spawn_player(1)
	var island: Dictionary = game.world.islands[0]
	game._ensure_guards(island)
	var home: Vector3 = game.guard_groups[0][0]["home"]
	if FruitCatalog.SHOT_INFUSIONS.size() != FruitCatalog.TYPES.size():
		_fail("Not all 14 fruits have an LMB infusion")
		return
	for hero in ["luffy", "zoro"]:
		for fruit in FruitCatalog.TYPES:
			var group: Array = game.guard_groups[0]
			for i in range(group.size()):
				var enemy: Dictionary = group[i]
				enemy["pos"] = enemy["home"]
				enemy["hp"] = 80
				enemy["max_hp"] = 80
				enemy["hit_number"] = 0
				enemy["dot_until"] = 0.0
				enemy["dot_next"] = INF
				enemy["freeze_until"] = 0.0
				enemy["slow_until"] = 0.0
				group[i] = enemy
			game.guard_groups[0] = group
			var pirate: Dictionary = game.players[1]
			pirate["mode"] = "land"
			pirate["hero"] = hero
			pirate["world"] = home + Vector3(0, 0, 8.0)
			pirate["abilities"] = [fruit]
			pirate["selected_fruit"] = fruit
			pirate["fruit_ranks"] = {fruit: 1}
			pirate["next_shot"] = 0.0
			pirate["shot_combo"] = 0
			pirate["shield_until"] = 0.0
			game.players[1] = pirate
			game.projectiles.clear()
			game.world_clock += 20.0
			game._server_fire(1, Vector2(0, -1))
			if game.projectiles.is_empty():
				_fail("No primary projectile for %s + %s" % [hero, fruit])
				return
			var style: Dictionary = FruitCatalog.shot_style(fruit)
			var first: Dictionary = game.projectiles.values()[0]
			if str(first["kind"]) != ("fist" if hero == "luffy" else "slash"):
				_fail("Hero weapon was replaced by a generic fruit bullet")
				return
			if str(first.get("infusion", "")) != fruit:
				_fail("Missing infusion in projectile: %s + %s" % [hero, fruit])
				return
			if str(first.get("status", "")) != str(style.get("status", "")):
				_fail("Wrong status for %s + %s" % [hero, fruit])
				return
			if absf(float(first.get("splash", 0.0)) - float(style.get("splash", 0.0))) > 0.001:
				_fail("Wrong area effect for %s + %s" % [hero, fruit])
				return
			if int(first["pierce"]) != (1 if hero == "luffy" else 3) + int(style.get("pierce", 0)):
				_fail("Wrong penetration for %s + %s" % [hero, fruit])
				return
			var network_shots: Dictionary = game._make_snapshot()["projectiles"]
			if str(network_shots.values()[0].get("infusion", "")) != fruit:
				_fail("LAN snapshot omitted equipped fruit")
				return
			if fruit == "barrier" and float(game.players[1]["shield_until"]) <= game.world_clock:
				_fail("Barrier shot did not protect its user")
				return
			var count := game.projectiles.size()
			game._server_fire(1, Vector2(0, -1))
			if game.projectiles.size() != count:
				_fail("Primary fire bypassed server cooldown")
				return
			for frame in range(20):
				game._step_projectiles(0.04)
				game.world_clock += 0.04
				game._step_guard_dots()
			if int(game.guard_groups[0][0]["hp"]) >= 80:
				_fail("Fruit-infused %s attack did not hit guard: %s" % [hero, fruit])
				return
			if fruit in ["fire", "magma", "poison"] and float(game.guard_groups[0][0].get("dot_until", 0.0)) <= game.world_clock:
				_fail("Infused damage-over-time missing: " + fruit)
				return
			if fruit in ["ice", "flower", "string"] and float(game.guard_groups[0][0].get("freeze_until", 0.0)) <= game.world_clock:
				_fail("Infused freeze/root missing: " + fruit)
				return

	# Every third shot has a different signature for each hero.
	var pirate: Dictionary = game.players[1]
	pirate["hero"] = hero
	pirate["abilities"] = []
	pirate["selected_fruit"] = ""
	pirate["shot_combo"] = 0
	pirate["mode"] = "land"
	game.players[1] = pirate
	for volley in range(3):
		pirate = game.players[1]
		pirate["next_shot"] = 0.0
		game.players[1] = pirate
		game.projectiles.clear()
		game.world_clock += 2.0
		game._server_fire(1, Vector2(0, -1))
		var expected := (3 if hero == "luffy" else 2) if volley == 2 else 1
		if game.projectiles.size() != expected:
			_fail("Incorrect %s combo volley %d" % [hero, volley + 1])
			return
		if int(game.players[1]["shot_combo"]) != (volley + 1) % 3:
			_fail("Server did not advance shot combo")
			return

	# An unowned selected fruit must never grant an infused projectile.
	var pirate: Dictionary = game.players[1]
	pirate["abilities"] = []
	pirate["selected_fruit"] = "magma"
	pirate["next_shot"] = 0.0
	pirate["shot_combo"] = 0
	game.players[1] = pirate
	game.projectiles.clear()
	game.world_clock += 2.0
	game._server_fire(1, Vector2(0, -1))
	if str(game.projectiles.values()[0].get("infusion", "")) != "":
		_fail("Server allowed an unowned fruit to infuse a shot")
		return
	pirate = game.players[1]
	pirate["mode"] = "swim"
	pirate["next_shot"] = 0.0
	game.players[1] = pirate
	game.projectiles.clear()
	game._server_fire(1, Vector2(0, -1))
	if not game.projectiles.is_empty():
		_fail("Player fired while swimming")
		return
	pirate["mode"] = "land"
	game.players[1] = pirate
	game._server_fire(1, Vector2.ZERO)
	if not game.projectiles.is_empty():
		_fail("Zero direction bypassed primary fire validation")
		return

	# Both weapon visuals retain their identity with a fruit-colored aura.
	var aim := AimingView.new()
	root.add_child(aim)
	for kind in ["fist", "slash"]:
		var visual: Node3D = aim._make_bullet({"kind": kind, "infusion": "fire"})
		if visual.get_child_count() < 3:
			_fail("Missing visible fruit infusion for " + kind)
			return
	print("HERO FRUIT SHOTS PASS: 14 fruit infusions x 2 heroes, combat hits, statuses, LAN, cooldowns, unique combos, visuals.")
	quit(0)

func _fail(reason: String) -> void:
	push_error("HERO FRUIT SHOTS FAIL: " + reason)
	quit(1)
