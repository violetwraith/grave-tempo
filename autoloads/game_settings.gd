extends Node

const SETTINGS_PATH := "user://settings.cfg"

var audio_offset: float = 0.0


func _ready() -> void:
	_load()


func save() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "offset", audio_offset)
	config.save(SETTINGS_PATH)


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	audio_offset = config.get_value("audio", "offset", 0.0)
