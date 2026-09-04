extends Camera3D
## updateCamera port: third-person follow rig with recoil shake, ADS gunner
## view on the optic mount, FOV lerp and ground-clamp. Pure kinematic follows;
## the player feeds aim_yaw/aim_pitch and current_aim_point each frame.

var player: Node
var world: Node

var camera_mode := 'third'
var distance := 15.0
var target_distance := 15.0
var height := 3.4
var shake_time := 0.0
var shake_mag := 0.0
var base_fov := 56.0
var ads_fov := 22.0

func _ready() -> void:
	fov = base_fov
	near = 0.1
	far = 1400.0

func recoil(mag: float) -> void:
	shake_time = 0.3
	shake_mag = mag

func toggle_view() -> void:
	camera_mode = 'first' if camera_mode == 'third' else 'third'

func update_camera(dt: float) -> void:
	if not player:
		return
	var in_combat: bool = world != null and world.engaged_boss_zone() != null
	var is_optic_view: bool = camera_mode == 'first' or player.aiming
	var target_fov: float = ads_fov if is_optic_view else base_fov
	fov = lerpf(fov, target_fov, dt * 9.0)

	var sx := 0.0
	var sy := 0.0
	if shake_time > 0.0:
		shake_time -= dt
		var decay: float = maxf(0.0, shake_time / 0.3)
		sx = (randf() - 0.5) * shake_mag * decay
		sy = (randf() - 0.5) * shake_mag * decay

	if not is_optic_view:
		var boss_scale: float = 0.0
		#if in_combat:
			#boss_scale = float(TERRAIN.BOSS['grid']['y']) * float(TERRAIN.BOSS['cellSize'])
		target_distance = 16.0 + boss_scale * 0.9 if in_combat else 14.5
		distance = lerpf(distance, target_distance, dt * 2.5)
		var target_cam_height: float = 3.4 + boss_scale * 0.16 if in_combat else 3.4
		height = lerpf(height, target_cam_height, dt * 2.5)

		var turret_anchor: Vector3 = player.position + Vector3(0, 1.8, 0.2)
		var aim_dir: Vector3 = (player.current_aim_point - turret_anchor).normalized()
		var cam_pos: Vector3 = turret_anchor - aim_dir * distance + Vector3(0, height, 0)
		cam_pos += Vector3(sx * 1.6, sy * 1.6, 0)
		#if world:
			#var ground_at_cam: float = TERRAIN.get_effective_ground_height(cam_pos.x, cam_pos.z)
			#if cam_pos.y < ground_at_cam + 0.85:
				#cam_pos.y = ground_at_cam + 0.85
		global_position = global_position.lerp(cam_pos, minf(1.0, dt * 12.0))
		look_at(player.current_aim_point, Vector3.UP)
	else:
		var optic_world: Vector3 = player.tank.optic_mount.global_position
		var cannon_dir: Vector3 = -player.tank.gun_pitch.global_transform.basis.z
		var look_target: Vector3 = optic_world + cannon_dir * 100.0
		if shake_time > 0.0:
			look_target += Vector3(sx * 3.0, sy * 3.0, 0)
		global_position = optic_world
		look_at(look_target, Vector3.UP)
