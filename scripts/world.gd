extends Node3D
const GEN := preload("res://scripts/world_gen.gd")
## Main world controller.
##
## Builds the procedural canyon level from heightmap + control maps produced by
## WorldGen (scripts/world_gen.gd). Those are pre-generated on a worker thread while Intro.tscn plays
## (see scripts/world_gen.gd); entering World directly regenerates synchronously
## as a fallback. This script is responsible for all scene work: Terrain3D
## asset/material setup, image import, collision, instanced rock + grass cards,
## water, outpost beacons and the boss-arena marker.
##
## The tank's health life is driven here: sitting submerged in the SE basin
## hazard (see WorldGen.is_in_hazard) drains health until the unit is destroyed.
## The mouse is captured on entry (pause menu / main menu restore it).

const HAZARD_DPS := 30.0

const TEX_PATH_GRASS := "res://assets/textures/grass_big.png"
const TEX_PATH_TIERRA := "res://assets/textures/tierra_big.png"
const TEX_PATH_GRAVA := "res://assets/textures/grava_big.png"
const TEX_PATH_ARENA := "res://assets/textures/arena_big.png"

const OUTPOST_A := Vector3(120.0, 0.0, 512.0)
const OUTPOST_B := Vector3(928.0, 0.0, 512.0)

var _boss_arena: Node3D
var _player: Node = null
var _water_mesh: MeshInstance3D = null


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var terrain := _create_terrain()
	_add_water()
	_add_outposts_and_markers(terrain)
	_show_controls_hint()


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_node_or_null("Player")
	if _player == null:
		return
	if _player.get("destroyed"):
		return
	if GEN.is_in_hazard(_player.global_position):
		if _player.has_method("take_damage"):
			_player.take_damage(HAZARD_DPS * delta)


func _create_terrain() -> Terrain3D:
	var maps := GEN.consume_result()
	if maps.size() < 2:
		maps = GEN.generate_now()

	var grass_ta := _create_texture_asset("Grass", TEX_PATH_GRASS, 0.65, 1001)
	var tierra_ta := _create_texture_asset("Tierra", TEX_PATH_TIERRA, 0.9, 2002)
	var grava_ta := _create_texture_asset("Grava", TEX_PATH_GRAVA, 1.2, 3003)
	var arena_ta := _create_texture_asset("Arena", TEX_PATH_ARENA, 1.05, 4004)
	var rock_ma := _create_mesh_asset("Rock", Color(0.55, 0.5, 0.45), false)
	var grass_ma := _create_mesh_asset("GrassCard", Color(0.28, 0.43, 0.2), true)

	var terrain := Terrain3D.new()
	terrain.name = "Terrain3D"
	add_child(terrain, true)

	terrain.material.world_background = Terrain3DMaterial.NONE
	terrain.material.auto_shader = true
	terrain.material.set_shader_param("auto_slope", 10)
	terrain.material.set_shader_param("blend_sharpness", 0.975)
	terrain.assets = Terrain3DAssets.new()
	terrain.assets.set_texture(GEN.TEX_GRASS, grass_ta)
	terrain.assets.set_texture(GEN.TEX_TIERRA, tierra_ta)
	terrain.assets.set_texture(GEN.TEX_GRAVA, grava_ta)
	terrain.assets.set_texture(GEN.TEX_ARENA, arena_ta)
	terrain.assets.set_mesh_asset(0, rock_ma)
	terrain.assets.set_mesh_asset(1, grass_ma)

	terrain.region_size = GEN.IMG_SIZE
	terrain.data.import_images([maps[0], maps[1], null], Vector3.ZERO, 0.0, 1.0)
	terrain.data.calc_height_range()

	# Auto-generate physics collision for the freshly imported heightmap
	terrain.collision.mode = Terrain3DCollision.FULL_GAME

	_scatter_rocks(terrain)
	_scatter_grass(terrain)

	return terrain


func _scatter_rocks(p_terrain: Terrain3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var xforms: Array[Transform3D]
	for i in 320:
		var rx: float = rng.randf_range(20.0, GEN.IMG_SIZE - 20.0)
		var rz: float = rng.randf_range(20.0, GEN.IMG_SIZE - 20.0)
		var d := absf(rz - GEN.SPINE_Z)
		# Keep the corridor floor drivable: scatter along the canyon walls only
		if d < GEN.HALF_WIDTH - 6.0 or d > GEN.WALL_BAND + 40.0:
			continue
		if GEN.terrain_height(rx, rz) < 0.0:
			continue
		var pos := Vector3(rx, 0.0, rz)
		pos.y = p_terrain.data.get_height(pos)
		var scale := rng.randf_range(1.2, 4.5)
		var t := Transform3D(Basis().scaled(Vector3.ONE * scale), pos)
		t = t.rotated(Vector3.UP, rng.randf_range(0.0, TAU))
		xforms.push_back(t)
	p_terrain.instancer.add_transforms(0, xforms)


func _scatter_grass(p_terrain: Terrain3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var xforms: Array[Transform3D]
	for i in 520:
		var rx: float = rng.randf_range(60.0, GEN.IMG_SIZE - 60.0)
		var rz: float = rng.randf_range(GEN.SPINE_Z - GEN.HALF_WIDTH + 6.0, GEN.SPINE_Z + GEN.HALF_WIDTH - 6.0)
		# Skip the boss bowl and keep spawn / beacon pads unobstructed
		if Vector2(rx, rz).distance_to(GEN.BOSS_CENTER) < GEN.BOSS_RADIUS + 12.0:
			continue
		if Vector2(rx, rz).distance_to(Vector2(OUTPOST_A.x, OUTPOST_A.z)) < 40.0:
			continue
		if Vector2(rx, rz).distance_to(Vector2(OUTPOST_B.x, OUTPOST_B.z)) < 40.0:
			continue
		if GEN.terrain_height(rx, rz) < 0.0:
			continue
		var pos := Vector3(rx, 0.0, rz)
		pos.y = p_terrain.data.get_height(pos)
		var scale := rng.randf_range(0.6, 1.8)
		var t := Transform3D(Basis().scaled(Vector3.ONE * scale), pos)
		t = t.rotated(Vector3.UP, rng.randf_range(0.0, TAU))
		xforms.push_back(t)
	p_terrain.instancer.add_transforms(1, xforms)


func _add_water() -> void:
	var water := MeshInstance3D.new()
	water.name = "Water"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(260, 220)
	water.mesh = mesh
	water.position = Vector3(910, GEN.SEA_LEVEL + 0.1, 880)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.15, 0.4, 0.65, 0.55)
	mat.metallic = 0.2
	mat.roughness = 0.15
	water.material_override = mat
	add_child(water)
	_water_mesh = water


func _add_outposts_and_markers(p_terrain: Terrain3D) -> void:
	_add_outpost("OutpostA", OUTPOST_A, p_terrain, Color(0.95, 0.6, 0.15))
	_add_outpost("OutpostB", OUTPOST_B, p_terrain, Color(0.85, 0.2, 0.2))
	_boss_arena = _add_marker("BossArena",
		Vector3(GEN.BOSS_CENTER.x, 0.0, GEN.BOSS_CENTER.y), p_terrain, Color(0.6, 0.2, 0.9))


## Snaps p_pos onto the terrain surface (keeping its x/z), so beacons planted
## with ground-level y still stand on top of the canyon floor.
func _snap_to_terrain(p_pos: Vector3, p_terrain: Terrain3D) -> Vector3:
	var h: float = p_terrain.data.get_height(p_pos)
	if is_nan(h):
		return p_pos
	return Vector3(p_pos.x, h, p_pos.z)


func _add_outpost(p_name: String, p_pos: Vector3, p_terrain: Terrain3D, p_color: Color) -> void:
	var outpost := Node3D.new()
	outpost.name = p_name
	outpost.position = _snap_to_terrain(p_pos, p_terrain)
	var pole := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 4.0, 1.0)
	pole.mesh = mesh
	pole.position = Vector3(0.0, 2.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = p_color
	mat.emission_enabled = true
	mat.emission = p_color
	mat.emission_energy_multiplier = 2.0
	pole.material_override = mat
	outpost.add_child(pole)
	var light := OmniLight3D.new()
	light.position = Vector3(0.0, 6.0, 0.0)
	light.light_color = p_color
	light.omni_range = 24.0
	light.light_energy = 2.0
	outpost.add_child(light)
	var label := Label3D.new()
	label.text = p_name
	label.position = Vector3(0.0, 6.5, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.005
	outpost.add_child(label)
	add_child(outpost)


func _add_marker(p_name: String, p_pos: Vector3, p_terrain: Terrain3D, p_color: Color) -> Node3D:
	var marker := Node3D.new()
	marker.name = p_name
	marker.position = _snap_to_terrain(p_pos, p_terrain) + Vector3(0.0, 0.5, 0.0)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 90.0
	torus.outer_radius = 96.0
	torus.rings = 24
	torus.ring_segments = 64
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = p_color
	mat.emission_enabled = true
	mat.emission = p_color
	mat.emission_energy_multiplier = 2.5
	ring.material_override = mat
	ring.rotation_degrees = Vector3(90, 0, 0)
	marker.add_child(ring)
	var label := Label3D.new()
	label.text = p_name
	label.position = Vector3(0.0, 5.0, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.005
	marker.add_child(label)
	add_child(marker)
	return marker


func _create_texture_asset(asset_name: String, path: String, uv_scale: float, seed: int) -> Terrain3DTextureAsset:
	var ta := Terrain3DTextureAsset.new()
	ta.name = asset_name
	ta.albedo_texture = load(path)
	ta.normal_texture = _make_procedural_normal(seed)
	ta.uv_scale = uv_scale
	ta.detiling_rotation = 0.1
	return ta


## Cheap procedural normal map (no real normal assets shipped with the arena
## textures) so the terrain catches directional light instead of looking flat.
func _make_procedural_normal(p_seed: int) -> ImageTexture:
	var sz := 256
	var img := Image.create_empty(sz, sz, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.04
	noise.seed = p_seed
	for y in sz:
		for x in sz:
			var h00 := noise.get_noise_2d(x, y)
			var hx := noise.get_noise_2d(x + 1, y)
			var hz := noise.get_noise_2d(x, y + 1)
			var v := Vector3(h00 - hx, h00 - hz, 0.3).normalized()
			img.set_pixel(x, y, Color(v.x * 0.5 + 0.5, v.y * 0.5 + 0.5, v.z * 0.5 + 0.5, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _create_mesh_asset(asset_name: String, color: Color, translucent: bool) -> Terrain3DMeshAsset:
	var ma := Terrain3DMeshAsset.new()
	ma.name = asset_name
	ma.generated_type = Terrain3DMeshAsset.TYPE_TEXTURE_CARD
	ma.material_override.albedo_color = color
	ma.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	if translucent:
		ma.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ma.material_override.albedo_color.a = 0.65
	return ma


func engaged_boss_zone() -> Node:
	return _boss_arena


## Shows a brief on-screen controls reminder at the very start of the level
## (not the intro screen — the intro carries a static panel). Auto-fades away
## after a few seconds so it never gets in the way.
func _show_controls_hint() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ControlsHint"
	add_child(layer)

	var holder := MarginContainer.new()
	holder.set_anchors_preset(Control.PRESET_TOP_WIDE)
	holder.offset_top = 18.0
	layer.add_child(holder)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.02, 0.03, 0.6)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", sb)
	holder.add_child(panel)

	var label := Label.new()
	label.text = "W/S Conducir  ·  A/D Girar  ·  RATÓN Apuntar  ·  CLIC IZQ. Disparar  ·  ESPACIO Freno  ·  V Cámara  ·  ESC Pausa"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	panel.add_child(label)

	var tween := create_tween()
	tween.tween_interval(6.0)
	tween.tween_property(holder, "modulate:a", 0.0, 1.2)
	tween.tween_callback(layer.queue_free)
