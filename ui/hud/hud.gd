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

var _boss_hp_bg: ColorRect = null
var _boss_hp_fill: ColorRect = null
var _boss_hp_pending: ColorRect = null
var _boss_name_label: Label = null
var _boss_hp_ticks: Array[ColorRect] = []
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
	_max_hp = max_hp


func update_hp(hp: int) -> void:
	hp_label.text = "<3".repeat(hp)


func update_combo(combo: int) -> void:
	combo_label.text = ("x %d" % combo) if combo > 0 else ""


func show_dead() -> void:
	_timing_show_id += 1
	timing_label.text = "DEADGE"
	timing_label.modulate = Color(0.8, 0.1, 0.1)


func clear_dead() -> void:
	timing_label.text = ""


func show_timing(result: String, color: Color) -> void:
	timing_label.text = result
	timing_label.modulate = color
	_timing_show_id += 1
	var my_id := _timing_show_id
	get_tree().create_timer(1.2).timeout.connect(func():
		if _timing_show_id == my_id:
			timing_label.text = ""
	)


func show_boss_hp(hp: float, max_hp: float, pending_damage: float = 0.0) -> void:
	var safe_max := maxf(max_hp, 0.001)
	var real_frac := clampf(hp / safe_max, 0.0, 1.0)
	var pending_frac := clampf(pending_damage / safe_max, 0.0, 1.0 - real_frac)
	var left := -_BOSS_BAR_WIDTH * 0.5
	_boss_hp_bg.visible = true
	_boss_hp_fill.visible = true
	_boss_hp_fill.offset_right = left + real_frac * _BOSS_BAR_WIDTH
	_boss_hp_pending.offset_left = left + real_frac * _BOSS_BAR_WIDTH
	_boss_hp_pending.offset_right = left + (real_frac + pending_frac) * _BOSS_BAR_WIDTH
	_boss_hp_pending.visible = pending_frac > 0.001
	_boss_name_label.visible = true
	for tick in _boss_hp_ticks:
		tick.visible = true


func hide_boss_hp() -> void:
	_boss_hp_bg.visible = false
	_boss_hp_fill.visible = false
	_boss_hp_pending.visible = false
	_boss_name_label.visible = false
	for tick in _boss_hp_ticks:
		tick.visible = false


func update_iframe_bar(progress: float) -> void:
	var show := progress > 0.005
	_iframe_bg.visible = show
	_iframe_fill.visible = show
	if show:
		_iframe_fill.offset_right = _iframe_fill.offset_left + progress * _IFRAME_BAR_WIDTH


func _setup_boss_hp_bar() -> void:
	_boss_hp_bg = _make_boss_bar_rect(Color(0.07, 0.04, 0.04, 0.9))
	# Pending (white) sits behind the red fill, the fill shrinks left to reveal it on a hit.
	_boss_hp_pending = _make_boss_bar_rect(Color(0.95, 0.95, 0.95, 1.0))
	_boss_hp_fill = _make_boss_bar_rect(Color(0.8, 0.12, 0.12, 1.0))
	# health bar tickmarks
	var left := -_BOSS_BAR_WIDTH * 0.5
	for i in range(1, 10):
		var tick := ColorRect.new()
		tick.color = Color(0.0, 0.0, 0.0, 0.55)
		tick.anchor_left = 0.5
		tick.anchor_right = 0.5
		tick.anchor_top = 1.0
		tick.anchor_bottom = 1.0
		tick.offset_left = left + float(i) / 10.0 * _BOSS_BAR_WIDTH - 1.0
		tick.offset_right = left + float(i) / 10.0 * _BOSS_BAR_WIDTH + 1.0
		tick.offset_top = -62.0
		tick.offset_bottom = -62.0 + _BOSS_BAR_H
		tick.visible = false
		add_child(tick)
		_boss_hp_ticks.append(tick)
	# Placeholder boss name above the bar's top-left corner.
	_boss_name_label = Label.new()
	_boss_name_label.text = "???"
	_boss_name_label.anchor_left = 0.5
	_boss_name_label.anchor_right = 0.5
	_boss_name_label.anchor_top = 1.0
	_boss_name_label.anchor_bottom = 1.0
	_boss_name_label.offset_left = left
	_boss_name_label.offset_right = left + 200.0
	_boss_name_label.offset_top = -88.0
	_boss_name_label.offset_bottom = -64.0
	_boss_name_label.add_theme_font_size_override("font_size", 18)
	_boss_name_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.8, 1.0))
	_boss_name_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	_boss_name_label.add_theme_constant_override("shadow_offset_x", 2)
	_boss_name_label.add_theme_constant_override("shadow_offset_y", 2)
	_boss_name_label.visible = false
	add_child(_boss_name_label)


func _make_boss_bar_rect(color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.anchor_left = 0.5
	rect.anchor_right = 0.5
	rect.anchor_top = 1.0
	rect.anchor_bottom = 1.0
	rect.offset_left = -_BOSS_BAR_WIDTH * 0.5
	rect.offset_right = _BOSS_BAR_WIDTH * 0.5
	rect.offset_top = -62.0
	rect.offset_bottom = -62.0 + _BOSS_BAR_H
	rect.visible = false
	add_child(rect)
	return rect


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
	var offset_keys: String = "D-pad" if _using_controller else "[ ] keys"
	if _has_samples:
		calib = "Suggested: %.1f ms     Offset: %.1f ms\n[%s] +/-10ms" % [_last_suggested_ms, _last_current_ms, offset_keys]
	else:
		calib = "Suggested: ---ms     Offset: %.1f ms   [%s] +/-10ms" % [_last_current_ms, offset_keys]

	var controls: String
	if _using_controller:
		var ting_line := "X: ting sfx %s" % ("on" if _ting_enabled else "off")
		controls = (
			"L-Stick: Move  |  R-Stick: Camera\n"
			+ "Start: Reset  |  R3: Lock on\n"
			+ "L1: Parry  |  R1: Quick attack  |  R2: Charge attack\n"
			+ ting_line + "  |  Y: Toggle move\n"
			+ "tap/release R1 while holding L1 for fast parries"
		)
	else:
		var ting_line := "V: ting %s" % ("on" if _ting_enabled else "off")
		controls = (
			"WASD: Move  |  Mouse: Camera\n"
			+ "R: Reset  |  F: Lock on\n"
			+ "Q: Parry  |  E: Quick attack  |  C: Charge attack\n"
			+ ting_line + "  |  T: Toggle move\n"
			+ "tap/release E while holding Q for fast parries"
		)

	offset_label.text = controls + "\n" + calib
