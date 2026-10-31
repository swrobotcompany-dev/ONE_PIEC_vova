class_name IslandStream
extends Node3D

const NEAR_DISTANCE := 950.0
const FAR_DISTANCE := 3300.0
const MAX_DETAILED := 4
const UPDATE_EVERY := 0.5

var world := SeaWorld.new()
var detailed: Dictionary = {}
var distant: Dictionary = {}
var clock := 0.0
var focus := Vector3.ZERO
var quality := 1

func _process(delta: float) -> void:
	clock += delta
	if clock < UPDATE_EVERY:
		return
	clock = 0.0
	_refresh()

func set_focus(new_focus: Vector3) -> void:
	focus = new_focus

func set_quality(new_quality: int) -> void:
	if quality == new_quality:
		return
	quality = new_quality
	for id in detailed:
		detailed[id].queue_free()
	detailed.clear()
	clock = UPDATE_EVERY

func _refresh() -> void:
	var nearby: Array[Dictionary] = []
	for island in world.islands:
		var c := Vector3(float(island["x"]), 0, float(island["z"]))
		var distance := Vector2(c.x - focus.x, c.z - focus.z).length()
		if distance < FAR_DISTANCE + float(island["radius"]):
			nearby.append({"island": island, "distance": distance})
	nearby.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance"]) < float(b["distance"]))
	var need_detailed: Dictionary = {}
	var need_distant: Dictionary = {}
	var used := 0
	for entry in nearby:
		var island: Dictionary = entry["island"]
		var id: int = island["id"]
		if float(entry["distance"]) < NEAR_DISTANCE + float(island["radius"]) and used < MAX_DETAILED:
			need_detailed[id] = island
			used += 1
		else:
			need_distant[id] = island
	for id in detailed.keys():
		if not need_detailed.has(id):
			detailed[id].queue_free()
			detailed.erase(id)
	for id in distant.keys():
		if not need_distant.has(id):
			distant[id].queue_free()
			distant.erase(id)
	for id in need_detailed:
		if distant.has(id):
			distant[id].queue_free()
			distant.erase(id)
		if not detailed.has(id):
			detailed[id] = _build_island(need_detailed[id])
	for id in need_distant:
		if detailed.has(id):
			continue
		if not distant.has(id):
			distant[id] = _build_proxy(need_distant[id])
	# A standalone `godot --script res://tools/smoke.gd` does not initialize
	# project autoload globals. Resolve the session node dynamically instead:
	# the same island streamer works in a full client and in the smoke test.
	var looted: Array = []
	var session: Node = null
	if is_inside_tree() and get_tree() != null:
		session = get_tree().root.get_node_or_null("GameNet")
	if session != null:
		var session_state: Dictionary = session.get("state")
		looted = session_state.get("looted", [])
		var taken: Array = session_state.get("fruits_taken", [])
		for id in detailed:
			var fruit: Node3D = detailed[id].get_node_or_null("DevilFruit")
			if fruit != null:
				fruit.visible = not (id in taken)
	for id in detailed:
		var treasure: Node3D = detailed[id].get_node_or_null("Treasure")
		if treasure != null:
			treasure.visible = not (id in looted)

func _build_proxy(info: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(float(info["x"]), 0, float(info["z"]))
	add_child(root)
	var shell := CylinderMesh.new()
	shell.top_radius = float(info["radius"]) * 0.48
	shell.bottom_radius = float(info["radius"])
	shell.height = maxf(12.0, float(info["height"]) * 0.70)
	shell.radial_segments = 9
	var instance := MeshInstance3D.new()
	instance.mesh = shell
	instance.position.y = shell.height * 0.35
	instance.material_override = _mat(_land_color(info))
	root.add_child(instance)
	return root

func _build_island(info: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(float(info["x"]), 0, float(info["z"]))
	add_child(root)
	var radius: float = float(info["radius"])
	var mesh_builder := SurfaceTool.new()
	mesh_builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 36 if quality == 1 else 18
	var segments := 96 if quality == 1 else 48
	var palette := _land_color(info)
	for ring in range(rings):
		var inner := radius * float(ring) / float(rings)
		var outer := radius * float(ring + 1) / float(rings)
		for section in range(segments):
			var a := TAU * float(section) / float(segments)
			var b := TAU * float(section + 1) / float(segments)
			var p1 := _terrain_point(info, inner, a)
			var p2 := _terrain_point(info, inner, b)
			var p3 := _terrain_point(info, outer, a)
			var p4 := _terrain_point(info, outer, b)
			_vertex(mesh_builder, p1, info, palette)
			_vertex(mesh_builder, p2, info, palette)
			_vertex(mesh_builder, p3, info, palette)
			_vertex(mesh_builder, p2, info, palette)
			_vertex(mesh_builder, p4, info, palette)
			_vertex(mesh_builder, p3, info, palette)
	mesh_builder.generate_normals()
	var land := MeshInstance3D.new()
	land.mesh = mesh_builder.commit()
	var land_material := StandardMaterial3D.new()
	land_material.vertex_color_use_as_albedo = true
	# Render the ground from both sides as a safeguard against winding
	# differences in steep procedural cliffs; never show sea through terrain.
	land_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	land_material.roughness = 0.96
	land.material_override = land_material
	root.add_child(land)
	if info["biome"] != "snow" and info["biome"] != "desert":
		_add_palms(root, info)
	_add_treasure(root, info)
	_add_fruit(root, info)
	_add_details(root, info)
	var label := Label3D.new()
	label.text = str(info["name"]) + "  •  " + str(info["biome"]).to_upper()
	label.font_size = 42
	label.pixel_size = 0.065
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = float(info["height"]) + 28.0
	label.modulate = Color(1.0, 0.9, 0.65, 0.9)
	root.add_child(label)
	return root

func _add_treasure(root: Node3D, info: Dictionary) -> void:
	var prize := Node3D.new()
	prize.name = "Treasure"
	var center := Vector3(float(info["x"]), 0, float(info["z"]))
	prize.position.y = world.ground_height(info, center) + 1.3
	root.add_child(prize)
	var body := BoxMesh.new()
	body.size = Vector3(6, 2.6, 4)
	var box := MeshInstance3D.new()
	box.mesh = body
	box.material_override = _mat(Color(0.26, 0.12, 0.07))
	prize.add_child(box)
	var lid := BoxMesh.new()
	lid.size = Vector3(6.3, 0.65, 4.3)
	var lid_mesh := MeshInstance3D.new()
	lid_mesh.mesh = lid
	lid_mesh.position.y = 1.7
	lid_mesh.material_override = _mat(Color(0.96, 0.73, 0.19) if int(info["id"]) == 1 else Color(0.75, 0.52, 0.15))
	prize.add_child(lid_mesh)

func _add_fruit(root: Node3D, info: Dictionary) -> void:
	var fruit_root := Node3D.new()
	fruit_root.name = "DevilFruit"
	fruit_root.position.y = float(info["height"]) + 5.0
	fruit_root.position.x = 9.0
	fruit_root.position.z = 0.0
	root.add_child(fruit_root)
	var body := SphereMesh.new()
	body.radius = 1.7
	body.height = 3.1
	body.radial_segments = 12
	body.rings = 7
	var sphere := MeshInstance3D.new()
	sphere.mesh = body
	sphere.material_override = _mat(Color(0.62, 0.23, 0.79))
	fruit_root.add_child(sphere)
	var stem := CylinderMesh.new()
	stem.top_radius = 0.13
	stem.bottom_radius = 0.16
	stem.height = 0.9
	var stem_node := MeshInstance3D.new()
	stem_node.mesh = stem
	stem_node.position.y = 1.9
	stem_node.material_override = _mat(Color(0.26, 0.62, 0.26))
	fruit_root.add_child(stem_node)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.65
	ring.outer_radius = 0.86
	ring.rings = 6
	ring.ring_segments = 14
	for i in range(3):
		var swirl := MeshInstance3D.new()
		swirl.mesh = ring
		swirl.rotation = Vector3(0.55 + i * 0.6, 0, i * 0.65)
		swirl.scale = Vector3.ONE * (0.8 + float(i) * 0.17)
		swirl.material_override = _mat(Color(0.93, 0.48, 0.92))
		fruit_root.add_child(swirl)
	var label := Label3D.new()
	label.text = "DEVIL FRUIT   •   DEFEAT GUARDS"
	label.position.y = 4.6
	label.pixel_size = 0.06
	label.font_size = 33
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1, 0.86, 0.94)
	fruit_root.add_child(label)

func _add_details(root: Node3D, info: Dictionary) -> void:
	# A few large landmarks read better than hundreds of draw calls.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(info["id"]) * 3571 + 219
	for i in range(15 if quality == 1 else 5):
		var angle := rng.randf_range(0.0, TAU)
		var distance := rng.randf_range(0.32, 0.72) * world.coast_radius(info, angle)
		var x := cos(angle) * distance
		var z := sin(angle) * distance
		var h := world.ground_height(info, Vector3(float(info["x"]) + x, 0, float(info["z"]) + z))
		var rock := SphereMesh.new()
		rock.radius = rng.randf_range(1.7, 4.2)
		rock.height = rng.randf_range(2.0, 4.7)
		rock.radial_segments = 6
		rock.rings = 4
		var mesh := MeshInstance3D.new()
		mesh.mesh = rock
		mesh.position = Vector3(x, h, z)
		var rock_tint := Color(0.46, 0.48, 0.47)
		match str(info["biome"]):
			"desert", "mesa": rock_tint = Color(0.74, 0.49, 0.29)
			"snow": rock_tint = Color(0.81, 0.89, 0.92)
			"volcanic": rock_tint = Color(0.22, 0.23, 0.25)
			"lagoon": rock_tint = Color(0.52, 0.64, 0.59)
		mesh.material_override = _mat(rock_tint)
		root.add_child(mesh)
	for building in world.buildings_for(info):
		if building["kind"] == "hut":
			_add_hut(root, info, building["offset"])
		else:
			_add_watchtower(root, info, building["offset"])

func _add_hut(root: Node3D, info: Dictionary, offset: Vector2) -> void:
	var hut := Node3D.new()
	var point := Vector3(float(info["x"]) + offset.x, 0, float(info["z"]) + offset.y)
	hut.position = Vector3(offset.x, world.ground_height(info, point), offset.y)
	root.add_child(hut)
	_add_solid_body(hut, Vector3(0, 3.6, 0), Vector3(12, 7.2, 10))
	# Walls, porch, door, windows and roof: small primitive meshes, no textures.
	_box_at(hut, Vector3(0, 3.6, 0), Vector3(12, 7.2, 10), Color(0.74, 0.57, 0.36))
	_box_at(hut, Vector3(0, 0.28, -7.3), Vector3(15, 0.5, 5.5), Color(0.42, 0.27, 0.16))
	_box_at(hut, Vector3(0, 2.6, -5.08), Vector3(2.7, 5.0, 0.24), Color(0.30, 0.18, 0.09))
	for side in [-1.0, 1.0]:
		_box_at(hut, Vector3(3.2 * side, 4.1, -5.10), Vector3(2.0, 2.2, 0.28), Color(0.17, 0.38, 0.42))
		_box_at(hut, Vector3(3.2 * side, 4.1, -5.27), Vector3(0.14, 2.4, 0.26), Color(0.94, 0.77, 0.48))
		_box_at(hut, Vector3(3.2 * side, 4.1, -5.29), Vector3(2.1, 0.14, 0.26), Color(0.94, 0.77, 0.48))
		_box_at(hut, Vector3(6.2 * side, 4.5, 0), Vector3(0.26, 2.6, 3.6), Color(0.24, 0.39, 0.41))
		for z in [-4.0, 4.0]:
			_box_at(hut, Vector3(5.4 * side, 4.2, z), Vector3(0.7, 0.7, 0.7), Color(0.42, 0.29, 0.16))
	var roof := PrismMesh.new()
	roof.size = Vector3(15.5, 5.6, 13)
	var roof_mesh := MeshInstance3D.new()
	roof_mesh.mesh = roof
	roof_mesh.position.y = 9.5
	roof_mesh.material_override = _mat(Color(0.53, 0.23, 0.12))
	hut.add_child(roof_mesh)
	for x in [-6.1, 6.1]:
		_box_at(hut, Vector3(x, 3.4, -8.6), Vector3(0.50, 6.8, 0.5), Color(0.37, 0.21, 0.10))
	var chimney := CylinderMesh.new()
	chimney.height = 3.2
	chimney.top_radius = 0.72
	chimney.bottom_radius = 0.82
	chimney.radial_segments = 6
	var pipe := MeshInstance3D.new()
	pipe.mesh = chimney
	pipe.position = Vector3(3.5, 11.7, 2.4)
	pipe.material_override = _mat(Color(0.41, 0.41, 0.38))
	hut.add_child(pipe)

func _add_watchtower(root: Node3D, info: Dictionary, offset: Vector2) -> void:
	var point := Vector3(float(info["x"]) + offset.x, 0, float(info["z"]) + offset.y)
	var height := world.ground_height(info, point)
	var tower := Node3D.new()
	tower.position = Vector3(offset.x, height, offset.y)
	root.add_child(tower)
	_add_solid_body(tower, Vector3(0, 5.5, 0), Vector3(8, 11, 8))
	_box_at(tower, Vector3(0, 10.0, 0), Vector3(8, 0.85, 8), Color(0.55, 0.34, 0.17))
	for x in [-3.1, 3.1]:
		for z in [-3.1, 3.1]:
			_box_at(tower, Vector3(x, 5.1, z), Vector3(0.72, 10.2, 0.72), Color(0.35, 0.22, 0.12))
			_box_at(tower, Vector3(x, 11.4, z), Vector3(0.62, 2.2, 0.62), Color(0.35, 0.22, 0.12))
	_box_at(tower, Vector3(0, 12.1, 0), Vector3(9.0, 0.45, 9.0), Color(0.53, 0.25, 0.15))
	var banner := PlaneMesh.new()
	banner.size = Vector2(3, 4.7)
	var flag := MeshInstance3D.new()
	flag.mesh = banner
	flag.position = Vector3(3.2, 15.2, 0)
	flag.rotation_degrees.x = 90
	flag.material_override = _mat(Color(0.84, 0.24, 0.16))
	tower.add_child(flag)

func _add_solid_body(parent: Node3D, center: Vector3, size: Vector3) -> void:
	# Local visual collision duplicates the server's shared AABB footprints;
	# it also allows future camera raycasts and physics interactions.
	var solid := StaticBody3D.new()
	solid.collision_layer = 1
	solid.collision_mask = 0
	solid.position = center
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	solid.add_child(collision)
	parent.add_child(solid)

func _box_at(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = box
	instance.position = pos
	instance.material_override = _mat(color)
	parent.add_child(instance)

func _terrain_point(info: Dictionary, radius: float, angle: float) -> Vector3:
	var coast := world.coast_radius(info, angle)
	var r := radius / maxf(float(info["radius"]), 1.0) * coast
	var x := cos(angle) * r
	var z := sin(angle) * r
	var world_pos := Vector3(float(info["x"]) + x, 0, float(info["z"]) + z)
	return Vector3(x, world.ground_height(info, world_pos), z)

func _vertex(tool: SurfaceTool, point: Vector3, info: Dictionary, base: Color) -> void:
	var wpos := Vector3(point.x + float(info["x"]), 0, point.z + float(info["z"]))
	var shore_ratio := world.terrain_zone(info, wpos)
	var biome := str(info["biome"])
	var sand := Color(0.86, 0.72, 0.48)
	if biome == "snow":
		sand = Color(0.62, 0.72, 0.77)
	elif biome == "volcanic":
		sand = Color(0.17, 0.18, 0.21)
	elif biome == "mesa":
		sand = Color(0.71, 0.39, 0.22)
	elif biome == "desert":
		sand = Color(0.91, 0.78, 0.50)
	var beach := smoothstep(0.76, 0.93, shore_ratio)
	var color := base.lerp(sand, beach)
	var height_fraction := point.y / maxf(float(info["height"]), 1.0)
	if height_fraction > 0.54 and shore_ratio < 0.67:
		var peaks := Color(0.54, 0.55, 0.55)
		if biome == "snow":
			peaks = Color(0.94, 0.96, 0.98)
		elif biome == "volcanic":
			peaks = Color(0.25, 0.23, 0.26)
		elif biome == "mesa":
			peaks = Color(0.79, 0.40, 0.25)
		elif biome == "desert":
			peaks = Color(0.83, 0.64, 0.38)
		color = color.lerp(peaks, clampf((height_fraction - 0.54) * 1.35, 0, 0.82))
	var jitter := sin(point.x * 0.087 + point.z * 0.049) * 0.045
	tool.set_color(color.lightened(maxf(0, jitter)).darkened(maxf(0, -jitter)))
	tool.add_vertex(point)

func _add_palms(root: Node3D, info: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(info["id"]) * 1337 + 789
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.28
	trunk.bottom_radius = 0.55
	trunk.height = 7.5
	trunk.radial_segments = 5
	var crown := _make_palm_fronds()
	var count := 42 if quality == 1 else 10
	var stems := MultiMesh.new()
	stems.transform_format = MultiMesh.TRANSFORM_3D
	stems.mesh = trunk
	stems.instance_count = count
	var leaves := MultiMesh.new()
	leaves.transform_format = MultiMesh.TRANSFORM_3D
	leaves.mesh = crown
	leaves.instance_count = count
	for i in range(count):
		var angle := rng.randf_range(0.0, TAU)
		var distance := rng.randf_range(0.2, 0.69) * world.coast_radius(info, angle)
		var x := cos(angle) * distance
		var z := sin(angle) * distance
		var h := world.ground_height(info, Vector3(float(info["x"]) + x,
			0, float(info["z"]) + z))
		var scale := rng.randf_range(0.7, 1.25)
		stems.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(scale,
			scale, scale)), Vector3(x, h + 3.75 * scale, z)))
		leaves.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(scale,
			scale, scale)), Vector3(x, h + 8.3 * scale, z)))
	var trunk_mesh := MultiMeshInstance3D.new()
	trunk_mesh.multimesh = stems
	trunk_mesh.material_override = _mat(Color(0.42, 0.23, 0.1))
	root.add_child(trunk_mesh)
	var leaves_mesh := MultiMeshInstance3D.new()
	leaves_mesh.multimesh = leaves
	leaves_mesh.material_override = _mat(Color(0.16, 0.49, 0.25))
	root.add_child(leaves_mesh)

func _make_palm_fronds() -> ArrayMesh:
	# Curved six-leaf canopy, roughly 70 triangles. One MultiMesh draw call
	# for all canopies, unlike individual spherical "lollipop" trees.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for leaf in range(7):
		var angle := TAU * float(leaf) / 7.0
		var direction := Vector3(cos(angle), 0, sin(angle))
		var across := Vector3(-sin(angle), 0, cos(angle))
		for segment in range(3):
			var t0 := float(segment) / 3.0
			var t1 := float(segment + 1) / 3.0
			var center0 := direction * (t0 * 5.8) + Vector3.UP * (0.8 - t0 * t0 * 3.2)
			var center1 := direction * (t1 * 5.8) + Vector3.UP * (0.8 - t1 * t1 * 3.2)
			var w0 := sin((0.1 + t0) * PI) * 1.45
			var w1 := sin((0.1 + t1) * PI) * 1.45
			_tri(tool, center0 - across * w0, center0 + across * w0, center1 - across * w1)
			_tri(tool, center0 + across * w0, center1 + across * w1, center1 - across * w1)
	tool.generate_normals()
	return tool.commit()

func _tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)

func _land_color(info: Dictionary) -> Color:
	match str(info["biome"]):
		"desert": return Color(0.87, 0.65, 0.34)
		"mesa": return Color(0.66, 0.36, 0.22)
		"lagoon": return Color(0.28, 0.68, 0.51)
		"volcanic": return Color(0.26, 0.29, 0.28)
		"rocky": return Color(0.45, 0.53, 0.46)
		"jungle": return Color(0.16, 0.48, 0.25)
		"snow": return Color(0.88, 0.93, 0.93)
		"legend": return Color(0.36, 0.56, 0.69)
		_: return Color(0.31, 0.66, 0.39)

func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
