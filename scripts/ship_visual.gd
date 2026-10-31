class_name PirateShip
extends Node3D
# All meshes are primitive, so there are no external asset downloads.
var hull_material: StandardMaterial3D
var foam_material: StandardMaterial3D

func _ready() -> void:
	hull_material = _material(Color(0.27, 0.13, 0.07))
	foam_material = _material(Color(0.97, 0.87, 0.65))
	_build_tapered_hull()
	_box(Vector3(7.3, 0.45, 14.5), Vector3(0, 2.4, 0), _material(Color(0.57, 0.33, 0.16)))
	_box(Vector3(6.4, 2.3, 4.4), Vector3(0, 3.1, 5.5), hull_material)
	_box(Vector3(6.0, 0.35, 4.1), Vector3(0, 4.3, 5.5), foam_material)
	_box(Vector3(2.0, 1.8, 4.0), Vector3(0, 3.4, -5.4), hull_material)
	_box(Vector3(0.7, 0.6, 4.5), Vector3(0, 2.4, -10.0), foam_material)
	for side in [-1, 1]:
		_box(Vector3(0.25, 1.3, 15.0), Vector3(float(side) * 3.7, 3.1, 0), hull_material)
		for z in [-5.0, 0.0, 5.0]:
			_box(Vector3(0.25, 0.8, 0.25), Vector3(float(side) * 3.7, 3.7, z), foam_material)
	# Mainmast and foremast.
	for mast_z in [-1.5, -5.9]:
		var mast := CylinderMesh.new()
		mast.top_radius = 0.17
		mast.bottom_radius = 0.26
		mast.height = 15.0 if mast_z > -3.0 else 11.0
		_mesh(mast, Vector3(0, 8.8 if mast_z > -3.0 else 6.5, mast_z), hull_material)
		var sail := PlaneMesh.new()
		sail.size = Vector2(9.5 if mast_z > -3.0 else 6.0, 7.0 if mast_z > -3.0 else 4.0)
		var sail_node := _mesh(sail, Vector3(0, 10.4 if mast_z > -3.0 else 8.1, mast_z),
			_material(Color(0.99, 0.93, 0.76), true))
		sail_node.rotation_degrees.x = 90.0
		_box(Vector3(10.0 if mast_z > -3 else 6.5, 0.25, 0.25),
			Vector3(0, 13.9 if mast_z > -3 else 10.1, mast_z), hull_material)
	# A distinct straw-hat-style gold pirate pennant.
	var flag := PlaneMesh.new()
	flag.size = Vector2(2.5, 1.6)
	var flag_mesh := _mesh(flag, Vector3(1.25, 16.0, -1.5),
		_material(Color(0.95, 0.69, 0.17), true))
	flag_mesh.rotation_degrees.x = 90.0
	# Warm lanterns, gold trim and rigging make the silhouette readable at sea.
	for side in [-1, 1]:
		for z in [-5.8, 5.7]:
			var lantern := SphereMesh.new()
			lantern.radius = 0.33
			lantern.height = 0.62
			var glow := _material(Color(1.0, 0.71, 0.27))
			glow.emission_enabled = true
			glow.emission = Color(1.0, 0.54, 0.10)
			glow.emission_energy_multiplier = 1.4
			_mesh(lantern, Vector3(float(side) * 3.55, 3.65, z), glow)
	_box(Vector3(7.1, 0.16, 0.21), Vector3(0, 2.75, -7.3), foam_material)
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.7
	wheel.bottom_radius = 0.7
	wheel.height = 0.22
	var wheel_node := _mesh(wheel, Vector3(0, 4.1, 3.2), foam_material)
	wheel_node.rotation_degrees.z = 90.0
	_add_ship_details()

func _add_ship_details() -> void:
	# Details reuse simple materials and meshes; no downloadable 4K textures.
	var dark_wood := _material(Color(0.21, 0.105, 0.063))
	var brass := _material(Color(0.85, 0.64, 0.25))
	var iron := _material(Color(0.14, 0.18, 0.20))
	var glass := _material(Color(0.21, 0.50, 0.56))
	# Deck planks, subtle gaps and a clear walkway to the helm.
	for i in range(10):
		var z := -6.6 + float(i) * 1.38
		_box(Vector3(6.95, 0.04, 0.045), Vector3(0, 2.66, z), dark_wood)
	for side in [-1.0, 1.0]:
		# Three dark cannon barrels and port frames on each broadside.
		for z in [-4.8, -0.8, 3.1]:
			_box(Vector3(0.27, 1.25, 1.8),
				Vector3(side * 3.92, 2.23, z), dark_wood)
			var barrel := CylinderMesh.new()
			barrel.height = 2.25
			barrel.top_radius = 0.31
			barrel.bottom_radius = 0.36
			barrel.radial_segments = 9
			var gun := _mesh(barrel, Vector3(side * 4.24, 2.50, z), iron)
			gun.rotation_degrees.z = 90.0
			_box(Vector3(0.8, 0.22, 1.0),
				Vector3(side * 3.52, 2.60, z), brass)
		for z in [5.5, 6.45, 7.3]:
			_box(Vector3(0.2, 0.6, 0.45),
				Vector3(side * 3.04, 3.22, z), glass)
	# Stern cabin windows and brass inlays.
	for x in [-2.1, 0.0, 2.1]:
		_box(Vector3(1.23, 1.15, 0.12),
			Vector3(x, 3.26, 7.76), glass)
		_box(Vector3(1.33, 0.10, 0.16),
			Vector3(x, 3.88, 7.81), brass)
	# Crossbeams, taut rigging and bowsprit create a more ship-like silhouette.
	_rope(Vector3(0, 2.9, -10.0), Vector3(0, 3.6, -16.0), 0.23, dark_wood)
	for side in [-1.0, 1.0]:
		_rope(Vector3(3.45 * side, 3.0, -5.5), Vector3(0, 16.0, -1.5), 0.07, dark_wood)
		_rope(Vector3(3.45 * side, 3.0, 4.9), Vector3(0, 16.0, -1.5), 0.07, dark_wood)
		_rope(Vector3(3.30 * side, 3.0, -7.5), Vector3(0, 11.0, -5.9), 0.07, dark_wood)
		_rope(Vector3(0, 15.5, -1.5), Vector3(side * 4.8, 13.5, -1.5), 0.07, dark_wood)
	# A small black flag with gold top ornament (no image asset).
	_box(Vector3(2.1, 1.1, 0.06), Vector3(1.06, 15.95, -1.6),
		_material(Color(0.13, 0.13, 0.19)))
	var ornament := SphereMesh.new()
	ornament.radius = 0.35
	ornament.height = 0.7
	_mesh(ornament, Vector3(0, 17.1, -1.5), brass)

func _rope(start: Vector3, finish: Vector3, radius: float,
		material: Material) -> void:
	var diff := finish - start
	var mesh := CylinderMesh.new()
	mesh.height = diff.length()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.radial_segments = 6
	var rope := _mesh(mesh, (start + finish) * 0.5, material)
	rope.quaternion = Quaternion(Vector3.UP, diff.normalized())

func _build_tapered_hull() -> void:
	# Contoured bow/stern instead of a rectangular block. 6 cross sections.
	var stations := [
		Vector2(-9.6, 0.35), Vector2(-8.0, 2.65),
		Vector2(-4.8, 3.9), Vector2(3.7, 3.95),
		Vector2(7.5, 2.8), Vector2(9.1, 1.0)]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(stations.size() - 1):
		var a: Vector2 = stations[i]
		var b: Vector2 = stations[i + 1]
		for side in [-1.0, 1.0]:
			var upper_a := Vector3(a.y * side, 2.5, a.x)
			var upper_b := Vector3(b.y * side, 2.5, b.x)
			var lower_a := Vector3(a.y * side * 0.42, -0.9, a.x)
			var lower_b := Vector3(b.y * side * 0.42, -0.9, b.x)
			_tri(surface, upper_a, upper_b, lower_b)
			_tri(surface, upper_a, lower_b, lower_a)
			_tri(surface, lower_a, lower_b, Vector3(0, -1.4, b.x))
			_tri(surface, lower_a, Vector3(0, -1.4, b.x), Vector3(0, -1.4, a.x))
	surface.generate_normals()
	_mesh(surface.commit(), Vector3.ZERO, hull_material)
	# Contrasting hull belt: cheap geometry, no large textures.
	for side in [-1.0, 1.0]:
		for i in range(stations.size() - 1):
			var a: Vector2 = stations[i]
			var b: Vector2 = stations[i + 1]
			var bar := BoxMesh.new()
			bar.size = Vector3(0.13, 0.16, b.x - a.x)
			_mesh(bar, Vector3((a.y + b.y) * side * 0.49, 2.07,
				(a.x + b.x) * 0.5), foam_material)

func _tri(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)

func _box(size: Vector3, at: Vector3, material: Material) -> void:
	var box := BoxMesh.new()
	box.size = size
	_mesh(box, at, material)

func _mesh(mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	add_child(node)
	return node

func _material(color: Color, double_sided := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.86
	if double_sided:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
