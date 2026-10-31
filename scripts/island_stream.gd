class_name IslandStream
extends Node3D

const NEAR_DISTANCE := 680.0
const FAR_DISTANCE := 3300.0
const MAX_DETAILED := 3
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
	var session := get_node_or_null("/root/GameNet")
	if session != null:
		var session_state: Dictionary = session.get("state")
		looted = session_state.get("looted", [])
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
	var rings := 12
	var segments := 40
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
			_vertex(mesh_builder, p1, radius, palette)
			_vertex(mesh_builder, p2, radius, palette)
			_vertex(mesh_builder, p3, radius, palette)
			_vertex(mesh_builder, p2, radius, palette)
			_vertex(mesh_builder, p4, radius, palette)
			_vertex(mesh_builder, p3, radius, palette)
	mesh_builder.generate_normals()
	var land := MeshInstance3D.new()
	land.mesh = mesh_builder.commit()
	var land_material := StandardMaterial3D.new()
	land_material.vertex_color_use_as_albedo = true
	land_material.roughness = 0.96
	land.material_override = land_material
	root.add_child(land)
	_add_shore_foam(root, info)
	_add_rocks(root, info)
	if info["biome"] != "snow" and info["biome"] != "desert":
		_add_palms(root, info)
	_add_treasure(root, info)
	var label := Label3D.new()
	label.text = str(info["name"])
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

func _terrain_point(info: Dictionary, radius: float, angle: float) -> Vector3:
	var x := cos(angle) * radius
	var z := sin(angle) * radius
	var world_pos := Vector3(float(info["x"]) + x, 0, float(info["z"]) + z)
	return Vector3(x, world.ground_height(info, world_pos), z)

func _vertex(tool: SurfaceTool, point: Vector3, radius: float, base: Color) -> void:
	var t := point.length() / maxf(radius, 1.0)
	var sand := Color(0.87, 0.76, 0.53)
	if base.b > 0.8:
		sand = Color(0.84, 0.91, 0.91)
	var color := sand.lerp(base, clampf((1.0 - t) * 4.7, 0.0, 1.0))
	# Tiny vertex-based color variation without textures/shader lookups.
	var noise := sin(point.x * 0.17 + point.z * 0.11) *
		cos(point.z * 0.19 - point.y * 0.06) * 0.055
	color = color.lightened(noise) if noise > 0.0 else color.darkened(-noise)
	tool.set_color(color)
	tool.add_vertex(point)

# White, translucent surf edge separates islands from flat ocean.
# One mesh per detailed island, disabled for distant LODs.
func _add_shore_foam(root: Node3D, info: Dictionary) -> void:
	var radius: float = float(info["radius"])
	var surf := TorusMesh.new()
	surf.inner_radius = radius * 0.985
	surf.outer_radius = radius * 1.025
	surf.rings = 5
	surf.ring_segments = 72
	var band := MeshInstance3D.new()
	band.mesh = surf
	band.position.y = 0.05
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.79, 0.95, 0.93, 0.68)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	band.material_override = material
	root.add_child(band)

# Scattered low-poly rocks provide depth and scale. MultiMesh keeps each
# island at one draw call for all of its stones.
func _add_rocks(root: Node3D, info: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(info["id"]) * 4111 + 77
	var rock := SphereMesh.new()
	rock.radius = 1.0
	rock.height = 2.0
	rock.radial_segments = 7
	rock.rings = 4
	var count := 24 if quality == 1 else 8
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = rock
	multi.instance_count = count
	for i in range(count):
		var a := rng.randf_range(0.0, TAU)
		var d := rng.randf_range(0.33, 0.87) * float(info["radius"])
		var x := cos(a) * d
		var z := sin(a) * d
		var y := world.ground_height(info, Vector3(float(info["x"]) + x,
			0.0, float(info["z"]) + z))
		var scale := rng.randf_range(0.7, 2.5)
		var transform := Transform3D(Basis().scaled(Vector3(scale,
			scale * rng.randf_range(0.55, 1.0), scale)), Vector3(x, y + 0.35, z))
		multi.set_instance_transform(i, transform)
	var rocks := MultiMeshInstance3D.new()
	rocks.multimesh = multi
	rocks.material_override = _mat(Color(0.41, 0.47, 0.45) if
		str(info["biome"]) != "desert" else Color(0.68, 0.53, 0.37))
	root.add_child(rocks)

func _add_palms(root: Node3D, info: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(info["id"]) * 1337 + 789
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.28
	trunk.bottom_radius = 0.55
	trunk.height = 7.5
	trunk.radial_segments = 5
	var crown := SphereMesh.new()
	crown.radius = 4.0
	crown.height = 5.5
	crown.radial_segments = 7
	crown.rings = 3
	var count := 18 if quality == 1 else 7
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
		var distance := rng.randf_range(0.2, 0.72) * float(info["radius"])
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

func _land_color(info: Dictionary) -> Color:
	match str(info["biome"]):
		"desert": return Color(0.86, 0.62, 0.34)
		"rocky": return Color(0.45, 0.53, 0.46)
		"jungle": return Color(0.16, 0.48, 0.25)
		"snow": return Color(0.88, 0.93, 0.93)
		"legend": return Color(0.36, 0.56, 0.69)
		_: return Color(0.31, 0.66, 0.39)

func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	return m
