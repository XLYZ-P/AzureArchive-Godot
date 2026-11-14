class_name AaInspectorPanel
extends PanelContainer
## 右侧检查器：按节点类型显示可编辑属性。
##
## - 入口节点：Header / Title
## - 脚本节点：脚本列表增删/排序 + 选中脚本的台词、额外指令、6 栏位属性、环境属性、高级字段
## - 选择节点：选项文本（数量 = 出边数）、断开选项连线
## - 出口节点：IsEnding / EndText / NeHeader / NeTitle / NeScriptDirty
## - 未选中节点：工程属性（工程名、封面、标题）
##
## 检查器只改模型，通过信号把“该刷新/该记撤销”交给 editor.gd。

signal begin_edit(tag: String)
signal changed(guid: String, tag: String)
signal project_changed(tag: String)
signal status(message: String)
signal picker_requested(kind: String, current: Variant, on_picked: Callable)
signal request_focus_node(guid: String)
signal request_delete_node(guid: String)

var backend: AaEditorBackend
var project = null
var node = null

var _content: VBoxContainer
var _selected_script := 0
var _selected_slot := 0
var _pending_commits: Array = []       # [{control, fn}]
var _dirty := false


func setup(p_backend: AaEditorBackend) -> void:
	backend = p_backend
	_build_shell()


func _build_shell() -> void:
	if _content != null:
		return
	custom_minimum_size.x = 600
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	scroll.add_child(_content)


# ---------------------------------------------------------------------------
# 对外入口
# ---------------------------------------------------------------------------

func show_project(p_project) -> void:
	project = p_project
	node = null
	_rebuild()


func show_node(p_project, p_node) -> void:
	project = p_project
	node = p_node
	if node != null and node.node_type == backend.NODE_SCRIPT:
		_selected_script = clampi(_selected_script, 0, maxi(0, node.scripts.size() - 1))
	_rebuild()


func get_node_guid() -> String:
	return "" if node == null else str(node.guid)


func selected_script_index() -> int:
	return _selected_script


## 保存/切换工程前把「正在编辑（仍有焦点）」的输入框内容写回模型。
## 只提交持有焦点的控件：避免把过期的空控件写回模型（覆盖外部修改，qa Q-006）。
func commit_all() -> void:
	var list := _pending_commits.duplicate()
	for item in list:
		var control = item.get("control", null)
		if control == null or not is_instance_valid(control):
			continue
		if not control.is_inside_tree():
			continue
		if control.has_focus():
			_do_commit(item)


# ---------------------------------------------------------------------------
# 构建工具
# ---------------------------------------------------------------------------

func _clear() -> void:
	_pending_commits.clear()
	if _content == null:
		return
	for c in _content.get_children():
		c.queue_free()
		_content.remove_child(c)


func _section(title: String) -> VBoxContainer:
	var sep := HSeparator.new()
	_content.add_child(sep)
	var head := Label.new()
	head.text = title
	head.add_theme_font_size_override("font_size", 22)
	head.add_theme_color_override("font_color", Color("#7dd3fc"))
	_content.add_child(head)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_content.add_child(box)
	return box


func _hint(text: String, box: VBoxContainer = null) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.add_theme_font_size_override("font_size", 16)
	lab.add_theme_color_override("font_color", Color("#94a3b8"))
	(box if box != null else _content).add_child(lab)
	return lab


func _title(text: String) -> void:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", 26)
	lab.add_theme_color_override("font_color", Color("#e2e8f0"))
	_content.add_child(lab)


func _row(label: String, control: Control, min_label := 120.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var lab := Label.new()
	lab.text = label
	lab.custom_minimum_size.x = min_label
	lab.add_theme_color_override("font_color", Color("#cbd5e1"))
	h.add_child(lab)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.custom_minimum_size.x = mini(control.custom_minimum_size.x, 380.0)
	h.add_child(control)
	return h


func _register_commit(control: Control, fn: Callable) -> void:
	_pending_commits.append({"control": control, "fn": fn})
	if control is LineEdit:
		var le := control as LineEdit
		le.text_submitted.connect(func(_t): _do_commit({"control": control, "fn": fn}))
		le.focus_exited.connect(func(): _do_commit({"control": control, "fn": fn}))
	elif control is TextEdit:
		var te := control as TextEdit
		te.focus_exited.connect(func(): _do_commit({"control": control, "fn": fn}))


func _do_commit(item: Dictionary) -> void:
	var control = item.get("control", null)
	# 只允许当前仍登记在待提交列表里的控件写回模型。
	# 关键：检查器重建时控件被 queue_free 会触发 focus_exited，如果不检查就会把
	# 即将丢弃的控件内容（比如空文本）覆盖到模型上（qa Q-006 的根因）。
	var found := false
	for i in range(_pending_commits.size() - 1, -1, -1):
		if _pending_commits[i].get("control", null) == control:
			_pending_commits.remove_at(i)
			found = true
			break
	if not found:
		return
	if control != null and not is_instance_valid(control):
		return
	var fn: Callable = item["fn"]
	# 约定：commit 回调接收控件本身（func(control): ...），避免闭包自引用问题
	if fn.get_argument_count() >= 1:
		fn.call(control)
	else:
		fn.call()


func _make_line_edit(value: String, on_commit: Callable) -> LineEdit:
	var le := LineEdit.new()
	le.text = value
	_register_commit(le, on_commit)
	return le


func _make_text_edit(value: String, height: float, on_commit: Callable) -> TextEdit:
	var te := TextEdit.new()
	te.text = value
	te.custom_minimum_size.y = height
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_register_commit(te, on_commit)
	return te


func _make_spin(value: int, min_v: int, max_v: int, on_change: Callable, step := 1) -> SpinBox:
	var sp := SpinBox.new()
	sp.min_value = min_v
	sp.max_value = max_v
	sp.step = step
	sp.value = value
	sp.value_changed.connect(func(v): on_change.call(int(v)))
	return sp


func _make_check(value: bool, text: String, on_change: Callable) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = text
	cb.button_pressed = value
	cb.toggled.connect(func(v): on_change.call(v))
	return cb


func _make_option(choices: Array, value: int, on_change: Callable) -> OptionButton:
	var ob := OptionButton.new()
	ob.clip_text = true
	ob.custom_minimum_size = Vector2(0, 0)
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var found := -1
	for i in choices.size():
		var pair: Array = choices[i]
		ob.add_item(str(pair[1]))
		ob.set_item_metadata(i, int(pair[0]))
		if int(pair[0]) == value:
			found = i
	if found == -1:
		ob.add_item("自定义值 %d" % value)
		ob.set_item_metadata(ob.item_count - 1, value)
		found = ob.item_count - 1
	ob.select(found)
	ob.item_selected.connect(func(idx):
		var meta = ob.get_item_metadata(idx)
		on_change.call(int(meta))
	)
	return ob


func _make_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	return b


func _make_btn_row(buttons: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	for b in buttons:
		if b is String:
			var lab := Label.new()
			lab.text = b
			lab.add_theme_color_override("font_color", Color("#94a3b8"))
			h.add_child(lab)
		else:
			h.add_child(b)
	return h


func _apply(tag: String, prop: String, value) -> void:
	if node == null:
		return
	begin_edit.emit(tag)
	node.set(prop, value)
	changed.emit(str(node.guid), tag)


func _apply_line(tag: String, prop: String, value) -> void:
	if node == null or _selected_script < 0 or _selected_script >= node.scripts.size():
		return
	begin_edit.emit(tag)
	var line = node.scripts[_selected_script]
	line.set(prop, value)
	changed.emit(str(node.guid), tag)


func _current_line():
	if node == null or node.node_type != backend.NODE_SCRIPT:
		return null
	if node.scripts.is_empty():
		return null
	_selected_script = clampi(_selected_script, 0, node.scripts.size() - 1)
	return node.scripts[_selected_script]


func _slot_char(line, slot: int):
	if line == null:
		return null
	if slot < 0 or slot >= line.characters.size():
		return null
	return line.characters[slot]


# ---------------------------------------------------------------------------
# 重绘
# ---------------------------------------------------------------------------

func _rebuild() -> void:
	_clear()
	if node == null:
		_build_project()
		return
	match node.node_type:
		_:
			pass
	if node.node_type == backend.NODE_ENTRY:
		_build_entry()
	elif node.node_type == backend.NODE_SCRIPT:
		_build_script()
	elif node.node_type == backend.NODE_CHOICE:
		_build_choice()
	elif node.node_type == backend.NODE_EXIT:
		_build_exit()
	else:
		_hint("未知节点类型：%d" % node.node_type)


# ---------------------------------------------------------------------------
# 工程属性
# ---------------------------------------------------------------------------

func _build_project() -> void:
	_title("工程属性")
	if project == null:
		_hint("没有打开的工程")
		return
	var box := _section("基础")
	var name_edit: LineEdit
	name_edit = _make_line_edit(str(project.project_name), func(name_edit):
		begin_edit.emit("project_name")
		project.project_name = name_edit.text
		project_changed.emit("project_name")
	)
	box.add_child(_row("工程名", name_edit))

	var bg_row := HBoxContainer.new()
	var bg_label := Label.new()
	var bg_name := _preview_bg_text()
	bg_label.text = bg_name
	bg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg_label.clip_text = true
	bg_row.add_child(bg_label)
	bg_row.add_child(_make_button("选择封面背景", func():
		picker_requested.emit("bg", {"id": project.preview_bg_name, "name": ""}, func(v):
			if v is Dictionary:
				begin_edit.emit("preview_bg")
				project.preview_bg_name = int(v.get("id", 0))
				project_changed.emit("preview_bg")
				_rebuild()
		)
	))
	bg_row.add_child(_make_button("清除", func():
		begin_edit.emit("preview_bg")
		project.preview_bg_name = 0
		project_changed.emit("preview_bg")
		_rebuild()
	))
	box.add_child(_row("封面背景", bg_row))

	var header_edit: LineEdit
	header_edit = _make_line_edit("" if project.preview_header == null else str(project.preview_header), func(header_edit):
		begin_edit.emit("preview_header")
		project.preview_header = null if header_edit.text.is_empty() else header_edit.text
		project_changed.emit("preview_header")
	)
	box.add_child(_row("PreviewHeader", header_edit))
	var title_edit: LineEdit
	title_edit = _make_line_edit("" if project.preview_title == null else str(project.preview_title), func(title_edit):
		begin_edit.emit("preview_title")
		project.preview_title = null if title_edit.text.is_empty() else title_edit.text
		project_changed.emit("preview_title")
	)
	box.add_child(_row("PreviewTitle", title_edit))

	var stats := _section("统计")
	var node_count: int = project.nodes.size()
	var line_count := 0
	for n in project.nodes:
		if n.node_type == backend.NODE_SCRIPT:
			line_count += n.scripts.size()
	var conn_count := 0
	for n in project.nodes:
		conn_count += n.connections.size()
	_hint("节点 %d 个（入口 %d / 脚本 %d / 选择 %d / 出口 %d）" % [
		node_count,
		project.get_nodes_of_type(backend.NODE_ENTRY).size() if project.has_method("get_nodes_of_type") else 1,
		project.get_nodes_of_type(backend.NODE_SCRIPT).size() if project.has_method("get_nodes_of_type") else 0,
		project.get_nodes_of_type(backend.NODE_CHOICE).size() if project.has_method("get_nodes_of_type") else 0,
		project.get_nodes_of_type(backend.NODE_EXIT).size() if project.has_method("get_nodes_of_type") else 0,
	], stats)
	_hint("脚本行 %d 条 · 连线 %d 条" % [line_count, conn_count], stats)
	var validate_btn := _make_button("校验工程结构", func():
		if project.has_method("validate"):
			var problems = project.call("validate")
			if problems is Array and not problems.is_empty():
				status.emit("校验发现 %d 个问题：" % problems.size() + "；".join(problems.slice(0, 6)))
			else:
				status.emit("校验通过：结构无问题")
		else:
			status.emit("当前数据层不支持 validate()")
	)
	stats.add_child(validate_btn)
	_hint("Tip：双击画布节点编辑属性；从左侧节点工厂拖节点到画布；右键拖动节点连线，右键拖空白剪断连线。", stats)


func _preview_bg_text() -> String:
	if project == null:
		return ""
	var id: int = int(project.preview_bg_name)
	if id == 0:
		return "（无）"
	var ctx = _context()
	if ctx != null and ctx.has_method("get_bg_entries"):
		var arr = ctx.call("get_bg_entries")
		if arr is Array:
			for it in arr:
				if it is Dictionary and int(it.get("id", -1)) == id:
					return "%s（%d）" % [str(it.get("name", "")), id]
	return str(id)


func _context():
	var tree := get_tree()
	if tree == null:
		return null
	var res := tree.root.get_node_or_null("/root/AAResources")
	if res == null or not res.has_method("make_context"):
		return null
	return res.call("make_context")


# ---------------------------------------------------------------------------
# 入口节点
# ---------------------------------------------------------------------------

func _build_entry() -> void:
	_title("入口节点")
	_hint("入口节点全工程唯一，不可删除；剧情从这里开始。")
	var box := _section("剧情标题")
	var header_edit: LineEdit
	header_edit = _make_line_edit(str(node.header), func(header_edit):
		_apply("entry_header", "header", header_edit.text)
	)
	box.add_child(_row("序号 Header", header_edit))
	var title_edit: LineEdit
	title_edit = _make_line_edit(str(node.title), func(title_edit):
		_apply("entry_title", "title", title_edit.text)
	)
	box.add_child(_row("标题 Title", title_edit))
	_hint("都不填 = 生成剧情不含标题；只填标题 = 隐藏序号。", box)
	var out := _section("出边")
	var targets: Array = []
	for g in node.connections:
		var t = project.find_node(g)
		targets.append("%s（%s）" % [str(g).substr(0, 8), "?" if t == null else t.type_name_zh() if t.has_method("type_name_zh") else "节点"])
	_hint("连接到：" + ("、".join(targets) if not targets.is_empty() else "（尚未连线）"), out)
	var focus_btn := _make_button("查看入口节点", func(): request_focus_node.emit(str(node.guid)))
	out.add_child(focus_btn)


# ---------------------------------------------------------------------------
# 脚本节点
# ---------------------------------------------------------------------------

func _build_script() -> void:
	var type_label := "脚本节点"
	_title(type_label)
	var name_box := _section("节点")
	var name_edit: LineEdit
	name_edit = _make_line_edit(str(node.node_name), func(name_edit):
		_apply("script_node_name", "node_name", name_edit.text)
	)
	name_box.add_child(_row("节点名称", name_edit))
	name_box.add_child(_make_btn_row([
		_make_button("在图上定位", func(): request_focus_node.emit(str(node.guid))),
		_make_button("删除此节点", func(): request_delete_node.emit(str(node.guid))),
	]))

	# ---- 脚本列表 ----
	var list_box := _section("脚本列表（%d 条）" % node.scripts.size())
	var list_row := HBoxContainer.new()
	list_row.add_theme_constant_override("separation", 6)
	var item_list := ItemList.new()
	item_list.custom_minimum_size = Vector2(0, 220)
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for i in node.scripts.size():
		var line = node.scripts[i]
		var text := str(line.text).replace("\n", " ")
		if text.is_empty():
			text = "（空脚本）"
		if text.length() > 26:
			text = text.substr(0, 26) + "…"
		item_list.add_item("%d. %s" % [i + 1, text])
	if not node.scripts.is_empty():
		_selected_script = clampi(_selected_script, 0, node.scripts.size() - 1)
		item_list.select(_selected_script)
		item_list.ensure_current_is_visible()
	item_list.item_selected.connect(func(idx):
		_selected_script = idx
		_rebuild()
	)
	list_row.add_child(item_list)

	list_box.add_child(list_row)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	btns.add_child(_make_button("＋ 添加", func(): _add_script(node.scripts.size())))
	btns.add_child(_make_button("− 删除", func(): _remove_script()))
	btns.add_child(_make_button("↑ 上移", func(): _move_script(-1)))
	btns.add_child(_make_button("↓ 下移", func(): _move_script(1)))
	btns.add_child(_make_button("⧉ 复制", func(): _duplicate_script()))
	list_box.add_child(btns)

	var line = _current_line()
	if line == null:
		_hint("空脚本节点。点「＋ 添加脚本」创建第一条对话。", list_box)
		list_box.add_child(_make_button("＋ 添加第一条脚本", func(): _add_script(0)))
		return

	# ---- 台词 ----
	var text_box := _section("对话（脚本 #%d）" % (_selected_script + 1))
	var te: TextEdit
	te = _make_text_edit(str(line.text), 110, func(te):
		_apply_line("line_text", "text", te.text)
	)
	text_box.add_child(te)
	_hint("支持 AA 内联标记：[size=60]文本[/size]、[FF0000]文字[-]、[ruby=注音]文本[/ruby]。", text_box)

	# ---- 额外指令 ----
	var cmd_box := _section("额外指令（#，每行一条）")
	var ce: TextEdit
	ce = _make_text_edit(str(line.additional_prompt), 86, func(ce):
		_apply_line("line_prompt", "additional_prompt", ce.text)
	)
	cmd_box.add_child(ce)
	_hint("例：#wait;2000  #bgshake  #zmc;smooth;0,0;1000;500  #st;[0,-430];serial;60;  #clearST", cmd_box)

	# ---- 栏位 ----
	var slot_box := _section("栏位（characters[6]，下标 0 = 说话/无立绘槽）")
	var slot_bar := HBoxContainer.new()
	slot_bar.add_theme_constant_override("separation", 4)
	for s in 6:
		var ch = _slot_char(line, s)
		var nm := ""
		if ch != null and not str(ch.name).is_empty():
			nm = str(ch.name)
		var label := "%d%s" % [s, ("·" + nm) if not nm.is_empty() else ""]
		var b := Button.new()
		b.text = label
		b.toggle_mode = true
		b.button_pressed = (_selected_slot == s)
		b.pressed.connect(func():
			_selected_slot = s
			_rebuild()
		)
		slot_bar.add_child(b)
	slot_box.add_child(slot_bar)
	_hint("当前编辑栏位：#%d（%s）" % [_selected_slot, "发言槽/旁白" if _selected_slot == 0 else "立绘位置"], slot_box)

	var ch = _slot_char(line, _selected_slot)
	if ch == null:
		_hint("栏位数据缺失（characters 不足 6 项）")
		return
	var char_box := _section("栏位 #%d 属性" % _selected_slot)
	var char_row := HBoxContainer.new()
	var char_label := Label.new()
	char_label.text = str(ch.name) if not str(ch.name).is_empty() else "（无角色）"
	char_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	char_row.add_child(char_label)
	char_row.add_child(_make_button("选择角色", func():
		picker_requested.emit("character", str(ch.name), func(v):
			_apply_char("char_name", ch, "name", str(v))
			_rebuild()
		)
	))
	char_row.add_child(_make_button("清除", func():
		_apply_char("char_clear", ch, "name", "")
		_apply_char("char_clear", ch, "starting_pos", 0)
		_apply_char("char_clear", ch, "ending_pos", 0)
		_rebuild()
	))
	char_box.add_child(_row("角色 name", char_row))

	var face_edit: LineEdit
	face_edit = _make_line_edit(str(ch.face_id), func(face_edit):
		_apply_char("char_face", ch, "face_id", face_edit.text)
	)
	char_box.add_child(_row("表情 faceId", face_edit))
	char_box.add_child(_row("位置 startingPos", _make_spin(int(ch.starting_pos), 0, 5, func(v):
		_apply_char("char_start", ch, "starting_pos", v)
	)))
	char_box.add_child(_row("终点 endingPos", _make_spin(int(ch.ending_pos), 0, 5, func(v):
		_apply_char("char_end", ch, "ending_pos", v)
	)))
	char_box.add_child(_row("进出场 appear", _make_option(backend.enum_choices("appear"), int(ch.appear), func(v):
		_apply_char("char_appear", ch, "appear", v)
	)))
	char_box.add_child(_row("动作 action", _make_option(backend.enum_choices("action"), int(ch.action), func(v):
		_apply_char("char_action", ch, "action", v)
	)))
	char_box.add_child(_row("气泡 emoticon", _make_option(backend.enum_choices("emoticon"), int(ch.emoticon), func(v):
		_apply_char("char_emoticon", ch, "emoticon", v)
	)))
	char_box.add_child(_row("形状 shapeOverride", _make_shape_checks(ch)))
	_hint("shapeOverride 是位掩码：1=sig 剪影 / 2=black 变暗 / 4=closeup 特写，可组合。", char_box)
	_hint("图标行顺序（AA）：≪(dl) ▷(ar) ＋(a) [1][2][3][4][5] －(d) ◁(al) ≫(dr)", char_box)

	# ---- 环境 ----
	var env := _section("环境")
	env.add_child(_row("背景 bgFriendlyName", _bg_row(line)))
	env.add_child(_row("背景效果 bgEffect", _make_option(backend.enum_choices("bg_effect"), int(line.bg_effect), func(v):
		_apply_line("line_bg_effect", "bg_effect", v)
	)))
	env.add_child(_row("过渡 transition", _make_option(backend.enum_choices("transition"), int(line.transition), func(v):
		_apply_line("line_transition", "transition", v)
	)))
	env.add_child(_row("BGM bgmId", _bgm_row(line)))
	env.add_child(_row("弹出图 popup", _string_res_row(line, "popup", "popup")))
	env.add_child(_row("音效 sound", _string_res_row(line, "sound", "sound")))
	env.add_child(_row("语音 voice", _string_res_row(line, "voice", "voice")))
	var place_edit: LineEdit
	place_edit = _make_line_edit(str(line.place_text), func(place_edit):
		_apply_line("line_place", "place_text", place_edit.text)
	)
	env.add_child(_row("地点名 placeText", place_edit))

	# ---- 高级 ----
	var adv := _section("高级")
	adv.add_child(_row("发言槽 speakerSlot", _make_spin(int(line.speaker_slot_num), 0, 5, func(v):
		_apply_line("line_speaker", "speaker_slot_num", v)
	)))
	var hl_text := ""
	if line.highlighted_slot_nums != null:
		var parts: Array = []
		for x in line.highlighted_slot_nums:
			parts.append(str(int(x)))
		hl_text = ",".join(parts)
	var hl_edit: LineEdit
	hl_edit = _make_line_edit(hl_text, func(hl_edit):
		var arr: Array = []
		var text: String = str(hl_edit.text)
		for part in text.split(",", false):
			var p: String = str(part).strip_edges()
			if p.is_valid_int():
				arr.append(int(p))
		var packed := PackedInt32Array()
		for x in arr:
			packed.append(int(x))
		_apply_line("line_highlight", "highlighted_slot_nums", packed)
	)
	adv.add_child(_row("高亮槽 highlighted", hl_edit))
	adv.add_child(_row("显示对话框 isDialog", _make_check(bool(line.is_dialog_script), "显示对话框", func(v):
		_apply_line("line_dialog", "is_dialog_script", v)
	)))
	adv.add_child(_row("选择组 selectionGroup", _make_spin(int(line.selection_group), 0, 999, func(v):
		_apply_line("line_selgroup", "selection_group", v)
	)))
	var bg_info := Label.new()
	bg_info.text = "bgName = %d（%s）" % [int(line.bg_name), "与 bgFriendlyName 匹配" if _bg_matches(line) else "与 bgFriendlyName 不匹配"]
	bg_info.add_theme_color_override("font_color", Color("#94a3b8"))
	bg_info.add_theme_font_size_override("font_size", 16)
	adv.add_child(bg_info)
	adv.add_child(_make_button("按 bgFriendlyName 重算 bgName", func():
		if line.has_method("repair_bg_id"):
			begin_edit.emit("line_repair_bg")
			line.call("repair_bg_id")
			changed.emit(str(node.guid), "line_repair_bg")
			status.emit("已重算 bgName")
		else:
			begin_edit.emit("line_repair_bg")
			line.bg_name = backend.bg_id(str(line.bg_friendly_name))
			changed.emit(str(node.guid), "line_repair_bg")
			status.emit("已重算 bgName（fallback 哈希）")
		_rebuild()
	))


func _bg_matches(line) -> bool:
	if line.has_method("bg_id_matches"):
		return bool(line.call("bg_id_matches"))
	return int(line.bg_name) == backend.bg_id(str(line.bg_friendly_name))


## shapeOverride 位掩码多选（lead 确认：可组合 1/2/4）
func _make_shape_checks(ch) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var cur := int(ch.shape_override)
	for bit in [1, 2, 4]:
		var cb := CheckBox.new()
		cb.text = {1: "sig 剪影", 2: "black 变暗", 4: "closeup 特写"}[bit]
		cb.button_pressed = (cur & bit) != 0
		cb.toggled.connect(func(pressed):
			var v := int(ch.shape_override)
			if pressed:
				v = v | bit
			else:
				v = v & ~bit
			_apply_char("char_shape", ch, "shape_override", v)
		)
		h.add_child(cb)
	return h


func _apply_char(tag: String, ch, prop: String, value) -> void:
	if ch == null:
		return
	begin_edit.emit(tag)
	ch.set(prop, value)
	if node != null:
		changed.emit(str(node.guid), tag)


func _bg_row(line) -> HBoxContainer:
	var h := HBoxContainer.new()
	var lab := Label.new()
	lab.text = str(line.bg_friendly_name) if not str(line.bg_friendly_name).is_empty() else "（无背景）"
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.clip_text = true
	h.add_child(lab)
	h.add_child(_make_button("选择背景", func():
		picker_requested.emit("bg", {"id": int(line.bg_name), "name": str(line.bg_friendly_name)}, func(v):
			if not (v is Dictionary):
				return
			begin_edit.emit("line_bg")
			var nm := str(v.get("name", ""))
			var id: int = int(v.get("id", 0))
			if id < 0 or (nm != "" and backend.hash_ready()):
				id = backend.bg_id(nm)
			line.bg_friendly_name = nm
			line.bg_name = id
			changed.emit(str(node.guid), "line_bg")
			_rebuild()
		)
	))
	h.add_child(_make_button("清除", func():
		begin_edit.emit("line_bg_clear")
		line.bg_friendly_name = ""
		line.bg_name = 0
		changed.emit(str(node.guid), "line_bg_clear")
		_rebuild()
	))
	return h


func _bgm_row(line) -> HBoxContainer:
	var h := HBoxContainer.new()
	var lab := Label.new()
	lab.text = _bgm_text(int(line.bgm_id))
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.clip_text = true
	h.add_child(lab)
	h.add_child(_make_button("选择 BGM", func():
		picker_requested.emit("bgm", int(line.bgm_id), func(v):
			begin_edit.emit("line_bgm")
			line.bgm_id = int(v)
			changed.emit(str(node.guid), "line_bgm")
			_rebuild()
		)
	))
	h.add_child(_make_button("静音999", func():
		begin_edit.emit("line_bgm_mute")
		line.bgm_id = 999
		changed.emit(str(node.guid), "line_bgm_mute")
		_rebuild()
	))
	return h


func _bgm_text(id: int) -> String:
	if id == 999:
		return "999（静音）"
	if id == 0:
		return "0（未设置）"
	return str(id)


func _string_res_row(line, prop: String, kind: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var lab := Label.new()
	var val := str(line.get(prop))
	lab.text = val if not val.is_empty() else "（无）"
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.clip_text = true
	h.add_child(lab)
	h.add_child(_make_button("选择", func():
		picker_requested.emit(kind, val, func(v):
			begin_edit.emit("line_" + prop)
			line.set(prop, str(v))
			changed.emit(str(node.guid), "line_" + prop)
			_rebuild()
		)
	))
	h.add_child(_make_button("清除", func():
		begin_edit.emit("line_" + prop + "_clear")
		line.set(prop, "")
		changed.emit(str(node.guid), "line_" + prop + "_clear")
		_rebuild()
	))
	return h


# ---- 脚本列表操作 ----

func _new_line_copy_env(from_line):
	var line = backend.new_script_line()
	if from_line != null:
		for prop in ["bg_effect", "bg_name", "bg_friendly_name", "transition", "bgm_id"]:
			if prop in from_line:
				line.set(prop, from_line.get(prop))
	else:
		line.bgm_id = 999
	return line


func _add_script(index: int) -> void:
	if node == null:
		return
	index = clampi(index, 0, node.scripts.size())
	var prev = node.scripts[index - 1] if index > 0 else null
	var line = _new_line_copy_env(prev)
	begin_edit.emit("script_add")
	node.scripts.insert(index, line)
	_selected_script = index
	changed.emit(str(node.guid), "script_add")
	_rebuild()


func _remove_script() -> void:
	if node == null or node.scripts.is_empty():
		return
	var idx := clampi(_selected_script, 0, node.scripts.size() - 1)
	begin_edit.emit("script_remove")
	node.scripts.remove_at(idx)
	_selected_script = clampi(idx, 0, maxi(0, node.scripts.size() - 1))
	changed.emit(str(node.guid), "script_remove")
	_rebuild()


func _move_script(delta: int) -> void:
	if node == null:
		return
	var idx := clampi(_selected_script, 0, node.scripts.size() - 1)
	var new_idx := idx + delta
	if new_idx < 0 or new_idx >= node.scripts.size():
		return
	begin_edit.emit("script_move")
	var line = node.scripts[idx]
	node.scripts.remove_at(idx)
	node.scripts.insert(new_idx, line)
	_selected_script = new_idx
	changed.emit(str(node.guid), "script_move")
	_rebuild()


func _duplicate_script() -> void:
	if node == null or node.scripts.is_empty():
		return
	var idx := clampi(_selected_script, 0, node.scripts.size() - 1)
	var src = node.scripts[idx]
	var copy = backend.new_script_line()
	var src_dict = src.to_dict()
	var copied = null
	if backend.line_script != null:
		copied = backend.line_script.call("from_dict", src_dict)
	if copied == null:
		copied = copy
	begin_edit.emit("script_dup")
	node.scripts.insert(idx + 1, copied)
	_selected_script = idx + 1
	changed.emit(str(node.guid), "script_dup")
	_rebuild()


# ---------------------------------------------------------------------------
# 选择节点
# ---------------------------------------------------------------------------

func _build_choice() -> void:
	_title("选择节点")
	_hint("选项数量 = 出边数量。到画布上从选择节点右侧端口拉线新增选项（最后一个「＋ 新选项」端口）。同一目标可以重复连线。")
	var opts: Array = backend.choice_options(project, node)
	var box := _section("选项（%d 个）" % opts.size())
	if opts.is_empty():
		_hint("还没有出边。选择节点至少连一条线才能编译。", box)
	for opt in opts:
		var i: int = int(opt.get("index", 0))
		var target_guid := str(opt.get("target_guid", ""))
		var target = opt.get("target", null)
		var row := VBoxContainer.new()
		var h := HBoxContainer.new()
		var num := Label.new()
		num.text = "%d." % (i + 1)
		num.custom_minimum_size.x = 30
		h.add_child(num)
		var le := LineEdit.new()
		le.text = str(opt.get("text", ""))
		le.placeholder_text = "选项文本"
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.text_submitted.connect(func(t): _set_choice_text(i, t))
		le.focus_exited.connect(func(): _set_choice_text(i, le.text))
		h.add_child(le)
		var target_label := Label.new()
		if target != null:
			var tn := ""
			if target.has_method("type_name_zh"):
				tn = str(target.call("type_name_zh"))
			else:
				tn = str(target.node_type)
			target_label.text = "→ %s（%s）" % [str(target_guid).substr(0, 8), tn]
		else:
			target_label.text = "→ 目标缺失（%s）" % str(target_guid).substr(0, 8)
		target_label.custom_minimum_size.x = 190
		target_label.add_theme_color_override("font_color", Color("#94a3b8"))
		h.add_child(target_label)
		h.add_child(_make_button("断开", func():
			begin_edit.emit("choice_disconnect")
			project.disconnect_nodes(node, project.find_node(target_guid), i)
			changed.emit(str(node.guid), "choice_disconnect")
			_rebuild()
		))
		row.add_child(h)
		box.add_child(row)
	box.add_child(_make_button("刷新选项列表", func(): _rebuild()))
	var out := _section("节点信息")
	out.add_child(_make_btn_row([
		_make_button("在图上定位", func(): request_focus_node.emit(str(node.guid))),
		_make_button("删除此节点", func(): request_delete_node.emit(str(node.guid))),
	]))
	var slot_hint := Label.new()
	slot_hint.text = "selectionTexts 固定 16 槽（未用补空串），编辑器只写前 N 项。"
	slot_hint.add_theme_color_override("font_color", Color("#94a3b8"))
	slot_hint.add_theme_font_size_override("font_size", 16)
	slot_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	out.add_child(slot_hint)


func _set_choice_text(index: int, text: String) -> void:
	if node == null:
		return
	begin_edit.emit("choice_text")
	if node.has_method("set_selection_text"):
		node.call("set_selection_text", index, text)
	else:
		var texts: PackedStringArray = node.selection_texts
		while texts.size() < 16:
			texts.append("")
		texts[index] = text
		node.selection_texts = texts
	changed.emit(str(node.guid), "choice_text")


# ---------------------------------------------------------------------------
# 出口节点
# ---------------------------------------------------------------------------

func _build_exit() -> void:
	_title("出口节点")
	_hint("出口节点标示剧情结束。完（Ending）可填结束语；未完待续可填下回预告。")
	var box := _section("类型")
	box.add_child(_make_check(bool(node.is_ending), "完（Ending）—— 勾选后使用 EndText", func(v):
		_apply("exit_ending", "is_ending", v)
		_rebuild()
	))
	if node.is_ending:
		var end_edit: TextEdit
		end_edit = _make_text_edit(str(node.end_text), 90, func(end_edit):
			_apply("exit_endtext", "end_text", end_edit.text)
		)
		box.add_child(_row("EndText", end_edit))
	else:
		var ne_header: LineEdit
		ne_header = _make_line_edit(str(node.ne_header), func(ne_header):
			_apply("exit_neheader", "ne_header", ne_header.text)
		)
		box.add_child(_row("NeHeader", ne_header))
		var ne_title: LineEdit
		ne_title = _make_line_edit(str(node.ne_title), func(ne_title):
			_apply("exit_netitle", "ne_title", ne_title.text)
		)
		box.add_child(_row("NeTitle", ne_title))
		_hint("按 AA 规则，编译时会自动写入 #nextepisode;NeHeader;NeTitle 到 NeScriptDirty.additionalPrompt。", box)

	var dirty := _section("NeScriptDirty（下回预告脚本，简单编辑）")
	var ne = node.get("ne_script")
	if ne == null:
		ne = node.get("ne_script_dirty")
	if ne == null:
		_hint("该出口没有 NeScriptDirty 数据")
	else:
		var ne_text: TextEdit
		ne_text = _make_text_edit(str(ne.text), 70, func(ne_text):
			_apply_ne("exit_ne_text", ne, "text", ne_text.text)
		)
		dirty.add_child(_row("text", ne_text))
		var ne_prompt: LineEdit
		ne_prompt = _make_line_edit(str(ne.additional_prompt), func(ne_prompt):
			_apply_ne("exit_ne_prompt", ne, "additional_prompt", ne_prompt.text)
		)
		dirty.add_child(_row("additionalPrompt", ne_prompt))
		var ne_bg: LineEdit
		ne_bg = _make_line_edit(str(ne.bg_friendly_name), func(ne_bg):
			_apply_ne("exit_ne_bg", ne, "bg_friendly_name", ne_bg.text)
			apply_ne_bg_id(ne)
		)
		dirty.add_child(_row("bgFriendlyName", ne_bg))
		var ne_bgm := _make_spin(int(ne.bgm_id), 0, 99999, func(v):
			_apply_ne("exit_ne_bgm", ne, "bgm_id", v)
		)
		dirty.add_child(_row("bgmId", ne_bgm))
	var out := _section("节点信息")
	out.add_child(_make_btn_row([
		_make_button("在图上定位", func(): request_focus_node.emit(str(node.guid))),
		_make_button("删除此节点", func(): request_delete_node.emit(str(node.guid))),
	]))


func apply_ne_bg_id(ne) -> void:
	if ne == null:
		return
	if ne.has_method("repair_bg_id"):
		ne.call("repair_bg_id")
	else:
		ne.bg_name = backend.bg_id(str(ne.bg_friendly_name))


func _apply_ne(tag: String, ne, prop: String, value) -> void:
	if ne == null:
		return
	begin_edit.emit(tag)
	ne.set(prop, value)
	changed.emit(str(node.guid), tag)
