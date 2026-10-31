class_name PirateShip
extends Node3D
# All meshes are primitive, so there are no external asset downloads.
var hull_material: StandardMaterial3D
var foam_material: StandardMaterial3D

func _ready() -> void:
	hull_material = _material(Color(0.27, 0.13, 0.07))
	foam_material = _material(Color(0.97, 0.87, 0.65))
	_box(Vector3(8.0, 2.2, 17.0), Vector3(0, 1.1, 0), hull_material)
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
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.7
	wheel.bottom_radius = 0.7
	wheel.height = 0.22
	var wheel_node := _mesh(wheel, Vector3(0, 4.1, 3.2), foam_material)
	# More readable low-poly silhouette without importing textures.
	# Material count stays small and the Compatibility renderer is retained.
	var gilding := _material(Color(0.86, 0.62, 0.22))
	var copper := _material(Color(0.35, 0.25, 0.22))
	var dark_wood := _material(Color(0.17, 0.10, 0.09))
	for side in [-1, 1]:
		var sx: float = float(side)
		# Contrasting upper gunwale and broad wooden waterline.
		_box(Vector3(0.25, 0.27, 16.0), Vector3(sx * 3.97, 2.39, 0), gilding)
		_box(Vector3(0.21, 0.35, 15.3), Vector3(sx * 4.0, 0.55, 0), dark_wood)
		for z in [-5.7, -1.7, 2.3, 6.3]:
			# Gun ports read as darker rectangles with projecting cannons.
			_box(Vector3(0.15, 0.95, 1.1), Vector3(sx * 4.06, 1.45, z), dark_wood)
			var gun := CylinderMesh.new()
			gun.top_radius = 0.29
			gun.bottom_radius = 0.38
			gun.height = 1.35
			gun.radial_segments = 7
			var cannon := _mesh(gun, Vector3(sx * 4.48, 1.6, z), copper)
			cannon.rotation_degrees.z = 90.0
		# Lanterns frame the rear cabin without dynamic lights/shadows.
		_lantern(Vector3(sx * 2.4, 4.95, 6.8), copper)
		_box(Vector3(0.21, 2.4, 0.21), Vector3(sx * 3.5, 5.1, 4.8), dark_wood)
	# Raised bow, bowsprit, stern windows and lookout crow's nest.
	_box(Vector3(4.3, 0.45, 4.5), Vector3(0, 3.0, -7.9), dark_wood)
	_box(Vector3(0.55, 0.48, 9.0), Vector3(0, 4.2, -10.8), gilding)
	for x in [-2.15, 0.0, 2.15]:
		_box(Vector3(1.4, 1.1, 0.14), Vector3(x, 3.45, 7.63), gilding)
	var basket := CylinderMesh.new()
	basket.top_radius = 1.75
	basket.bottom_radius = 1.35
	basket.height = 1.4
	basket.radial_segments = 8
	_mesh(basket, Vector3(0, 16.4, -1.5), dark_wood)
	_box(Vector3(3.4, 0.24, 0.2), Vector3(0, 17.15, -1.5), gilding)
	wheel_node.rotation_degrees.z = 90.0

func _lantern(at: Vector3, metal: Material) -> void:
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.70, 0.20)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.50, 0.08)
	glow.emission_energy_multiplier = 1.8
	var lamp := SphereMesh.new()
	lamp.radius = 0.37
	lamp.height = 0.72
	lamp.radial_segments = 8
	lamp.rings = 4
	_mesh(lamp, at, glow)
	var cover := CylinderMesh.new()
	cover.top_radius = 0.52
	cover.bottom_radius = 0.52
	cover.height = 0.12
	cover.radial_segments = 8
	_mesh(cover, at + Vector3(0, 0.46, 0), metal)

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
