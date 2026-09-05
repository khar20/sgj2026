extends CanvasLayer
## In-game HUD: crosshair, hull (player life) bar, damage flash, a
## "UNIDAD DESTRUÍDA" overlay, and a boss health bar. Reads the tank life
## from the player in the "player" group and subscribes to its health_changed
## / died signals. Boss bar tracks the CrystalBoss in the "boss" group.

@onready var hull_bar: ProgressBar = %HullBar
@onready var hull_value: Label = %HullValue
@onready var damage_flash: ColorRect = %DamageFlash
@onready var destroyed_label: Label = %Destroyed
@onready var boss_panel: PanelContainer = %BossPanel
@onready var boss_bar: ProgressBar = %BossBar

var _player: Node = null
var _last_health := -1.0
var _boss: Node = null


func _process(_delta: float) -> void:
	_track_player()
	_track_boss()


func _track_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player != _player:
		_untrack()
		_player = player
		if _player != null:
			if _player.has_signal("health_changed"):
				_player.health_changed.connect(_on_health_changed)
			if _player.has_signal("died"):
				_player.died.connect(_on_died)
			_last_health = _player.get("health")
			_apply_health(_last_health, _player.get("max_health"))


func _untrack() -> void:
	if _player != null and is_instance_valid(_player):
		if _player.health_changed.is_connected(_on_health_changed):
			_player.health_changed.disconnect(_on_health_changed)
		if _player.died.is_connected(_on_died):
			_player.died.disconnect(_on_died)
	_player = null


func _on_health_changed(new_health: float, max_health: float) -> void:
	if new_health < _last_health:
		_flash()
	_last_health = new_health
	_apply_health(new_health, max_health)


func _apply_health(health: float, max_health: float) -> void:
	if hull_bar == null or hull_value == null:
		return
	hull_bar.max_value = maxf(1.0, max_health)
	hull_bar.value = clampf(health, 0.0, hull_bar.max_value)
	hull_value.text = str(int(health))


func _flash() -> void:
	if damage_flash == null:
		return
	var tween := damage_flash.create_tween()
	tween.tween_property(damage_flash, "modulate:a", 0.35, 0.06)
	tween.tween_property(damage_flash, "modulate:a", 0.0, 0.5)


func _on_died() -> void:
	if destroyed_label != null:
		destroyed_label.visible = true


# ---------------------------------------------------------------------------
# Boss tracking
# ---------------------------------------------------------------------------

func _track_boss() -> void:
	var boss := get_tree().get_first_node_in_group("boss")
	if boss == _boss:
		return
	if _boss != null and is_instance_valid(_boss):
		if _boss.health_changed.is_connected(_on_boss_health_changed):
			_boss.health_changed.disconnect(_on_boss_health_changed)
		if _boss.defeated.is_connected(_on_boss_defeated):
			_boss.defeated.disconnect(_on_boss_defeated)
	_boss = boss
	if _boss != null:
		if _boss.has_signal("health_changed"):
			_boss.health_changed.connect(_on_boss_health_changed)
		if _boss.has_signal("defeated"):
			_boss.defeated.connect(_on_boss_defeated)
		_apply_boss_health(_boss.get("health"), _boss.get("max_health"))
		boss_panel.visible = true
	else:
		boss_panel.visible = false


func _on_boss_health_changed(new_health: float, max_health: float) -> void:
	_apply_boss_health(new_health, max_health)


func _apply_boss_health(health: float, max_health: float) -> void:
	if boss_bar == null:
		return
	boss_bar.max_value = maxf(1.0, max_health)
	boss_bar.value = clampf(health, 0.0, boss_bar.max_value)


func _on_boss_defeated() -> void:
	if boss_panel != null:
		boss_panel.visible = false