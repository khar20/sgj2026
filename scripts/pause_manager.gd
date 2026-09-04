extends Node

const PAUSE_MENU_SCENE = preload("res://scenes/pause_menu.tscn")

var canvas_layer: CanvasLayer = null
var pause_menu_instance: Control = null

func _ready() -> void:
	# Ensure the pause manager runs even when the tree pauses
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if get_tree().paused and is_instance_valid(pause_menu_instance) and pause_menu_instance.visible:
			toggle_pause()
			return

		if can_pause():
			print("can be paused")
			toggle_pause()

func can_pause() -> bool:
	# Only pause while the World scene is active
	var current_scene = get_tree().current_scene
	if not current_scene or current_scene.scene_file_path != "res://scenes/world.tscn":
		return false

	# Block pausing while any blocking UI (Inventory, Dialogue, etc.) is open
	var open_menus = get_tree().get_nodes_in_group("blocking_ui")
	for menu in open_menus:
		if menu.visible:
			return false

	return true

func toggle_pause() -> void:
	# Instantiate the pause menu dynamically on first use
	if not is_instance_valid(pause_menu_instance):
		print("not instance")
		canvas_layer = CanvasLayer.new()
		canvas_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		# Keep on top of other HUD elements
		canvas_layer.layer = 100
		pause_menu_instance = PAUSE_MENU_SCENE.instantiate()
		canvas_layer.add_child(pause_menu_instance)
		add_child(canvas_layer)
	
	var new_pause_state = not get_tree().paused
	get_tree().paused = new_pause_state
	
	canvas_layer.visible = new_pause_state
	pause_menu_instance.visible = new_pause_state
	
	if new_pause_state:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		
		var first_button = pause_menu_instance.find_child("*Button*", true, false)
		if first_button and first_button is Button:
			first_button.grab_focus()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
