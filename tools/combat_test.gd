extends SceneTree

func _initialize() -> void:
	var game = load("res://scripts/network_session.gd").new()
	root.add_child(game)
	game._spawn_player(1)
	var island: Dictionary = game.world.islands[0]
	game._ensure_guards(island)
	var guards: Array = game.guard_groups[0]
	var target: Vector3 = guards[0]["pos"]
	var player: Dictionary = game.players[1]
	player["mode"] = "land"
	player["world"] = target + Vector3(0, 0, 3.0)
	player["hero"] = "luffy"
	game.players[1] = player
	game.inputs[1] = {"forward": 0.0, "strafe": 0.0, "yaw": 0.0}
	game.world_clock = 1.0
	var hp: int = int(guards[0]["hp"])
	game._attack(1)
	if int(game.guard_groups[0][0]["hp"]) != hp:
		_fail("Damage occurred in windup, not active frames")
		return
	game._step_attacks()
	if int(game.guard_groups[0][0]["hp"]) != hp:
		_fail("Damage registered during startup")
		return
	game.world_clock += 0.16
	game._step_attacks()
	if int(game.guard_groups[0][0]["hp"]) != hp - 1:
		_fail("Luffy melee did not damage a nearby guard")
		return
	game._step_attacks()
	if int(game.guard_groups[0][0]["hp"]) != hp - 1:
		_fail("One swing damaged the guard more than once")
		return
	game.world_clock += 1.0
	player = game.players[1]
	player["hero"] = "zoro"
	player["next_attack"] = 0.0
	game.players[1] = player
	game._attack(1)
	game.world_clock += 0.16
	game._step_attacks()
	if int(game.guard_groups[0][0]["hp"]) != 0:
		_fail("Zoro sword did not finish the guard")
		return
	if int(game.players[1]["hits_total"]) != 2:
		_fail("Confirmed hit counter not updated")
		return
	# Test forgiving forward cone without allowing 360-degree back attacks.
	var second: Dictionary = game.guard_groups[0][1]
	var second_player: Dictionary = game.players[1]
	second_player["world"] = second["pos"] + Vector3(0, 0, 3.0)
	second_player["next_attack"] = 0.0
	game.players[1] = second_player
	game.inputs[1]["yaw"] = PI
	game.world_clock += 1.0
	var hp2: int = int(second["hp"])
	game._attack(1)
	game.world_clock += 0.16
	game._step_attacks()
	if int(game.guard_groups[0][1]["hp"]) != hp2:
		_fail("Combat erroneously hits targets behind the character")
		return
	print("COMBAT PASS: startup, active hit, no duplicate hits, hero damage, aim cone.")
	quit(0)

func _fail(reason: String) -> void:
	push_error("COMBAT FAIL: " + reason)
	quit(1)
