class_name AaDialogueBox
extends Control
## BA 风格底部对话框：姓名牌 + 台词打字机 + 内联标记 + 继续指示。
## 点击推进由 AaPlayer 统一处理；这里只负责显示与打字机状态。

signal typing_finished
signal line_shown

const TYPE_SPEED := 42.0        # 默认字/秒（中文）
const MIN_TYPE_SPEED := 8.0

var panel: Panel
var name_plate: PanelContainer
var name_label: Label
var nick_label: Label
var text_label: RichTextLabel
var indicator: Label

var instant_mode := false
var speaker_name := ""
var full_text := ""

var _typing := false
var _char_count := 0
var _shown := 0.0
var _speed := TYPE_SPEED
var _built := false
var _indicator_tween: Tween = null


func _ready() -> void:
	ensure_built()


func ensure_built() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 对话框底板
	panel = Panel.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.05
	panel.anchor_top = 0.725
	panel.anchor_right = 0.95
	panel.anchor_bottom = 0.968
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.06, 0.11, 0.86)
	style.border_color = Color(0.45, 0.78, 1.0, 0.75)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 4)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	# 台词
	text_label = RichTextLabel.new()
	text_label.name = "Text"
	text_label.bbcode_enabled = true
	text_label.fit_content = false
	text_label.scroll_active = false
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_label.anchor_left = 0.0
	text_label.anchor_top = 0.0
	text_label.anchor_right = 1.0
	text_label.anchor_bottom = 1.0
	# 台词区靠下锚定：单行时视觉上贴近对话框下部（AA 原作风格）
	text_label.anchor_top = 1.0
	text_label.anchor_bottom = 1.0
	text_label.offset_left = 52
	text_label.offset_top = -168
	text_label.offset_right = -52
	text_label.offset_bottom = -20
	text_label.add_theme_font_override("normal_font", AaArt.ui_font())
	text_label.add_theme_font_size_override("normal_font_size", 30)
	text_label.add_theme_color_override("default_color", Color("#f2f7ff"))
	text_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	text_label.add_theme_constant_override("outline_size", 3)
	text_label.add_theme_constant_override("line_separation", 8)
	panel.add_child(text_label)
	# 姓名牌
	name_plate = PanelContainer.new()
	name_plate.name = "NamePlate"
	name_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_plate.anchor_left = 0.075
	name_plate.anchor_top = 0.725
	name_plate.anchor_right = 0.075
	name_plate.anchor_bottom = 0.725
	name_plate.offset_top = -48
	name_plate.offset_bottom = -2
	name_plate.offset_left = 0
	name_plate.offset_right = 380
	var name_style := StyleBoxFlat.new()
	name_style.bg_color = Color(0.06, 0.11, 0.20, 0.94)
	name_style.border_color = Color(0.55, 0.85, 1.0, 0.9)
	name_style.set_border_width_all(2)
	name_style.set_corner_radius_all(12)
	name_style.set_content_margin_all(8)
	name_style.content_margin_left = 22
	name_style.content_margin_right = 22
	name_plate.add_theme_stylebox_override("panel", name_style)
	add_child(name_plate)
	var name_box := HBoxContainer.new()
	name_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_plate.add_child(name_box)
	name_label = Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_override("font", AaArt.ui_font())
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_color", Color("#aee2ff"))
	name_box.add_child(name_label)
	nick_label = Label.new()
	nick_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nick_label.add_theme_font_override("font", AaArt.ui_font())
	nick_label.add_theme_font_size_override("font_size", 18)
	nick_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.92, 0.85))
	name_box.add_child(nick_label)
	# 继续指示
	indicator = Label.new()
	indicator.name = "Indicator"
	indicator.text = "▼"
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	indicator.anchor_left = 1.0
	indicator.anchor_top = 1.0
	indicator.anchor_right = 1.0
	indicator.anchor_bottom = 1.0
	indicator.offset_left = -58
	indicator.offset_top = -48
	indicator.offset_right = -22
	indicator.offset_bottom = -12
	indicator.add_theme_font_override("font", AaArt.ui_font())
	indicator.add_theme_font_size_override("font_size", 26)
	indicator.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0, 0.9))
	panel.add_child(indicator)
	name_plate.visible = false
	indicator.visible = false
	_start_indicator_blink()


func _start_indicator_blink() -> void:
	if not is_inside_tree():
		return
	if _indicator_tween != null and _indicator_tween.is_valid():
		_indicator_tween.kill()
	_indicator_tween = create_tween().set_loops()
	_indicator_tween.tween_property(indicator, "modulate:a", 0.25, 0.6)
	_indicator_tween.tween_property(indicator, "modulate:a", 1.0, 0.6)


## 显示一行台词。speaker 为空 = 旁白（不显示姓名牌）。
func show_line(speaker: Variant, nick: Variant, text: String, voice_length := 0.0, voice_missing := false) -> void:
	ensure_built()
	speaker_name = str(speaker) if speaker != null else ""
	full_text = text
	panel.visible = true
	if speaker_name.is_empty():
		name_plate.visible = false
	else:
		name_plate.visible = true
		name_label.text = speaker_name
		var nick_s := str(nick) if nick != null else ""
		nick_label.text = "" if nick_s.is_empty() or nick_s == speaker_name else nick_s
		name_plate.reset_size()
		name_plate.custom_minimum_size = Vector2(0, 0)
	text_label.text = AaText.to_bbcode(text)
	text_label.visible_characters = 0
	_char_count = maxi(text_label.get_total_character_count(), 0)
	_shown = 0.0
	_typing = false
	_speed = TYPE_SPEED
	if voice_length > 0.4 and _char_count > 0 and not voice_missing:
		# 语音同步：台词在语音时长内匀速打完
		_speed = maxf(float(_char_count) / maxf(voice_length - 0.15, 0.4), MIN_TYPE_SPEED)
	if instant_mode or _char_count <= 0:
		_finish_typing()
	else:
		_typing = true
		indicator.visible = false
	line_shown.emit()


## 只改文字、不重置姓名（打字机测试/历史回看用，避免时序问题留作扩展）
func set_visible_box(v: bool) -> void:
	ensure_built()
	panel.visible = v
	if not v:
		name_plate.visible = false
		indicator.visible = false


func clear() -> void:
	ensure_built()
	text_label.text = ""
	name_plate.visible = false
	indicator.visible = false
	_typing = false
	_char_count = 0
	full_text = ""


func skip_typing() -> void:
	if _typing:
		_finish_typing()


func is_typing() -> bool:
	return _typing


func _finish_typing() -> void:
	_typing = false
	text_label.visible_characters = -1
	indicator.visible = true
	typing_finished.emit()


func _process(delta: float) -> void:
	if not _typing:
		return
	_shown += _speed * delta
	var v := int(_shown)
	if v >= _char_count:
		_finish_typing()
	else:
		text_label.visible_characters = v
