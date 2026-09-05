extends VehicleBody3D
## Player tank driver (natively on VehicleBody3D).
##
## Adaptation extracted from sample/scripts/player/player.gd + sample camera
## + projectile_mgr.gd, replatformed from kinematic movement to Godot's
## VehicleBody3D wheel physics, and with the turret/cannon articulated through
## the imported pivot nodes ("PivotCannon" yaw / "Turret2" pitch) when the model
## exports them; a runtime AABB rig is kept as a fallback for models without
## pivots (see _build_aim_rig).
##
## INSPECTOR MAP (scenes/player.tscn, script attached to "Player/Body"):
##   tank_path              : NodePath to the tank visual root -> "Tank"
##   model_pivots           : drive the exported turret pivots directly (true)
##   turret_node_path       : leave "" to auto-detect "PivotCannon" under tank (yaw)
##   gun_node_path          : leave "" to auto-detect "Turret2" under turret (pitch)
##   barrel_node_path       : leave "" to auto-detect "Turret3" under turret (muzzle)
##   camera_path            : the game camera -> "CameraBase/Camera3D"
##   (camera.gd is auto-wired here in _ready: camera.player/player.world)
##   projectile_scene       : optional PackedScene; if set it is spawned at the
##                            muzzle instead of the default raycast hit scan
##
## Input actions consumed (add/rename in Project Settings -> Input Map):
##   accelerate (W), reverse (S), handbrake (Space), fire (mouse left),
##   camera_toggle (V), move_left (A), move_right (D).

# --- movement tuning (Inspector) ---
@export var engine_force_value := 1000.0
@export var reverse_force_factor := 0.6
@export var brake_force := 18.0
@export var handbrake_force := 60.0
@export var max_steering := 0.45
@export var steering_lerp_speed := 4.0
@export var max_speed := 30.0
@export var low_speed_boost := 5.0

# --- input action names (Inspector) ---
@export var action_accelerate := "accelerate"
@export var action_reverse := "reverse"
@export var action_handbrake := "handbrake"
@export var action_fire := "fire"
@export var action_toggle_view := "camera_toggle"

# --- node wiring (Inspector: reassign freely) ---
@export var tank_path := NodePath("Tank")
@export var model_pivots := true
@export var turret_node_path := NodePath("")
@export var gun_node_path := NodePath("")
@export var barrel_node_path := NodePath("")
@export var camera_path := NodePath("CameraBase/Camera3D")
@export var optic_forward_offset := Vector3(0.0, 0.12, 0.0)

# --- turret / cannons tuning (Inspector) ---
@export var turret_slew_rate := 2.2
@export var turret_arc_limit := deg_to_rad(45.0)
@export var turret_min_pitch := -0.2
@export var turret_max_pitch := 0.45
@export var mouse_sens := 0.0022
@export var fpp_pitch_min := -0.55
@export var fpp_pitch_max := 0.75
@export var tpp_pitch_min := -0.45
@export var tpp_pitch_max := 0.75

@export var fire_cooldown := 0.6
@export var raycast_distance := 400.0
@export var recoil_mag := 0.22
@export var recoil_impulse := 30.0
@export var projectile_scene: PackedScene
@export var projectile_speed := 98.0
@export var muzzle_flash_energy := 6.0

# --- aim state (fed by mouse, drives turret automatically) ---
var aim_yaw := 0.0
var aim_pitch := 0.12
var _cannon_yaw := 0.0
var _cannon_pitch := 0.12
var current_aim_point := Vector3.ZERO
var aiming := false
var is_turret_aligned := true
var _fire_timer := 0.0

# --- runtime aim-rig nodes (built in _ready, inspectable in the tree) ---
var turret_pivot: Node3D
var gun_pivot: Node3D
var muzzle: Node3D
var optic_mount: Node3D
var _flash_light: OmniLight3D

# --- wired in _ready() ---
var camera: Camera3D

# Lightweight view of the rig so scripts/camera.gd can keep its sample-style
# interface (player.tank.optic_mount / player.tank.gun_pitch).
class TankView:
	extends RefCounted
	var optic_mount: Node3D
	var gun_pitch: Node3D

var tank := TankView.new()


func _ready() -> void:
	camera = get_node_or_null(camera_path)
	var tank_visual := get_node_or_null(tank_path)
	_build_aim_rig(tank_visual)
	_build_muzzle_flash()
	tank.optic_mount = optic_mount
	tank.gun_pitch = gun_pivot
	if camera:
		camera.player = self
		camera.world = _find_world()


func _find_world() -> Node:
	var w := get_node_or_null("/root/World")
	if w:
		return w
	var n := get_parent()
	while n:
		if n.name == "World":
			return n
		n = n.get_parent()
	return null


## Builds the aim rig: yaw pivot, pitch pivot, muzzle and optic anchors.
## When the model carries real pivots (Tank.glb exports "PivotCannon" for yaw and
## "Turret2" for pitch), they are driven directly. Otherwise the pivots are
## synthesized from mesh AABBs (hinge at turret base centre, pitch at the
## barrel's base, muzzle at its tip) so the rig survives model swaps.
func _build_aim_rig(tank_visual: Node3D) -> void:
	if tank_visual == null:
		push_warning("player.gd: tank visual not found at '%s'" % str(tank_path))
		return
	var turret_node := _find_node(tank_visual, turret_node_path, "PivotCannon")
	var gun_node: Node = null
	var barrel_node: Node = null
	if turret_node:
		gun_node = _find_node(turret_node, gun_node_path, "Turret2")
		barrel_node = _find_node(turret_node, barrel_node_path, "Turret3")

	if model_pivots and turret_node is Node3D and gun_node is Node3D:
		_mount_model_pivots(tank_visual, turret_node as Node3D, gun_node as Node3D, barrel_node)
		return

	var yaw_hinge := tank_visual.global_position
	if turret_node:
		var turret_bb := _collect_global_aabb(turret_node)
		yaw_hinge = turret_bb.get_center()
		yaw_hinge.y = turret_bb.position.y
	else:
		push_warning("player.gd: turret node not found under '%s' (named '%s' or given by turret_node_path)" % [tank_visual.name, "PivotCannon"])

	turret_pivot = Node3D.new()
	turret_pivot.name = "TurretPivot"
	tank_visual.add_child(turret_pivot)
	turret_pivot.global_position = yaw_hinge
	turret_pivot.rotation = Vector3.ZERO

	var gun_hinge := yaw_hinge
	if turret_node:
		turret_node.reparent(turret_pivot, true)

	gun_pivot = turret_pivot
	var muzzle_tip := gun_hinge + Vector3(0.0, 0.0, 1.5)
	var optic_pos := gun_hinge + optic_forward_offset
	if barrel_node:
		var barrel_bb := _collect_global_aabb(barrel_node)
		gun_hinge = Vector3(barrel_bb.get_center().x, barrel_bb.get_center().y, barrel_bb.position.z)
		muzzle_tip = Vector3(barrel_bb.get_center().x, barrel_bb.get_center().y, barrel_bb.end.z)
		optic_pos = _optic_anchor(barrel_bb)
		gun_pivot = Node3D.new()
		gun_pivot.name = "GunPivot"
		turret_pivot.add_child(gun_pivot)
		gun_pivot.global_position = gun_hinge
		gun_pivot.rotation = Vector3.ZERO
		barrel_node.reparent(gun_pivot, true)

	_setup_muzzle_and_optic(tank_visual, gun_pivot, optic_pos, muzzle_tip)


func _mount_model_pivots(tank_visual: Node3D, turret_node: Node3D, gun_node: Node3D, barrel_node: Node) -> void:
	turret_pivot = turret_node
	gun_pivot = gun_node
	turret_pivot.rotation = Vector3.ZERO
	gun_pivot.rotation = Vector3.ZERO
	var muzzle_tip := gun_pivot.global_position + Vector3(0.0, 0.0, 1.5)
	var optic_pos := gun_pivot.global_position + optic_forward_offset
	if barrel_node:
		var bb := _collect_global_aabb(barrel_node)
		muzzle_tip = Vector3(bb.get_center().x, bb.get_center().y, bb.end.z)
		optic_pos = _optic_anchor(bb)
	_setup_muzzle_and_optic(tank_visual, gun_pivot, optic_pos, muzzle_tip)


## Optic anchor for the first-person view: just above the barrel, just ahead of
## the mantlet, so the camera sits outside the turret and looks down the gun.
func _optic_anchor(barrel_bb: AABB) -> Vector3:
	return Vector3(
		barrel_bb.get_center().x,
		barrel_bb.end.y + 0.18,
		barrel_bb.position.z + barrel_bb.size.z * 0.3
	) + optic_forward_offset


func _setup_muzzle_and_optic(tank_visual: Node3D, gun_pivot: Node3D, optic_pos: Vector3, muzzle_tip: Vector3) -> void:
	muzzle = Node3D.new()
	muzzle.name = "Muzzle"
	tank_visual.add_child(muzzle)
	muzzle.global_position = muzzle_tip
	muzzle.reparent(gun_pivot, true)

	optic_mount = Node3D.new()
	optic_mount.name = "OpticMount"
	tank_visual.add_child(optic_mount)
	optic_mount.global_position = optic_pos
	optic_mount.reparent(gun_pivot, true)


func _find_node(scope: Node, override_path: NodePath, auto_name: String) -> Node:
	if override_path != NodePath("") and scope.has_node(override_path):
		return scope.get_node(override_path)
	return scope.find_child(auto_name, true, false)


## Combined global AABB of every MeshInstance3D under `root` (fills in the gaps
## of MeshInstance3D.get_aabb(), which only reports the node's own mesh).
func _collect_global_aabb(root: Node) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh:
				var bb: AABB = mi.global_transform * mi.mesh.get_aabb()
				if first:
					out = bb
					first = false
				else:
					out = out.merge(bb)
		for c in n.get_children():
			stack.append(c)
	if first and root is Node3D:
		out = AABB((root as Node3D).global_position, Vector3.ONE)
	return out


func _build_muzzle_flash() -> void:
	if muzzle == null:
		return
	_flash_light = OmniLight3D.new()
	_flash_light.name = "MuzzleFlash"
	_flash_light.light_color = Color("#f27d4d")
	_flash_light.omni_range = 20.0
	_flash_light.light_energy = 0.0
	_flash_light.position = Vector3(0.0, 0.0, 0.6)
	muzzle.add_child(_flash_light)


# ============================================================================
# per-frame
# ============================================================================

func _physics_process(delta: float) -> void:
	_fire_timer = maxf(0.0, _fire_timer - delta)
	_drive_vehicle(delta)
	_update_turret_aim(delta)
	aiming = camera != null and camera.camera_mode == "first"
	if _flash_light:
		_flash_light.light_energy = lerpf(_flash_light.light_energy, 0.0, delta * 8.0)
	if InputMap.has_action(action_fire) and Input.is_action_just_pressed(action_fire):
		_fire_cannon()
	if InputMap.has_action(action_toggle_view) and Input.is_action_just_pressed(action_toggle_view):
		_toggle_view()
	if camera:
		camera.update_camera(delta)


## Sample _update_movement, remapped from manual kinematic velocity to the
## VehicleBody3D wheel API (engine_force / brake / steering). All 8 wheels are
## drive+steer in the scene, so the body-level properties reach them directly.
func _drive_vehicle(delta: float) -> void:
	var throttle := 0.0
	if _action_pressed(action_accelerate):
		throttle += 1.0
	if _action_pressed(action_reverse):
		throttle -= reverse_force_factor
	# A -> +1 (positive steering = left turn, matching the official truck demo).
	var target_steering: float = Input.get_axis("move_right", "move_left") * max_steering
	steering = move_toward(steering, target_steering, steering_lerp_speed * delta)

	if _action_pressed(action_handbrake):
		engine_force = 0.0
		brake = handbrake_force
		return

	brake = 0.0
	engine_force = 0.0
	if absf(throttle) <= 0.001:
		brake = brake_force
		return

	var speed := linear_velocity.length()
	var eff := engine_force_value
	if speed < 5.0:
		eff *= clampf(low_speed_boost / maxf(speed, 1.0), 1.0, low_speed_boost)
	if speed > max_speed:
		var over := clampf((speed - max_speed) / 5.0, 0.0, 1.0)
		eff *= 1.0 - over
	engine_force = eff * throttle


## Sample _update_turret_aim: turn mouse aim into a clamped, slew-limited turret
## yaw/pitch. Applied to the runtime rig instead of sample tank_model pivots.
func _update_turret_aim(delta: float) -> void:
	var anchor := global_position + Vector3(0.0, 1.8, 0.2)
	var cd := cos(aim_pitch)
	var d := Vector3(sin(aim_yaw) * cd, sin(aim_pitch), cos(aim_yaw) * cd)
	current_aim_point = anchor + d * 200.0

	var desired_yaw := _cannon_yaw
	var desired_pitch := _cannon_pitch
	if gun_pivot:
		var local_aim := to_local(current_aim_point)
		desired_yaw = clampf(atan2(local_aim.x, local_aim.z), -turret_arc_limit, turret_arc_limit)
		var aim_dist := maxf(1.0, Vector2(local_aim.x, local_aim.z).length())
		desired_pitch = clampf(atan2(local_aim.y, aim_dist), turret_min_pitch, turret_max_pitch)

	_cannon_yaw = _slew_toward(_cannon_yaw, desired_yaw, turret_slew_rate * delta)
	_cannon_pitch = _slew_toward(_cannon_pitch, desired_pitch, 1.8 * delta)
	if turret_pivot:
		turret_pivot.rotation.y = _cannon_yaw
	if gun_pivot and gun_pivot != turret_pivot:
		gun_pivot.rotation.x = -_cannon_pitch
	var yaw_aligned := absf(_cannon_yaw - desired_yaw) < 0.035
	var pitch_aligned := absf(_cannon_pitch - desired_pitch) < 0.035
	is_turret_aligned = yaw_aligned and pitch_aligned


func _slew_toward(current: float, target: float, max_step: float) -> float:
	var diff := target - current
	if absf(diff) <= max_step:
		return target
	return current + signf(diff) * max_step


func _action_pressed(name: String) -> bool:
	return InputMap.has_action(name) and Input.is_action_pressed(name)


## Sample fire_main_cannon, minus the chamber/reload/overheat economy (out of
## scope): primary fire on the designated action. Fires from the Muzzle marker
## along the gun's local +Z (barrel forward). Raycast by default; spawns
## projectile_scene instead when one is assigned.
func _fire_cannon() -> void:
	if _fire_timer > 0.0 or muzzle == null:
		return
	_fire_timer = fire_cooldown
	var origin := muzzle.global_position
	var dir := gun_pivot.global_transform.basis.z.normalized() if gun_pivot else -global_transform.basis.z

	if _flash_light:
		_flash_light.light_energy = muzzle_flash_energy
	if projectile_scene:
		_spawn_projectile(origin, dir)
	else:
		_hitscan_fire(origin, dir)
	if camera:
		camera.recoil(recoil_mag)
	apply_impulse(-dir * recoil_impulse)


func _spawn_projectile(origin: Vector3, dir: Vector3) -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	var proj := projectile_scene.instantiate()
	host.add_child(proj)
	proj.global_position = origin
	if proj is RigidBody3D:
		(proj as RigidBody3D).linear_velocity = dir * projectile_speed
	elif proj.has_method("setup"):
		proj.setup(dir * projectile_speed)


func _hitscan_fire(origin: Vector3, dir: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * raycast_distance, collision_mask)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	var impact_pos: Vector3 = origin + dir * raycast_distance
	var impact_nrm := Vector3.UP
	if not hit.is_empty():
		impact_pos = hit.get("position", impact_pos)
		impact_nrm = hit.get("normal", impact_nrm)
	_spawn_impact(impact_pos, impact_nrm)


## Short-lived runtime impact flash (sphere + light). No extra asset required.
func _spawn_impact(pos: Vector3, nrm: Vector3) -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	var root := Node3D.new()
	root.name = "CannonImpact"
	host.add_child(root)
	root.global_position = pos + nrm * 0.1

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#ffd9a3")
	mat.emission_enabled = true
	mat.emission = Color("#ff9a3d")
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mesh := SphereMesh.new()
	mesh.radius = 0.25
	mesh.height = 0.5
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	root.add_child(mi)

	var light := OmniLight3D.new()
	light.light_color = Color("#ffb05e")
	light.light_energy = 5.0
	light.omni_range = 8.0
	root.add_child(light)

	var tween := root.create_tween()
	tween.tween_interval(0.35)
	tween.tween_property(root, "scale", Vector3.ONE * 0.1, 0.15)
	tween.tween_callback(root.queue_free)


func _toggle_view() -> void:
	if camera:
		camera.toggle_view()


## Mouse look + raw-key fallbacks. When the project input actions are present
## (they are added to project.godot), fire/toggle are consumed in _physics_process
## via Input.is_action_just_pressed; the raw handlers below stay only as a safety
## net so the mechanics work even with an unedited Input Map.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var pmin := tpp_pitch_min
		var pmax := tpp_pitch_max
		if camera and camera.camera_mode == "first":
			pmin = fpp_pitch_min
			pmax = fpp_pitch_max
		aim_yaw -= event.relative.x * mouse_sens
		aim_pitch -= event.relative.y * mouse_sens
		aim_pitch = clampf(aim_pitch, pmin, pmax)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not InputMap.has_action(action_fire):
			_fire_cannon()
	elif event is InputEventKey and event.pressed and not event.echo:
		if not InputMap.has_action(action_toggle_view) and event.keycode == KEY_V:
			_toggle_view()
