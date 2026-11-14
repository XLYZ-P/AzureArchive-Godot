class_name AaChoiceOverlay
extends Control
## 居中选项按钮：鼠标点击 / 数字键 1-9（按键在 AaPlayer 中统一处理）。
## 选择后发出 chosen(index)，由解释器跳转。

signal chosen(index: int)

const BTN_MIN_SIZE := Vector2(920, 78)

var center: CenterContainer
var box: VBoxContainer
var dim: ColorRect

var _buttons: Array = []
var _built := false


func ensure_built() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.38)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	box = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 22)
	center.add_child(box)
	visible = false


func show_choices(texts: Array) -> void:
	ensure_built()
	clear_buttons()
	for i in texts.size():
		var index := i
		var text := str(texts[i])
		if text.strip_edges().is_empty():
			text = "选项 %d" % (index + 1)
		var btn := Button.new()
		btn.text = "%d. %s" % [index + 1, AaText.strip_inline(text)]
		btn.custom_minimum_size = BTN_MIN_SIZE
		btn.add_theme_font_override("font", AaArt.ui_font())
		btn.add_theme_font_size_override("font_size", 32)
		btn.add_theme_color_override("font_color", Color("#eaf5ff"))
		btn.add_theme_color_override("font_hover_color", Color("#ffffff"))
		btn.add_theme_stylebox_override("normal", _make_style(Color(0.05, 0.10, 0.18, 0.92), Color(0.45, 0.75, 1.0, 0.75)))
		btn.add_theme_stylebox_override("hover", _make_style(Color(0.10, 0.20, 0.32, 0.95), Color(0.65, 0.9, 1.0, 1.0)))
		btn.add_theme_stylebox_override("pressed", _make_style(Color(0.16, 0.30, 0.45, 0.95), Color(0.8, 0.95, 1.0, 1.0)))
		btn.pressed.connect(func() -> void: _on_pressed(index))
		box.add_child(btn)
		_buttons.append(btn)
	visible = true
	if _buttons.size() > 0 and is_inside_tree():
		_buttons[0].grab_focus()


func _make_style(bg: Color, border: Color) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(2)
	st.set_corner_radius_all(14)
	st.set_content_margin_all(14)
	return st


func _on_pressed(index: int) -> void:
	visible = false
	chosen.emit(index)


func choose(index: int) -> void:
	if not visible:
		return
	if index < 0 or index >= _buttons.size():
		return
	_on_pressed(index)


func has_choices() -> bool:
	return visible


func choice_count() -> int:
	return _buttons.size()


func hide_choices() -> void:
	visible = false
	clear_buttons()


func clear_buttons() -> void:
	for b in _buttons:
		if is_instance_valid(b):
			b.queue_free()
	_buttons.clear()
