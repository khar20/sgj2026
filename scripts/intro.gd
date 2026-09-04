extends Control

@export_multiline var lore_entries: Array[String] = [
	"Entry 1: Long ago, in a kingdom far away...",
	"Entry 2: Darkness fell upon the lands.",
	"Entry 3: One hero rose to face the shadow."
]
@export var fade_time: float = 0.3
@export var game_scene: PackedScene

@onready var label: Label = $Label

var current_index: int = 0
var tween: Tween
var is_transitioning: bool = false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	if lore_entries.size() > 0:
		label.text = lore_entries[current_index]
		
func _unhandled_input(event: InputEvent) -> void:
	if is_transitioning:
		return

	# Navigate backward: A or Left Arrow
	if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		if current_index > 0:
			change_entry(current_index - 1)

	# Navigate forward: D or Right Arrow
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		if current_index < lore_entries.size() - 1:
			change_entry(current_index + 1)

	# Next scene trigger (Space/Enter/Accept) when on the final entry
	elif event.is_action_pressed("ui_accept"):
		if current_index == lore_entries.size() - 1:
			start_game()
			
func change_entry(new_index: int) -> void:
	is_transitioning = true
	current_index = new_index

	# Kill any ongoing tween to avoid overlapping state bugs
	if tween and tween.is_running():
		tween.kill()

	tween = create_tween()
	# Step 1: Fade text out
	tween.tween_property(label, "modulate:a", 0.0, fade_time)
	
	# Step 2: Swap text instantly while invisible
	tween.tween_callback(func(): label.text = lore_entries[current_index])
	
	# Step 3: Fade text back in
	tween.tween_property(label, "modulate:a", 1.0, fade_time)
	
	# Unlock input when animation finishes
	await tween.finished
	is_transitioning = false
	
func start_game() -> void:
	is_transitioning = true
	if tween and tween.is_running():
		tween.kill()

	tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, fade_time)
	await tween.finished
	get_tree().change_scene_to_packed(game_scene)
