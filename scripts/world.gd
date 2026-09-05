extends Node3D
## Main world controller.
##
## Builds the procedural canyon level at runtime from a heightmap generated in
## code (ported from demo/CanyonDemo.tscn + demo/src/CanyonGenerated.gd):
## a 1024x1024 m canyon corridor carved through a 150 m high ridge, a boss
## arena bowl, a ramp down to a NE sea basin, water, outpost beacons and a
## boss-arena marker. Terrain is splatted with four texture layers loaded from
## assets/textures (grass / tierra / grava / arena) via a slope-driven control
## map, and decorated with instanced rock + grass cards.
##
## Captures the mouse on entry so mouse-look aiming works (pause menu / main
## menu restore it).

const IMG_SIZE := 1024

const SEA_LEVEL := 0.0
const FLOOR_HEIGHT := 30.0
const BOSS_FLOOR := 18.0
const WALL_HEIGHT := 150.0
const HALF_WIDTH := 40.0
const WALL_BAND := 90.0
const SPINE_Z := 512.0

const BOSS_CENTER := Vector2(512.0, 512.0)
const BOSS_RADIUS := 95.0

const RAMP_P0 := Vector2(690.0, 512.0)
const RAMP_P1 := Vector2(880.0, 900.0)
const COAST_ROUGH := -14.0

const BASIN_ORIGIN := Vector2(780.0, 720.0)
const BASIN_EXTENT := Vector2(200.0, 260.0)
const BASIN_DEPTH := -30.0

const OUTPOST_A := Vector3(120.0, 0.0, 512.0)
const OUTPOST_B := Vector3(928.0, 0.0, 512.0)

## Control-map texture slots (Terrain3DAssets texture_list / control IDs)
const TEX_GRASS := 0
const TEX_TIERRA := 1
const TEX_GRAVA := 2
const TEX_ARENA := 3

const TEX_PATH_GRASS := "res://assets/textures/grass.png"
const TEX_PATH_TIERRA := "res://assets/textures/tierra.png"
const TEX_PATH_GRAVA := "res://assets/textures/grava.png"
const TEX_PATH_ARENA := "res://assets/textures/arena.png"

var _noise := FastNoiseLite.new()
var _patch_noise := FastNoiseLite.new()

var _boss_arena: Node3D


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var terrain := _create_terrain()
	_add_water()
	_add_outposts_and_markers(terrain)


func _create_terrain() -> Terrain3D:
	_noise.frequency = 0.02
	_noise.seed = 1337
	_patch_noise.frequency = 0.045
	_patch_noise.seed = 777

	var grass_ta := _create_texture_asset("Grass", TEX_PATH_GRASS, 0.5, 1001)
	var tierra_ta := _create_texture_asset("Tierra", TEX_PATH_TIERRA, 0.7, 2002)
	var grava_ta := _create_texture_asset("Grava", TEX_PATH_GRAVA, 0.9, 3003)
	var arena_ta := _create_texture_asset("Arena", TEX_PATH_ARENA, 0.8, 4004)
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
	terrain.assets.set_texture(TEX_GRASS, grass_ta)
	terrain.assets.set_texture(TEX_TIERRA, tierra_ta)
	terrain.assets.set_texture(TEX_GRAVA, grava_ta)
	terrain.assets.set_texture(TEX_ARENA, arena_ta)
	terrain.assets.set_mesh_asset(0, rock_ma)
	terrain.assets.set_mesh_asset(1, grass_ma)

	var height_img := _build_heightmap()
	var control_img := _build_controlmap(height_img)

	terrain.region_size = IMG_SIZE
	terrain.data.import_images([height_img, control_img, null], Vector3.ZERO, 0.0, 1.0)
	terrain.data.calc_height_range()

	# Auto-generate physics collision for the freshly imported heightmap
	terrain.collision.mode = Terrain3DCollision.FULL_GAME

	_scatter_rocks(terrain)
	_scatter_grass(terrain)

	return terrain


## Builds a 32-bit float heightmap. Every pixel maps to one world meter.
func _build_heightmap() -> Image:
	var img := Image.create_empty(IMG_SIZE, IMG_SIZE, false, Image.FORMAT_RF)
	for x in IMG_SIZE:
		for y in IMG_SIZE:
			img.set_pixel(x, y, Color(_terrain_height(float(x), float(y)), 0.0, 0.0, 1.0))
	return img


## Splats the four texture layers with a per-texel control map: base/overlay
## texture ids plus a blend or the auto-slope flag. Slope is sampled from the
## height image so no extra heightmap re-evaluations are needed.
func _build_controlmap(p_height: Image) -> Image:
	var img := Image.create_empty(IMG_SIZE, IMG_SIZE, false, Image.FORMAT_RF)
	for y in IMG_SIZE:
		for x in IMG_SIZE:
			var wx := float(x)
			var wz := float(y)

			var hl := p_height.get_pixel(maxi(x - 1, 0), y).r
			var hr := p_height.get_pixel(mini(x + 1, IMG_SIZE - 1), y).r
			var hu := p_height.get_pixel(x, maxi(y - 1, 0)).r
			var hd := p_height.get_pixel(x, mini(y + 1, IMG_SIZE - 1)).r
			var slope := Vector2(hr - hl, hd - hu).length() * 0.5

			var d := absf(wz - SPINE_Z)
			var br := Vector2(wx, wz).distance_to(BOSS_CENTER)
			var f := _basin_factor(wx, wz)
			var sd := point_segment_distance(Vector2(wx, wz), RAMP_P0, RAMP_P1)
			var t := segment_param(Vector2(wx, wz), RAMP_P0, RAMP_P1)

			var base := TEX_TIERRA
			var overlay := TEX_GRASS
			var blend := 64
			var auto := false

			if f > 0.0:
				# NE sea basin: gravel bed, mid earth mix
				base = TEX_GRAVA
				overlay = TEX_TIERRA
				blend = 190
			elif sd <= WALL_BAND:
				# Ramp descending to the coast: rocky, drying toward the sea
				base = TEX_GRAVA
				overlay = TEX_ARENA
				blend = int(lerpf(90.0, 210.0, smoothstep01(t)))
			elif br <= BOSS_RADIUS:
				# Boss arena bowl: packed arena dirt with grass creeping in
				base = TEX_ARENA
				overlay = TEX_GRASS
				auto = true
			elif d <= HALF_WIDTH:
				# Corridor floor: grass dominant, with noisy dirt/gravel patches
				var patch := _patch_noise.get_noise_2d(wx * 0.5, wz * 0.5)
				if patch > 0.35:
					base = TEX_TIERRA
					overlay = TEX_GRAVA
					var strength := smoothstep01(clampf((patch - 0.35) / 0.4, 0.0, 1.0))
					blend = int(lerpf(40.0, 170.0, strength))
				else:
					base = TEX_GRASS
					overlay = TEX_TIERRA
					auto = true
			elif d < WALL_BAND:
				# Canyon walls: rock face, more bare gravel on steeper slopes
				base = TEX_ARENA
				overlay = TEX_GRAVA
				blend = int(lerpf(120.0, 250.0, clampf(slope * 0.3, 0.0, 1.0)))
			else:
				# Open badlands beyond the ridge: bare earth with grass on bumps
				base = TEX_TIERRA
				overlay = TEX_GRASS
				auto = true

			var bits := Terrain3DUtil.enc_base(base) | Terrain3DUtil.enc_overlay(overlay)
			if auto:
				bits |= Terrain3DUtil.enc_auto(true)
			else:
				bits |= Terrain3DUtil.enc_blend(clampi(blend, 0, 255))
			img.set_pixel(x, y, Color(Terrain3DUtil.as_float(bits), 0.0, 0.0, 1.0))
	return img


func _terrain_height(wx: float, wz: float) -> float:
	var h: float = WALL_HEIGHT

	# Main canyon corridor along z=512
	var d: float = absf(wz - SPINE_Z)
	if d <= HALF_WIDTH:
		h = FLOOR_HEIGHT + _floor_noise(wx, wz)
	elif d < WALL_BAND:
		h = lerpf(FLOOR_HEIGHT, WALL_HEIGHT,
			smoothstep01((d - HALF_WIDTH) / (WALL_BAND - HALF_WIDTH)))

	# Boss arena bowl carved into the corridor
	var br: float = Vector2(wx, wz).distance_to(BOSS_CENTER)
	if br <= BOSS_RADIUS:
		h = minf(h, lerpf(BOSS_FLOOR, FLOOR_HEIGHT, smoothstep01(br / BOSS_RADIUS)))

	# NE sea basin
	var f: float = _basin_factor(wx, wz)
	if f > 0.0:
		h = lerpf(h, BASIN_DEPTH, f)

	# Coast ramp forking off the main corridor toward the NE basin
	var sd: float = point_segment_distance(Vector2(wx, wz), RAMP_P0, RAMP_P1)
	var t: float = segment_param(Vector2(wx, wz), RAMP_P0, RAMP_P1)
	var ramp_v: float = lerpf(FLOOR_HEIGHT, COAST_ROUGH, smoothstep01(t))
	if sd <= HALF_WIDTH:
		h = ramp_v + _floor_noise(wx, wz) * 0.5
	elif sd < WALL_BAND:
		var mixv: float = smoothstep01((sd - HALF_WIDTH) / (WALL_BAND - HALF_WIDTH))
		h = lerpf(ramp_v, h, mixv)

	return h


func _floor_noise(wx: float, wz: float) -> float:
	return (_noise.get_noise_2d(wx, wz) + 1.0) * 0.35


func _basin_factor(wx: float, wz: float) -> float:
	var fx: float = smoothstep01((wx - BASIN_ORIGIN.x) / BASIN_EXTENT.x)
	var fz: float = smoothstep01((wz - BASIN_ORIGIN.y) / BASIN_EXTENT.y)
	return fx * fz


func _scatter_rocks(p_terrain: Terrain3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var xforms: Array[Transform3D]
	for i in 320:
		var rx: float = rng.randf_range(20.0, IMG_SIZE - 20.0)
		var rz: float = rng.randf_range(20.0, IMG_SIZE - 20.0)
		var d := absf(rz - SPINE_Z)
		# Keep the corridor floor drivable: scatter along the canyon walls only
		if d < HALF_WIDTH - 6.0 or d > WALL_BAND + 40.0:
			continue
		if _terrain_height(rx, rz) < 0.0:
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
		var rx: float = rng.randf_range(60.0, IMG_SIZE - 60.0)
		var rz: float = rng.randf_range(SPINE_Z - HALF_WIDTH + 6.0, SPINE_Z + HALF_WIDTH - 6.0)
		# Skip the boss bowl and keep spawn / beacon pads unobstructed
		if Vector2(rx, rz).distance_to(BOSS_CENTER) < BOSS_RADIUS + 12.0:
			continue
		if Vector2(rx, rz).distance_to(Vector2(OUTPOST_A.x, OUTPOST_A.z)) < 40.0:
			continue
		if Vector2(rx, rz).distance_to(Vector2(OUTPOST_B.x, OUTPOST_B.z)) < 40.0:
			continue
		if _terrain_height(rx, rz) < 0.0:
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
	water.position = Vector3(910, SEA_LEVEL + 0.1, 880)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.15, 0.4, 0.65, 0.55)
	mat.metallic = 0.2
	mat.roughness = 0.15
	water.material_override = mat
	add_child(water)


func _add_outposts_and_markers(p_terrain: Terrain3D) -> void:
	_add_outpost("OutpostA", OUTPOST_A, p_terrain, Color(0.95, 0.6, 0.15))
	_add_outpost("OutpostB", OUTPOST_B, p_terrain, Color(0.85, 0.2, 0.2))
	_boss_arena = _add_marker("BossArena",
		Vector3(BOSS_CENTER.x, 0.0, BOSS_CENTER.y), p_terrain, Color(0.6, 0.2, 0.9))


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


func smoothstep01(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(a.lerp(b, clampf((p - a).dot(b - a) / a.distance_squared_to(b), 0.0, 1.0)))


func segment_param(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	if ab.length_squared() <= 0.000001:
		return 0.0
	return clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
