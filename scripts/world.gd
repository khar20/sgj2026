extends Node3D

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle_pause()

func toggle_pause() -> void:
	var new_state = not get_tree().paused
	get_tree().paused = new_state
	visible = new_state
