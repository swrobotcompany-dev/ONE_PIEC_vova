extends Node3D

const DEFAULT_CAMERA_DISTANCE := 22.0
var world := SeaWorld.new()
var ship: PirateShip
var ocean: MeshInstance3D
var wake: MeshInstance3D
var islands: IslandStream
var camera: Camera3D
var hud: PirateHud
var avatars: Dictionary = {}
var cam_yaw := 0.2
var cam_pitch := 0.30
var camera_distance := DEFAULT_CAMERA_DISTANCE
var low_graphics := false
var input_clock := 0.0

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
	ocean = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3900.0, 3900.0)
	plane.subdivide_width = 106
	plane.subdivide_depth = 106
	ocean.mesh = plane
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform vec4 ocean_dark : source_color = vec4(0.017, 0.12, 0.21, 1.0);
uniform vec4 ocean_shallow : source_color = vec4(0.055, 0.46, 0.52, 1.0);
uniform vec4 foam_tint : source_color = vec4(0.78, 0.96, 0.97, 1.0);
varying vec3 sea_position;
varying float swell;

void vertex() {
    // Two broad Gerstner-like swell components; normals are approximated
    // analytically to let diffuse lighting read their crests.
    vec3 absolute_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float a = absolute_pos.x * 0.021 + TIME * 1.0;
    float b = absolute_pos.z * 0.028 + TIME * 1.36;
    float c = (absolute_pos.x + absolute_pos.z) * 0.051 - TIME * 1.7;
    float wave = sin(a) * 0.53 + cos(b) * 0.34 + sin(c) * 0.16;
    VERTEX.y += wave;
    float ddx = cos(a) * 0.021 * 0.53 + cos(c) * 0.051 * 0.16;
    float ddz = -sin(b) * 0.028 * 0.34 + cos(c) * 0.051 * 0.16;
    NORMAL = normalize(vec3(-ddx, 1.0, -ddz));
    sea_position = absolute_pos;
    swell = wave;
}
void fragment() {
    // Fine-scale ripples are evaluated per pixel, no extra geometry.
    float ripple = sin(sea_position.x * 0.31 + TIME * 2.2) *
        cos(sea_position.z * 0.27 - TIME * 1.8);
    float choppy = sin((sea_position.x + sea_position.z) * 0.12 - TIME * 1.2);
    float fresnel = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 3.0);
    float tint = clamp(0.36 + 0.22 * swell + ripple * 0.08, 0.05, 0.9);
    vec3 water = mix(ocean_dark.rgb, ocean_shallow.rgb, tint);
    float crest = smoothstep(0.50, 0.89, swell + ripple * 0.17 + choppy * 0.10);
    ALBEDO = mix(water, foam_tint.rgb, crest * 0.38);
    ALBEDO += fresnel * vec3(0.07, 0.14, 0.17);
    ROUGHNESS = mix(0.41, 0.19, clamp(fresnel * 0.7 + crest * 0.2, 0.0, 1.0));
    SPECULAR = 0.8;
    METALLIC = 0.02;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	ocean.material_override = material
	ocean.position.y = -0.3
	add_child(ocean)
	# Cheap animated foam trail behind the moving vessel. Only one quad
	# (no particles or shadows), disabled while the ship is idle.
	wake = MeshInstance3D.new()
	var wake_mesh := PlaneMesh.new()
	wake_mesh.size = Vector2(11.0, 34.0)
	wake.mesh = wake_mesh
	var wake_shader := Shader.new()
	wake_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
void fragment() {
    float v = UV.y;
    float side = abs(UV.x - 0.5) * 2.0;
    float foam = smoothstep(0.55, 0.12, side) *
        smoothstep(0.01, 0.16, v) * (1.0 - smoothstep(0.60, 1.0, v));
    float streaks = sin(UV.y * 42.0 - TIME * 4.0 + UV.x * 5.0) * 0.17;
    ALBEDO = vec3(0.83, 0.96, 1.0);
    ALPHA = clamp((foam + streaks) * 0.53, 0.0, 0.57);
}
"""
	var wake_material := ShaderMaterial.new()
	wake_material.shader = wake_shader
	wake.material_override = wake_material
	wake.visible = false
	add_child(wake)

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
	islands.quality = 0 if low else 1
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
		"yaw": cam_yaw}
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
	# Foamy wake moves with the ship, yet stays level at sea level.
	wake.visible = absf(speed) > 2.0
	wake.position = Vector3(ship.position.x, 0.08, ship.position.z) + \
		Vector3(0, 0, 16.0).rotated(Vector3.UP, ship.rotation.y)
	wake.rotation.y = ship.rotation.y
	var focus := ship.position + Vector3(0, 6, 0)
	var local_id := str(multiplayer.get_unique_id())
	var pirates: Dictionary = current.get("players", {})
	_sync_avatars(pirates, delta)
	if avatars.has(local_id):
		focus = avatars[local_id].global_position + Vector3(0, 2.5, 0)
	islands.set_focus(focus)
	ocean.position.x = focus.x
	ocean.position.z = focus.z
	var orbit := Vector3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch),
		cos(cam_yaw) * cos(cam_pitch))
	var target_camera := focus + orbit * camera_distance
	camera.global_position = camera.global_position.lerp(target_camera,
		minf(delta * 7.0, 1.0))
	camera.look_at(focus, Vector3.UP)
	if GameNet.is_active:
		var nearest := world.closest_island(focus)
		var distance := ship_position.distance_to(Vector3(
			float(world.islands[1]["x"]), 0, float(world.islands[1]["z"])))
		var local_player: Dictionary = pirates.get(local_id, {})
		var mode := "SAILING" if int(current.get("helmsman", 0)) == \
			multiplayer.get_unique_id() else "DECK"
		if not bool(local_player.get("aboard", true)):
			mode = "SWIMMING" if bool(local_player.get("swimming", false)) else "WALKING"
		hud.update_details(speed, str(nearest["name"]), pirates.size(),
			distance, int(current.get("helmsman", 0)) == multiplayer.get_unique_id(),
			int(local_player.get("gold", 0)), bool(local_player.get("one_piece", false)), mode)

func _sync_avatars(pirates: Dictionary, delta: float) -> void:
	for id in avatars.keys():
		if not pirates.has(id):
			avatars[id].queue_free()
			avatars.erase(id)
	for id in pirates:
		var pirate: Dictionary = pirates[id]
		var destination: Vector3
		if bool(pirate.get("aboard", true)):
			destination = ship.to_global(pirate["local"])
		else:
			destination = pirate["world"]
		if not avatars.has(id):
			avatars[id] = _create_avatar(id)
			avatars[id].global_position = destination
		var avatar: Node3D = avatars[id]
		avatar.global_position = avatar.global_position.lerp(destination,
			minf(delta * 12.0, 1.0))
		var swimming := bool(pirate.get("swimming", false))
		var aboard := bool(pirate.get("aboard", true))
		var heading: float = float(pirate.get("yaw", 0.0))
		avatar.rotation.y = ship.rotation.y + heading if aboard else heading
		var pose: Node3D = avatar.get_node("Pose")
		pose.rotation.x = lerpf(pose.rotation.x, 0.55 if swimming else 0.0,
			minf(delta * 6.0, 1.0))
		var bob := sin(Time.get_ticks_msec() * 0.005 + float(id.to_int())) * 0.13
		pose.position.y = lerpf(pose.position.y, bob if swimming else 0.0,
			minf(delta * 6.0, 1.0))
		var left_arm: Node3D = pose.get_node("LeftArm")
		var right_arm: Node3D = pose.get_node("RightArm")
		var left_leg: Node3D = pose.get_node("LeftLeg")
		var right_leg: Node3D = pose.get_node("RightLeg")
		var phase := Time.get_ticks_msec() * (0.005 if swimming else 0.008)
		var stroke := sin(phase + float(id.to_int()))
		var motion := bool(pirate.get("moving", false))
		var effort := 1.0 if motion else 0.15
		left_arm.rotation.x = stroke * (0.85 if swimming else 0.45) * effort
		right_arm.rotation.x = -stroke * (0.85 if swimming else 0.45) * effort
		left_leg.rotation.x = -stroke * 0.32 * effort
		right_leg.rotation.x = stroke * 0.32 * effort

func _create_avatar(id: String) -> Node3D:
	var avatar := Node3D.new()
	avatar.name = "Pirate_" + id
	add_child(avatar)
	var pose := Node3D.new()
	pose.name = "Pose"
	avatar.add_child(pose)
	var jacket := CapsuleMesh.new()
	jacket.radius = 0.53
	jacket.height = 2.3
	var clothes := Color(0.8, 0.14, 0.12) if id == "1" else Color(0.16, 0.40, 0.72)
	_mesh_on(pose, jacket, Vector3(0, 1.2, 0), clothes)
	var head := SphereMesh.new()
	head.radius = 0.45
	head.height = 0.9
	_mesh_on(pose, head, Vector3(0, 2.65, 0), Color(0.97, 0.74, 0.48))
	var hat := CylinderMesh.new()
	hat.top_radius = 0.75
	hat.bottom_radius = 0.94
	hat.height = 0.18
	_mesh_on(pose, hat, Vector3(0, 3.07, 0), Color(0.91, 0.69, 0.24))
	var crown := CylinderMesh.new()
	crown.top_radius = 0.48
	crown.bottom_radius = 0.51
	crown.height = 0.52
	_mesh_on(pose, crown, Vector3(0, 3.31, 0), Color(0.89, 0.69, 0.27))
	var arm_mesh := CapsuleMesh.new()
	arm_mesh.radius = 0.18
	arm_mesh.height = 1.25
	var leg_mesh := CapsuleMesh.new()
	leg_mesh.radius = 0.23
	leg_mesh.height = 1.3
	for side in [-1, 1]:
		var sx: float = float(side)
		var arm := Node3D.new()
		arm.name = "LeftArm" if side < 0 else "RightArm"
		arm.position = Vector3(sx * 0.67, 2.05, 0)
		pose.add_child(arm)
		_mesh_on(arm, arm_mesh, Vector3(sx * 0.10, -0.55, 0), clothes)
		var leg := Node3D.new()
		leg.name = "LeftLeg" if side < 0 else "RightLeg"
		leg.position = Vector3(sx * 0.31, 0.65, 0)
		pose.add_child(leg)
		_mesh_on(leg, leg_mesh, Vector3(0, -0.40, 0), Color(0.31, 0.25, 0.20))
	return avatar

func _mesh_on(parent: Node3D, shape: Mesh, pos: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = shape
	instance.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.87
	instance.material_override = mat
	parent.add_child(instance)

func _unhandled_input(event: InputEvent) -> void:
	if not GameNet.is_active or hud == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw -= event.relative.x * 0.004
		cam_pitch = clampf(cam_pitch + event.relative.y * 0.003, -0.08, 0.90)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
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
