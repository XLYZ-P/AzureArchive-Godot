class_name AaBacklog
extends Control
## 对话历史（backlog）：可滚动回看，不修改任何剧情状态。
## 历史记录图层在选项按钮之上（对齐 AA 0.4.0 修复项）。

signal closed

const MAX_ENTRIES := 400

var root_panel: Panel
var scroll: ScrollContainer
var list: VBoxContainer
var title_label: Label
var close_btn: Button
var entries: Array = []

var _built := false


func ensure_built() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_panel = Panel.new()
	root_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.03, 0.06, 0.94)
	root_panel.add_theme_stylebox_override("panel", style)
	root_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root_panel)

	title_label = Label.new()
	title_label.text = "对话记录（回看不会改变剧情）"
	title_label.anchor_right = 0.7
	title_label.offset_left = 80
	title_label.offset_top = 40
	title_label.offset_right = 0
	title_label.offset_bottom = 96
	title_label.add_theme_font_override("font", AaArt.ui_font())
	title_label.add_theme_font_size_override("font_size", 38)
	title_label.add_theme_color_override("font_color", Color("#aee2ff"))
	root_panel.add_child(title_label)

	close_btn = Button.new()
	close_btn.text = "关闭（Esc / H）"
	close_btn.anchor_left = 1.0
	close_btn.anchor_right = 1.0
	close_btn.offset_left = -320
	close_btn.offset_right = -60
	close_btn.offset_top = 48
	close_btn.offset_bottom = 108
	close_btn.add_theme_font_override("font", AaArt.ui_font())
	close_btn.add_theme_font_size_override("font_size", 26)
	close_btn.pressed.connect(close)
	root_panel.add_child(close_btn)

	scroll = ScrollContainer.new()
	scroll.anchor_left = 0.0
	scroll.anchor_top = 0.0
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = 70
	scroll.offset_top = 120
	scroll.offset_right = -70
	scroll.offset_bottom = -50
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root_panel.add_child(scroll)

	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 18)
	scroll.add_child(list)
	visible = false


func add_entry(speaker: String, text: String) -> void:
	ensure_built()
	entries.append({"speaker": speaker, "text": text})
	var entry := HBoxContainer.new()
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.add_theme_constant_override("separation", 18)
	if not speaker.is_empty():
		var nm := Label.new()
		nm.text = speaker
		nm.custom_minimum_size.x = 220
		nm.add_theme_font_override("font", AaArt.ui_font())
		nm.add_theme_font_size_override("font_size", 26)
		nm.add_theme_color_override("font_color", Color("#8fd4ff"))
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.add_child(nm)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.add_theme_font_override("normal_font", AaArt.ui_font())
	rt.add_theme_font_size_override("normal_font_size", 26)
	rt.add_theme_color_override("default_color", Color("#e6eefb"))
	rt.text = AaText.to_bbcode(text)
	entry.add_child(rt)
	list.add_child(entry)
	while list.get_child_count() > MAX_ENTRIES:
		var first := list.get_child(0)
		list.remove_child(first)
		first.queue_free()
		entries.pop_front()


func open() -> void:
	ensure_built()
	visible = true
	_scroll_to_bottom()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func _scroll_to_bottom() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if scroll != null:
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func clear() -> void:
	entries.clear()
	if list != null:
		for c in list.get_children():
			c.queue_free()
