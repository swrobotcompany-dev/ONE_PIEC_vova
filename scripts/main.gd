extends Node3D

const DEFAULT_CAMERA_DISTANCE := 22.0
var world := SeaWorld.new()
var ship: PirateShip
var ocean: OceanSurface
var islands: IslandStream
var camera: Camera3D
var aiming: AimingView
var hud: PirateHud
var avatars: Dictionary = {}
var guardians: Dictionary = {}
var last_locations: Dictionary = {}
var last_deck_positions: Dictionary = {}
var cam_yaw := 0.2
var cam_pitch := 0.30
var camera_distance := DEFAULT_CAMERA_DISTANCE
var low_graphics := false
var input_clock := 0.0
var ocean_mask_clock := 0.0
var graphics_clock := 0.0

func _ready() -> void:
	GameNet.session_ready.connect(_on_connected)
	GameNet.connection_lost.connect(_on_disconnected)
	var arguments := OS.get_cmdline_user_args()
	if "--server" in arguments or DisplayServer.get_name() == "headless":
		var port := _server_port(arguments)
		var error := GameNet.host_game(port)
		if error != "":
			push_error(error)
			get_tree().quit(1)
		else:
			print("ONE PIECE dedicated server ready on UDP ", port)
		return
	_setup_environment()
	_setup_ocean()
	ship = PirateShip.new()
	add_child(ship)
	islands = IslandStream.new()
	add_child(islands)
	camera = Camera3D.new()
	camera.current = true
	camera.far = 4600.0
	add_child(camera)
	aiming = AimingView.new()
	aiming.active_camera = camera
	add_child(aiming)
	hud = PirateHud.new()
	add_child(hud)
	hud.host_pressed.connect(_host)
	hud.join_pressed.connect(_join)
	hud.quality_pressed.connect(_quality)

func _server_port(args: PackedStringArray) -> int:
	for argument in args:
		if argument.begins_with("--port="):
			return clampi(argument.trim_prefix("--port=").to_int(), 1024, 65535)
	return GameNet.DEFAULT_PORT

func _setup_environment() -> void:
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.09, 0.36, 0.66)
	sky_mat.sky_horizon_color = Color(0.74, 0.85, 0.88)
	sky_mat.ground_bottom_color = Color(0.10, 0.27, 0.31)
	sky_mat.ground_horizon_color = Color(0.67, 0.80, 0.84)
	sky.sky_material = sky_mat
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.53, 0.76, 0.81)
	environment.fog_density = 0.00035
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-43, -27, 0)
	sun.light_color = Color(1.0, 0.89, 0.69)
	sun.light_energy = 1.2
	sun.shadow_enabled = false # Strong performance benefit on integrated GPUs.
	add_child(sun)

func _setup_ocean() -> void:
	ocean = OceanSurface.new()
	add_child(ocean)
	ocean.update_focus(Vector3(0, 0, -160))

func _host(port: int) -> void:
	var error := GameNet.host_game(port)
	if error != "":
		hud.show_error(error)

func _join(address: String, port: int) -> void:
	var error := GameNet.join_game(address, port)
	if error != "":
		hud.show_error(error)
	else:
		hud.status.text = "Connecting to %s:%d ..." % [address, port]

func _on_connected() -> void:
	if hud != null:
		hud.show_connected()

func _on_disconnected(message: String) -> void:
	if hud != null:
		hud.show_disconnected(message)

func _quality(low: bool) -> void:
	low_graphics = low
	islands.set_quality(0 if low else 1)
	camera.far = 2800.0 if low else 4600.0

func _physics_process(delta: float) -> void:
	if not GameNet.is_active or hud == null:
		return
	input_clock += delta
	if input_clock < 0.05:
		return
	input_clock = 0.0
	var command := {"forward": float(Input.is_key_pressed(KEY_W)) -
		float(Input.is_key_pressed(KEY_S)),
		"strafe": float(Input.is_key_pressed(KEY_D)) -
		float(Input.is_key_pressed(KEY_A)),
		"yaw": cam_yaw, "sprint": Input.is_key_pressed(KEY_SHIFT)}
	GameNet.submit_local_input(command)

func _process(delta: float) -> void:
	if ship == null:
		return
	var current: Dictionary = GameNet.state
	var ship_position := Vector3.ZERO
	var ship_angle := 0.0
	var speed := 0.0
	if current.has("ship_position"):
		ship_position = current["ship_position"]
		ship_angle = float(current.get("ship_heading", 0.0))
		speed = float(current.get("ship_speed", 0.0))
	ship.position = ship.position.lerp(ship_position + Vector3(0,
		sin(Time.get_ticks_msec() * 0.0016) * 0.28, 0), minf(delta * 8.0, 1.0))
	ship.rotation.y = lerp_angle(ship.rotation.y, ship_angle, minf(delta * 8.0, 1.0))
	ship.rotation.z = sin(Time.get_ticks_msec() * 0.0013) * 0.025
	var focus := ship.position + Vector3(0, 6, 0)
	var local_id := str(multiplayer.get_unique_id())
	var pirates: Dictionary = current.get("players", {})
	_sync_avatars(pirates, delta)
	if avatars.has(local_id):
		focus = avatars[local_id].global_position + Vector3(0, 2.5, 0)
	_sync_guards(current.get("guards", {}), focus, delta)
	islands.set_focus(focus)
	ocean.update_focus(focus)
	var orbit := Vector3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch),
		cos(cam_yaw) * cos(cam_pitch))
	var target_camera := focus + orbit * camera_distance
	camera.global_position = camera.global_position.lerp(target_camera,
		minf(delta * 7.0, 1.0))
	camera.look_at(focus, Vector3.UP)
	var active_pirate: Node3D = avatars.get(local_id, null)
	aiming.update_view(delta, active_pirate, cam_yaw, current,
		GameNet.is_active and active_pirate != null)
	if GameNet.is_active:
		var nearest := world.closest_island(focus)
		var distance := ship_position.distance_to(Vector3(
			float(world.islands[1]["x"]), 0, float(world.islands[1]["z"])))
		var local_player: Dictionary = pirates.get(local_id, {})
		hud.update_details(speed, str(nearest["name"]), pirates.size(),
			distance, int(current.get("helmsman", 0)) == multiplayer.get_unique_id(),
			int(local_player.get("gold", 0)), bool(local_player.get("one_piece", false)),
			str(local_player.get("hero", "luffy")), str(local_player.get("mode", "deck")),
			int(local_player.get("hp", 100)), int(local_player.get("fruits", 0)),
			int(local_player.get("hits_total", 0)))

func _sync_avatars(pirates: Dictionary, delta: float) -> void:
	for id in avatars.keys():
		if not pirates.has(id):
			avatars[id].queue_free()
			avatars.erase(id)
			last_locations.erase(id)
			last_deck_positions.erase(id)
	for id in pirates:
		var pirate: Dictionary = pirates[id]
		var target: Vector3
		var mode := str(pirate.get("mode", "deck"))
		if mode == "deck":
			target = ship.to_global(pirate["local"])
		else:
			target = pirate["world"]
		if not avatars.has(id):
			var created := HeroVisual.new()
			created.name = "Pirate_" + id
			add_child(created)
			created.set_hero(str(pirate.get("hero", "luffy")))
			created.global_position = target
			avatars[id] = created
		var avatar: HeroVisual = avatars[id]
		avatar.set_hero(str(pirate.get("hero", "luffy")))
		var distance := avatar.global_position.distance_to(target)
		avatar.global_position = target if distance > 40.0 else avatar.global_position.lerp(target,
			minf(delta * 12.0, 1.0))
		var moving := distance > 0.025
		if mode == "deck":
			var deck_loc: Vector3 = pirate["local"]
			var previous: Vector3 = last_deck_positions.get(id, deck_loc)
			moving = previous.distance_to(deck_loc) > 0.02
			last_deck_positions[id] = deck_loc
		avatar.set_motion(mode, moving)
		avatar.show_attack(int(pirate.get("attack_number", 0)))
		avatar.show_hit(int(pirate.get("hurt_number", 0)))
		if mode == "deck":
			avatar.rotation.y = lerp_angle(avatar.rotation.y,
				float(pirate.get("facing", 0.0)), minf(delta * 12.0, 1.0))
		else:
			avatar.rotation.y = lerp_angle(avatar.rotation.y,
				float(pirate.get("facing", 0.0)), minf(delta * 12.0, 1.0))
		last_locations[id] = target

func _sync_guards(groups: Dictionary, focus: Vector3, delta: float) -> void:
	var visible_keys: Dictionary = {}
	for island_id in groups:
		var group: Array = groups[island_id]
		for i in range(group.size()):
			var enemy: Dictionary = group[i]
			if int(enemy.get("hp", 0)) <= 0:
				continue
			var pos: Vector3 = enemy["pos"]
			if pos.distance_to(focus) > 240.0:
				continue
			var key: String = str(island_id) + "_" + str(i)
			visible_keys[key] = true
			if not guardians.has(key):
				var guard := HeroVisual.new()
				guard.name = "PirateGuard_" + key
				add_child(guard)
				guard.set_hero("guard")
				var hp_label := Label3D.new()
				hp_label.name = "HealthLabel"
				hp_label.position = Vector3(0, 3.3, 0)
				hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				hp_label.font_size = 32
				hp_label.pixel_size = 0.042
				hp_label.modulate = Color(1.0, 0.45, 0.32)
				guard.add_child(hp_label)
				guard.global_position = pos
				guardians[key] = guard
			var visual: HeroVisual = guardians[key]
			var old: Vector3 = visual.global_position
			visual.global_position = old.lerp(pos, minf(delta * 8.0, 1.0))
			visual.set_motion("land", old.distance_to(pos) > 0.02)
			visual.show_hit(int(enemy.get("hit_number", 0)))
			var hp_label := visual.get_node_or_null("HealthLabel") as Label3D
			if hp_label != null:
				hp_label.text = "PIRATE  ♥ %d" % int(enemy.get("hp", 0))
	for key in guardians.keys():
		if not visible_keys.has(key):
			guardians[key].queue_free()
			guardians.erase(key)

func _unhandled_input(event: InputEvent) -> void:
	if not GameNet.is_active or hud == null:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		cam_yaw -= event.relative.x * 0.004
		cam_pitch = clampf(cam_pitch + event.relative.y * 0.003, -0.08, 0.90)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var local_id := str(multiplayer.get_unique_id())
			if avatars.has(local_id):
				var local_player: Dictionary = GameNet.state.get("players", {}).get(local_id, {})
				aiming.shoot(avatars[local_id].global_position, cam_yaw,
					str(local_player.get("hero", "luffy")))
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = maxf(camera_distance - 2.0, 10.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = minf(camera_distance + 2.0, 42.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_E:
			GameNet.toggle_helm()
		elif event.keycode == KEY_F:
			GameNet.toggle_shore()
		elif event.keycode == KEY_G:
			GameNet.collect_treasure()
		elif event.keycode == KEY_TAB:
			GameNet.switch_character()
		elif event.keycode == KEY_SPACE:
			GameNet.attack()
