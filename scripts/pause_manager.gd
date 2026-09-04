extends Node

const PAUSE_MENU_SCENE = preload("res://scenes/pause_menu.tscn")

var pause_menu_instance: Control = null

func _ready() -> void:
	# Ensure the pause manager runs even when the tree pauses
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# If the game is already paused by our pause menu, unpause it
		if get_tree().paused and is_instance_valid(pause_menu_instance) and pause_menu_instance.visible:
			toggle_pause()
			return

		# Otherwise, check if pausing is currently allowed
		if can_pause():
			toggle_pause()

func can_pause() -> bool:
	# 1. Ensure World/Gameplay scene is loaded
	var current_scene = get_tree().current_scene
	if not current_scene or current_scene.scene_file_path != "res://scenes/world.tscn":
		return false

	# 2. Prevent pausing if any blocking UI (Inventory, Dialogue, etc.) is open
	# We check if any node in the "blocking_ui" group is currently visible
	var open_menus = get_tree().get_nodes_in_group("blocking_ui")
	for menu in open_menus:
		if menu.visible:
			return false

	return true

func toggle_pause() -> void:
	# Instantiate the pause menu dynamically on first use
	if not is_instance_valid(pause_menu_instance):
		var canvas_layer = CanvasLayer.new()
		canvas_layer.layer = 100 # Keep on top of other HUD elements
		pause_menu_instance = PAUSE_MENU_SCENE.instantiate()
		canvas_layer.add_child(pause_menu_instance)
		add_child(canvas_layer)

	var new_pause_state = not get_tree().paused
	get_tree().paused = new_pause_state
	pause_menu_instance.visible = new_pause_state
	
	# Handle mouse capture automatically
	if new_pause_state:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
