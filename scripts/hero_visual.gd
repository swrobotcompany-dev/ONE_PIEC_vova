class_name HeroVisual
extends Node3D
# KayKit Adventurers CC0 GLB (rigged, animated) is bundled into native builds.
# Custom lightweight accessories distinguish the One Piece heroes.
const ROGUE_PATH := "res://assets/characters/rogue.glb"
const BARBARIAN_PATH := "res://assets/characters/barbarian.glb"

var hero_kind := ""
var avatar_model: Node3D
var animation_player: AnimationPlayer
var swing_clock := 0.0
var attack_index := -1

func _ready() -> void:
	if hero_kind == "":
		set_hero("luffy")

func set_hero(kind: String) -> void:
	if hero_kind == kind and avatar_model != null:
		return
	hero_kind = kind
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var source := BARBARIAN_PATH if kind == "zoro" else ROGUE_PATH
	if ResourceLoader.exists(source):
		var packed := load(source) as PackedScene
		if packed != null:
			avatar_model = packed.instantiate() as Node3D
			add_child(avatar_model)
			avatar_model.scale = Vector3.ONE * 1.1
			_find_animation(avatar_model)
	else:
		# Models are fetched by the Docker build, not stored as heavy addons.
		push_warning("Missing character asset: " + source + " (run tools/fetch_models.sh)")
		avatar_model = Node3D.new()
		add_child(avatar_model)
	if kind == "luffy":
		_style_luffy()
	elif kind == "zoro":
		_style_zoro()
	else:
		_style_guard()

func _find_animation(node: Node) -> void:
	if node is AnimationPlayer:
		animation_player = node
		for animation_name in animation_player.get_animation_list():
			if "idle" in str(animation_name).to_lower():
				animation_player.play(animation_name)
				break
	for child in node.get_children():
		_find_animation(child)

func set_motion(mode: String, moving: bool) -> void:
	# Avoid allocating nodes or restarting animations on each snapshot.
	if animation_player == null:
		return
	var desired := "idle"
	if mode == "swim":
		desired = "swim"
	elif moving:
		desired = "run"
	for anim in animation_player.get_animation_list():
		var name := str(anim).to_lower()
		if desired in name or (desired == "run" and "walk" in name):
			if animation_player.current_animation != anim:
				animation_player.play(anim, 0.18)
			return

func show_attack(counter: int) -> void:
	if counter == attack_index:
		return
	attack_index = counter
	if animation_player == null or counter == 0:
		return
	for anim in animation_player.get_animation_list():
		var name := str(anim).to_lower()
		if "attack" in name or "slash" in name or "punch" in name:
			animation_player.play(anim, 0.05)
			return

func _style_luffy() -> void:
	# Straw hat, scarlet open vest, blue shorts, golden sash.
	_cylinder(Vector3(0, 1.93, 0), 0.80, 0.10, Color(0.93, 0.72, 0.30))
	_cylinder(Vector3(0, 2.06, 0), 0.50, 0.25, Color(0.94, 0.73, 0.31))
	_cylinder(Vector3(0, 1.97, 0), 0.53, 0.07, Color(0.72, 0.17, 0.13))
	_box(Vector3(-0.21, 1.05, -0.24), Vector3(0.35, 0.69, 0.09), Color(0.75, 0.11, 0.08))
	_box(Vector3(0.21, 1.05, -0.24), Vector3(0.35, 0.69, 0.09), Color(0.75, 0.11, 0.08))
	_box(Vector3(0, 0.75, 0), Vector3(0.88, 0.13, 0.68), Color(0.89, 0.69, 0.21))

func _style_zoro() -> void:
	# Distinct moss-green hair, green waist sash and three katana.
	var hair := SphereMesh.new()
	hair.radius = 0.49
	hair.height = 0.5
	hair.radial_segments = 11
	hair.rings = 5
	_mesh(hair, Vector3(0, 1.85, 0.0), Color(0.13, 0.57, 0.19))
	_box(Vector3(0, 0.75, 0), Vector3(0.97, 0.19, 0.76), Color(0.14, 0.43, 0.18))
	for i in range(3):
		# Three unique blades at the left hip (compact mesh, no texture atlas).
		var sword := Node3D.new()
		add_child(sword)
		sword.position = Vector3(-0.64, 0.96, (float(i) - 1.0) * 0.18)
		sword.rotation_degrees.z = -26 + i * 11
		_add_sword(sword)

func _style_guard() -> void:
	_cylinder(Vector3(0, 1.95, 0), 0.52, 0.20, Color(0.36, 0.14, 0.11))
	_box(Vector3(0, 1.02, -0.25), Vector3(0.67, 0.57, 0.1), Color(0.19, 0.19, 0.33))
	var sword := Node3D.new()
	sword.position = Vector3(-0.52, 0.75, 0)
	add_child(sword)
	_add_sword(sword)

func _add_sword(parent: Node3D) -> void:
	var blade := BoxMesh.new()
	blade.size = Vector3(0.055, 1.15, 0.11)
	_mesh(blade, Vector3(0, 0.71, 0), Color(0.79, 0.86, 0.89), parent)
	var grip := CylinderMesh.new()
	grip.top_radius = 0.065
	grip.bottom_radius = 0.065
	grip.height = 0.48
	_mesh(grip, Vector3(0, -0.04, 0), Color(0.15, 0.17, 0.25), parent)
	var guard := BoxMesh.new()
	guard.size = Vector3(0.31, 0.06, 0.17)
	_mesh(guard, Vector3.ZERO, Color(0.90, 0.72, 0.29), parent)

func _box(pos: Vector3, size: Vector3, tint: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_mesh(mesh, pos, tint)

func _cylinder(pos: Vector3, radius: float, height: float, tint: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	_mesh(mesh, pos, tint)

func _mesh(mesh: Mesh, pos: Vector3, tint: Color, parent: Node3D = null) -> void:
	var shape := MeshInstance3D.new()
	shape.mesh = mesh
	shape.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = 0.83
	shape.material_override = mat
	(parent if parent != null else self).add_child(shape)
