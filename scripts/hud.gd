extends CanvasLayer
## In-game HUD: crosshair, hull (player life) bar, damage flash and a
## "UNIT DESTROYED" overlay. Reads the tank life from the player in the "player"
## group and subscribes to its health_changed / died signals.

@onready var hull_bar: ProgressBar = %HullBar
@onready var hull_value: Label = %HullValue
@onready var damage_flash: ColorRect = %DamageFlash
@onready var destroyed_label: Label = %Destroyed

var _player: Node = null
var _last_health := -1.0


func _process(_delta: float) -> void:
	_track_player()


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