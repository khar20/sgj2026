class_name WorldGen
## Procedural terrain generator shared by the Intro and World scenes.
##
## The heavy heightmap / control-map loops run on a worker thread started by
## Intro (so the map generates while the lore is on screen); World then picks up
## the finished images. Running World directly (e.g. F6 from the editor) falls
## back to generating synchronously in _create_terrain.
##
## Everything on this class is pure data: plain math, FastNoiseLite sampling and
## Image writes. No SceneTree / Node / UI access, so it is safe on a worker
## thread. Bit packing reproduces Terrain3DUtil's control-map layout locally so
## no addon code is touched off-thread:
##   bits 27-31 base id (.5 bits), 22-26 overlay id, 14-21 blend,
##   10-13 uv rotation (0-15), 7-9 uv scale (0-7), 2 hole, 1 nav, 0 auto.

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

## Rect where the tank is submerged (matches the water plane world.gd places at
## (910, 0.1, 880), size 260x220).
const HAZARD_RECT := Rect2(780.0, 770.0, 260.0, 220.0)
const HAZARD_CEILING := 1.0

## Control-map texture slots (Terrain3DAssets texture_list / control IDs)
const TEX_GRASS := 0
const TEX_TIERRA := 1
const TEX_GRAVA := 2
const TEX_ARENA := 3

static var _thread: Thread = null
static var _result: Array = []
static var _progress := 0.0

static var _relief: FastNoiseLite = null
static var _patch: FastNoiseLite = null


## Starts map generation on a background thread. Safe to call any number of times.
static func start_generation() -> void:
	if _thread != null and _thread.is_alive():
		return
	if not _result.is_empty():
		return
	_thread = Thread.new()
	_thread.start(_generate_on_thread)


static func _generate_on_thread() -> void:
	_result = _generate()


static func _generate() -> Array:
	_progress = 0.0
	var height_img := _build_heightmap(_relief_noise(), _patch_noise())
	_progress = 0.5
	var control_img := _build_controlmap(height_img, _patch_noise())
	_progress = 1.0
	return [height_img, control_img]


## Returns [height_image, control_image] once available. If the worker thread is
## still running it is waited for (blocks the caller briefly). Returns an empty
## Array when nothing was generated yet (World-generates-on-demand instead).
static func consume_result() -> Array:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	var maps := _result
	_result = []
	return maps


static func ready() -> bool:
	return _result.size() == 2


static func progress() -> float:
	return _progress


## Synchronous generation (recalled by World when run directly with no cache).
static func generate_now() -> Array:
	return _generate()


## Single-point height query used by decoration scatter on the main thread.
static func terrain_height(wx: float, wz: float) -> float:
	return _terrain_height(_relief_noise(), _patch_noise(), wx, wz)


## True when a tank parked at p_pos is inside the submerged hazard basin.
static func is_in_hazard(p_pos: Vector3) -> bool:
	if p_pos.y > HAZARD_CEILING:
		return false
	return HAZARD_RECT.has_point(Vector2(p_pos.x, p_pos.z))


# ============================================================================
# Noise
# ============================================================================

static func _relief_noise() -> FastNoiseLite:
	if _relief == null:
		_relief = FastNoiseLite.new()
		_relief.frequency = 0.017
		_relief.seed = 1337
		_relief.fractal_type = FastNoiseLite.FRACTAL_FBM
		_relief.fractal_octaves = 6
		_relief.fractal_lacunarity = 2.0
		_relief.fractal_gain = 0.5
		_relief.domain_warp_enabled = true
		_relief.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
		_relief.domain_warp_amplitude = 6.0
		_relief.domain_warp_frequency = 0.02
	return _relief


static func _patch_noise() -> FastNoiseLite:
	if _patch == null:
		_patch = FastNoiseLite.new()
		_patch.frequency = 0.045
		_patch.seed = 777
	return _patch


# ============================================================================
# Heightmap
# ============================================================================

## Returns a 32-bit float heightmap. Every pixel maps to one world meter.
static func _build_heightmap(relief: FastNoiseLite, patch: FastNoiseLite) -> Image:
	var img := Image.create_empty(IMG_SIZE, IMG_SIZE, false, Image.FORMAT_RF)
	for y in IMG_SIZE:
		for x in IMG_SIZE:
			img.set_pixel(x, y, Color(_terrain_height(relief, patch, float(x), float(y)), 0.0, 0.0, 1.0))
		_progress = 0.5 * (y + 1.0) / IMG_SIZE
	return img


static func _terrain_height(relief: FastNoiseLite, patch: FastNoiseLite, wx: float, wz: float) -> float:
	# Shared relief field: multi-octave FBM + domain warp reads as natural terrain
	var hn := relief.get_noise_2d(wx, wz)
	var h: float = WALL_HEIGHT + hn * 4.0

	# Main canyon corridor along z=512; the ridgeline edge is jittered so the
	# cliff shoulders meander instead of running ruler-straight
	var d: float = absf(wz - SPINE_Z)
	var d_eff := d + patch.get_noise_2d(wx * 0.7 + 40.0, wz * 0.7 + 20.0) * 8.0
	if d_eff <= HALF_WIDTH:
		h = FLOOR_HEIGHT + hn * 1.2
	elif d_eff < WALL_BAND:
		var band: float = smoothstep01((d_eff - HALF_WIDTH) / (WALL_BAND - HALF_WIDTH))
		h = lerpf(FLOOR_HEIGHT + hn * 1.2, h, band)

	# Boss arena bowl carved into the corridor, keeping its natural relief
	var br: float = Vector2(wx, wz).distance_to(BOSS_CENTER)
	if br <= BOSS_RADIUS:
		var bowl_h: float = lerpf(BOSS_FLOOR, FLOOR_HEIGHT, smoothstep01(br / BOSS_RADIUS))
		h = minf(h, bowl_h + hn * 0.9)

	# NE sea basin
	var f: float = _basin_factor(wx, wz)
	if f > 0.0:
		h = lerpf(h, BASIN_DEPTH, f)

	# Coast ramp forking off the main corridor toward the NE basin
	var sd: float = point_segment_distance(Vector2(wx, wz), RAMP_P0, RAMP_P1)
	var t: float = segment_param(Vector2(wx, wz), RAMP_P0, RAMP_P1)
	var ramp_v: float = lerpf(FLOOR_HEIGHT, COAST_ROUGH, smoothstep01(t))
	if sd <= HALF_WIDTH:
		h = ramp_v + hn * 0.8
	elif sd < WALL_BAND:
		var mixv: float = smoothstep01((sd - HALF_WIDTH) / (WALL_BAND - HALF_WIDTH))
		h = lerpf(ramp_v + hn * 0.8, h, mixv)

	return h


static func _basin_factor(wx: float, wz: float) -> float:
	var fx: float = smoothstep01((wx - BASIN_ORIGIN.x) / BASIN_EXTENT.x)
	var fz: float = smoothstep01((wz - BASIN_ORIGIN.y) / BASIN_EXTENT.y)
	return fx * fz


# ============================================================================
# Control map
# ============================================================================

static func _build_controlmap(p_height: Image, patch: FastNoiseLite) -> Image:
	var img := Image.create_empty(IMG_SIZE, IMG_SIZE, false, Image.FORMAT_RF)
	for y in IMG_SIZE:
		for x in IMG_SIZE:
			var wx := float(x)
			var wz := float(y)

			var h0 := p_height.get_pixel(x, y).r
			var hl := p_height.get_pixel(maxi(x - 1, 0), y).r
			var hr := p_height.get_pixel(mini(x + 1, IMG_SIZE - 1), y).r
			var hu := p_height.get_pixel(x, maxi(y - 1, 0)).r
			var hd := p_height.get_pixel(x, mini(y + 1, IMG_SIZE - 1)).r
			var slope := Vector2(hr - hl, hd - hu).length() * 0.5

			# Dual-scaling stipple: vary the texture scale and rotation every few
			# meters (interpolated from smooth noise, so it patches rather than shimmers)
			var stipple := patch.get_noise_2d(wx * 3.7, wz * 3.7)
			var uv_scale := 0
			if absf(stipple) > 0.12:
				uv_scale = 1 + int(absf(stipple) * 5.99)
			var uv_rot := int((stipple * 0.5 + 0.5) * 15.0)

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
				# Corridor floor: grass dominant, dirt/gravel where the relief dips
				var low := FLOOR_HEIGHT - h0
				if low > 0.0:
					base = TEX_TIERRA
					overlay = TEX_GRAVA
					blend = int(lerpf(40.0, 170.0, clampf(low / 1.2, 0.0, 1.0)))
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

			var bits := _enc_base(base) | _enc_overlay(overlay) | _enc_uv_scale(uv_scale)
			bits |= _enc_uv_rotation(uv_rot)
			if auto:
				bits |= _enc_auto(true)
			else:
				bits |= _enc_blend(clampi(blend + int(stipple * 25.0), 0, 255))
			img.set_pixel(x, y, Color(_bits_to_float(bits), 0.0, 0.0, 1.0))
		_progress = 0.5 + 0.5 * (y + 1.0) / IMG_SIZE
	return img


# ============================================================================
# Control-map bit packing (mirrors Terrain3DUtil, see header docs above)
# ============================================================================

static func _enc_base(p_id: int) -> int:
	return (p_id & 0x1F) << 27


static func _enc_overlay(p_id: int) -> int:
	return (p_id & 0x1F) << 22


static func _enc_blend(p_blend: int) -> int:
	return (p_blend & 0xFF) << 14


static func _enc_uv_rotation(p_rot: int) -> int:
	return (p_rot & 0xF) << 10


static func _enc_uv_scale(p_scale: int) -> int:
	return (p_scale & 0x7) << 7


static func _enc_auto(p_on: bool) -> int:
	return 1 if p_on else 0


## Reinterprets a 32-bit uint as an IEEE float (Terrain3D stores control data in
## FORMAT_RF images; the shader reads the float back as a uint).
static func _bits_to_float(p_bits: int) -> float:
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes.encode_u32(0, p_bits & 0xFFFFFFFF)
	return bytes.decode_float(0)


# ============================================================================
# Small math helpers
# ============================================================================

static func smoothstep01(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(a.lerp(b, clampf((p - a).dot(b - a) / a.distance_squared_to(b), 0.0, 1.0)))


static func segment_param(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	if ab.length_squared() <= 0.000001:
		return 0.0
	return clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)