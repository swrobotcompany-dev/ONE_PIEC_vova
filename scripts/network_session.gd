extends Node
# Authoritative LAN game state, characters, shoreline blocking and sleeping pirate AI.
signal session_ready
signal connection_lost(message: String)
signal state_updated

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 8
const UPDATE_INTERVAL := 1.0 / 12.0
const SPEED_MAX := 23.0
const WALK_SPEED := 7.2
const SWIM_SPEED := 3.1
const HULL_CLEARANCE := 20.0
const GUARD_COUNT := 3

var world := SeaWorld.new()
var ship_position := Vector3(0, 0, -160)
var ship_heading := 0.0
var ship_speed := 0.0
var helmsman_id := 0
var players: Dictionary = {}
var inputs: Dictionary = {}
var guard_groups: Dictionary = {}
var claimed_treasures: Dictionary = {}
var claimed_fruits: Dictionary = {}
var state: Dictionary = {}
var is_active := false
var snapshot_clock := 0.0
var save_clock := 0.0
var world_clock := 0.0

func _ready() -> void:
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_failed)
	multiplayer.server_disconnected.connect(_disconnected)

func host_game(port: int = DEFAULT_PORT) -> String:
	if is_active:
		return "A session is already running"
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		return "Unable to bind UDP port %d (error %d)" % [port, error]
	multiplayer.multiplayer_peer = peer
	is_active = true
	_load_world()
	_spawn_player(1)
	_push_state()
	session_ready.emit()
	return ""

func join_game(ip: String, port: int = DEFAULT_PORT) -> String:
	if is_active:
		return "A session is already running"
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(ip.strip_edges(), port)
	if error != OK:
		return "Cannot connect to %s:%d (error %d)" % [ip, port, error]
	multiplayer.multiplayer_peer = peer
	return ""

func _connected() -> void:
	is_active = true
	session_ready.emit()

func _failed() -> void:
	_reset()
	connection_lost.emit("Connection failed. Check LAN IP, UDP port and firewall.")

func _disconnected() -> void:
	_reset()
	connection_lost.emit("Server disconnected.")

func _reset() -> void:
	is_active = false
	players.clear()
	inputs.clear()
	guard_groups.clear()
	state.clear()
	helmsman_id = 0
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func _spawn_player(id: int) -> void:
	var side := float(players.size() % 3) * 1.6 - 1.6
	players[id] = {"name": "Pirate %d" % id, "mode": "deck", "hero": "luffy",
		"local": Vector3(side, 3.1, 3.2), "world": Vector3.ZERO,
		"hp": 100, "gold": 0, "fruits": 0, "one_piece": false,
		"attack_number": 0, "next_attack": 0.0}
	inputs[id] = {"forward": 0.0, "strafe": 0.0, "yaw": 0.0}

func _peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_spawn_player(id)
		_push_state()

func _peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	players.erase(id)
	inputs.erase(id)
	if helmsman_id == id:
		helmsman_id = 0
	_push_state()

func submit_local_input(data: Dictionary) -> void:
	if not is_active:
		return
	if multiplayer.is_server():
		inputs[1] = _sanitize_input(data)
	else:
		_send_input.rpc_id(1, data)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _send_input(data: Dictionary) -> void:
	if multiplayer.is_server():
		var id := multiplayer.get_remote_sender_id()
		if players.has(id):
			inputs[id] = _sanitize_input(data)

func _sanitize_input(data: Dictionary) -> Dictionary:
	return {"forward": clampf(float(data.get("forward", 0.0)), -1.0, 1.0),
		"strafe": clampf(float(data.get("strafe", 0.0)), -1.0, 1.0),
		"yaw": wrapf(float(data.get("yaw", 0.0)), -PI, PI)}

func switch_character() -> void:
	if multiplayer.is_server():
		_switch(1)
	elif is_active:
		_request_switch.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_switch() -> void:
	if multiplayer.is_server():
		_switch(multiplayer.get_remote_sender_id())

func _switch(id: int) -> void:
	if not players.has(id):
		return
	var pirate: Dictionary = players[id]
	pirate["hero"] = "zoro" if str(pirate["hero"]) == "luffy" else "luffy"
	players[id] = pirate
	_push_state()

func toggle_helm() -> void:
	if multiplayer.is_server():
		_toggle_helm(1)
	elif is_active:
		_request_helm.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_helm() -> void:
	if multiplayer.is_server():
		_toggle_helm(multiplayer.get_remote_sender_id())

func _toggle_helm(id: int) -> void:
	if not players.has(id) or str(players[id]["mode"]) != "deck":
		return
	if helmsman_id == id:
		helmsman_id = 0
	elif helmsman_id == 0:
		var loc: Vector3 = players[id]["local"]
		if loc.distance_to(Vector3(0, 3.1, 3.2)) < 6.0:
			helmsman_id = id
			players[id]["local"] = Vector3(0, 3.1, 3.2)
	_push_state()

func toggle_shore() -> void:
	if multiplayer.is_server():
		_toggle_shore(1)
	elif is_active:
		_request_shore.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_shore() -> void:
	if multiplayer.is_server():
		_toggle_shore(multiplayer.get_remote_sender_id())

func _toggle_shore(id: int) -> void:
	if not players.has(id):
		return
	var pirate: Dictionary = players[id]
	if str(pirate["mode"]) == "deck":
		var island := world.closest_island(ship_position)
		if _distance(ship_position, island) > float(island["radius"]) + 105.0 or absf(ship_speed) > 5.0:
			return
		if helmsman_id == id:
			helmsman_id = 0
		pirate["mode"] = "swim"
		pirate["world"] = ship_position + Vector3.RIGHT.rotated(Vector3.UP, ship_heading) * 10.0
		_snap_to_surface(pirate)
	else:
		var pos: Vector3 = pirate["world"]
		if pos.distance_to(ship_position) > 18.0 or absf(ship_speed) > 5.0:
			return
		pirate["mode"] = "deck"
		pirate["local"] = Vector3(0, 3.1, 0)
	players[id] = pirate
	_push_state()

func _distance(pos: Vector3, island: Dictionary) -> float:
	return Vector2(pos.x - float(island["x"]), pos.z - float(island["z"])).length()

func ship_can_occupy(pos: Vector3) -> bool:
	if absf(pos.x) > SeaWorld.WORLD_RADIUS or absf(pos.z) > SeaWorld.WORLD_RADIUS:
		return false
	for island in world.islands:
		if _distance(pos, island) < float(island["radius"]) + HULL_CLEARANCE:
			return false
	return true

func _step_ship(delta: float) -> void:
	var command: Dictionary = inputs.get(helmsman_id, {})
	ship_speed = move_toward(ship_speed, float(command.get("forward", 0.0)) * SPEED_MAX, delta * 6.0)
	var steer := float(command.get("strafe", 0.0))
	if absf(ship_speed) > 0.2:
		ship_heading += steer * delta * 0.52 * clampf(absf(ship_speed) / 7.0, 0.25, 1.0) * signf(ship_speed)
	var movement := Vector3(-sin(ship_heading), 0, -cos(ship_heading)) * ship_speed * delta
	# Substeps prevent crossing a narrow shoreline in one tick.
	var steps := maxi(1, int(ceil(movement.length() / 2.0)))
	for index in range(steps):
		var candidate := ship_position + movement / float(steps)
		if ship_can_occupy(candidate):
			ship_position = candidate
		else:
			ship_speed = 0.0
			break

func _snap_to_surface(pirate: Dictionary) -> void:
	var position: Vector3 = pirate["world"]
	var island := world.closest_island(position)
	var h := world.ground_height(island, position)
	if h >= 0.8:
		pirate["mode"] = "land"
		position.y = h
	else:
		pirate["mode"] = "swim"
		position.y = -1.2
	pirate["world"] = position

func _step_players(delta: float) -> void:
	for id in players:
		if id == helmsman_id:
			continue
		var pirate: Dictionary = players[id]
		var command: Dictionary = inputs.get(id, {})
		var motion := Vector3(float(command.get("strafe", 0.0)), 0,
			-float(command.get("forward", 0.0))).limit_length(1.0)
		var yaw := float(command.get("yaw", 0.0))
		motion = motion.rotated(Vector3.UP, yaw)
		if str(pirate["mode"]) == "deck":
			var loc: Vector3 = pirate["local"]
			loc += motion.rotated(Vector3.UP, -ship_heading) * WALK_SPEED * delta
			loc.x = clampf(loc.x, -3.2, 3.2)
			loc.z = clampf(loc.z, -6.5, 6.7)
			loc.y = 3.1
			pirate["local"] = loc
		else:
			var pos: Vector3 = pirate["world"]
			var speed := SWIM_SPEED if str(pirate["mode"]) == "swim" else WALK_SPEED
			pos += motion * speed * delta
			pos.x = clampf(pos.x, -SeaWorld.WORLD_RADIUS, SeaWorld.WORLD_RADIUS)
			pos.z = clampf(pos.z, -SeaWorld.WORLD_RADIUS, SeaWorld.WORLD_RADIUS)
			pirate["world"] = pos
			_snap_to_surface(pirate)
		players[id] = pirate

func attack() -> void:
	if multiplayer.is_server():
		_attack(1)
	elif is_active:
		_request_attack.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_attack() -> void:
	if multiplayer.is_server():
		_attack(multiplayer.get_remote_sender_id())

func _attack(id: int) -> void:
	if not players.has(id):
		return
	var pirate: Dictionary = players[id]
	if str(pirate["mode"]) != "land" or world_clock < float(pirate["next_attack"]):
		return
	var is_zoro := str(pirate["hero"]) == "zoro"
	pirate["next_attack"] = world_clock + (0.55 if is_zoro else 0.42)
	pirate["attack_number"] = int(pirate["attack_number"]) + 1
	players[id] = pirate
	var pos: Vector3 = pirate["world"]
	var island := world.closest_island(pos)
	var island_id: int = int(island["id"])
	_ensure_guards(island)
	var nearest := -1
	var best := 5.2 if is_zoro else 3.8
	var group: Array = guard_groups[island_id]
	for i in range(group.size()):
		var enemy: Dictionary = group[i]
		if int(enemy["hp"]) <= 0:
			continue
		var target: Vector3 = enemy["pos"]
		var dist := Vector2(target.x - pos.x, target.z - pos.z).length()
		if dist < best:
			best = dist
			nearest = i
	if nearest >= 0:
		var hit_enemy: Dictionary = group[nearest]
		hit_enemy["hp"] = maxi(0, int(hit_enemy["hp"]) - (2 if is_zoro else 1))
		group[nearest] = hit_enemy
		guard_groups[island_id] = group
	_push_state()

func _ensure_guards(island: Dictionary) -> void:
	var island_id: int = int(island["id"])
	if guard_groups.has(island_id):
		return
	var group: Array = []
	if not claimed_fruits.has(island_id):
		var center := Vector3(float(island["x"]), 0, float(island["z"]))
		for i in range(GUARD_COUNT):
			var angle := TAU * float(i) / float(GUARD_COUNT) + float(island_id) * 0.44
			var pos := center + Vector3(cos(angle), 0, sin(angle)) * 18.0
			pos.y = world.ground_height(island, pos)
			group.append({"pos": pos, "home": pos, "hp": 3, "next_hit": 0.0})
	guard_groups[island_id] = group

func _step_guards(delta: float) -> void:
	var active: Dictionary = {}
	for id in players:
		var pirate: Dictionary = players[id]
		if str(pirate["mode"]) != "land":
			continue
		var island := world.closest_island(pirate["world"])
		if _distance(pirate["world"], island) < float(island["radius"]) + 30:
			active[int(island["id"])] = island
	for island_id in active:
		var island: Dictionary = active[island_id]
		_ensure_guards(island)
		var group: Array = guard_groups[island_id]
		for i in range(group.size()):
			var enemy: Dictionary = group[i]
			if int(enemy["hp"]) <= 0:
				continue
			var pos: Vector3 = enemy["pos"]
			var home: Vector3 = enemy["home"]
			var target_id := -1
			var best := 38.0
			for player_id in players:
				var pirate: Dictionary = players[player_id]
				if str(pirate["mode"]) != "land":
					continue
				var p: Vector3 = pirate["world"]
				var dist := Vector2(p.x - pos.x, p.z - pos.z).length()
				if dist < best:
					target_id = player_id
					best = dist
			var destination := home
			if target_id >= 0:
				destination = players[target_id]["world"]
			if destination.distance_to(pos) > 2.5:
				var diff := destination - pos
				diff.y = 0
				if diff.length() > 0.2:
					pos += diff.normalized() * minf(4.0 * delta, diff.length())
			pos.y = world.ground_height(island, pos)
			enemy["pos"] = pos
			if target_id >= 0 and best < 3.0 and world_clock >= float(enemy["next_hit"]):
				var victim: Dictionary = players[target_id]
				victim["hp"] = int(victim["hp"]) - 10
				if int(victim["hp"]) <= 0:
					victim["hp"] = 100
					victim["mode"] = "deck"
					victim["local"] = Vector3(0, 3.1, 0)
				players[target_id] = victim
				enemy["next_hit"] = world_clock + 1.5
			group[i] = enemy
		guard_groups[island_id] = group

func collect_treasure() -> void:
	if multiplayer.is_server():
		_collect(1)
	elif is_active:
		_request_collect.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_collect() -> void:
	if multiplayer.is_server():
		_collect(multiplayer.get_remote_sender_id())

func _collect(id: int) -> void:
	if not players.has(id):
		return
	var pirate: Dictionary = players[id]
	if str(pirate["mode"]) != "land":
		return
	var island := world.closest_island(pirate["world"])
	var island_id: int = int(island["id"])
	if _distance(pirate["world"], island) > 12:
		return
	_ensure_guards(island)
	for enemy in guard_groups[island_id]:
		if int(enemy["hp"]) > 0:
			return
	if not claimed_treasures.has(island_id):
		claimed_treasures[island_id] = id
		pirate["gold"] = int(pirate["gold"]) + (1000 if island_id == 1 else 40)
		if island_id == 1:
			pirate["one_piece"] = true
	if not claimed_fruits.has(island_id):
		claimed_fruits[island_id] = id
		pirate["fruits"] = int(pirate["fruits"]) + 1
	players[id] = pirate
	_push_state()
	_save_world()

func _physics_process(delta: float) -> void:
	if not is_active or not multiplayer.is_server():
		return
	world_clock += delta
	_step_ship(delta)
	_step_players(delta)
	_step_guards(delta)
	snapshot_clock += delta
	save_clock += delta
	if snapshot_clock >= UPDATE_INTERVAL:
		snapshot_clock = 0.0
		_push_state()
	if save_clock >= 20.0:
		save_clock = 0.0
		_save_world()

func _push_state() -> void:
	state = _make_snapshot()
	if multiplayer.is_server():
		_receive_snapshot.rpc(state)
	state_updated.emit()

func _make_snapshot() -> Dictionary:
	var current_players: Dictionary = {}
	var active_guards: Dictionary = {}
	for id in players:
		var pirate: Dictionary = players[id]
		current_players[str(id)] = {"name": pirate["name"], "mode": pirate["mode"],
			"hero": pirate["hero"], "local": pirate["local"], "world": pirate["world"],
			"hp": pirate["hp"], "gold": pirate["gold"], "fruits": pirate["fruits"],
			"one_piece": pirate["one_piece"], "attack_number": pirate["attack_number"]}
	for island_id in guard_groups:
		var group: Array = guard_groups[island_id]
		var near := false
		var island: Dictionary = world.islands[int(island_id)]
		for player_id in players:
			var player: Dictionary = players[player_id]
			if str(player["mode"]) == "land" and _distance(player["world"], island) < float(island["radius"]) + 75:
				near = true
				break
		if near:
			active_guards[str(island_id)] = group
	return {"ship_position": ship_position, "ship_heading": ship_heading,
		"ship_speed": ship_speed, "helmsman": helmsman_id,
		"players": current_players, "guards": active_guards,
		"looted": claimed_treasures.keys(), "fruits_taken": claimed_fruits.keys()}

@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_snapshot(data: Dictionary) -> void:
	if multiplayer.is_server():
		return
	state = data
	state_updated.emit()

func _save_world() -> void:
	var file := FileAccess.open("user://world_save.json", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"ship_x": ship_position.x, "ship_z": ship_position.z,
		"heading": ship_heading, "claimed": claimed_treasures.keys(),
		"fruits": claimed_fruits.keys()}))
	file.close()

func _load_world() -> void:
	if not FileAccess.file_exists("user://world_save.json"):
		return
	var file := FileAccess.open("user://world_save.json", FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	if data is Dictionary:
		ship_position = Vector3(clampf(float(data.get("ship_x", 0)), -SeaWorld.WORLD_RADIUS,
			SeaWorld.WORLD_RADIUS), 0, clampf(float(data.get("ship_z", -160)),
			-SeaWorld.WORLD_RADIUS, SeaWorld.WORLD_RADIUS))
		ship_heading = float(data.get("heading", 0))
		for id in data.get("claimed", []):
			claimed_treasures[int(id)] = 1
		for id in data.get("fruits", []):
			claimed_fruits[int(id)] = 1
