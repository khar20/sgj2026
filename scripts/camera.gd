extends Camera3D
## First/third person camera rig for the VehicleBody3D tank.
##
## Adaptation of sample/scripts/camera_ctrl.gd, hardened for this project:
##  - First person = "optic view": camera rides player.tank.optic_mount and
##    looks down the barrel (gun local +Z). Mouse look constraints come from
##    the turret's pitch clamps in player.gd; the view is slew-limited so it
##    never snaps.
##  - Third person = orbit behind the aim point (turret anchor), FOV lerp,
##    recoil shake, optional ground clamp via a downward ray (replaces the
##    sample's TERRAIN autoload calls).
##  - The sample's boss-distance growth is kept but guarded (world method may
##    not exist in this project's world script).
##
## INSPECTOR MAP (scenes/player.tscn):
##   node            -> Camera3D under Body/CameraBase
##   player / world  -> assigned automatically by scripts/player.gd in _ready;
##                      override optic_mount_path / gun_pitch_path if you move
##                      the rig nodes.

@export var base_fov := 56.0
@export var ads_fov := 22.0
@export var camera_distance := 35.0
@export var camera_height := 3.4
@export var follow_lerp_speed := 12.0
@export var distance_lerp_speed := 2.5
@export var clamp_to_ground := true
@export var ground_clearance := 0.85
@export_node_path("Node3D") var optic_mount_path := NodePath("")
@export_node_path("Node3D") var gun_pitch_path := NodePath("")

var player: Node
var world: Node

var camera_mode := "third"
var shake_time := 0.0
var shake_mag := 0.0
var _current_distance := 15.0
var _current_height := 3.4


func _ready() -> void:
	fov = base_fov
	near = 0.1
	far = 1400.0
	_current_distance = camera_distance
	_current_height = camera_height


func toggle_view() -> void:
	camera_mode = "first" if camera_mode == "third" else "third"


func recoil(mag: float) -> void:
	shake_time = 0.3
	shake_mag = mag


func _get_optic() -> Node3D:
	if optic_mount_path != NodePath("") and has_node(optic_mount_path):
		return get_node(optic_mount_path) as Node3D
	if player and player.get("tank") != null:
		var view = player.get("tank")
		if view and view.get("optic_mount") != null:
			return view.get("optic_mount") as Node3D
	return null


func _get_gun() -> Node3D:
	if gun_pitch_path != NodePath("") and has_node(gun_pitch_path):
		return get_node(gun_pitch_path) as Node3D
	if player and player.get("tank") != null:
		var view = player.get("tank")
		if view and view.get("gun_pitch") != null:
			return view.get("gun_pitch") as Node3D
	return null


func update_camera(dt: float) -> void:
	if not player:
		return

	var is_optic := camera_mode == "first" or bool(player.get("aiming"))
	fov = lerpf(fov, ads_fov if is_optic else base_fov, dt * 9.0)

	var sx := 0.0
	var sy := 0.0
	if shake_time > 0.0:
		shake_time = maxf(0.0, shake_time - dt)
		var decay: float = shake_time / 0.3
		sx = (randf() - 0.5) * shake_mag * decay
		sy = (randf() - 0.5) * shake_mag * decay

	if is_optic:
		_update_optic_view(sx, sy)
	else:
		_update_third_person_view(dt, sx, sy)


func _update_optic_view(sx: float, sy: float) -> void:
	var optic := _get_optic()
	if optic == null:
		return
	global_position = optic.global_position
	# Barrel forward is local +Z (Vector3.MODEL_FRONT). The sample camera used
	# -basis.z, which pointed backwards for this model; fixed here.
	var gun := _get_gun()
	var fwd := gun.global_transform.basis.z.normalized() if gun else Vector3.BACK
	var look := optic.global_position + fwd * 100.0
	if shake_time > 0.0:
		look += Vector3(sx * 3.0, sy * 3.0, 0.0)
	look_at(look, Vector3.UP)


func _update_third_person_view(dt: float, sx: float, sy: float) -> void:
	# Optional boss-scale distance growth, kept from the sample (guarded: this
	# project's world script has no engaged_boss_zone method yet).
	var boss_scale := 0.0
	if world and world.has_method("engaged_boss_zone") and world.engaged_boss_zone() != null:
		boss_scale = 1.0
	var target_distance: float = camera_distance + boss_scale * 1.5
	var target_height: float = camera_height + boss_scale * 0.16
	_current_distance = lerpf(_current_distance, target_distance, minf(1.0, dt * distance_lerp_speed))
	_current_height = lerpf(_current_height, target_height, minf(1.0, dt * distance_lerp_speed))

	var anchor: Vector3 = player.global_position + Vector3(0.0, 1.8, 0.2)
	var aim: Vector3 = player.get("current_aim_point") as Vector3
	var aim_dir := (aim - anchor).normalized()
	var cam_pos := anchor - aim_dir * _current_distance + Vector3(0.0, _current_height, 0.0)
	cam_pos += Vector3(sx * 1.6, sy * 1.6, 0.0)
	if clamp_to_ground:
		cam_pos = _clamp_above_ground(cam_pos)
	global_position = global_position.lerp(cam_pos, minf(1.0, dt * follow_lerp_speed))
	look_at(aim, Vector3.UP)


## Replaces the sample's TERRAIN.get_effective_ground_height() clamp: cast down
## and keep the camera a fixed clearance above whatever it finds.
func _clamp_above_ground(p: Vector3) -> Vector3:
	if player is CollisionObject3D:
		var space := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(p, p + Vector3(0.0, -80.0, 0.0))
		query.exclude = [(player as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			var ground_y: float = hit.get("position", p).y
			if p.y < ground_y + ground_clearance:
				return Vector3(p.x, ground_y + ground_clearance, p.z)
	return p
