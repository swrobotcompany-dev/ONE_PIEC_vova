class_name HeroVisual
extends Node3D
# Real skinned KayKit Adventurers rigs (CC0), with lightweight bone-attached
# identity accessories. Combat visuals never drive authoritative damage.
const ROGUE_PATH := "res://assets/characters/rogue.glb"
const BARBARIAN_PATH := "res://assets/characters/barbarian.glb"

var hero_kind := ""
var avatar_model: Node3D
var animation_player: AnimationPlayer
var attack_vfx: MeshInstance3D
var hit_vfx: MeshInstance3D
var swing_clock := 0.0
var hit_clock := 0.0
var attack_index := 0
var hit_index := 0

func _ready() -> void:
	if hero_kind == "":
		set_hero("luffy")

func set_hero(kind: String) -> void:
	if hero_kind == kind and avatar_model != null:
		return
	hero_kind = kind
	animation_player = null
	attack_vfx = null
	hit_vfx = null
	swing_clock = 0.0
	for child in get_children():
		# Remove old rig immediately, not after the next rendered frame.
		if child is Node3D:
			child.visible = false
		remove_child(child)
		child.queue_free()
	var path := ROGUE_PATH if kind == "luffy" or kind == "guard_1" else BARBARIAN_PATH
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("Missing rigged character model: " + path)
		return
	avatar_model = packed.instantiate() as Node3D
	add_child(avatar_model)
	avatar_model.scale = Vector3.ONE
	# KayKit rig artwork faces +Z; Godot's forward is -Z.
	# Rotate ONLY the imported rig, never the motion/world-space controller.
	avatar_model.rotation.y = PI
	_find_animation(avatar_model)
	if kind == "luffy":
		_style_luffy()
	elif kind == "zoro":
		_style_zoro()
	else:
		_style_guard()
	_make_combat_fx()

func _find_animation(node: Node) -> void:
	if node is AnimationPlayer:
		animation_player = node
	for child in node.get_children():
		_find_animation(child)
	if node == avatar_model and animation_player != null:
		_play_named("idle", 0.0)

func _play_named(category: String, blend: float) -> bool:
	if animation_player == null:
		return false
	for clip in animation_player.get_animation_list():
		var name := str(clip).to_lower()
		if category in name or (category == "run" and "walk" in name):
			if animation_player.current_animation != clip:
				animation_player.play(clip, blend)
			return true
	return false

func set_motion(mode: String, moving: bool) -> void:
	if avatar_model == null:
		return
	# Never cancel an attack each network snapshot with the idle animation.
	if swing_clock > 0:
		return
	if mode == "jump":
		avatar_model.rotation.x = lerpf(avatar_model.rotation.x, 0.0, 0.16)
		if not _play_named("jump", 0.12):
			_play_named("idle", 0.12)
		return
	if mode == "swim":
		if not _play_named("swim", 0.13):
			_play_named("idle", 0.13)
		avatar_model.rotation.x = lerpf(avatar_model.rotation.x, -0.5, 0.12)
	else:
		avatar_model.rotation.x = lerpf(avatar_model.rotation.x, 0.0, 0.16)
		_play_named("run" if moving else "idle", 0.18)

func show_attack(counter: int) -> void:
	if counter == attack_index:
		return
	attack_index = counter
	if counter <= 0:
		return
	swing_clock = 0.36 if hero_kind == "luffy" else 0.48
	if not _play_named("attack", 0.05):
		_play_named("slash" if hero_kind == "zoro" else "punch", 0.05)
	if attack_vfx != null:
		attack_vfx.visible = true
		attack_vfx.scale = Vector3.ONE

func show_hit(counter: int) -> void:
	if counter == hit_index:
		return
	hit_index = counter
	if counter <= 0:
		return
	hit_clock = 0.26
	if hit_vfx != null:
		hit_vfx.visible = true

func _process(delta: float) -> void:
	if swing_clock > 0:
		swing_clock = maxf(0.0, swing_clock - delta)
		if attack_vfx != null:
			attack_vfx.scale = Vector3.ONE * (1.0 + (1.0 - swing_clock / 0.48) * 0.6)
			attack_vfx.visible = swing_clock > 0.04
	if hit_clock > 0:
		hit_clock = maxf(0.0, hit_clock - delta)
		if hit_vfx != null:
			hit_vfx.visible = hit_clock > 0

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

func _bone_anchor(hints: Array[String], fallback: Vector3) -> Node3D:
	var skeleton := _find_skeleton(avatar_model)
	if skeleton != null:
		for i in range(skeleton.get_bone_count()):
			var name := str(skeleton.get_bone_name(i)).to_lower()
			for term in hints:
				if term in name:
					var attachment := BoneAttachment3D.new()
					attachment.bone_name = skeleton.get_bone_name(i)
					skeleton.add_child(attachment)
					return attachment
	var anchor := Node3D.new()
	anchor.position = fallback
	add_child(anchor)
	return anchor

func _style_luffy() -> void:
	# Straw hat, black spiked hair, open red vest, yellow sash, blue shorts.
	# Worn accessories follow the relevant rig bones during animations.
	var head := _bone_anchor(["head"], Vector3(0, 1.9, 0))
	_cylinder(Vector3(0, 0.36, 0), 0.78, 0.09, Color(0.94, 0.76, 0.34), head)
	_cylinder(Vector3(0, 0.49, 0), 0.45, 0.27, Color(0.92, 0.70, 0.24), head)
	_cylinder(Vector3(0, 0.38, 0), 0.46, 0.05, Color(0.76, 0.12, 0.10), head)
	for i in range(9):
		var angle := TAU * float(i) / 9.0
		var tuft := CylinderMesh.new()
		tuft.top_radius = 0.01
		tuft.bottom_radius = 0.12
		tuft.height = 0.22
		tuft.radial_segments = 6
		_mesh(tuft, Vector3(cos(angle) * 0.31, 0.13, sin(angle) * 0.31),
			Color(0.042, 0.043, 0.052), head)
	var chest := _bone_anchor(["chest", "spine"], Vector3(0, 1.25, 0))
	for side in [-1.0, 1.0]:
		_cloth(chest, Vector3(side * 0.29, -0.07, -0.25),
			Vector3(0.34, 0.89, 0.13), Color(0.85, 0.09, 0.08))
		_cloth(chest, Vector3(side * 0.43, -0.1, -0.23),
			Vector3(0.11, 0.67, 0.16), Color(0.96, 0.15, 0.10))
	var hips := _bone_anchor(["hips", "pelvis"], Vector3(0, 0.85, 0))
	_cloth(hips, Vector3(0, -0.03, 0), Vector3(0.91, 0.23, 0.68),
		Color(0.96, 0.74, 0.26))
	for side in [-1.0, 1.0]:
		_cloth(hips, Vector3(side * 0.23, -0.39, 0),
			Vector3(0.43, 0.45, 0.59), Color(0.13, 0.32, 0.69))
		_cloth(hips, Vector3(side * 0.23, -0.61, 0),
			Vector3(0.43, 0.10, 0.59), Color(0.90, 0.86, 0.65))

func _style_zoro() -> void:
	# Distinct short spiky green hair, green robe, sash and three katanas.
	var head := _bone_anchor(["head"], Vector3(0, 1.9, 0))
	var hair := SphereMesh.new()
	hair.radius = 0.43
	hair.height = 0.33
	hair.radial_segments = 14
	hair.rings = 5
	_mesh(hair, Vector3(0, 0.21, 0), Color(0.13, 0.61, 0.19), head)
	for i in range(12):
		var angle := TAU * float(i) / 12.0
		var spike := CylinderMesh.new()
		spike.top_radius = 0.01
		spike.bottom_radius = 0.13
		spike.height = 0.39
		spike.radial_segments = 6
		var peak := _mesh(spike, Vector3(cos(angle) * 0.33, 0.37, sin(angle) * 0.33),
			Color(0.09, 0.54, 0.17), head)
		peak.rotation.z = cos(angle) * 0.24
		peak.rotation.x = sin(angle) * 0.24
	for i in range(3):
		var gold_ring := TorusMesh.new()
		gold_ring.inner_radius = 0.042
		gold_ring.outer_radius = 0.068
		gold_ring.rings = 4
		gold_ring.ring_segments = 9
		_mesh(gold_ring, Vector3(-0.43, -0.05 - 0.12 * float(i), 0.0),
			Color(0.97, 0.78, 0.27), head)
	var chest := _bone_anchor(["chest", "spine"], Vector3(0, 1.25, 0))
	for side in [-1.0, 1.0]:
		_cloth(chest, Vector3(side * 0.28, -0.15, -0.25),
			Vector3(0.36, 0.91, 0.15), Color(0.15, 0.40, 0.24))
	var hips := _bone_anchor(["hips", "pelvis"], Vector3(0, 0.9, 0))
	_cloth(hips, Vector3(0, -0.05, 0), Vector3(1.0, 0.38, 0.73),
		Color(0.15, 0.49, 0.25))
	for i in range(3):
		var sword := Node3D.new()
		hips.add_child(sword)
		sword.position = Vector3(-0.65, -0.11, (float(i) - 1.0) * 0.20)
		sword.rotation_degrees.z = -28 + i * 12
		_add_sword(sword)

func _style_guard() -> void:
	var variant := int(hero_kind.trim_prefix("guard_")) if hero_kind.begins_with("guard_") else 0
	var head := _bone_anchor(["head"], Vector3(0, 1.9, 0))
	var torso := _bone_anchor(["chest", "spine"], Vector3(0, 1.2, 0))
	var hips := _bone_anchor(["hips", "pelvis"], Vector3(0, 0.9, 0))
	match variant:
		0:
			# Cutlass corsair with broad three-corner hat.
			_cylinder(Vector3(0, 0.32, 0), 0.69, 0.12, Color(0.15, 0.13, 0.20), head)
			_cloth(head, Vector3(0, 0.48, 0), Vector3(0.91, 0.30, 0.52),
				Color(0.20, 0.13, 0.22))
			_cloth(torso, Vector3(0, -0.18, -0.29), Vector3(0.9, 0.76, 0.16),
				Color(0.40, 0.12, 0.15))
			var blade_anchor := Node3D.new()
			hips.add_child(blade_anchor)
			blade_anchor.position = Vector3(0.5, 0, 0.1)
			_add_sword(blade_anchor)
		1:
			# Light raider: bandana, eyepatch and slim dagger.
			_cylinder(Vector3(0, 0.17, 0), 0.45, 0.14, Color(0.72, 0.13, 0.11), head)
			_cloth(head, Vector3(0.19, -0.09, -0.43), Vector3(0.23, 0.16, 0.09),
				Color(0.08, 0.09, 0.12))
			_cloth(torso, Vector3(0, -0.18, -0.27), Vector3(0.77, 0.68, 0.13),
				Color(0.49, 0.37, 0.21))
			var dagger_anchor := Node3D.new()
			hips.add_child(dagger_anchor)
			dagger_anchor.position = Vector3(0.46, -0.1, -0.1)
			dagger_anchor.scale = Vector3.ONE * 0.70
			_add_sword(dagger_anchor)
		_:
			# Armored brute: heavy pauldrons and an iron pot helmet.
			_cylinder(Vector3(0, 0.18, 0), 0.52, 0.35, Color(0.32, 0.36, 0.38), head)
			_cloth(torso, Vector3(0, -0.21, -0.31), Vector3(1.0, 0.84, 0.16),
				Color(0.25, 0.30, 0.33))
			for side in [-1.0, 1.0]:
				var plate := SphereMesh.new()
				plate.radius = 0.39
				plate.height = 0.39
				plate.radial_segments = 8
				plate.rings = 4
				_mesh(plate, Vector3(side * 0.69, 0.11, 0),
					Color(0.39, 0.43, 0.46), torso)

func _cloth(parent: Node3D, pos: Vector3, size: Vector3, tint: Color) -> void:
	var cloth := BoxMesh.new()
	cloth.size = size
	_mesh(cloth, pos, tint, parent)

func _add_sword(parent: Node3D) -> void:
	var blade := BoxMesh.new()
	blade.size = Vector3(0.055, 1.03, 0.10)
	_mesh(blade, Vector3(0, 0.65, 0), Color(0.79, 0.84, 0.89), parent)
	var grip := CylinderMesh.new()
	grip.top_radius = 0.06
	grip.bottom_radius = 0.06
	grip.height = 0.42
	_mesh(grip, Vector3(0, -0.02, 0), Color(0.12, 0.12, 0.20), parent)

func _make_combat_fx() -> void:
	var attack_shape := TorusMesh.new()
	attack_shape.inner_radius = 1.3 if hero_kind == "zoro" else 0.75
	attack_shape.outer_radius = 1.54 if hero_kind == "zoro" else 0.96
	attack_shape.rings = 6
	attack_shape.ring_segments = 24
	attack_vfx = _mesh(attack_shape, Vector3(0, 1.1, -1.8),
		Color(0.4, 0.95, 1.0) if hero_kind == "zoro" else Color(1.0, 0.72, 0.26))
	attack_vfx.rotation_degrees.x = 72.0
	attack_vfx.visible = false
	var hit_shape := SphereMesh.new()
	hit_shape.radius = 0.6
	hit_shape.height = 1.2
	hit_vfx = _mesh(hit_shape, Vector3(0, 1.4, 0), Color(1.0, 0.35, 0.19))
	hit_vfx.visible = false

func _cylinder(pos: Vector3, radius: float, height: float,
		tint: Color, parent: Node3D) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 14
	_mesh(mesh, pos, tint, parent)

func _mesh(mesh: Mesh, pos: Vector3, tint: Color,
		parent: Node3D = null) -> MeshInstance3D:
	var shape := MeshInstance3D.new()
	shape.mesh = mesh
	shape.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = 0.72
	shape.material_override = mat
	(parent if parent != null else self).add_child(shape)
	return shape
