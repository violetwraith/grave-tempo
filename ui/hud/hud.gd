extends CanvasLayer
class_name HUD

@onready var offset_label: Label = $OffsetLabel
@onready var timing_label: Label = $TimingLabel
@onready var fps_label: Label = $FPSLabel
@onready var hp_label: Label = $HPLabel
@onready var combo_label: Label = $ComboLabel

const _BOSS_BAR_WIDTH := 600.0
const _BOSS_BAR_H := 18.0
const _IFRAME_BAR_WIDTH := 220.0
const _IFRAME_BAR_H := 10.0

var _max_hp: int = 3
var _timing_show_id: int = 0
var _last_suggested_ms: float = 0.0
var _last_current_ms: float = 0.0
var _has_samples: bool = false
var _ting_enabled: bool = false
var _using_controller: bool = false

var _boss_name_label: Label = null
var _boss_hp_bg: ColorRect = null
var _boss_hp_fill: ColorRect = null
var _iframe_bg: ColorRect = null
var _iframe_fill: ColorRect = null


func _ready() -> void:
	Input.joy_connection_changed.connect(func(_device, _connected): _refresh_label())
	_using_controller = not Input.get_connected_joypads().is_empty()
	_refresh_label()
	_setup_boss_hp_bar()
	_setup_iframe_bar()


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


func set_max_hp(max_hp: int) -> void:
	_max_hp = maxi(max_hp, 1)


func update_hp(hp: int) -> void:
	var clamped := clampi(hp, 0, _max_hp)
	hp_label.text = "♥".repeat(clamped) + "♡".repeat(_max_hp - clamped)


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


func show_boss_hp(hp: float, max_hp: float, phase_label: String) -> void:
	var frac := clampf(hp / maxf(max_hp, 0.001), 0.0, 1.0)
	_boss_name_label.text = phase_label
	_boss_name_label.visible = not phase_label.is_empty()
	_boss_hp_bg.visible = true
	_boss_hp_fill.visible = true
	_boss_hp_fill.offset_right = -_BOSS_BAR_WIDTH * 0.5 + frac * _BOSS_BAR_WIDTH


func hide_boss_hp() -> void:
	_boss_name_label.visible = false
	_boss_hp_bg.visible = false
	_boss_hp_fill.visible = false


func update_iframe_bar(progress: float) -> void:
	var show := progress > 0.005
	_iframe_bg.visible = show
	_iframe_fill.visible = show
	if show:
		_iframe_fill.offset_right = _iframe_fill.offset_left + progress * _IFRAME_BAR_WIDTH


func _setup_boss_hp_bar() -> void:
	_boss_name_label = Label.new()
	_boss_name_label.anchor_left = 0.5
	_boss_name_label.anchor_right = 0.5
	_boss_name_label.anchor_top = 1.0
	_boss_name_label.anchor_bottom = 1.0
	_boss_name_label.offset_left = -_BOSS_BAR_WIDTH * 0.5
	_boss_name_label.offset_right = _BOSS_BAR_WIDTH * 0.5
	_boss_name_label.offset_top = -88.0
	_boss_name_label.offset_bottom = -64.0
	_boss_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name_label.add_theme_font_size_override("font_size", 14)
	_boss_name_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.65, 1.0))
	_boss_name_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	_boss_name_label.add_theme_constant_override("shadow_offset_x", 2)
	_boss_name_label.add_theme_constant_override("shadow_offset_y", 2)
	_boss_name_label.visible = false
	add_child(_boss_name_label)

	_boss_hp_bg = ColorRect.new()
	_boss_hp_bg.color = Color(0.07, 0.04, 0.04, 0.9)
	_boss_hp_bg.anchor_left = 0.5
	_boss_hp_bg.anchor_right = 0.5
	_boss_hp_bg.anchor_top = 1.0
	_boss_hp_bg.anchor_bottom = 1.0
	_boss_hp_bg.offset_left = -_BOSS_BAR_WIDTH * 0.5
	_boss_hp_bg.offset_right = _BOSS_BAR_WIDTH * 0.5
	_boss_hp_bg.offset_top = -62.0
	_boss_hp_bg.offset_bottom = -62.0 + _BOSS_BAR_H
	_boss_hp_bg.visible = false
	add_child(_boss_hp_bg)

	_boss_hp_fill = ColorRect.new()
	_boss_hp_fill.color = Color(0.88, 0.72, 0.18, 1.0)
	_boss_hp_fill.anchor_left = 0.5
	_boss_hp_fill.anchor_right = 0.5
	_boss_hp_fill.anchor_top = 1.0
	_boss_hp_fill.anchor_bottom = 1.0
	_boss_hp_fill.offset_left = -_BOSS_BAR_WIDTH * 0.5
	_boss_hp_fill.offset_right = _BOSS_BAR_WIDTH * 0.5
	_boss_hp_fill.offset_top = -62.0
	_boss_hp_fill.offset_bottom = -62.0 + _BOSS_BAR_H
	_boss_hp_fill.visible = false
	add_child(_boss_hp_fill)


func _setup_iframe_bar() -> void:
	var center_x := -_IFRAME_BAR_WIDTH * 0.5
	_iframe_bg = ColorRect.new()
	_iframe_bg.color = Color(0.05, 0.1, 0.2, 0.85)
	_iframe_bg.anchor_left = 0.5
	_iframe_bg.anchor_right = 0.5
	_iframe_bg.anchor_top = 1.0
	_iframe_bg.anchor_bottom = 1.0
	_iframe_bg.offset_left = center_x
	_iframe_bg.offset_right = center_x + _IFRAME_BAR_WIDTH
	_iframe_bg.offset_top = -88.0 - _IFRAME_BAR_H - 6.0
	_iframe_bg.offset_bottom = -88.0 - 6.0
	_iframe_bg.visible = false
	add_child(_iframe_bg)

	_iframe_fill = ColorRect.new()
	_iframe_fill.color = Color(0.3, 0.7, 1.0, 0.9)
	_iframe_fill.anchor_left = 0.5
	_iframe_fill.anchor_right = 0.5
	_iframe_fill.anchor_top = 1.0
	_iframe_fill.anchor_bottom = 1.0
	_iframe_fill.offset_left = center_x
	_iframe_fill.offset_right = center_x + _IFRAME_BAR_WIDTH
	_iframe_fill.offset_top = -88.0 - _IFRAME_BAR_H - 6.0
	_iframe_fill.offset_bottom = -88.0 - 6.0
	_iframe_fill.visible = false
	add_child(_iframe_fill)


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
