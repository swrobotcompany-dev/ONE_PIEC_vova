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
const SPRINT_MULTIPLIER := 1.28
const ATTACK_WINDUP := 0.12
const ATTACK_ACTIVE_END := 0.32
const HULL_CLEARANCE := 20.0
const GUARD_COUNT := 3
const GUARD_RESPAWN_SECONDS := 90.0
const JUMP_IMPULSE := 10.5
const JUMP_GRAVITY := 24.0
const PROJECTILE_SPEED := 35.0
const PROJECTILE_LIFE := 2.1

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
var projectiles: Dictionary = {}
var projectile_sequence := 0
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
	# Every island is protected, even after the island's fruit has been collected.
	for island in world.islands:
		_ensure_guards(island)
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
	projectiles.clear()
	state.clear()
	helmsman_id = 0
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func _spawn_player(id: int) -> void:
	var index := players.size()
	var side := float(index % 3 - 1) * 2.3
	var deck_z := 3.1 - float(index / 3) * 3.0
	players[id] = {"name": "Pirate %d" % id, "mode": "deck", "hero": "luffy",
		"local": Vector3(side, 3.1, deck_z), "world": Vector3.ZERO,
		"hp": 100, "gold": 0, "fruits": 0, "one_piece": false,
		"attack_number": 0, "next_attack": 0.0,
		"attack_start": 0.0, "attack_pending": false, "facing": 0.0,
		"move_velocity": Vector3.ZERO, "hurt_number": 0, "hits_total": 0,
		"next_shot": 0.0, "aim_lock_until": 0.0, "kills": 0, "score": 0,
		"abilities": [], "fruit_ranks": {}, "selected_fruit": "",
		"next_fruit": 0.0, "shield_until": 0.0,
		"jump_count": 0, "jump_height": 0.0, "jump_speed": 0.0}
	# Restore island fruit powers on reconnect/restart, using the recorded
	# claimant ID. No account system exists yet, so peer IDs are provisional.
	var restored: Array = []
	var ranks: Dictionary = {}
	for island_id in claimed_fruits:
		if int(claimed_fruits[island_id]) == id:
			var ability := fruit_power_for(int(island_id))
			if not restored.has(ability):
				restored.append(ability)
			ranks[ability] = mini(4, int(ranks.get(ability, 0)) + 1)
	players[id]["abilities"] = restored
	players[id]["fruit_ranks"] = ranks
	players[id]["selected_fruit"] = str(restored[0]) if not restored.is_empty() else ""
	var fruit_count := 0
	for island_id in claimed_fruits:
		if int(claimed_fruits[island_id]) == id:
			fruit_count += 1
	players[id]["fruits"] = fruit_count
	inputs[id] = {"forward": 0.0, "strafe": 0.0, "yaw": 0.0, "sprint": false}

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
		"yaw": wrapf(float(data.get("yaw", 0.0)), -PI, PI),
		"sprint": bool(data.get("sprint", false))}

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
		pirate["jump_count"] = 0
		pirate["jump_height"] = 0.0
		pirate["jump_speed"] = 0.0
		pirate["move_velocity"] = Vector3.ZERO
		pirate["world"] = ship_position + Vector3.RIGHT.rotated(Vector3.UP, ship_heading) * 10.0
		_snap_to_surface(pirate)
	else:
		var pos: Vector3 = pirate["world"]
		if pos.distance_to(ship_position) > 18.0 or absf(ship_speed) > 5.0:
			return
		pirate["mode"] = "deck"
		pirate["jump_count"] = 0
		pirate["jump_height"] = 0.0
		pirate["jump_speed"] = 0.0
		pirate["move_velocity"] = Vector3.ZERO
		pirate["local"] = Vector3(0, 3.1, 0)
	players[id] = pirate
	_push_state()

func _distance(pos: Vector3, island: Dictionary) -> float:
	return Vector2(pos.x - float(island["x"]), pos.z - float(island["z"])).length()

func ship_can_occupy(pos: Vector3) -> bool:
	if absf(pos.x) > SeaWorld.WORLD_RADIUS or absf(pos.z) > SeaWorld.WORLD_RADIUS:
		return false
	for island in world.islands:
		var angle := atan2(pos.z - float(island["z"]), pos.x - float(island["x"]))
		if _distance(pos, island) < world.coast_radius(island, angle) + HULL_CLEARANCE:
			return false
	return true

func _step_ship(delta: float) -> void:
	var command: Dictionary = inputs.get(helmsman_id, {})
	ship_speed = move_toward(ship_speed, float(command.get("forward", 0.0)) * SPEED_MAX, delta * 6.0)
	var steer := float(command.get("strafe", 0.0))
	if absf(ship_speed) > 0.2:
		ship_heading -= steer * delta * 0.52 * clampf(absf(ship_speed) / 7.0, 0.25, 1.0) * signf(ship_speed)
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
	if h >= 0.0:
		pirate["mode"] = "land"
		position.y = h + float(pirate.get("jump_height", 0.0))
	else:
		pirate["mode"] = "swim"
		pirate["jump_count"] = 0
		pirate["jump_height"] = 0.0
		pirate["jump_speed"] = 0.0
		position.y = -1.2
	pirate["world"] = position

func _step_players(delta: float) -> void:
	for id in players:
		var pirate: Dictionary = players[id]
		_integrate_jump(pirate, delta)
		var command: Dictionary = inputs.get(id, {})
		var yaw := float(command.get("yaw", 0.0))
		if id == helmsman_id:
			pirate["move_velocity"] = Vector3.ZERO
			players[id] = pirate
			continue
		var motion := Vector3(float(command.get("strafe", 0.0)), 0.0,
			-float(command.get("forward", 0.0))).limit_length(1.0)
		motion = motion.rotated(Vector3.UP, yaw)
		var mode := str(pirate["mode"])
		var speed := WALK_SPEED
		var acceleration := 26.0
		if mode == "swim":
			speed = SWIM_SPEED
			acceleration = 10.0
		elif bool(command.get("sprint", false)):
			speed *= SPRINT_MULTIPLIER
		if "lightning" in pirate.get("abilities", []):
			speed *= 1.3
		var velocity: Vector3 = pirate.get("move_velocity", Vector3.ZERO)
		velocity = velocity.move_toward(motion * speed, acceleration * delta)
		pirate["move_velocity"] = velocity
		if world_clock >= float(pirate.get("aim_lock_until", 0.0)) and motion.length_squared() > 0.002 and velocity.length_squared() > 0.01:
			var desired_facing := atan2(-velocity.x, -velocity.z)
			pirate["facing"] = lerp_angle(float(pirate.get("facing", 0.0)),
				desired_facing, minf(delta * 14.0, 1.0))
		if mode == "deck":
			var local_position: Vector3 = pirate["local"]
			local_position += velocity.rotated(Vector3.UP, -ship_heading) * delta
			local_position.x = clampf(local_position.x, -2.95, 2.95)
			local_position.z = clampf(local_position.z, -6.3, 6.4)
			local_position.y = 3.1 + float(pirate.get("jump_height", 0.0))
			pirate["local"] = local_position
		else:
			var position: Vector3 = pirate["world"]
			var displacement := velocity * delta
			var candidate := position
			var nearest := world.closest_island(position)
			var on_land := str(pirate["mode"]) == "land"
			var test_x := Vector3(position.x + displacement.x, position.y, position.z)
			if not (on_land and world.blocked_by_building(nearest, test_x)):
				candidate.x = test_x.x
			else:
				velocity.x = 0.0
			var test_z := Vector3(candidate.x, position.y, position.z + displacement.z)
			if not (on_land and world.blocked_by_building(nearest, test_z)):
				candidate.z = test_z.z
			else:
				velocity.z = 0.0
			candidate.x = clampf(candidate.x, -SeaWorld.WORLD_RADIUS, SeaWorld.WORLD_RADIUS)
			candidate.z = clampf(candidate.z, -SeaWorld.WORLD_RADIUS, SeaWorld.WORLD_RADIUS)
			pirate["move_velocity"] = velocity
			pirate["world"] = candidate
			_snap_to_surface(pirate)
		players[id] = pirate

func fire_projectile(aim: Vector2) -> void:
	if not is_active:
		return
	if multiplayer.is_server():
		_server_fire(1, aim)
	else:
		_request_fire.rpc_id(1, aim)

@rpc("any_peer", "call_remote", "reliable")
func _request_fire(aim: Vector2) -> void:
	if multiplayer.is_server():
		_server_fire(multiplayer.get_remote_sender_id(), aim)

func _server_fire(id: int, aim: Vector2) -> void:
	if not players.has(id) or not aim.is_finite() or aim.length_squared() < 0.25 or id == helmsman_id:
		return
	var pirate: Dictionary = players[id]
	if str(pirate["mode"]) == "swim" or world_clock < float(pirate["next_shot"]):
		return
	var hero := str(pirate["hero"])
	var direction := aim.normalized()
	pirate["next_shot"] = world_clock + (0.40 if hero == "luffy" else 0.86)
	pirate["facing"] = atan2(-direction.x, -direction.y)
	pirate["aim_lock_until"] = world_clock + 0.30
	players[id] = pirate
	var origin := _player_origin(pirate)
	if hero == "luffy":
		# Elastic fist: fast, narrow, frequent hits with a little knockback.
		_spawn_shot(id, hero, "fist", origin, direction, 35.0, 1.4, 1, 1.25, 1, 0.0, "", 0.0, 2.5)
	else:
		# Flying three-sword slash: wider, slower cooldown, penetrates 3 guards.
		_spawn_shot(id, hero, "slash", origin, direction, 44.0, 1.5, 2, 2.2, 3)
	_push_state()

func _player_origin(pirate: Dictionary) -> Vector3:
	var origin: Vector3
	if str(pirate["mode"]) == "deck":
		origin = ship_position + (pirate["local"] as Vector3).rotated(Vector3.UP, ship_heading)
	else:
		origin = pirate["world"]
	origin.y += 1.45
	return origin

func _spawn_shot(owner_id: int, hero: String, kind: String, origin: Vector3,
		direction: Vector2, speed: float, life: float, damage: int,
		radius: float = 1.5, pierce: int = 1, splash: float = 0.0,
		status: String = "", status_time: float = 0.0, push: float = 0.0) -> void:
	projectile_sequence += 1
	projectiles[projectile_sequence] = {
		"owner": owner_id, "hero": hero, "kind": kind, "pos": origin,
		"velocity": Vector3(direction.x, 0.0, direction.y) * speed,
		"life": life, "damage": damage, "radius": radius, "pierce": pierce,
		"splash": splash, "status": status, "status_time": status_time,
		"push": push, "hit_guards": [], "visual_only": false}

func _spawn_pulse(owner_id: int, kind: String, center: Vector3, radius: float) -> void:
	projectile_sequence += 1
	projectiles[projectile_sequence] = {
		"owner": owner_id, "hero": "fruit", "kind": kind, "pos": center,
		"velocity": Vector3.ZERO, "life": 0.42, "damage": 0, "radius": radius,
		"visual_only": true}

func cycle_fruit() -> void:
	if multiplayer.is_server():
		_cycle_fruit(1)
	elif is_active:
		_request_cycle_fruit.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_cycle_fruit() -> void:
	if multiplayer.is_server():
		_cycle_fruit(multiplayer.get_remote_sender_id())

func _cycle_fruit(id: int) -> void:
	if not players.has(id):
		return
	var pirate: Dictionary = players[id]
	var abilities: Array = pirate.get("abilities", [])
	if abilities.is_empty():
		return
	var index := abilities.find(str(pirate.get("selected_fruit", "")))
	pirate["selected_fruit"] = abilities[(index + 1) % abilities.size()]
	players[id] = pirate
	_push_state()

func cast_fruit(aim: Vector2) -> void:
	if not is_active:
		return
	if multiplayer.is_server():
		_server_cast_fruit(1, aim)
	else:
		_request_cast_fruit.rpc_id(1, aim)

@rpc("any_peer", "call_remote", "reliable")
func _request_cast_fruit(aim: Vector2) -> void:
	if multiplayer.is_server():
		_server_cast_fruit(multiplayer.get_remote_sender_id(), aim)

func _server_cast_fruit(id: int, aim: Vector2) -> void:
	if not players.has(id) or not aim.is_finite() or aim.length_squared() < 0.25 or id == helmsman_id:
		return
	var pirate: Dictionary = players[id]
	var kind := str(pirate.get("selected_fruit", ""))
	if not FruitCatalog.TYPES.has(kind) or not pirate.get("abilities", []).has(kind):
		return
	if str(pirate["mode"]) == "swim" or world_clock < float(pirate.get("next_fruit", 0.0)):
		return
	var rank := clampi(int(pirate.get("fruit_ranks", {}).get(kind, 1)), 1, 4)
	var bonus := 1 if rank >= 3 else 0
	var direction := aim.normalized()
	var origin := _player_origin(pirate)
	pirate["next_fruit"] = world_clock + FruitCatalog.cooldown(kind, rank)
	pirate["facing"] = atan2(-direction.x, -direction.y)
	pirate["aim_lock_until"] = world_clock + 0.38
	players[id] = pirate
	match kind:
		"rubber":
			for offset in [-0.18, 0.0, 0.18]:
				_spawn_shot(id, "fruit", kind, origin, direction.rotated(offset),
					42.0, 1.2, 1 + bonus, 1.45, 1, 0.0, "", 0.0, 3.5)
		"fire":
			_spawn_shot(id, "fruit", kind, origin, direction, 27.0, 1.7,
				3 + bonus, 1.8, 1, 5.0, "burn", 3.0)
		"ice":
			_spawn_shot(id, "fruit", kind, origin, direction, 49.0, 1.2,
				2 + bonus, 1.8, 1, 0.0, "freeze", 2.4)
		"lightning":
			_spawn_shot(id, "fruit", kind, origin, direction, 95.0, 0.8,
				2 + bonus, 1.8)
		"sand":
			for offset in [-0.30, -0.15, 0.0, 0.15, 0.30]:
				_spawn_shot(id, "fruit", kind, origin, direction.rotated(offset),
					33.0, 0.65, 1 + bonus, 1.1, 1, 0.0, "slow", 2.0)
		"smoke":
			_area_hit(id, origin, 9.0, 1 + bonus, "slow", 2.5, 4.0)
			_spawn_pulse(id, kind, origin, 9.0)
		"flower":
			_area_hit(id, origin, 15.0, 2 + bonus, "", 0.0, 0.0, 3)
			_spawn_pulse(id, kind, origin, 15.0)
		"string":
			_spawn_shot(id, "fruit", kind, origin, direction, 52.0, 1.3,
				2 + bonus, 1.2, 4, 0.0, "root", 1.8)
		"light":
			_spawn_shot(id, "fruit", kind, origin, direction, 115.0, 0.7,
				2 + bonus, 1.1, 4)
		"gravity":
			var center := origin + Vector3(direction.x, 0, direction.y) * 13.0
			var island := world.closest_island(center)
			if world.segment_hits_building(island, origin, center):
				center = origin + Vector3(direction.x, 0, direction.y) * 3.0
			_area_hit(id, center, 8.0, 2 + bonus, "slow", 3.0, -5.0)
			_spawn_pulse(id, kind, center, 8.0)
		"magma":
			_spawn_shot(id, "fruit", kind, origin, direction, 22.0, 1.8,
				4 + bonus, 2.3, 1, 4.2, "burn", 4.0)
		"quake":
			_area_hit(id, origin, 12.0, 3 + bonus, "", 0.0, 6.0, 8, direction)
			_spawn_pulse(id, kind, origin + Vector3(direction.x, 0, direction.y) * 4.0, 10.0)
		"barrier":
			pirate["shield_until"] = world_clock + 5.0 + float(rank - 1)
			players[id] = pirate
			_area_hit(id, origin, 5.5, 1 + bonus, "", 0.0, 3.0)
			_spawn_pulse(id, kind, origin, 5.5)
		"poison":
			_spawn_shot(id, "fruit", kind, origin, direction, 30.0, 1.6,
				2 + bonus, 1.8, 1, 4.0, "poison", 5.0)
	_push_state()

func _step_projectiles(delta: float) -> void:
	for projectile_id in projectiles.keys():
		var shot: Dictionary = projectiles[projectile_id]
		var start: Vector3 = shot["pos"]
		var finish: Vector3 = start + (shot["velocity"] as Vector3) * delta
		shot["life"] = float(shot["life"]) - delta
		if bool(shot.get("visual_only", false)):
			if float(shot["life"]) <= 0.0:
				projectiles.erase(projectile_id)
			else:
				projectiles[projectile_id] = shot
			continue
		var island := world.closest_island(finish)
		var island_id := int(island["id"])
		var blocked := world.segment_hits_building(island, start, finish)
		var consumed := false
		if guard_groups.has(island_id):
			var guards: Array = guard_groups[island_id]
			var begin := Vector2(start.x, start.z)
			var end := Vector2(finish.x, finish.z)
			var segment := end - begin
			for i in range(guards.size()):
				var enemy: Dictionary = guards[i]
				if int(enemy["hp"]) <= 0 or shot["hit_guards"].has(i):
					continue
				var pos: Vector3 = enemy["pos"]
				var point := Vector2(pos.x, pos.z)
				var t := clampf((point - begin).dot(segment) / maxf(segment.length_squared(), 0.001), 0.0, 1.0)
				if point.distance_to(begin.lerp(end, t)) > float(shot["radius"]) + 0.65:
					continue
				if world.segment_hits_building(island, start, pos):
					continue
				var splash := float(shot.get("splash", 0.0))
				if splash > 0.0:
					_area_hit(int(shot["owner"]), pos, splash, int(shot["damage"]),
						str(shot["status"]), float(shot["status_time"]), float(shot["push"]))
					consumed = true
				else:
					_damage_guard(island_id, i, int(shot["damage"]), int(shot["owner"]),
						str(shot["status"]), float(shot["status_time"]), float(shot["push"]), start)
					shot["hit_guards"].append(i)
					shot["pierce"] = int(shot["pierce"]) - 1
					if str(shot["kind"]) == "lightning":
						_area_hit(int(shot["owner"]), pos, 8.0, 1, "", 0.0, 0.0, 2, Vector2.ZERO, i)
					if int(shot["pierce"]) <= 0:
						consumed = true
				if consumed:
					break
		if blocked or consumed or float(shot["life"]) <= 0.0:
			projectiles.erase(projectile_id)
		else:
			shot["pos"] = finish
			projectiles[projectile_id] = shot

func _damage_guard(island_id: int, guard_index: int, damage: int, owner_id: int,
		status: String = "", duration: float = 0.0, push: float = 0.0,
		from_pos: Vector3 = Vector3.ZERO) -> void:
	if not guard_groups.has(island_id):
		return
	var guards: Array = guard_groups[island_id]
	if guard_index < 0 or guard_index >= guards.size():
		return
	var enemy: Dictionary = guards[guard_index]
	if int(enemy["hp"]) <= 0:
		return
	var hp_before := int(enemy["hp"])
	enemy["hp"] = maxi(0, hp_before - maxi(damage, 0))
	enemy["hit_number"] = int(enemy.get("hit_number", 0)) + 1
	if int(enemy["hp"]) > 0:
		match status:
			"burn", "poison":
				enemy["dot_until"] = maxf(float(enemy.get("dot_until", 0.0)), world_clock + duration)
				enemy["dot_next"] = world_clock + 1.0
				enemy["dot_owner"] = owner_id
				enemy["dot_damage"] = 1
			"freeze", "root":
				enemy["freeze_until"] = maxf(float(enemy.get("freeze_until", 0.0)), world_clock + duration)
			"slow":
				enemy["slow_until"] = maxf(float(enemy.get("slow_until", 0.0)), world_clock + duration)
		if absf(push) > 0.1:
			var away: Vector3 = enemy["pos"] - from_pos
			away.y = 0
			if away.length_squared() > 0.01:
				var candidate: Vector3 = enemy["pos"] + away.normalized() * push
				var island: Dictionary = world.islands[island_id]
				if world.ground_height(island, candidate) >= 0.0 and not world.blocked_by_building(island, candidate, 0.9):
					candidate.y = world.ground_height(island, candidate)
					enemy["pos"] = candidate
	else:
		enemy["respawn_at"] = world_clock + GUARD_RESPAWN_SECONDS
	guards[guard_index] = enemy
	guard_groups[island_id] = guards
	if players.has(owner_id) and damage > 0:
		var shooter: Dictionary = players[owner_id]
		shooter["hits_total"] = int(shooter["hits_total"]) + 1
		if int(enemy["hp"]) == 0:
			shooter["kills"] = int(shooter["kills"]) + 1
			shooter["score"] = int(shooter["score"]) + 100
		players[owner_id] = shooter

func _area_hit(owner_id: int, center: Vector3, radius: float, damage: int,
		status: String = "", duration: float = 0.0, push: float = 0.0,
		max_targets: int = 99, facing: Vector2 = Vector2.ZERO, exclude: int = -1) -> void:
	var island := world.closest_island(center)
	var island_id := int(island["id"])
	if not guard_groups.has(island_id):
		return
	var hit_count := 0
	var group: Array = guard_groups[island_id]
	for i in range(group.size()):
		if i == exclude or int(group[i]["hp"]) <= 0:
			continue
		var pos: Vector3 = group[i]["pos"]
		var offset := Vector2(pos.x - center.x, pos.z - center.z)
		if offset.length() > radius:
			continue
		if facing.length_squared() > 0.1 and offset.length_squared() > 0.1 and facing.normalized().dot(offset.normalized()) < 0.1:
			continue
		if world.segment_hits_building(island, center, pos):
			continue
		_damage_guard(island_id, i, damage, owner_id, status, duration, push, center)
		hit_count += 1
		if hit_count >= max_targets:
			break

func _projectile_snapshot() -> Dictionary:
	var results := {}
	for id in projectiles:
		var shot: Dictionary = projectiles[id]
		results[str(id)] = {"pos": shot["pos"], "hero": shot["hero"],
			"kind": shot["kind"], "radius": shot["radius"],
			"velocity": shot["velocity"]}
	return results

func jump() -> void:
	if not is_active:
		return
	if multiplayer.is_server():
		_server_jump(1)
	else:
		_request_jump.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_jump() -> void:
	if multiplayer.is_server():
		_server_jump(multiplayer.get_remote_sender_id())

func _server_jump(id: int) -> void:
	if not players.has(id) or id == helmsman_id:
		return
	var pirate: Dictionary = players[id]
	if str(pirate["mode"]) != "land" and str(pirate["mode"]) != "deck":
		return
	var max_jumps := 2 if "flower" in pirate.get("abilities", []) else 1
	if int(pirate.get("jump_count", 0)) >= max_jumps:
		return
	pirate["jump_count"] = int(pirate.get("jump_count", 0)) + 1
	pirate["jump_speed"] = JUMP_IMPULSE
	players[id] = pirate
	_push_state()

func _integrate_jump(pirate: Dictionary, delta: float) -> void:
	if str(pirate["mode"]) == "swim":
		pirate["jump_height"] = 0.0
		pirate["jump_speed"] = 0.0
		pirate["jump_count"] = 0
		return
	var vertical_speed := float(pirate.get("jump_speed", 0.0))
	var height := float(pirate.get("jump_height", 0.0))
	if vertical_speed == 0.0 and height <= 0.0:
		return
	height += vertical_speed * delta
	vertical_speed -= JUMP_GRAVITY * delta
	if height <= 0.0 and vertical_speed < 0.0:
		height = 0.0
		vertical_speed = 0.0
		pirate["jump_count"] = 0
	pirate["jump_height"] = height
	pirate["jump_speed"] = vertical_speed

func fruit_power_for(island_id: int) -> String:
	return FruitCatalog.for_island(island_id)

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
	# Only grounded attacks: swimming and steering never produce damage.
	if str(pirate["mode"]) != "land" or world_clock < float(pirate["next_attack"]):
		return
	var is_zoro := str(pirate["hero"]) == "zoro"
	var duration := 0.62 if is_zoro else 0.50
	pirate["next_attack"] = world_clock + duration
	pirate["attack_start"] = world_clock
	pirate["attack_pending"] = true
	pirate["attack_number"] = int(pirate["attack_number"]) + 1
	# Keyboard melee uses last movement facing.
	players[id] = pirate
	_push_state()

func _step_attacks() -> void:
	for id in players:
		var pirate: Dictionary = players[id]
		if not bool(pirate.get("attack_pending", false)):
			continue
		var elapsed := world_clock - float(pirate["attack_start"])
		if elapsed < ATTACK_WINDUP:
			continue
		# A single server-side hit query in the active frames, never every
		# render frame. Per-target hit numbers drive client's impact effects.
		pirate["attack_pending"] = false
		if elapsed > ATTACK_ACTIVE_END or str(pirate["mode"]) != "land":
			players[id] = pirate
			continue
		var is_zoro := str(pirate["hero"]) == "zoro"
		var radius := 5.8 if is_zoro else 4.2
		var max_targets := 2 if is_zoro else 1
		var direction := Vector3(-sin(float(pirate["facing"])), 0.0,
			-cos(float(pirate["facing"])))
		var origin: Vector3 = pirate["world"]
		var island := world.closest_island(origin)
		var island_id: int = int(island["id"])
		_ensure_guards(island)
		var guards: Array = guard_groups[island_id]
		var candidates: Array[Dictionary] = []
		for i in range(guards.size()):
			var enemy: Dictionary = guards[i]
			if int(enemy["hp"]) <= 0:
				continue
			var offset: Vector3 = enemy["pos"] - origin
			offset.y = 0
			var distance := offset.length()
			if distance < radius and distance > 0.01 and direction.dot(offset.normalized()) > 0.04 and not world.segment_hits_building(island, origin, enemy["pos"]):
				candidates.append({"index": i, "distance": distance})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["distance"]) < float(b["distance"]))
		var hits := 0
		for candidate in candidates:
			if hits >= max_targets:
				break
			var index: int = int(candidate["index"])
			var target: Dictionary = guards[index]
			var hp_before: int = int(target["hp"])
			var damage := (2 if is_zoro else 1) + (1 if "quake" in pirate.get("abilities", []) else 0)
			target["hp"] = maxi(0, hp_before - damage)
			target["hit_number"] = int(target.get("hit_number", 0)) + 1
			if hp_before > 0 and int(target["hp"]) == 0:
				target["respawn_at"] = world_clock + GUARD_RESPAWN_SECONDS
				pirate["kills"] = int(pirate["kills"]) + 1
				pirate["score"] = int(pirate["score"]) + 100
			guards[index] = target
			hits += 1
		if hits > 0:
			pirate["hits_total"] = int(pirate["hits_total"]) + hits
			guard_groups[island_id] = guards
		players[id] = pirate

func _ensure_guards(island: Dictionary) -> void:
	var island_id: int = int(island["id"])
	if guard_groups.has(island_id):
		return
	var group: Array = []
	var center := Vector3(float(island["x"]), 0.0, float(island["z"]))
	for i in range(GUARD_COUNT):
		var angle := TAU * float(i) / float(GUARD_COUNT) + float(island_id) * 0.44
		var pos := center + Vector3(cos(angle), 0, sin(angle)) * (20.0 + float(i) * 6.0)
		pos.y = world.ground_height(island, pos)
		group.append({"pos": pos, "home": pos, "hp": 3 if i < 2 else 5,
			"max_hp": 3 if i < 2 else 5, "kind": i, "next_hit": 0.0,
			"hit_number": 0, "respawn_at": 0.0})
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
				if world_clock >= float(enemy.get("respawn_at", INF)):
					enemy["hp"] = int(enemy.get("max_hp", 3))
					enemy["pos"] = enemy["home"]
					enemy["next_hit"] = world_clock + 1.0
					group[i] = enemy
				else:
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
			if world_clock < float(enemy.get("freeze_until", 0.0)):
				group[i] = enemy
				continue
			if destination.distance_to(pos) > 2.5:
				var diff := destination - pos
				diff.y = 0
				if diff.length() > 0.2:
					var slow_factor := 0.38 if world_clock < float(enemy.get("slow_until", 0.0)) else 1.0
					var next := pos + diff.normalized() * minf(4.0 * slow_factor * delta, diff.length())
					if not world.blocked_by_building(island, next, 0.8):
						pos = next
					else:
						var sideways := Vector3(-diff.z, 0, diff.x).normalized()
						var around := pos + sideways * 4.0 * delta
						if not world.blocked_by_building(island, around, 0.8):
							pos = around
			pos.y = world.ground_height(island, pos)
			enemy["pos"] = pos
			if target_id >= 0 and best < 3.0 and world_clock >= float(enemy["next_hit"]):
				var victim: Dictionary = players[target_id]
				victim["hp"] = int(victim["hp"]) - (2 if world_clock < float(victim.get("shield_until", 0.0)) else 10)
				victim["hurt_number"] = int(victim.get("hurt_number", 0)) + 1
				if int(victim["hp"]) <= 0:
					victim["hp"] = 100
					victim["jump_count"] = 0
					victim["jump_height"] = 0.0
					victim["jump_speed"] = 0.0
					victim["mode"] = "deck"
					victim["local"] = Vector3(0, 3.1, 0)
				players[target_id] = victim
				enemy["next_hit"] = world_clock + 1.5
			group[i] = enemy
		guard_groups[island_id] = group

func _step_guard_dots() -> void:
	for island_id in guard_groups:
		var group: Array = guard_groups[island_id]
		for i in range(group.size()):
			var enemy: Dictionary = group[i]
			if int(enemy["hp"]) <= 0:
				continue
			if world_clock < float(enemy.get("dot_until", 0.0)) and world_clock >= float(enemy.get("dot_next", INF)):
				enemy["dot_next"] = world_clock + 1.0
				group[i] = enemy
				guard_groups[island_id] = group
				_damage_guard(int(island_id), i, int(enemy.get("dot_damage", 1)), int(enemy.get("dot_owner", -1)))
				group = guard_groups[island_id]

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
		var power := fruit_power_for(island_id)
		var known: Array = pirate.get("abilities", [])
		if not known.has(power):
			known.append(power)
		pirate["selected_fruit"] = power
		var ranks: Dictionary = pirate.get("fruit_ranks", {})
		ranks[power] = mini(4, int(ranks.get(power, 0)) + 1)
		pirate["fruit_ranks"] = ranks
		pirate["abilities"] = known
	players[id] = pirate
	_push_state()
	_save_world()

func _physics_process(delta: float) -> void:
	if not is_active or not multiplayer.is_server():
		return
	world_clock += delta
	_step_ship(delta)
	_step_players(delta)
	_step_attacks()
	_step_projectiles(delta)
	_step_guard_dots()
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
	if is_active and multiplayer.is_server():
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
			"one_piece": pirate["one_piece"], "attack_number": pirate["attack_number"],
			"facing": pirate.get("facing", 0.0), "hurt_number": pirate.get("hurt_number", 0),
			"hits_total": pirate.get("hits_total", 0),
			"kills": pirate.get("kills", 0), "score": pirate.get("score", 0),
			"abilities": pirate.get("abilities", []),
			"fruit_ranks": pirate.get("fruit_ranks", {}),
			"selected_fruit": pirate.get("selected_fruit", ""),
			"fruit_cooldown": maxf(0.0, float(pirate.get("next_fruit", 0.0)) - world_clock),
			"shield": maxf(0.0, float(pirate.get("shield_until", 0.0)) - world_clock),
			"jump_count": pirate.get("jump_count", 0)}
	for island_id in guard_groups:
		var group: Array = guard_groups[island_id]
		var near := false
		var island: Dictionary = world.islands[int(island_id)]
		for player_id in players:
			var player: Dictionary = players[player_id]
			if (str(player["mode"]) == "land" and _distance(player["world"], island) < float(island["radius"]) + 140) or _distance(ship_position, island) < float(island["radius"]) + 240:
				near = true
				break
		if near:
			active_guards[str(island_id)] = group
	return {"ship_position": ship_position, "ship_heading": ship_heading,
		"ship_speed": ship_speed, "helmsman": helmsman_id,
		"players": current_players, "guards": active_guards,
		"looted": claimed_treasures.keys(), "fruits_taken": claimed_fruits.keys(),
		"projectiles": _projectile_snapshot()}

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
	var fruit_owners: Dictionary = {}
	for island_id in claimed_fruits:
		fruit_owners[str(island_id)] = claimed_fruits[island_id]
	file.store_string(JSON.stringify({"ship_x": ship_position.x, "ship_z": ship_position.z,
		"heading": ship_heading, "claimed": claimed_treasures.keys(),
		"fruits": claimed_fruits.keys(), "fruit_owners": fruit_owners}))
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
		var owners: Dictionary = data.get("fruit_owners", {})
		if not owners.is_empty():
			for island_id in owners:
				claimed_fruits[int(island_id)] = int(owners[island_id])
		else:
			# Backwards compatible with earlier save versions, where owner
			# information was not recorded and host ID 1 claimed old fruits.
			for island_id in data.get("fruits", []):
				claimed_fruits[int(island_id)] = 1
