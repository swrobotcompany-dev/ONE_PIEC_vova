class_name OceanSurface
extends MeshInstance3D
# The old polygon-against-circle clipping was invalid: "outside a circle"
# is non-convex, so triangles could survive and cover entire beaches.
# Here a quadtree emits ONLY fully-water tiles. Shoreline tiles are split
# down to <2 m then skipped if they might touch land. No alpha or Z-fighting.
const GRID_STEP := 30.0
const GRID_CELLS := 128
const REBUILD_DISTANCE := 210.0
const MASK_MARGIN := 3.0
const MAX_SHORE_SUBDIVISIONS := 4

var sea_world := SeaWorld.new()
var last_center := Vector2(INF, INF)
var active_land: Array[Dictionary] = []
var rebuild_count := 0
var water_tiles := 0
var omitted_tiles := 0

func _ready() -> void:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/ocean.gdshader")
	material.set_shader_parameter("land_masks", PackedVector4Array([
		Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO,
		Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]))
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func update_focus(focus: Vector3) -> void:
	var next := Vector2(
		roundf(focus.x / GRID_STEP) * GRID_STEP,
		roundf(focus.z / GRID_STEP) * GRID_STEP)
	if next.distance_to(last_center) < REBUILD_DISTANCE:
		return
	rebuild_at(next)

func rebuild_at(center: Vector2) -> void:
	last_center = center
	var half := GRID_STEP * float(GRID_CELLS) * 0.5
	active_land.clear()
	for island in sea_world.islands:
		var radius: float = float(island["radius"]) * 1.25
		if absf(float(island["x"]) - center.x) <= half + radius + GRID_STEP \
				and absf(float(island["z"]) - center.y) <= half + radius + GRID_STEP:
			active_land.append(island)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	water_tiles = 0
	omitted_tiles = 0
	for row in range(GRID_CELLS):
		for col in range(GRID_CELLS):
			var x := -half + float(col) * GRID_STEP
			var z := -half + float(row) * GRID_STEP
			_emit_safe_cell(surface, x, z, GRID_STEP, center, 0)
	mesh = surface.commit()
	position = Vector3(center.x, -0.85, center.y)
	rebuild_count += 1
	_set_shader_masks(center)

func _cell_status(x: float, z: float, size: float, origin: Vector2) -> int:
	# 0: definitely sea, 1: definitely land, 2: boundary uncertain.
	# Centre-to-coast distance plus a conservative diagonal variation bound.
	# Uncertain cells are never rendered; they are subdivided or discarded.
	var mid := origin + Vector2(x + size * 0.5, z + size * 0.5)
	var uncertain := false
	for island in active_land:
		var offset := mid - Vector2(float(island["x"]), float(island["z"]))
		var coast := sea_world.coast_radius(island, atan2(offset.y, offset.x))
		var signed := offset.length() - coast
		var bound := size * 1.8 + MASK_MARGIN
		if signed < -bound:
			return 1
		if signed <= bound:
			uncertain = true
	return 2 if uncertain else 0

func _emit_safe_cell(surface: SurfaceTool, x: float, z: float,
		size: float, center: Vector2, depth: int) -> void:
	var status := _cell_status(x, z, size, center)
	if status == 1:
		omitted_tiles += 1
		return
	if status == 2:
		if depth >= MAX_SHORE_SUBDIVISIONS:
			omitted_tiles += 1
			return
		var half := size * 0.5
		_emit_safe_cell(surface, x, z, half, center, depth + 1)
		_emit_safe_cell(surface, x + half, z, half, center, depth + 1)
		_emit_safe_cell(surface, x, z + half, half, center, depth + 1)
		_emit_safe_cell(surface, x + half, z + half, half, center, depth + 1)
		return
	# Both triangles have guaranteed positive clearance to all coastlines.
	# Winding points upwards in Godot's clockwise-front-face convention.
	var a := Vector2(x, z)
	var b := Vector2(x + size, z)
	var c := Vector2(x, z + size)
	var d := Vector2(x + size, z + size)
	_emit_vertex(surface, a)
	_emit_vertex(surface, c)
	_emit_vertex(surface, b)
	_emit_vertex(surface, b)
	_emit_vertex(surface, c)
	_emit_vertex(surface, d)
	water_tiles += 1

func _emit_vertex(surface: SurfaceTool, p: Vector2) -> void:
	surface.set_normal(Vector3.UP)
	surface.add_vertex(Vector3(p.x, 0.0, p.y))

func _set_shader_masks(center: Vector2) -> void:
	var closest := active_land.duplicate()
	closest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return Vector2(float(a["x"]), float(a["z"])).distance_squared_to(center) < \
			Vector2(float(b["x"]), float(b["z"])).distance_squared_to(center))
	var masks := PackedVector4Array()
	for i in range(8):
		if i < closest.size():
			var island: Dictionary = closest[i]
			# Visual shader may discard an additional edge fringe.
			masks.append(Vector4(float(island["x"]), float(island["z"]),
				float(island["radius"]) * 1.20, float(island["height"])))
		else:
			masks.append(Vector4.ZERO)
	var water_material := material_override as ShaderMaterial
	if water_material != null:
		water_material.set_shader_parameter("land_masks", masks)
