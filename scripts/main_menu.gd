extends Node3D

const INTRO = preload("res://scenes/intro.tscn")

@export var fade_time: float = 0.5
@export var move_duration: float = 0.15

@onready var selector: Label = $MarginContainer/MenuContainer/Selector
@onready var menu_container: VBoxContainer = $MarginContainer/MenuContainer
@onready var button_container: VBoxContainer = $MarginContainer/MenuContainer/ButtonContainer

var is_transitioning: bool = false
var selector_tween: Tween
var active_button: Button = null

func _ready() -> void:
	get_tree().paused = false
	is_transitioning = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	for child in button_container.get_children():
		if child is Button:
			child.mouse_entered.connect(_on_button_hovered.bind(child))
			child.focus_entered.connect(_on_button_focused.bind(child))
	
	await get_tree().process_frame
	var first_button = _get_first_button()
	if first_button:
		first_button.grab_focus()
		
func _get_first_button() -> Button:
	for child in button_container.get_children():
		if child is Button and not child.disabled:
			return child
	return null

func _on_button_hovered(button: Button) -> void:
	if is_transitioning:
		return
	button.grab_focus() # Keep focus in sync with mouse hovering

func _on_button_focused(button: Button) -> void:
	if is_transitioning or active_button == button:
		return
	
	active_button = button
	_move_selector_to(button)

func _move_selector_to(target_button: Button) -> void:
	# Calculate vertical position relative to the selector's parent
	var target_y = target_button.global_position.y - selector.get_parent().global_position.y
	
	if selector_tween and selector_tween.is_running():
		selector_tween.kill()

	selector_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	selector_tween.tween_property(selector, "position:y", target_y, move_duration)

func _animate_press(button: Button) -> Tween:
	# Quick scale punch on selection
	var press_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	press_tween.tween_property(button, "scale", Vector2(1.1, 1.1), 0.08)
	press_tween.tween_property(button, "scale", Vector2(1.0, 1.0), 0.08)
	return press_tween

func _on_new_game_button_pressed() -> void:
	if is_transitioning:
		return
	is_transitioning = true

	var btn = button_container.get_node("NewGameButton") as Button
	await _animate_press(btn).finished

	var tween = create_tween()
	tween.tween_property(menu_container, "modulate:a", 0.0, fade_time)
	
	await tween.finished
	get_tree().change_scene_to_packed(INTRO)

func _on_exit_button_pressed() -> void:
	if is_transitioning:
		return
	is_transitioning = true

	var btn = button_container.get_node("ExitButton") as Button
	await _animate_press(btn).finished

	var tween = create_tween()
	tween.tween_property(menu_container, "modulate:a", 0.0, fade_time)
	await tween.finished
	get_tree().quit()
