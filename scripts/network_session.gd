extends Node
# Authoritative, low-overhead LAN session. One shared starter ship.
signal session_ready
signal connection_lost(message: String)
signal state_updated

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 8
const UPDATE_INTERVAL := 1.0 / 12.0
const SPEED_MAX := 23.0
const WALK_SPEED := 7.5

var world := SeaWorld.new()
var ship_position := Vector3.ZERO
var ship_heading := 0.0
var ship_speed := 0.0
var helmsman_id := 0
var players: Dictionary = {}
var claimed_treasures: Dictionary = {}
var inputs: Dictionary = {}
var state: Dictionary = {}
var is_active := false
var snapshot_clock := 0.0
var save_clock := 0.0

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
	state = _make_snapshot()
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
	connection_lost.emit("Connection failed. Check IP, UDP port and firewall.")

func _disconnected() -> void:
	_reset()
	connection_lost.emit("The server disconnected.")

func _reset() -> void:
	is_active = false
	players.clear()
	inputs.clear()
	state.clear()
	helmsman_id = 0
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func _spawn_player(id: int) -> void:
	var side := float(players.size() % 3) * 1.6 - 1.6
	players[id] = {"id": id, "name": "Pirate %d" % id, "aboard": true,
		"local": Vector3(side, 3.1, 3.2), "world": Vector3.ZERO,
		"gold": 0, "one_piece": false}
	inputs[id] = {"forward": 0.0, "strafe": 0.0}

func _peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_spawn_player(id)
		state = _make_snapshot()

func _peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	players.erase(id)
	inputs.erase(id)
	if helmsman_id == id:
		helmsman_id = 0
	state = _make_snapshot()

func submit_local_input(data: Dictionary) -> void:
	if not is_active:
		return
	if multiplayer.is_server():
		inputs[1] = _sanitize_input(data)
	else:
		_send_input.rpc_id(1, data)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _send_input(data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		inputs[id] = _sanitize_input(data)

func _sanitize_input(data: Dictionary) -> Dictionary:
	return {"forward": clampf(float(data.get("forward", 0.0)), -1.0, 1.0),
		"strafe": clampf(float(data.get("strafe", 0.0)), -1.0, 1.0)}

func toggle_helm() -> void:
	if not is_active:
		return
	if multiplayer.is_server():
		_server_toggle_helm(1)
	else:
		_ask_helm.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _ask_helm() -> void:
	if multiplayer.is_server():
		_server_toggle_helm(multiplayer.get_remote_sender_id())

func _server_toggle_helm(id: int) -> void:
	if not players.has(id) or not bool(players[id]["aboard"]):
		return
	if helmsman_id == id:
		helmsman_id = 0
	elif helmsman_id == 0:
		var local_position: Vector3 = players[id]["local"]
		if local_position.distance_to(Vector3(0, 3.1, 3.2)) < 6.0:
			helmsman_id = id
			players[id]["local"] = Vector3(0, 3.1, 3.2)
	state = _make_snapshot()

func toggle_shore() -> void:
	if not is_active:
		return
	if multiplayer.is_server():
		_server_toggle_shore(1)
	else:
		_ask_shore.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _ask_shore() -> void:
	if multiplayer.is_server():
		_server_toggle_shore(multiplayer.get_remote_sender_id())

func _server_toggle_shore(id: int) -> void:
	if not players.has(id):
		return
	var pirate: Dictionary = players[id]
	if bool(pirate["aboard"]):
		var island := world.closest_island(ship_position)
		var distance := ship_position.distance_to(Vector3(
			float(island["x"]), 0, float(island["z"])))
		if distance > float(island["radius"]) + 125.0 or absf(ship_speed) > 8.0:
			return
		if helmsman_id == id:
			helmsman_id = 0
		pirate["aboard"] = false
		pirate["world"] = world.coast_point(island, ship_position)
	else:
		var pos: Vector3 = pirate["world"]
		if pos.distance_to(ship_position) > 320.0 or absf(ship_speed) > 8.0:
			return
		pirate["aboard"] = true
		pirate["local"] = Vector3(0, 3.1, 0)
	players[id] = pirate
	state = _make_snapshot()

func collect_treasure() -> void:
	if not is_active:
		return
	if multiplayer.is_server():
		_server_collect(1)
	else:
		_ask_collect.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _ask_collect() -> void:
	if multiplayer.is_server():
		_server_collect(multiplayer.get_remote_sender_id())

func _server_collect(id: int) -> void:
	if not players.has(id):
		return
	var pirate: Dictionary = players[id]
	if bool(pirate["aboard"]):
		return
	var pos: Vector3 = pirate["world"]
	var island := world.closest_island(pos)
	var island_id: int = island["id"]
	if claimed_treasures.has(island_id):
		return
	var center := Vector2(float(island["x"]), float(island["z"]))
	if Vector2(pos.x, pos.z).distance_to(center) > maxf(25.0, float(island["radius"]) * 0.22):
		return
	claimed_treasures[island_id] = id
	pirate["gold"] = int(pirate.get("gold", 0)) + (1000 if island_id == 1 else 40)
	if island_id == 1:
		pirate["one_piece"] = true
	players[id] = pirate
	state = _make_snapshot()
	_receive_snapshot.rpc(state)
	state_updated.emit()
	_save_world()

func _physics_process(delta: float) -> void:
	if not is_active or not multiplayer.is_server():
		return
	var command: Dictionary = inputs.get(helmsman_id, {})
	var forward: float = float(command.get("forward", 0.0))
	var turn: float = float(command.get("strafe", 0.0))
	var target_speed := forward * SPEED_MAX
	ship_speed = move_toward(ship_speed, target_speed, delta * 7.0)
	if absf(ship_speed) > 0.2:
		ship_heading += turn * delta * 0.55 * clampf(absf(ship_speed) / 7.0, 0.25, 1.0) * signf(ship_speed)
	ship_position += Vector3(-sin(ship_heading), 0, -cos(ship_heading)) * ship_speed * delta
	ship_position.x = clampf(ship_position.x, -SeaWorld.WORLD_RADIUS, SeaWorld.WORLD_RADIUS)
	ship_position.z = clampf(ship_position.z, -SeaWorld.WORLD_RADIUS, SeaWorld.WORLD_RADIUS)
	for id in players:
		var pirate: Dictionary = players[id]
		if id == helmsman_id:
			continue
		var motion: Dictionary = inputs.get(id, {})
		var x: float = float(motion.get("strafe", 0.0))
		var z: float = -float(motion.get("forward", 0.0))
		var direction := Vector3(x, 0.0, z).limit_length(1.0)
		if bool(pirate["aboard"]):
			var local_position: Vector3 = pirate["local"]
			local_position += direction * WALK_SPEED * delta
			local_position.x = clampf(local_position.x, -3.2, 3.2)
			local_position.z = clampf(local_position.z, -6.5, 6.7)
			local_position.y = 3.1
			pirate["local"] = local_position
		else:
			var p: Vector3 = pirate["world"]
			p += direction.rotated(Vector3.UP, ship_heading) * WALK_SPEED * delta
			var island := world.closest_island(p)
			var island_center := Vector2(float(island["x"]), float(island["z"]))
			if Vector2(p.x, p.z).distance_to(island_center) > float(island["radius"]) * 0.92:
				p = pirate["world"]
			p.y = world.ground_height(island, p) + 2.0
			pirate["world"] = p
		players[id] = pirate
	snapshot_clock += delta
	save_clock += delta
	if snapshot_clock >= UPDATE_INTERVAL:
		snapshot_clock = 0.0
		state = _make_snapshot()
		_receive_snapshot.rpc(state)
		state_updated.emit()
	if save_clock >= 20.0:
		save_clock = 0.0
		_save_world()

func _make_snapshot() -> Dictionary:
	var all_players: Dictionary = {}
	for id in players:
		var pirate: Dictionary = players[id]
		all_players[str(id)] = {"name": pirate["name"], "aboard": pirate["aboard"],
			"local": pirate["local"], "world": pirate["world"],
			"gold": pirate.get("gold", 0), "one_piece": pirate.get("one_piece", false)}
	return {"ship_position": ship_position, "ship_heading": ship_heading,
		"ship_speed": ship_speed, "helmsman": helmsman_id, "players": all_players,
		"looted": claimed_treasures.keys()}

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
		"heading": ship_heading, "claimed": claimed_treasures.keys()}))
	file.close()

func _load_world() -> void:
	if not FileAccess.file_exists("user://world_save.json"):
		return
	var file := FileAccess.open("user://world_save.json", FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	if data is Dictionary:
		ship_position = Vector3(clampf(float(data.get("ship_x", 0.0)), -SeaWorld.WORLD_RADIUS,
			SeaWorld.WORLD_RADIUS), 0, clampf(float(data.get("ship_z", 0.0)),
			-SeaWorld.WORLD_RADIUS, SeaWorld.WORLD_RADIUS))
		ship_heading = float(data.get("heading", 0.0))
		claimed_treasures.clear()
		for treasure_id in data.get("claimed", []):
			claimed_treasures[int(treasure_id)] = 1
