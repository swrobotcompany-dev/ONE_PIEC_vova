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

func shoot(player_pos: Vector3, camera_yaw: float, hero: String,
		selected_fruit: String = "") -> void:
	if shot_cooldown > 0.0:
		return
	var style := FruitCatalog.shot_style(selected_fruit)
	shot_cooldown = (0.40 if hero == "luffy" else 0.86) * float(style.get("rate", 1.0))
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
			var visual := _make_bullet(shot)
			bullets[id] = visual
			visual.global_position = shot["pos"]
		var bullet: Node3D = bullets[id]
		bullet.global_position = bullet.global_position.lerp(shot["pos"], minf(delta * 19.0, 1.0))
		var direction: Vector3 = shot["velocity"]
		if direction.length_squared() > 0.01:
			bullet.rotation.y = atan2(-direction.x, -direction.z)
		else:
			bullet.rotation.y += delta * 0.9
		var age := float(bullet.get_meta("age", 0.0)) + delta
		bullet.set_meta("age", age)
		if bool(bullet.get_meta("pulse", false)):
			var radius := float(shot.get("radius", 5.0))
			bullet.scale = Vector3.ONE * radius * minf(1.0, 0.22 + age * 2.2)
		elif str(shot.get("hero", "")) == "fruit":
			bullet.rotate_object_local(Vector3.FORWARD, delta * 2.8)

func _make_bullet(shot: Dictionary) -> Node3D:
	var kind := str(shot.get("kind", "fist"))
	var infusion := str(shot.get("infusion", ""))
	var visual := Node3D.new()
	add_child(visual)
	visual.set_meta("age", 0.0)
	var is_pulse := kind in ["smoke", "flower", "gravity", "quake", "barrier"]
	if is_pulse:
		visual.set_meta("pulse", true)
		var ring := TorusMesh.new()
		ring.inner_radius = 0.82
		ring.outer_radius = 1.0
		ring.rings = 8
		ring.ring_segments = 32
		var wave := _part(visual, ring, FruitCatalog.tint(kind))
		wave.position.y = -1.25
		return visual
	if kind == "fist":
		# Luffy: elastic forearm and a visible oversized flying punch.
		var arm := CapsuleMesh.new()
		arm.radius = 0.31
		arm.height = 2.45
		var stretch := _part(visual, arm, Color(0.98, 0.68, 0.44))
		stretch.rotation.x = PI * 0.5
		stretch.position.z = 0.8
		var hand := SphereMesh.new()
		hand.radius = 0.65
		hand.height = 1.1
		_part(visual, hand, Color(1.0, 0.80, 0.54)).position.z = -0.55
		_add_infusion_aura(visual, kind, infusion)
		return visual
	if kind == "slash":
		# Zoro: a wide horizontal turquoise flying blade, not a bullet.
		var blade := BoxMesh.new()
		blade.size = Vector3(3.8, 0.16, 0.42)
		var edge := _part(visual, blade, Color(0.23, 0.94, 0.96))
		edge.rotation.z = -0.21
		var highlight := BoxMesh.new()
		highlight.size = Vector3(3.2, 0.08, 0.55)
		var shine := _part(visual, highlight, Color(0.90, 1.0, 1.0))
		shine.rotation.z = -0.21
		_add_infusion_aura(visual, kind, infusion)
		return visual
	var orb := SphereMesh.new()
	orb.radius = clampf(float(shot.get("radius", 1.5)) * 0.38, 0.38, 1.10)
	orb.height = orb.radius * 2.0
	orb.radial_segments = 12
	orb.rings = 6
	_part(visual, orb, FruitCatalog.tint(kind))
	var halo := TorusMesh.new()
	halo.inner_radius = 0.72
	halo.outer_radius = 0.93
	halo.rings = 6
	halo.ring_segments = 20
	var aura := _part(visual, halo, FruitCatalog.tint(kind).lightened(0.3))
	aura.scale = Vector3.ONE * (orb.radius * 1.4)
	aura.rotation.x = 0.45
	if kind in ["lightning", "light", "string", "ice"]:
		# Piercing beams and shards read as long, thin projectiles.
		visual.scale = Vector3(0.58, 0.58, 2.1)
	return visual

# A separate colored aura keeps Luffy's fist and Zoro's blade recognizable,
# while making the equipped Devil Fruit visible to every LAN player.
func _add_infusion_aura(visual: Node3D, kind: String, infusion: String) -> void:
	if not FruitCatalog.TYPES.has(infusion):
		return
	var tint := FruitCatalog.tint(infusion)
	if kind == "fist":
		var ring := TorusMesh.new()
		ring.inner_radius = 0.72
		ring.outer_radius = 0.96
		ring.rings = 6
		ring.ring_segments = 24
		var aura := _part(visual, ring, tint)
		aura.position.z = -0.58
		aura.rotation.x = PI * 0.5
	else:
		var edge := BoxMesh.new()
		edge.size = Vector3(4.4, 0.13, 0.25)
		var aura := _part(visual, edge, tint)
		aura.position.y = 0.24
		aura.rotation.z = -0.21

func _part(parent: Node3D, mesh: Mesh, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.9
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part
