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
	wheel_node.rotation_degrees.z = 90.0

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
