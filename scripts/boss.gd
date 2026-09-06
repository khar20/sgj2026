extends Node3D
## Crystal boss enemy for the arena at (512, 512): a tall crystal tower (~37
## units, ~10x the tank height) that erupts from the ground at scene start,
## fires predictive shard volleys once the player is in combat range, and can
## be destroyed by cannon fire.
##
## The StaticBody3D child sits on collision layer 1 (same as terrain) so the
## player's projectile/hitscan raycasts detect it naturally; world.gd routes
## the hit to take_damage().

const GEN := preload("res://scripts/world_gen.gd")
const CRYSTAL_SCENE := preload("res://assets/models/crystal/Crystals.glb")

static var _crystal_mesh: Mesh = null

@export var max_health := 800.0
@export var combat_range := 400.0
@export var eruption_seconds := 3.0
@export var shard_interval := 4.0
@export var shards_per_volley := 5
@export var shard_speed := 85.0
@export var shard_damage := 8.0

var health := 800.0
var state := "idle"
var eruption_t := 0.0
var shard_timer := 0.0
var world: Node3D
var _shards: Array = []
var _body: StaticBody3D
var _crystal_nodes: Array[MeshInstance3D] = []
var _crystal_mats: Array[StandardMaterial3D] = []
var _formation: Node3D
var _flash_mat: StandardMaterial3D = null

var _last_player_pos := Vector3.ZERO
var _player_velocity := Vector3.ZERO

signal health_changed(new_health: float, max_health: float)
signal defeated


func _ready() -> void:
	health = max_health
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.albedo_color = Color.WHITE
	_flash_mat.emission_enabled = true
	_flash_mat.emission = Color.WHITE
	_flash_mat.emission_energy_multiplier = 5.0
	_build_collision()
	_build_crystal_formation()
	# Rise from the ground immediately at scene start (no proximity gate), so
	# the boss is up and fighting by the time the player reaches the arena.
	var th: float = GEN.terrain_height(position.x, position.z)
	position.y = th - 30.0
	state = "erupting"
	eruption_t = 0.0
	visible = true


func setup(p_world: Node3D, center: Vector3) -> void:
	world = p_world
	position.x = center.x
	position.z = center.z


func update(dt: float, player_pos: Vector3, player_vel: Vector3 = Vector3.ZERO) -> void:
	match state:
		"erupting":
			eruption_t += dt / eruption_seconds
			var eased: float = 1.0 - pow(1.0 - clampf(eruption_t, 0.0, 1.0), 3.0)
			var th: float = GEN.terrain_height(position.x, position.z)
			position.y = lerpf(th - 30.0, th + 2.0, eased)
			if eruption_t >= 1.0:
				state = "active"
				shard_timer = shard_interval * 0.4
		"active":
			var flat := Vector3(player_pos.x, 0.0, player_pos.z)
			var boss_flat := Vector3(position.x, 0.0, position.z)
			if flat.distance_to(boss_flat) <= combat_range:
				_face_toward(player_pos, dt)
				shard_timer -= dt
				if shard_timer <= 0.0:
					shard_timer = shard_interval * (0.8 + randf() * 0.4)
					_fire_volley(player_pos, player_vel)
			_update_shards(dt, player_pos)
		"defeated":
			_update_shards(dt, player_pos)


func take_damage(amount: float) -> void:
	if state == "defeated":
		return
	health = clampf(health - amount, 0.0, max_health)
	health_changed.emit(health, max_health)
	_flash_hit()
	if health <= 0.0:
		_on_defeated()


func _flash_hit() -> void:
	for i in _crystal_nodes.size():
		var mi: MeshInstance3D = _crystal_nodes[i]
		if not is_instance_valid(mi):
			continue
		mi.material_override = _flash_mat
		var captured_mi := mi
		var captured_mat: StandardMaterial3D = _crystal_mats[i]
		var tw := create_tween()
		tw.tween_interval(0.08)
		tw.tween_callback(func() -> void:
			if is_instance_valid(captured_mi):
				captured_mi.material_override = captured_mat
		)


func is_active() -> bool:
	return state == "active" or state == "erupting"


# ---------------------------------------------------------------------------
# Crystal formation
# ---------------------------------------------------------------------------

func _build_crystal_formation() -> void:
	_formation = Node3D.new()
	_formation.name = "Formation"
	add_child(_formation)

	# Compact purple tower: crystals stacked vertically with almost no outward
	# spread. Total height ~37 units (~10x the tank's ~3.5 unit height).
	var base_col := Color(0.55, 0.27, 0.85)
	var mid_col := Color(0.62, 0.3, 0.9)
	var up_col := Color(0.7, 0.35, 0.95)

	_add_crystal(_formation, Vector3(0.0, 4.0, 0.0), Vector3(15.0, 9.0, 15.0), Vector3.ZERO, base_col)
	_add_crystal(_formation, Vector3(0.0, 9.5, 0.0), Vector3(11.0, 11.0, 11.0),
		Vector3(0.0, deg_to_rad(45.0), 0.0), mid_col)
	_add_crystal(_formation, Vector3(0.0, 19.0, 0.0), Vector3(7.5, 10.0, 7.5),
		Vector3(0.0, deg_to_rad(20.0), 0.0), up_col)
	_add_crystal(_formation, Vector3(0.0, 27.5, 0.0), Vector3(4.5, 9.0, 4.5),
		Vector3(0.0, deg_to_rad(60.0), 0.0), Color(0.78, 0.4, 1.0))
	_add_crystal(_formation, Vector3(0.0, 34.0, 0.0), Vector3(2.5, 6.0, 2.5),
		Vector3(0.0, deg_to_rad(110.0), 0.0), Color(0.9, 0.55, 1.0))

	# Four small guards clustered tight around the base for a planted look
	for i in 4:
		var angle: float = TAU * i / 4 + 0.45
		var offset := Vector3(cos(angle) * 3.2, 0.0, sin(angle) * 3.2)
		var c := Color(0.4, 0.2, 0.7)
		_add_crystal(_formation, offset + Vector3(0.0, 2.5, 0.0),
			Vector3(4.0, 6.0, 4.0),
			Vector3(deg_to_rad(randf_range(-12.0, 12.0)), angle, 0.0), c)


func _add_crystal(parent: Node3D, pos: Vector3, scale_val: Vector3, rot: Vector3, tint: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Crystal"
	mi.mesh = _get_crystal_mesh()
	mi.scale = scale_val
	mi.position = pos
	mi.rotation = rot
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 1.2
	mat.metallic = 0.3
	mat.roughness = 0.4
	mi.material_override = mat
	parent.add_child(mi)
	_crystal_nodes.append(mi)
	_crystal_mats.append(mat)


## Crystals.glb is a PackedScene, not a Mesh. Instantiate it once and pull out
## the actual Mesh resource from the first MeshInstance3D so it can be reused
## across the whole formation.
static func _get_crystal_mesh() -> Mesh:
	if _crystal_mesh != null:
		return _crystal_mesh
	var root := CRYSTAL_SCENE.instantiate()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				_crystal_mesh = mi.mesh
				break
		for c in n.get_children():
			stack.append(c)
	root.free()
	return _crystal_mesh


# ---------------------------------------------------------------------------
# Collision
# ---------------------------------------------------------------------------

func _build_collision() -> void:
	_body = StaticBody3D.new()
	_body.name = "BossBody"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.add_to_group("boss")
	add_child(_body)

	# Main tower box covering most of the formation
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(16.0, 34.0, 16.0)
	col.shape = box
	col.position.y = 16.0
	_body.add_child(col)

	# Lower base box so shots at the guards also connect
	var col2 := CollisionShape3D.new()
	var box2 := BoxShape3D.new()
	box2.size = Vector3(17.0, 10.0, 17.0)
	col2.shape = box2
	col2.position.y = 4.0
	_body.add_child(col2)


# ---------------------------------------------------------------------------
# Combat
# ---------------------------------------------------------------------------

func _face_toward(tgt: Vector3, dt: float) -> void:
	var dx: float = tgt.x - position.x
	var dz: float = tgt.z - position.z
	var target_yaw: float = atan2(dx, dz)
	var delta: float = _angle_diff(target_yaw, rotation.y)
	rotation.y += delta * minf(0.5 * dt, 1.0)


func _fire_volley(player_pos: Vector3, player_vel: Vector3 = Vector3.ZERO) -> void:
	var apex: Vector3 = position + Vector3(0.0, 28.0, 0.0)
	
	# Calculate estimated travel time to current position
	var flight_time: float = apex.distance_to(player_pos) / shard_speed
	
	# Predict player location when the shards reach them
	var predicted_pos: Vector3 = player_pos + (player_vel * flight_time)
	
	# Account for gravity drop during flight in _update_shards (19.6 m/s^2)
	# by aiming slightly higher: height_offset = 0.5 * g * t^2
	predicted_pos.y += 0.5 * 19.6 * pow(flight_time, 2.0)
	
	var base_dir: Vector3 = (predicted_pos - apex).normalized()

	for i in shards_per_volley:
		var sv: Vector3 = base_dir * shard_speed
		
		# Add spread around predicted position
		sv.x += (randf() - 0.5) * 6.0
		sv.y += (randf() - 0.5) * 3.0
		sv.z += (randf() - 0.5) * 6.0
		
		var origin: Vector3 = apex + Vector3((randf() - 0.5) * 4.0, 0.0, (randf() - 0.5) * 4.0)
		_spawn_shard(origin, sv)


func _spawn_shard(pos: Vector3, vel: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Shard"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.6, 0.6, 0.6)
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.65, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.85, 0.65, 0.2)
	mat.emission_energy_multiplier = 1.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	# Shards live in world space (parent = world) so boss rotation does not skew them
	var host: Node = world if world != null else get_parent()
	host.add_child(mi)
	mi.global_position = pos
	mi.set_meta("vel", vel)
	_shards.append({"node": mi, "vel": vel, "life": 0.0})
	print("TMP append name=", mi.name, " buf=", _shards.size())


func _spawn_shard_impact(pos: Vector3) -> void:
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.5
	sphere.height = 3.0
	flash.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.7, 0.2, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.6, 0.1)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash.material_override = mat
	var host: Node = world if world != null else get_parent()
	host.add_child(flash)
	flash.global_position = pos
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(flash, "scale", Vector3.ONE * 3.0, 0.3)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tw.chain().tween_callback(flash.queue_free)


func _update_shards(dt: float, player_pos: Vector3) -> void:
	var i: int = 0
	while i < _shards.size():
		var s: Dictionary = _shards[i]
		print("TMP update i=", i, " sz=", _shards.size(), " life=", s["life"], " vel=", s["vel"])
		s["life"] += dt
		var vel: Vector3 = s["vel"]
		vel.y -= 19.6 * dt
		vel += Vector3(0.4, 0.0, 0.15) * dt
		var mi: MeshInstance3D = s["node"]
		mi.position += vel * dt
		mi.rotation.x += dt * 3.0
		mi.rotation.y += dt * 4.0
		s["vel"] = vel
		var dead := false
		var shard_global: Vector3 = mi.global_position
		if shard_global.distance_to(player_pos) < 4.0:
			if world and world.has_method("damage_player"):
				world.damage_player(shard_damage)
			dead = true
		elif shard_global.y <= GEN.terrain_height(shard_global.x, shard_global.z):
			dead = true
		elif s["life"] > 6.0:
			dead = true
		if dead:
			print("TMP dead dist=", shard_global.distance_to(player_pos),
				" y=", roundf(shard_global.y), " terr=", roundf(GEN.terrain_height(shard_global.x, shard_global.z)),
				" life=", s["life"], " dead=", dead)
			_spawn_shard_impact(shard_global)
			mi.queue_free()
			_shards.remove_at(i)
		else:
			i += 1


func _on_defeated() -> void:
	state = "defeated"
	for s in _shards:
		(s["node"] as Node3D).queue_free()
	_shards.clear()
	_body.set_deferred("collision_layer", 0)
	defeated.emit()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - 5.0, 1.5).set_ease(Tween.EASE_IN)
	for i in _crystal_nodes.size():
		var mi: MeshInstance3D = _crystal_nodes[i]
		if is_instance_valid(mi):
			mi.material_override = _crystal_mats[i]
			tween.tween_property(_crystal_mats[i], "albedo_color:a", 0.0, 1.5)
	tween.chain().tween_callback(queue_free)


static func _angle_diff(target: float, current: float) -> float:
	var d: float = target - current
	while d > PI:
		d -= TAU
	while d < -PI:
		d += TAU
	return d
