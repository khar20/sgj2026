extends Control

const GEN := preload("res://scripts/world_gen.gd")

@export_multiline var lore_entries: Array[String] = [
	"Entry 1: Long ago, in a kingdom far away...",
	"Entry 2: Darkness fell upon the lands.",
	"Entry 3: One hero rose to face the shadow."
]
@export var fade_time: float = 0.3
@export var game_scene: PackedScene

@onready var label: Label = $Label
@onready var loading_label: Label = $Loading

var current_index: int = 0
var tween: Tween
var is_transitioning: bool = false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Start generating the world terrain on a worker thread while the lore is on
	# screen, so switching to the World scene has no generation hitch.
	GEN.start_generation()
	loading_label.visible = false
	
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

	# Kill any running tween before starting a new transition
	if tween and tween.is_running():
		tween.kill()

	tween = create_tween()
	# Step 1: Fade text out
	tween.tween_property(label, "modulate:a", 0.0, fade_time)
	
	# Step 2: Swap text instantly while invisible
	tween.tween_callback(func(): label.text = lore_entries[current_index])
	
	# Step 3: Fade text back in
	tween.tween_property(label, "modulate:a", 1.0, fade_time)
	
	await tween.finished
	is_transitioning = false
	
func start_game() -> void:
	is_transitioning = true
	# If the worker hasn't finished yet (fast reader), wait it out here while the
	# intro stays visible, showing progress.
	if not GEN.ready():
		loading_label.visible = true
		await _poll_generation()
	loading_label.visible = false

	if tween and tween.is_running():
		tween.kill()

	tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, fade_time)
	await tween.finished
	get_tree().change_scene_to_packed(game_scene)


func _poll_generation() -> void:
	while not GEN.ready():
		loading_label.text = "GENERATING TERRAIN... %d%%" % int(GEN.progress() * 100.0)
		await get_tree().process_frame
