class_name AaNodeFactory
extends PanelContainer
## 左侧「节点工厂」：入口 / 脚本 / 选择 / 出口。
##
## 交互：拖到 GraphEdit 画布上创建（经 AaPaletteButton._get_drag_data +
## AaGraphView._drop_data）；也可以直接单击 = 在当前画布中心创建。
## 入口节点全工程唯一，已存在时按钮禁用。

signal create_requested(node_type: int)
signal status(message: String)

var backend: AaEditorBackend
var _box: VBoxContainer
var _entry_button: AaPaletteButton
var _entry_present := false


func setup(p_backend: AaEditorBackend) -> void:
	backend = p_backend
	_build()


func _build() -> void:
	if _box != null:
		return
	custom_minimum_size.x = 232
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	margin.add_child(_box)

	var title := Label.new()
	title.text = "节点工厂"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#7dd3fc"))
	_box.add_child(title)
	var hint := Label.new()
	hint.text = "拖到画布创建\n单击 = 在视野中心创建"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color("#94a3b8"))
	_box.add_child(hint)
	_box.add_child(HSeparator.new())

	_entry_button = _add_button("入口节点", backend.NODE_ENTRY, "唯一，不可删除", Color("#34d399"))
	_add_button("脚本节点", backend.NODE_SCRIPT, "对话 / 环境 / 额外指令", Color("#60a5fa"))
	_add_button("选择节点", backend.NODE_CHOICE, "分支选项（出边数=选项数）", Color("#fbbf24"))
	_add_button("出口节点", backend.NODE_EXIT, "完结 / 未完待续", Color("#fb7185"))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_box.add_child(spacer)

	var tip := Label.new()
	tip.text = "画布操作：\n· 左键拖空白：平移\n· 滚轮：缩放\n· 右键拖节点：连线\n· 右键拖空白：划线剪断\n· 双击节点：编辑属性"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 15)
	tip.add_theme_color_override("font_color", Color("#64748b"))
	_box.add_child(tip)


func _add_button(label: String, node_type: int, sub: String, color: Color) -> AaPaletteButton:
	var b := AaPaletteButton.new()
	b.text = ""            # 按钮不用内建文字（改由下面 VBox 分行显示，避免与按钮文字重叠）
	b.node_type = node_type
	b.drag_display = label
	b.custom_minimum_size = Vector2(0, 64)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(func():
		if not b.drag_enabled:
			status.emit("入口节点全工程唯一，已存在")
			return
		create_requested.emit(node_type)
	)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	var s := Label.new()
	s.text = sub
	s.add_theme_font_size_override("font_size", 13)
	s.add_theme_color_override("font_color", Color("#94a3b8"))
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(s)
	margin.add_child(box)
	b.add_child(margin)
	_box.add_child(b)
	return b


func set_entry_present(present: bool) -> void:
	_entry_present = present
	if _entry_button != null:
		_entry_button.disabled = present
		_entry_button.drag_enabled = not present
		_entry_button.tooltip_text = "入口节点全工程唯一" if present else "拖到画布创建入口节点"


func set_enabled(enabled: bool) -> void:
	visible = enabled
