extends SceneTree

func _initialize() -> void:
	var game = load("res://scripts/network_session.gd").new()
	root.add_child(game)
	game._spawn_player(1)
	game._spawn_player(2)
	var island: Dictionary = game.world.islands[0]
	game._ensure_guards(island)
	var guard: Dictionary = game.guard_groups[0][0]
	var p: Dictionary = game.players[1]
	p["mode"] = "land"
	p["hero"] = "zoro"
	p["world"] = guard["pos"] + Vector3(0, 0, 3)
	p["facing"] = 0.0
	game.players[1] = p
	game.world_clock = 1.0
	game._attack(1)
	game.world_clock += 0.16
	game._step_attacks()
	if int(game.guard_groups[0][0]["hp"]) != 1:
		_fail("First Zoro hit damage wrong")
		return
	if int(game.players[1]["kills"]) != 0 or int(game.players[1]["score"]) != 0:
		_fail("Points awarded before enemy death")
		return
	game.world_clock += 1.0
	game._attack(1)
	game.world_clock += 0.16
	game._step_attacks()
	if int(game.guard_groups[0][0]["hp"]) != 0:
		_fail("Guard did not die")
		return
	if int(game.players[1]["kills"]) != 1 or int(game.players[1]["score"]) != 100:
		_fail("Killer did not earn 1 kill and 100 points")
		return
	game.world_clock += 1.0
	game._attack(1)
	game.world_clock += 0.16
	game._step_attacks()
	if int(game.players[1]["score"]) != 100:
		_fail("Double score after dead enemy")
		return
	var second: Dictionary = game.guard_groups[0][1]
	second["hp"] = 1
	game.guard_groups[0][1] = second
	var p2: Dictionary = game.players[2]
	p2["mode"] = "land"
	p2["hero"] = "luffy"
	p2["world"] = second["pos"] + Vector3(0, 0, 9)
	game.players[2] = p2
	game.world_clock += 1.0
	game._server_fire(2, Vector2(0, -1))
	for i in range(7):
		game._step_projectiles(0.06)
	if int(game.guard_groups[0][1]["hp"]) > 0:
		_fail("Projectile did not defeat guard")
		return
	if int(game.players[2]["kills"]) != 1 or int(game.players[2]["score"]) != 100:
		_fail("Ranged finishing blow did not credit correct player")
		return
	if int(game.players[1]["score"]) != 100:
		_fail("Points credited to the wrong player")
		return
	var snapshot: Dictionary = game._make_snapshot()
	var scores: Dictionary = snapshot["players"]
	if int(scores["1"]["kills"]) != 1 or int(scores["2"]["score"]) != 100:
		_fail("Scores missing from LAN snapshot")
		return
	print("SCORE PASS: melee/ranged kills, +100 points, no duplicates, LAN scoreboard.")
	quit(0)

func _fail(reason: String) -> void:
	push_error("SCORE FAIL: " + reason)
	quit(1)
