class_name AaEditor
extends Control
## 节点式剧情编辑器（AA `.aap`）。
##
## 布局：顶部工具栏 + 左侧节点工厂 + 中间 GraphEdit 节点图 + 右侧检查器 + 底部状态栏。
## 数据层：AaEditorBackend（优先 core 的 AapProject，core 缺失时回退 aa_editor/model/fallback_project.gd）。
##
## 对外 API（目录界面 / headless 测试用）：
##   open_project_file(path) -> bool
##   open(project, path := "") -> bool
##   new_project() -> bool
##   get_project()
##   add_node(node_type, pos := Vector2.ZERO) -> String（返回 guid）
##   connect_nodes(from_guid, to_guid, option_index := -1) -> bool
##   delete_node(guid) -> bool
##   save() -> bool / save_as(path) -> bool
##   compile() -> PlayScript|null
##   undo() / redo() -> bool
## 信号：request_exit、request_play(project)

signal request_exit
signal request_play(project)
signal project_saved(path)

const FONT_PATH := "res://assets/fonts/wqy-zenhei-extracted.ttf"
const UI_FONT_SIZE := 19
const BG_COLOR := Color("#0b1220")
const PANEL_COLOR := Color("#151f31")
const ACCENT := Color("#7dd3fc")

var backend: AaEditorBackend
var project = null
var current_path := ""
var dirty := false
var resource_context = null

var graph: AaGraphView
var inspector: AaInspectorPanel
var factory: AaNodeFactory

var _toolbar: PanelContainer
var _project_name_edit: LineEdit
var _status_path: Label
var _status_dirty: Label
var _status_message: Label
var _status_counts: Label
var _undo_btn: Button
var _redo_btn: Button
var _autosave_check: CheckBox
var _autosave_timer: Timer
var _open_dialog: FileDialog
var _save_dialog: FileDialog
var _preview_root: Control = null
var _ready_done := false

var _undo: Array = []
var _redo: Array = []
var _last_edit_tag := ""
var _last_edit_ms := 0
var _status_msg := "就绪"


# ---------------------------------------------------------------------------
# 生命周期
# ---------------------------------------------------------------------------

func _ready() -> void:
	_ensure_ready()


func _ensure_ready() -> void:
	if _ready_done:
		return
	_ready_done = true
	backend = AaEditorBackend.new()
	_build_theme()
	_build_ui()
	new_project()


func _build_theme() -> void:
	var font: Font = null
	# 用 raw loader 运行时加载字体（headless 没有导入器）
	if ResourceLoader.exists("res://addons/aa_resources/raw_loader.gd"):
		var loader = load("res://addons/aa_resources/raw_loader.gd")
		if loader != null:
			font = loader.call("load_font", FONT_PATH)
	if font == null:
		var f := FontFile.new()
		if f.load_dynamic_font(FONT_PATH) == OK:
			font = f
	var th := Theme.new()
	if font != null:
		th.default_font = font
	th.default_font_size = UI_FONT_SIZE
	theme = th


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root_v := VBoxContainer.new()
	root_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_v.add_theme_constant_override("separation", 0)
	add_child(root_v)

	# ---- 顶部工具栏 ----
	_toolbar = PanelContainer.new()
	var toolbar_style := StyleBoxFlat.new()
	toolbar_style.bg_color = PANEL_COLOR
	toolbar_style.content_margin_left = 12
	toolbar_style.content_margin_right = 12
	toolbar_style.content_margin_top = 8
	toolbar_style.content_margin_bottom = 8
	_toolbar.add_theme_stylebox_override("panel", toolbar_style)
	root_v.add_child(_toolbar)
	var tb := HBoxContainer.new()
	tb.add_theme_constant_override("separation", 8)
	_toolbar.add_child(tb)

	tb.add_child(_toolbar_button("新建", new_project, "Ctrl+N"))
	tb.add_child(_toolbar_button("打开", _on_open_pressed, "Ctrl+O"))
	tb.add_child(_toolbar_button("保存", save, "Ctrl+S"))
	tb.add_child(_toolbar_button("另存为", _on_save_as_pressed, "Ctrl+Shift+S"))
	tb.add_child(VSeparator.new())
	tb.add_child(_toolbar_button("－", func(): _zoom_by(1.0 / 1.25), "缩小"))
	tb.add_child(_toolbar_button("＋", func(): _zoom_by(1.25), "放大"))
	tb.add_child(_toolbar_button("适应", func(): graph.zoom_to_fit(), "总览全部节点"))
	tb.add_child(VSeparator.new())
	tb.add_child(_toolbar_button("编译", compile, "Ctrl+B"))
	var play_btn := _toolbar_button("▶ 播放预览", _on_play_pressed, "F5")
	play_btn.add_theme_color_override("font_color", Color("#86efac"))
	tb.add_child(play_btn)
	tb.add_child(VSeparator.new())
	_undo_btn = _toolbar_button("↶ 撤销", undo, "Ctrl+Z")
	tb.add_child(_undo_btn)
	_redo_btn = _toolbar_button("↷ 重做", redo, "Ctrl+Y")
	tb.add_child(_redo_btn)
	tb.add_child(VSeparator.new())

	var name_label := Label.new()
	name_label.text = "工程名"
	name_label.add_theme_color_override("font_color", Color("#94a3b8"))
	tb.add_child(name_label)
	_project_name_edit = LineEdit.new()
	_project_name_edit.custom_minimum_size.x = 220
	_project_name_edit.placeholder_text = "工程名"
	_project_name_edit.text_submitted.connect(func(_t): _commit_project_name())
	_project_name_edit.focus_exited.connect(func(): _commit_project_name())
	tb.add_child(_project_name_edit)

	tb.add_child(VSeparator.new())
	_autosave_check = CheckBox.new()
	_autosave_check.text = "自动保存(60s)"
	_autosave_check.button_pressed = false
	_autosave_check.toggled.connect(_on_autosave_toggled)
	tb.add_child(_autosave_check)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tb.add_child(spacer)
	var back_btn := _toolbar_button("返回", _on_back_pressed, "Esc")
	back_btn.add_theme_color_override("font_color", Color("#fca5a5"))
	tb.add_child(back_btn)

	# ---- 中部三栏 ----
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 2)
	root_v.add_child(body)

	factory = AaNodeFactory.new()
	factory.setup(backend)
	factory.create_requested.connect(_on_factory_create)
	factory.status.connect(_set_status)
	body.add_child(factory)

	graph = AaGraphView.new()
	graph.setup(backend)
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph.create_node_requested.connect(_on_create_node_requested)
	graph.connect_requested.connect(_on_connect_requested)
	graph.disconnect_requested.connect(_on_disconnect_requested)
	graph.delete_requested.connect(_on_delete_requested)
	graph.node_selection_changed.connect(_on_node_selection_changed)
	graph.node_activated.connect(_on_node_activated)
	graph.status_message.connect(_set_status)
	graph.begin_node_move.connect(func(): push_undo("move_node", true))
	body.add_child(graph)

	inspector = AaInspectorPanel.new()
	inspector.setup(backend)
	inspector.begin_edit.connect(_on_inspector_begin_edit)
	inspector.changed.connect(_on_inspector_changed)
	inspector.project_changed.connect(_on_inspector_project_changed)
	inspector.status.connect(_set_status)
	inspector.picker_requested.connect(_open_picker)
	inspector.request_focus_node.connect(_on_focus_node)
	inspector.request_delete_node.connect(_on_delete_node_by_guid)
	body.add_child(inspector)

	# ---- 底部状态栏 ----
	var status_panel := PanelContainer.new()
	var status_style := StyleBoxFlat.new()
	status_style.bg_color = PANEL_COLOR
	status_style.content_margin_left = 12
	status_style.content_margin_right = 12
	status_style.content_margin_top = 5
	status_style.content_margin_bottom = 5
	status_panel.add_theme_stylebox_override("panel", status_style)
	root_v.add_child(status_panel)
	var sb := HBoxContainer.new()
	sb.add_theme_constant_override("separation", 18)
	status_panel.add_child(sb)
	_status_path = Label.new()
	_status_path.add_theme_color_override("font_color", Color("#94a3b8"))
	_status_path.add_theme_font_size_override("font_size", 16)
	_status_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_path.clip_text = true
	sb.add_child(_status_path)
	_status_counts = Label.new()
	_status_counts.add_theme_color_override("font_color", Color("#94a3b8"))
	_status_counts.add_theme_font_size_override("font_size", 16)
	sb.add_child(_status_counts)
	_status_dirty = Label.new()
	_status_dirty.add_theme_font_size_override("font_size", 16)
	sb.add_child(_status_dirty)
	_status_message = Label.new()
	_status_message.add_theme_color_override("font_color", ACCENT)
	_status_message.add_theme_font_size_override("font_size", 16)
	sb.add_child(_status_message)

	# ---- 自动保存 ----
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = 60.0
	_autosave_timer.one_shot = false
	_autosave_timer.timeout.connect(_on_autosave_timeout)
	add_child(_autosave_timer)

	_build_dialogs()
	_update_controls()


func _toolbar_button(text: String, cb: Callable, shortcut_hint := "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 44
	b.add_theme_font_size_override("font_size", 18)
	if not shortcut_hint.is_empty():
		b.tooltip_text = "%s（%s）" % [text, shortcut_hint]
	b.pressed.connect(cb)
	return b


func _build_dialogs() -> void:
	_open_dialog = FileDialog.new()
	_open_dialog.title = "打开 .aap 工程"
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_dialog.filters = PackedStringArray(["*.aap ; AzureArchive 工程"])
	_open_dialog.current_dir = _projects_dir()
	_open_dialog.file_selected.connect(func(path): open_project_file(path))
	add_child(_open_dialog)

	_save_dialog = FileDialog.new()
	_save_dialog.title = "另存为 .aap"
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.filters = PackedStringArray(["*.aap ; AzureArchive 工程"])
	_save_dialog.current_dir = _projects_dir()
	_save_dialog.file_selected.connect(func(path): save_as(path))
	add_child(_save_dialog)


# ---------------------------------------------------------------------------
# 主题/控件刷新
# ---------------------------------------------------------------------------

func _update_controls() -> void:
	if _project_name_edit != null and project != null and not _project_name_edit.has_focus():
		_project_name_edit.text = str(project.project_name)
	if _undo_btn != null:
		_undo_btn.disabled = _undo.is_empty()
	if _redo_btn != null:
		_redo_btn.disabled = _redo.is_empty()
	if _status_path != null:
		_status_path.text = "文件：" + (current_path if not current_path.is_empty() else "（未保存）")
	if _status_dirty != null:
		_status_dirty.text = "● 未保存修改" if dirty else "✓ 已保存"
		_status_dirty.add_theme_color_override("font_color", Color("#fbbf24") if dirty else Color("#4ade80"))
	if _status_counts != null and project != null:
		var lines := 0
		for n in project.nodes:
			if n.node_type == backend.NODE_SCRIPT:
				lines += n.scripts.size()
		var conns := 0
		for n in project.nodes:
			conns += n.connections.size()
		_status_counts.text = "节点 %d · 脚本行 %d · 连线 %d" % [project.nodes.size(), lines, conns]
	if factory != null and project != null:
		factory.set_entry_present(project.get_entry() != null)


func _set_status(message: String) -> void:
	_status_msg = message
	if _status_message != null:
		_status_message.text = message


func _mark_dirty() -> void:
	dirty = true
	_update_controls()


# ---------------------------------------------------------------------------
# 工程装载
# ---------------------------------------------------------------------------

func new_project() -> bool:
	_ensure_ready()
	_commit_inspector()
	project = backend.new_project()
	if project == null:
		_set_status("新建工程失败：" + backend.last_error)
		return false
	current_path = ""
	dirty = false
	_undo.clear()
	_redo.clear()
	_selected_guid = ""
	graph.zoom = 1.0
	graph.scroll_offset = Vector2.ZERO
	graph.set_project(project)
	inspector.show_project(project)
	_refresh_resource_context()
	_update_controls()
	_set_status("已新建工程（数据层：%s）" % backend.backend_name)
	return true


func open_project_file(path: String) -> bool:
	_ensure_ready()
	_commit_inspector()
	var p = backend.load_from_file(path)
	if p == null:
		_set_status("打开失败：" + (backend.last_error if not backend.last_error.is_empty() else path))
		return false
	_install_project(p, path)
	_set_status("已打开：" + path + (("（%s）" % backend.last_error) if not backend.last_error.is_empty() else ""))
	return true


func open(p_project, p_path := "") -> bool:
	_ensure_ready()
	_commit_inspector()
	if p_project == null:
		return false
	_install_project(p_project, p_path)
	_set_status("已装载工程：" + (p_path if not p_path.is_empty() else str(p_project.project_name)))
	return true


func _install_project(p_project, p_path: String) -> void:
	project = p_project
	current_path = p_path
	dirty = false
	_undo.clear()
	_redo.clear()
	_selected_guid = ""
	graph.set_project(project)
	inspector.show_project(project)
	_refresh_resource_context()
	_update_controls()
	# 打开工程后自动缩放到能看到全部节点的包围盒；布局完成后再算一次
	graph.zoom_to_fit()
	call_deferred("_deferred_fit_view")


func _deferred_fit_view() -> void:
	# 等容器布局完成（GraphEdit.size 有效）后再算一次，保证打开工程就能看到全部节点
	if not is_inside_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if graph != null and project != null:
		graph.zoom_to_fit()


func get_project():
	return project


func get_current_path() -> String:
	return current_path


func is_dirty() -> bool:
	return dirty


func get_graph() -> AaGraphView:
	return graph


func get_inspector() -> AaInspectorPanel:
	return inspector


func _refresh_resource_context() -> void:
	resource_context = null
	var res := get_node_or_null("/root/AAResources")
	if res != null and res.has_method("make_context"):
		resource_context = res.call("make_context", current_path, "")


# ---------------------------------------------------------------------------
# 节点/连线编辑 API
# ---------------------------------------------------------------------------

func add_node(node_type: int, pos := Vector2.ZERO) -> String:
	_ensure_ready()
	if project == null:
		return ""
	push_undo("add_node", true)
	var node = project.add_node(node_type, pos)
	if node == null:
		_set_status("创建节点失败（入口节点唯一？）")
		return ""
	# 新建脚本节点默认带一条空脚本，方便立刻填台词（AA 允许空节点，但空节点无法编译）
	if node_type == backend.NODE_SCRIPT and node.scripts.is_empty():
		node.scripts.append(backend.new_script_line())
	_mark_dirty()
	graph.rebuild()
	var guid := str(node.guid)
	graph.select_guid(guid)
	_on_node_selection_changed(guid)
	_set_status("已创建%s" % _node_type_name(node_type))
	return guid


func connect_nodes(from_guid: String, to_guid: String, option_index := -1) -> bool:
	_ensure_ready()
	if project == null:
		return false
	var from = project.find_node(from_guid)
	var to = project.find_node(to_guid)
	if from == null or to == null:
		_set_status("连线失败：节点不存在")
		return false
	if from == to:
		_set_status("连线失败：不能连到自己")
		return false
	if to.get("node_type") == backend.NODE_ENTRY:
		_set_status("连线失败：入口节点没有入端")
		return false
	if from.node_type == backend.NODE_EXIT:
		_set_status("连线失败：出口节点没有出端")
		return false
	if not _can_reach_ok(from, to):
		_set_status("连线失败：会形成环（AA 编译按行展开，禁止环）")
		return false
	push_undo("connect", true)
	var ok := false
	if from.node_type == backend.NODE_CHOICE:
		if option_index >= 0 and option_index < from.connections.size():
			# 改接已有选项：保留选项文本，只替换目标
			var conns: PackedStringArray = from.connections.duplicate()
			conns[option_index] = to.guid
			from.connections = conns
			ok = true
		else:
			ok = _choice_append(from, to)
	else:
		ok = bool(project.connect_nodes(from, to))
	if ok:
		_mark_dirty()
		graph.rebuild()
		graph.select_guid(from_guid)
		_set_status("已连线：%s → %s" % [_guid_short(from_guid), _guid_short(to_guid)])
	else:
		_set_status("连线失败（选择节点选项最多 16 个）")
	return ok


func _choice_append(from, to) -> bool:
	# AA 允许选择节点重复连到同一目标（aap.md 实测）。core 新版 add_connection 已不去重，
	# 这里仍直接操作模型：对 core / fallback 两种实现行为一致，且不依赖版本差异。
	var conns: PackedStringArray = from.connections.duplicate()
	if conns.size() >= 16:
		return false
	conns.append(to.guid)
	from.connections = conns
	if from.has_method("normalize_selection_texts"):
		from.call("normalize_selection_texts")
	return true


func _can_reach_ok(from, to) -> bool:
	# 广度优先：从 to 出发若能在出边里找到 from，则 from→to 会成环
	var seen: Dictionary = {}
	var queue: Array = [str(to.guid)]
	while not queue.is_empty():
		var g: String = queue.pop_front()
		if g == str(from.guid):
			return false
		if seen.has(g):
			continue
		seen[g] = true
		var n = project.find_node(g)
		if n == null:
			continue
		for c in n.connections:
			queue.append(str(c))
	return true


func disconnect_nodes(from_guid: String, to_guid: String, option_index := -1) -> bool:
	_ensure_ready()
	if project == null:
		return false
	var from = project.find_node(from_guid)
	if from == null:
		return false
	push_undo("disconnect", true)
	var ok := false
	if from.node_type != backend.NODE_CHOICE:
		option_index = -1
	ok = bool(project.disconnect_nodes(from, project.find_node(to_guid), option_index))
	if ok:
		_mark_dirty()
		graph.rebuild()
		_set_status("已断开连线")
		if inspector.get_node_guid() == from_guid:
			inspector.show_node(project, from)
	return ok


func delete_node(guid: String) -> bool:
	_ensure_ready()
	if project == null:
		return false
	var node = project.find_node(guid)
	if node == null:
		return false
	if node.node_type == backend.NODE_ENTRY:
		_set_status("入口节点不可删除")
		return false
	if node.connections.size() > 0:
		_set_status("%s还有 %d 条出边，请先断开连线再删除" % [node.type_name_zh() if node.has_method("type_name_zh") else "节点", node.connections.size()])
		return false
	var incoming: Array = []
	for n in project.nodes:
		if n != node and guid in n.connections:
			incoming.append(n)
	if not incoming.is_empty():
		_set_status("还有 %d 条连线指向该节点，请先断开再删除" % incoming.size())
		return false
	push_undo("delete_node", true)
	if not project.remove_node(node):
		_set_status("删除节点失败")
		return false
	_mark_dirty()
	graph.rebuild()
	graph.clear_selection()
	inspector.show_project(project)
	_set_status("已删除节点")
	return true


# ---------------------------------------------------------------------------
# 保存/编译/播放
# ---------------------------------------------------------------------------

func save() -> bool:
	_ensure_ready()
	_commit_inspector()
	if project == null:
		return false
	var path := current_path
	if path.is_empty():
		path = _default_save_path()
	elif path.begins_with("res://"):
		# res:// 是只读安装目录（fixtures 等），不覆盖源文件，改存到数据目录
		path = _default_save_path()
	return save_as(path)


func save_as(path: String) -> bool:
	_ensure_ready()
	_commit_inspector()
	if project == null:
		return false
	if path.is_empty():
		_set_status("保存失败：路径为空")
		return false
	if path.get_extension().is_empty():
		path += ".aap"
	var err: int = backend.save_to_file(project, path)
	if err != OK:
		_set_status("保存失败（错误码 %d）：%s" % [err, path])
		return false
	current_path = path
	dirty = false
	_refresh_resource_context()
	_update_controls()
	_set_status("已保存：" + path)
	project_saved.emit(path)
	return true


func compile():
	_ensure_ready()
	_commit_inspector()
	if project == null:
		return null
	if project.has_method("validate"):
		var problems = project.call("validate")
		if problems is Array and not problems.is_empty():
			_set_status("编译前校验：%d 个问题（仍继续编译）：%s" % [problems.size(), "；".join(problems.slice(0, 3))])
	var play_script = null
	if project.has_method("compile"):
		play_script = project.call("compile")
	if play_script == null:
		_set_status("编译失败：core 未提供 compile() 或节点图不完整")
		return null
	var count := 0
	if play_script.has_method("get_node_count"):
		count = int(play_script.call("get_node_count"))
	_set_status("编译成功：可执行节点 %d 个%s" % [count, ("（有警告）" if play_script.has_method("has_warnings") and play_script.call("has_warnings") else "")])
	return play_script


func _on_play_pressed() -> void:
	var ps = compile()
	if ps == null:
		return
	var scene_path: String = backend.player_scene_path()
	if scene_path.is_empty():
		_set_status("播放器（scenes/player/Player.tscn）尚未就绪，已编译但无法预览")
		return
	_start_preview(ps)


func _start_preview(play_script) -> void:
	if _preview_root != null:
		return
	var scene = load(backend.player_scene_path())
	if scene == null:
		_set_status("加载播放器场景失败")
		return
	var player = scene.instantiate()
	if player == null:
		_set_status("实例化播放器失败")
		return
	_preview_root = Control.new()
	_preview_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_root.z_index = 100
	_preview_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_preview_root)
	var bg := ColorRect.new()
	bg.color = Color("#000000")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_root.add_child(bg)
	player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_root.add_child(player)
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	bar.position = Vector2(size.x - 220, 8)
	bar.z_index = 2
	_preview_root.add_child(bar)
	var exit_btn := Button.new()
	exit_btn.text = "✕ 退出预览"
	exit_btn.custom_minimum_size = Vector2(180, 48)
	exit_btn.pressed.connect(_stop_preview)
	bar.add_child(exit_btn)
	var ok := false
	# 优先按 runtime-dev 的契约 AaPlayer.setup(project)；有 PlayScript 接口则也支持
	for method in ["setup_from_play_script", "setup_play_script"]:
		if player.has_method(method):
			player.call(method, play_script)
			ok = true
			break
	if not ok:
		for method in ["setup_from_project", "setup", "set_project"]:
			if player.has_method(method):
				player.call(method, project)
				ok = true
				break
	if not ok and player.has_method("setup_from_path"):
		player.call("setup_from_path", current_path)
		ok = true
	if player.has_signal("finished"):
		player.connect("finished", _stop_preview)
	if player.has_signal("request_exit"):
		player.connect("request_exit", _stop_preview)
	if player.has_method("play"):
		player.call("play")
	_set_status("播放预览中（%s）" % ("setup" if ok else "播放器接口未知，直接加入"))
	request_play.emit(project)


func _stop_preview() -> void:
	if _preview_root != null:
		_preview_root.queue_free()
		_preview_root = null
		_set_status("已退出播放预览")


# ---------------------------------------------------------------------------
# 撤销/重做
# ---------------------------------------------------------------------------

func push_undo(tag: String, structural := false) -> void:
	if project == null:
		return
	var now := Time.get_ticks_msec()
	if not structural and tag == _last_edit_tag and now - _last_edit_ms < 900:
		_last_edit_ms = now
		return
	var snap := {
		"json": backend.snapshot_text(project),
		"dirty": dirty,
		"sel": _selected_guid,
		"tag": tag,
	}
	_undo.append(snap)
	if _undo.size() > 80:
		_undo.pop_front()
	_redo.clear()
	_last_edit_tag = tag
	_last_edit_ms = now
	_update_controls()


func undo() -> bool:
	_ensure_ready()
	if _undo.is_empty() or project == null:
		_set_status("没有可撤销的操作")
		return false
	var cur := {
		"json": backend.snapshot_text(project),
		"dirty": dirty,
		"sel": _selected_guid,
		"tag": str(_undo[-1].get("tag", "")),
	}
	var snap: Dictionary = _undo.pop_back()
	_redo.append(cur)
	_restore_snapshot(snap)
	_set_status("已撤销：" + str(snap.get("tag", "")))
	return true


func redo() -> bool:
	_ensure_ready()
	if _redo.is_empty() or project == null:
		_set_status("没有可重做的操作")
		return false
	var cur := {
		"json": backend.snapshot_text(project),
		"dirty": dirty,
		"sel": _selected_guid,
		"tag": str(_redo[-1].get("tag", "")),
	}
	var snap: Dictionary = _redo.pop_back()
	_undo.append(cur)
	_restore_snapshot(snap)
	_set_status("已重做：" + str(snap.get("tag", "")))
	return true


func _restore_snapshot(snap: Dictionary) -> void:
	var p = backend.load_from_string(str(snap.get("json", "")))
	if p == null:
		_set_status("撤销/重做失败：快照解析失败")
		return
	project = p
	if not current_path.is_empty() and "source_path" in project:
		project.set("source_path", current_path)
	dirty = bool(snap.get("dirty", true))
	graph.set_project(project)
	var sel := str(snap.get("sel", ""))
	if not sel.is_empty() and project.find_node(sel) != null:
		graph.select_guid(sel)
		inspector.show_node(project, project.find_node(sel))
	else:
		_selected_guid = ""
		inspector.show_project(project)
	_update_controls()


var _selected_guid := ""


# ---------------------------------------------------------------------------
# 画布/检查器信号
# ---------------------------------------------------------------------------

func _on_factory_create(node_type: int) -> void:
	if project == null:
		return
	var pos := _graph_center_pos()
	if node_type == backend.NODE_ENTRY and project.get_entry() != null:
		_set_status("入口节点全工程唯一，已存在")
		return
	add_node(node_type, pos)


func _graph_center_pos() -> Vector2:
	# 4.7 变换：view = position_offset * zoom - scroll_offset
	var center_view: Vector2 = graph.size * 0.5
	return (center_view + graph.scroll_offset) / maxf(graph.zoom, 0.01)


func _on_create_node_requested(node_type: int, graph_pos: Vector2) -> void:
	add_node(node_type, graph_pos)


func _on_connect_requested(from_guid: String, to_guid: String, option_index: int) -> void:
	connect_nodes(from_guid, to_guid, option_index)


func _on_disconnect_requested(from_guid: String, to_guid: String, option_index: int) -> void:
	disconnect_nodes(from_guid, to_guid, option_index)


func _on_delete_requested(guids: PackedStringArray) -> void:
	var ok_count := 0
	for guid in guids:
		if delete_node(guid):
			ok_count += 1
	if ok_count > 1:
		_set_status("已删除 %d 个节点" % ok_count)


func _on_delete_node_by_guid(guid: String) -> void:
	delete_node(guid)


func _on_node_selection_changed(guid: String) -> void:
	_selected_guid = guid
	if project == null:
		return
	if guid.is_empty():
		inspector.show_project(project)
	else:
		var node = project.find_node(guid)
		if node != null:
			inspector.show_node(project, node)


func _on_node_activated(guid: String) -> void:
	if project == null:
		return
	var node = project.find_node(guid)
	if node != null:
		graph.select_guid(guid)
		if graph.zoom < 0.45:
			graph.zoom = 0.8
		graph.focus_guid(guid)
		inspector.show_node(project, node)
		_set_status("编辑%s属性（右侧检查器）" % (node.type_name_zh() if node.has_method("type_name_zh") else "节点"))


func _on_focus_node(guid: String) -> void:
	if project == null or project.find_node(guid) == null:
		return
	graph.select_guid(guid)
	graph.focus_guid(guid)
	inspector.show_node(project, project.find_node(guid))


# ---------------------------------------------------------------------------
# 检查器信号
# ---------------------------------------------------------------------------

func _on_inspector_begin_edit(tag: String) -> void:
	push_undo(tag)


func _on_inspector_changed(guid: String, _tag: String) -> void:
	_mark_dirty()
	if project == null:
		return
	graph.refresh_node_visual(guid)
	_update_controls()


func _on_inspector_project_changed(_tag: String) -> void:
	_mark_dirty()
	_update_controls()


func _commit_inspector() -> void:
	if inspector != null:
		inspector.commit_all()


func _commit_project_name() -> void:
	if project == null or _project_name_edit == null:
		return
	var new_name := _project_name_edit.text.strip_edges()
	if new_name.is_empty():
		new_name = "新建工程"
	if new_name == str(project.project_name):
		return
	push_undo("project_name")
	project.project_name = new_name
	_mark_dirty()


# ---------------------------------------------------------------------------
# 资源选择器
# ---------------------------------------------------------------------------

func _open_picker(kind: String, current: Variant, on_picked: Callable) -> void:
	var dlg := AaPickerDialog.new()
	dlg.setup(kind, resource_context, current, backend)
	add_child(dlg)
	dlg.picked.connect(func(value):
		on_picked.call(value)
	)
	dlg.popup_centered(Vector2i(860, 660))


# ---------------------------------------------------------------------------
# 打开/另存为/返回/自动保存
# ---------------------------------------------------------------------------

func _on_open_pressed() -> void:
	_commit_inspector()
	if _open_dialog != null:
		_open_dialog.current_dir = _projects_dir()
		_open_dialog.popup_centered(Vector2i(900, 640))


func _on_save_as_pressed() -> void:
	_commit_inspector()
	if _save_dialog != null:
		_save_dialog.current_dir = _projects_dir()
		_save_dialog.current_file = str(project.project_name if project != null else "新建工程") + ".aap"
		_save_dialog.popup_centered(Vector2i(900, 640))


func _on_back_pressed() -> void:
	_commit_inspector()
	_on_autosave_timeout()
	var had_listener := not get_signal_connection_list("request_exit").is_empty()
	request_exit.emit()
	if not had_listener:
		# 独立运行时：有目录界面就回去，否则退出
		if ResourceLoader.exists("res://scenes/main/Main.tscn"):
			get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
		else:
			get_tree().quit()


func _on_autosave_toggled(pressed: bool) -> void:
	if _autosave_timer == null:
		return
	if pressed:
		_autosave_timer.start()
		_set_status("自动保存已开启（每 60 秒）")
	else:
		_autosave_timer.stop()
		_set_status("自动保存已关闭")


func _on_autosave_timeout() -> void:
	if not _autosave_check.button_pressed or not dirty or project == null:
		return
	if current_path.is_empty() or current_path.begins_with("res://"):
		return
	if save():
		_set_status("已自动保存：" + current_path)


func _projects_dir() -> String:
	var res := get_node_or_null("/root/AAResources")
	if res != null and "data_root" in res:
		var dir := str(res.get("data_root")).path_join("projects")
		var abs_dir := ProjectSettings.globalize_path(dir)
		if DirAccess.dir_exists_absolute(abs_dir):
			return abs_dir
	var fixtures := ProjectSettings.globalize_path("res://fixtures/aap")
	if DirAccess.dir_exists_absolute(fixtures):
		return fixtures
	return ProjectSettings.globalize_path("user://")


func _default_save_path() -> String:
	var name := "新建工程"
	if project != null:
		name = str(project.project_name)
	var safe := ""
	for i in name.length():
		var c := name[i]
		if c in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
			safe += "_"
		else:
			safe += c
	if safe.strip_edges().is_empty():
		safe = "未命名工程"
	return _projects_dir_for_write().path_join(safe + ".aap")


func _projects_dir_for_write() -> String:
	var res := get_node_or_null("/root/AAResources")
	if res != null and "data_root" in res:
		var dir := str(res.get("data_root")).path_join("projects")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		return dir
	var fallback := "user://aa_editor_projects"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fallback))
	return fallback


# ---------------------------------------------------------------------------
# 键盘快捷键
# ---------------------------------------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var ctrl := key.ctrl_pressed or key.meta_pressed
	if ctrl and key.keycode == KEY_S:
		if key.shift_pressed:
			_on_save_as_pressed()
		else:
			save()
		get_viewport().set_input_as_handled()
	elif ctrl and key.keycode == KEY_O:
		_on_open_pressed()
		get_viewport().set_input_as_handled()
	elif ctrl and key.keycode == KEY_N:
		new_project()
		get_viewport().set_input_as_handled()
	elif ctrl and key.keycode == KEY_Z:
		if key.shift_pressed:
			redo()
		else:
			undo()
		get_viewport().set_input_as_handled()
	elif ctrl and key.keycode == KEY_Y:
		redo()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F5:
		_on_play_pressed()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE and _preview_root != null:
		_stop_preview()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _zoom_by(factor: float) -> void:
	if graph == null:
		return
	graph.zoom = clampf(graph.zoom * factor, graph.zoom_min, graph.zoom_max)
	_set_status("缩放：%d%%" % int(round(graph.zoom * 100.0)))


func _node_type_name(node_type: int) -> String:
	match node_type:
		backend.NODE_ENTRY:
			return "入口节点"
		backend.NODE_SCRIPT:
			return "脚本节点"
		backend.NODE_CHOICE:
			return "选择节点"
		backend.NODE_EXIT:
			return "出口节点"
	return "节点"


func _guid_short(guid: String) -> String:
	return guid.substr(0, 8)


## 测试辅助：模拟用户双击节点（打开检查器）
func select_node(guid: String) -> void:
	_on_node_activated(guid)
