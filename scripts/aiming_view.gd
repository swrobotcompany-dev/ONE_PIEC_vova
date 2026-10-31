class_name AimingView
extends Node3D

# Diablo-style cursor aiming for a third-person camera: the mouse ray is
# intersected with a horizontal plane through the hero. The client sends
# ONLY direction; the server owns projectile speed, hits, cooldowns and damage.
var active_camera: Camera3D
var reticle: MeshInstance3D
var indicator: MeshInstance3D
var bullets: Dictionary = {}
var shot_cooldown := 0.0
var sea_world := SeaWorld.new()

func _ready() -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.70
	ring.outer_radius = 0.98
	ring.rings = 8
	ring.ring_segments = 30
	reticle = _shape(ring, Color(0.42, 1.0, 0.78), true)
	var line := BoxMesh.new()
	line.size = Vector3(0.14, 0.08, 1)
	indicator = _shape(line, Color(0.29, 0.89, 0.72, 0.26), false)
	reticle.visible = false
	indicator.visible = false

func _shape(mesh: Mesh, color: Color, glowing: bool) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if glowing:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.3
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	return inst

func get_aim(player_pos: Vector3, camera_yaw: float) -> Vector2:
	var fallback := Vector2(-sin(camera_yaw), -cos(camera_yaw))
	if active_camera == null:
		return fallback
	var mouse := get_viewport().get_mouse_position()
	var ray_origin := active_camera.project_ray_origin(mouse)
	var ray := active_camera.project_ray_normal(mouse)
	var hit = Plane(Vector3.UP, player_pos.y + 1.2).intersects_ray(ray_origin, ray)
	if hit is Vector3:
		var offset: Vector3 = hit - player_pos
		if Vector2(offset.x, offset.z).length_squared() > 0.4:
			return Vector2(offset.x, offset.z).normalized()
	return fallback

func shoot(player_pos: Vector3, camera_yaw: float, hero: String) -> void:
	if shot_cooldown > 0.0:
		return
	shot_cooldown = 0.56 if hero == "luffy" else 0.82
	GameNet.fire_projectile(get_aim(player_pos, camera_yaw))

func update_view(delta: float, hero: Node3D, camera_yaw: float,
		snapshot: Dictionary, can_aim: bool) -> void:
	shot_cooldown = maxf(0, shot_cooldown - delta)
	reticle.visible = can_aim and hero != null
	indicator.visible = can_aim and hero != null
	if hero != null and can_aim:
		var direction2 := get_aim(hero.global_position, camera_yaw)
		var direction := Vector3(direction2.x, 0, direction2.y)
		var destination := hero.global_position + direction * 16.0
		var island := sea_world.closest_island(destination)
		destination.y = maxf(sea_world.ground_height(island, destination) + 0.15, 0.1)
		reticle.global_position = destination
		indicator.global_position = hero.global_position + direction * 8.0 + Vector3.UP * 0.2
		indicator.rotation.y = atan2(-direction.x, -direction.z)
		indicator.scale = Vector3(1, 1, 16)
	var live: Dictionary = snapshot.get("projectiles", {})
	for id in bullets.keys():
		if not live.has(id):
			bullets[id].queue_free()
			bullets.erase(id)
	for id in live:
		var shot: Dictionary = live[id]
		if not bullets.has(id):
			var mesh := SphereMesh.new()
			mesh.radius = 0.6 if str(shot["hero"]) == "luffy" else 0.9
			mesh.height = 1.2
			mesh.radial_segments = 12
			mesh.rings = 6
			var color := Color(1.0, 0.67, 0.19) if str(shot["hero"]) == "luffy" else Color(0.31, 0.93, 0.97)
			bullets[id] = _shape(mesh, color, true)
			bullets[id].global_position = shot["pos"]
		var bullet: MeshInstance3D = bullets[id]
		bullet.global_position = bullet.global_position.lerp(shot["pos"], minf(delta * 16.0, 1.0))
		var direction: Vector3 = shot["velocity"]
		bullet.rotation.y = atan2(-direction.x, -direction.z)
