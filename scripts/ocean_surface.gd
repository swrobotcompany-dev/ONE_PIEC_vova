class_name OceanSurface
extends MeshInstance3D
# A CPU-clipped ocean grid: land holes are absent from *geometry*, not just
# hidden by fragment discard. Only rebuilt when the player moves a grid chunk.
const GRID_STEP := 30.0
const GRID_CELLS := 128
const REBUILD_DISTANCE := 210.0
const MASK_MARGIN := 1.0

var sea_world := SeaWorld.new()
var last_center := Vector2(INF, INF)
var active_land: Array[Dictionary] = []
var rebuild_count := 0

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
		var x := float(island["x"])
		var z := float(island["z"])
		var reach := float(island["radius"]) + half + GRID_STEP
		if absf(x - center.x) < reach and absf(z - center.y) < reach:
			active_land.append(island)
	# Spatial clipping is also performed for the full manifest, not just the
	# eight nearest islands allowed by the fallback pixel shader mask.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(GRID_CELLS):
		for col in range(GRID_CELLS):
			var x := -half + float(col) * GRID_STEP
			var z := -half + float(row) * GRID_STEP
			var a := Vector2(x, z)
			var b := Vector2(x + GRID_STEP, z)
			var c := Vector2(x, z + GRID_STEP)
			var d := Vector2(x + GRID_STEP, z + GRID_STEP)
			_emit_clipped(surface, [a, c, b], center)
			_emit_clipped(surface, [b, c, d], center)
	mesh = surface.commit()
	position = Vector3(center.x, -0.75, center.y)
	rebuild_count += 1
	_set_shader_masks(center)

func _emit_clipped(surface: SurfaceTool, triangle: Array[Vector2],
		center: Vector2) -> void:
	var poly: Array[Vector2] = triangle
	for island in active_land:
		var center2 := Vector2(float(island["x"]), float(island["z"]))
		var radius := float(island["radius"]) + MASK_MARGIN
		var near := false
		for v in triangle:
			if (v + center).distance_squared_to(center2) < (radius + GRID_STEP * 2.0) * (radius + GRID_STEP * 2.0):
				near = true
				break
		if not near:
			continue
		poly = _clip_outside_disc(poly, center, center2, radius)
		if poly.is_empty():
			return
	if poly.size() < 3:
		return
	for i in range(1, poly.size() - 1):
		_emit_vertex(surface, poly[0])
		_emit_vertex(surface, poly[i])
		_emit_vertex(surface, poly[i + 1])

func _clip_outside_disc(poly: Array[Vector2], origin: Vector2,
		center: Vector2, radius: float) -> Array[Vector2]:
	# Piecewise linear signed distance (Sutherland-Hodgman clipping).
	var result: Array[Vector2] = []
	if poly.is_empty():
		return result
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var va := (a + origin).distance_to(center) - radius
		var vb := (b + origin).distance_to(center) - radius
		if va >= 0.0:
			result.append(a)
		if (va < 0.0 and vb > 0.0) or (va > 0.0 and vb < 0.0):
			var fraction := va / (va - vb)
			result.append(a.lerp(b, clampf(fraction, 0.0, 1.0)))
	return result

func _emit_vertex(surface: SurfaceTool, p: Vector2) -> void:
	surface.set_normal(Vector3.UP)
	surface.add_vertex(Vector3(p.x, 0.0, p.y))

func _set_shader_masks(center: Vector2) -> void:
	var closest := active_land.duplicate()
	closest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_dist := Vector2(float(a["x"]), float(a["z"])).distance_squared_to(center)
		var b_dist := Vector2(float(b["x"]), float(b["z"])).distance_squared_to(center)
		return a_dist < b_dist)
	var masks := PackedVector4Array()
	for i in range(8):
		if i < closest.size():
			var island: Dictionary = closest[i]
			masks.append(Vector4(float(island["x"]), float(island["z"]),
				float(island["radius"]), float(island["height"])))
		else:
			masks.append(Vector4.ZERO)
	(material_override as ShaderMaterial).set_shader_parameter("land_masks", masks)
