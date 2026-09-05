extends Node
## Background soundtrack autoload. Streams assets/audio/soundtrack.wav in a
## seamless loop that persists across scene changes (menu -> intro -> world).
## Silently no-ops when the file is missing so the project still runs without
## the audio asset; drop a soundtrack.wav into assets/audio to enable music.

const SOUNDTRACK_PATH := "res://assets/audio/soundtrack.wav"
const FADE_IN_DB := -18.0
const START_VOLUME_DB := -8.0

var _player: AudioStreamPlayer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not ResourceLoader.exists(SOUNDTRACK_PATH):
		return
	var stream := load(SOUNDTRACK_PATH) as AudioStream
	if stream == null:
		return
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(stream as AudioStreamWAV).loop_end = (stream as AudioStreamWAV).data.size()
	_player = AudioStreamPlayer.new()
	_player.stream = stream
	_player.volume_db = START_VOLUME_DB
	_player.finished.connect(_on_finished)
	add_child(_player)
	_player.play()
	var fade := create_tween()
	fade.tween_property(_player, "volume_db", START_VOLUME_DB, 3.0).from(FADE_IN_DB)


func _on_finished() -> void:
	_player.play()