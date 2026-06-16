extends CanvasLayer
class_name HUD

@onready var offset_label: Label = $OffsetLabel
@onready var timing_label: Label = $TimingLabel

var _timing_show_id: int = 0
var _last_suggested_ms: float = 0.0
var _last_current_ms: float = 0.0
var _has_samples: bool = false
var _parry_mode: bool = false


func _ready() -> void:
	_refresh_label()


func update_calibration(suggested_ms: float, current_offset_ms: float, has_samples: bool = true) -> void:
	_last_suggested_ms = suggested_ms
	_last_current_ms = current_offset_ms
	_has_samples = has_samples
	_refresh_label()


func set_parry_mode(active: bool) -> void:
	_parry_mode = active
	_refresh_label()


func show_timing(result: String, color: Color) -> void:
	timing_label.text = result
	timing_label.modulate = color
	_timing_show_id += 1
	var my_id := _timing_show_id
	get_tree().create_timer(1.2).timeout.connect(func():
		if _timing_show_id == my_id:
			timing_label.text = ""
	)


func _refresh_label() -> void:
	var calib: String
	if _has_samples:
		calib = "\nSuggested: %.1f ms     Current: %.1f ms\n[D-pad / [ ]] ±10ms" % [_last_suggested_ms, _last_current_ms]
	else:
		calib = "\nCurrent: %.1f ms   [D-pad / [ ]] ±10ms" % _last_current_ms

	if _parry_mode:
		offset_label.text = "[ L2 / F ]  Calibrating\nY / T  =  Beat 1  (high click)\nA / G  =  Beats 2, 3, 4  (low click)" + calib
	else:
		offset_label.text = (
			"Move: WASD / Left Stick\nCamera: Right Stick\nStart / R: reset"
			+ "\n\nHold L2 / F to calibrate" + calib
		)
