extends CanvasLayer
class_name HUD

@onready var offset_label: Label = $OffsetLabel
@onready var timing_label: Label = $TimingLabel
@onready var fps_label: Label = $FPSLabel
@onready var hp_label: Label = $HPLabel
@onready var combo_label: Label = $ComboLabel

const _MAX_HP := 3

var _timing_show_id: int = 0
var _last_suggested_ms: float = 0.0
var _last_current_ms: float = 0.0
var _has_samples: bool = false
var _ting_enabled: bool = false
var _using_controller: bool = false


func _ready() -> void:
	Input.joy_connection_changed.connect(func(_device, _connected): _refresh_label())
	_using_controller = not Input.get_connected_joypads().is_empty()
	_refresh_label()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if not _using_controller:
			_using_controller = true
			_refresh_label()
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		if _using_controller:
			_using_controller = false
			_refresh_label()


func _process(_delta: float) -> void:
	fps_label.text = "%d fps" % Engine.get_frames_per_second()


func update_calibration(suggested_ms: float, current_offset_ms: float, has_samples: bool = true) -> void:
	_last_suggested_ms = suggested_ms
	_last_current_ms = current_offset_ms
	_has_samples = has_samples
	_refresh_label()


func set_ting_enabled(enabled: bool) -> void:
	_ting_enabled = enabled
	_refresh_label()


func update_hp(hp: int) -> void:
	hp_label.text = "♥".repeat(hp) + "♡".repeat(_MAX_HP - hp)


func update_combo(combo: int) -> void:
	combo_label.text = ("× %d" % combo) if combo > 0 else ""


func show_dead() -> void:
	_timing_show_id += 1
	timing_label.text = "You Died"
	timing_label.modulate = Color(0.8, 0.1, 0.1)


func clear_dead() -> void:
	timing_label.text = ""


func show_windup() -> void:
	timing_label.text = "!"
	timing_label.modulate = Color(1.0, 0.6, 0.1)
	_timing_show_id += 1
	var my_id := _timing_show_id
	get_tree().create_timer(0.45).timeout.connect(func():
		if _timing_show_id == my_id:
			timing_label.text = ""
	)


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
	var offset_keys: String = "D-pad" if _using_controller else "[ ]"
	if _has_samples:
		calib = "Suggested: %.1f ms     Current: %.1f ms\n[%s] ±10ms" % [_last_suggested_ms, _last_current_ms, offset_keys]
	else:
		calib = "Current: %.1f ms   [%s] ±10ms" % [_last_current_ms, offset_keys]

	var controls: String
	if _using_controller:
		var ting_line := "X: ting %s" % ("on" if _ting_enabled else "off")
		controls = (
			"L-Stick: Move  |  R-Stick: Camera\n"
			+ "Start: Reset  |  R3: Lock on\n"
			+ "L1: Parry  |  R1: Quick attack  |  R2: Charge attack\n"
			+ ting_line + "  |  Y: Toggle move\n"
			+ "Tip: R1 or R2↑ while holding L1 = extra parry"
		)
	else:
		var ting_line := "V: ting %s" % ("on" if _ting_enabled else "off")
		controls = (
			"WASD: Move  |  Mouse: Camera\n"
			+ "R: Reset  |  F: Lock on\n"
			+ "Q: Parry  |  E: Quick attack  |  C: Charge attack\n"
			+ ting_line + "  |  T: Toggle move\n"
			+ "Tip: E or C (release) while holding Q = extra parry"
		)

	offset_label.text = controls + "\n" + calib
