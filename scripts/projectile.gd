class_name Projectile
extends Area3D
## High-speed tank shell. Moves in a straight line with a swept physics query
## per step (so it cannot tunnel through the terrain), then detonates an impact
## burst at the hit point instead of the old placeholder sphere. The shell body
## and smoke trail are built in code so the scene needs no external assets.

@export var speed := 98.0
@export var lifetime := 8.0
@export var damage := 25.0

var _velocity := Vector3.ZERO
var _excluded_rid := RID()
var _life := 0.0


## dir_speed is the full velocity vector (direction * projectile_speed) the
## player wants; p_owner is the firing tank body, excluded from the hit query.
func setup(dir_speed: Vector3, p_owner: Node) -> void:
	_velocity = dir_speed
	_life = lifetime
	if p_owner is CollisionObject3D:
		_excluded_rid = (p_owner as CollisionObject3D).get_rid()
	var dir := _velocity.normalized()
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var x := up.cross(dir).normalized()
	var y := dir.cross(x).normalized()
	basis = Basis(x, y, dir)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	_build_shell()


func _physics_process(delta: float) -> void:
	if _velocity == Vector3.ZERO:
		queue_free()
		return
	var from := global_position
	var to := from + _velocity * delta
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	if _excluded_rid.is_valid():
		query.exclude = [_excluded_rid]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		var pos: Vector3 = hit.get("position", to)
		var nrm: Vector3 = hit.get("normal", Vector3.UP)
		_detonate(pos, nrm)
		return
	global_position = to
	_life -= delta
	if _life <= 0.0:
		queue_free()


func _detonate(p_pos: Vector3, p_nrm: Vector3) -> void:
	var host := get_tree().current_scene
	if host is Node3D:
		spawn_impact(host, p_pos, p_nrm)
	queue_free()


# ============================================================================
# Visuals (no external assets)
# ============================================================================

func _build_shell() -> void:
	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.1
	mesh.bottom_radius = 0.12
	mesh.height = 1.4
	shell.mesh = mesh
	shell.rotation_degrees = Vector3(-90, 0, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.82, 0.65)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.25)
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shell.material_override = mat
	shell.position = Vector3(0, 0, 0.0)
	add_child(shell)

	var glow := OmniLight3D.new()
	glow.name = "Glow"
	glow.light_color = Color(1.0, 0.55, 0.25)
	glow.omni_range = 5.0
	glow.light_energy = 3.0
	add_child(glow)

	var trail := GPUParticles3D.new()
	trail.name = "Trail"
	trail.amount = 32
	trail.lifetime = 0.3
	trail.explosiveness = 0.85
	trail.local_coords = false
	trail.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.BACK
	pm.spread = 18.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.35
	pm.scale_max = 0.9
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.7, 0.35, 0.85))
	ramp.set_color(1, Color(0.4, 0.2, 0.1, 0.0))
	pm.color_ramp = ramp
	trail.process_material = pm
	var puff := SphereMesh.new()
	puff.radius = 0.07
	puff.height = 0.14
	trail.draw_pass_1 = puff
	add_child(trail)


## Shared impact burst used both by projectiles and the player's hitscan fallback:
## an expanding additive flash, a spark burst and a quick light. Pure scene-tree
## work, so it always runs on the main thread.
static func spawn_impact(p_host: Node, p_pos: Vector3, p_nrm: Vector3) -> void:
	if p_host == null:
		return
	var root := Node3D.new()
	root.name = "CannonImpact"
	p_host.add_child(root)
	root.global_position = p_pos + p_nrm * 0.12

	var nrm := p_nrm.normalized()
	var up := Vector3.UP
	if absf(nrm.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var x := up.cross(nrm).normalized()
	var z := nrm.cross(x).normalized()
	root.basis = Basis(x, nrm, z)

	var flash := MeshInstance3D.new()
	flash.name = "Flash"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.3, 1.3)
	flash.mesh = quad
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fmat.albedo_color = Color(1.0, 0.72, 0.35, 0.95)
	flash.material_override = fmat
	root.add_child(flash)

	var sparks := GPUParticles3D.new()
	sparks.name = "Sparks"
	sparks.amount = 28
	sparks.lifetime = 0.5
	sparks.local_coords = false
	sparks.one_shot = true
	sparks.emitting = true
	var smat := ParticleProcessMaterial.new()
	smat.direction = Vector3.UP
	smat.spread = 180.0
	smat.initial_velocity_min = 2.0
	smat.initial_velocity_max = 8.0
	smat.gravity = Vector3(0.0, -24.0, 0.0)
	smat.scale_min = 0.12
	smat.scale_max = 0.45
	var sramp := Gradient.new()
	sramp.set_color(0, Color(1.0, 0.9, 0.5, 1.0))
	sramp.set_color(1, Color(0.7, 0.25, 0.1, 0.0))
	smat.color_ramp = sramp
	sparks.process_material = smat
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.06
	spark_mesh.height = 0.12
	sparks.draw_pass_1 = spark_mesh
	root.add_child(sparks)

	var light := OmniLight3D.new()
	light.name = "FlashLight"
	light.light_color = Color(1.0, 0.6, 0.3)
	light.omni_range = 9.0
	light.light_energy = 6.0
	root.add_child(light)

	var tween := root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 2.4, 0.18)
	tween.tween_property(fmat, "albedo_color:a", 0.0, 0.18)
	tween.tween_property(light, "light_energy", 0.0, 0.3)
	tween.chain().tween_callback(root.queue_free)