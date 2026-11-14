class_name AaGraphView
extends GraphEdit
## 节点图画布：入口 / 脚本 / 选择 / 出口四种 GraphNode。
##
## 交互（对齐 AA 编辑器 operate 方式）：
## - 节点工厂拖出节点 / 双击空白画布也可创建（见 editor.gd）
## - 左键拖动节点移动，X/Y 写回模型；左键拖动空白平移视角；滚轮缩放
## - 右键从节点上半部分拖出 = 从「入端」反向连线，下半部分 = 从「出端」连线
## - 右键在空白处拖动 = 划红线，松手切断与红线相交的连线
## - 选择节点每个选项一个出端口（最后一个是「＋ 新选项」）
## - Delete 键 / 右键菜单删除选中节点（入口/仍有连线的节点禁止，由 editor 校验）
## - 双击节点 = 打开检查器
##
## 注意：本类不直接改数据层，只发信号；由 editor.gd 负责改 AapProject 并调用 rebuild()。

signal node_activated(guid: String)
signal node_selection_changed(guid: String)
signal create_node_requested(node_type: int, graph_pos: Vector2)
signal connect_requested(from_guid: String, to_guid: String, option_index: int)
signal disconnect_requested(from_guid: String, to_guid: String, option_index: int)
signal delete_requested(guids: PackedStringArray)
signal nodes_moved()
signal status_message(message: String)

const COLOR_ENTRY := Color("#34d399")
const COLOR_SCRIPT := Color("#60a5fa")
const COLOR_CHOICE := Color("#fbbf24")
const COLOR_EXIT := Color("#fb7185")
const COLOR_PORT_IN := Color("#93c5fd")
const COLOR_PORT_OUT := Color("#f9a8d4")
const COLOR_CUT := Color("#ff3b5c")
const COLOR_CONNECT := Color("#ffe066")

## 节点类型（与 backend 同步；editor 调用 setup 时传入）
var node_entry := 0
var node_script := 1
var node_choice := 2
var node_exit := 3

var backend: AaEditorBackend

var _project = null
var _guids_by_name: Dictionary = {}      # StringName -> guid
var _names_by_guid: Dictionary = {}      # guid -> StringName
var _graph_nodes: Dictionary = {}        # guid -> GraphNode
var _selected_guid := ""
var _node_meta: Dictionary = {}          # guid -> {type:int, title:String}
var _body_nodes: Dictionary = {}        # guid -> Control（正文根节点，刷新时整体替换）

# 右键拖拽状态
var _drag_mode := ""                     # "", "connect", "cut"
var _drag_from_guid := ""
var _drag_is_output := true
var _drag_start_local := Vector2.ZERO
var _drag_current_local := Vector2.ZERO
var _drag_option_index := 0

# 左键平移
var _panning := false
var _pan_last := Vector2.ZERO


func _ready() -> void:
	_configure()


func setup(p_backend: AaEditorBackend) -> void:
	backend = p_backend
	node_entry = backend.NODE_ENTRY
	node_script = backend.NODE_SCRIPT
	node_choice = backend.NODE_CHOICE
	node_exit = backend.NODE_EXIT
	_configure()


func _configure() -> void:
	# 外观/行为（不依赖编辑器导入的贴图、字体资源）
	show_grid = true
	grid_pattern = GraphEdit.GRID_PATTERN_DOTS
	snapping_enabled = false
	panning_scheme = 0  # 0 = 滚轮缩放；左键平移由本类自定义实现
	zoom_min = 0.08     # AA 的节点图很长（Y 轴上千米），允许缩得更小以便总览
	zoom_max = 2.5
	right_disconnects = false
	show_menu = false
	show_zoom_label = true
	show_zoom_buttons = true
	minimap_enabled = false
	connection_lines_curvature = 0.45
	connection_lines_thickness = 3.0
	connection_lines_antialiased = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	# 连接类型：统一 0 号类型，允许任意节点互连（具体合法性由 editor 校验）
	if not is_connected("connection_request", _on_connection_request):
		connection_request.connect(_on_connection_request)
	if not is_connected("disconnection_request", _on_disconnection_request):
		disconnection_request.connect(_on_disconnection_request)
	if not is_connected("node_selected", _on_node_selected):
		node_selected.connect(_on_node_selected)
	if not is_connected("node_deselected", _on_node_deselected):
		node_deselected.connect(_on_node_deselected)
	if not is_connected("end_node_move", _on_end_node_move):
		end_node_move.connect(_on_end_node_move)
	if not is_connected("delete_nodes_request", _on_delete_nodes_request):
		delete_nodes_request.connect(_on_delete_nodes_request)


# ---------------------------------------------------------------------------
# 构建
# ---------------------------------------------------------------------------

func set_project(project) -> void:
	_project = project
	rebuild()


func rebuild(preserve_view := true) -> void:
	var old_zoom := zoom
	var old_scroll := scroll_offset
	_release_all_nodes()
	_guids_by_name.clear()
	_names_by_guid.clear()
	_graph_nodes.clear()
	_node_meta.clear()
	_body_nodes.clear()
	_selected_guid = ""
	if _project == null:
		return
	var nodes: Array = _project.nodes
	for n in nodes:
		_add_graph_node(n)
	for n in nodes:
		var from_name: StringName = _node_name_for(n.guid)
		for i in n.connections.size():
			var target_guid: String = n.connections[i]
			var to_name: StringName = _node_name_for(target_guid)
			if from_name == &"" or to_name == &"":
				continue
			var e := connect_node(from_name, i, to_name, 0)
			if e != OK:
				# 选择节点端口可能不够（旧数据 16 选项限制等），忽略
				pass
	if preserve_view:
		zoom = old_zoom
		scroll_offset = old_scroll
	else:
		zoom = 1.0
		scroll_offset = Vector2.ZERO


func _release_all_nodes() -> void:
	for child in get_children():
		if child is GraphNode:
			remove_child(child)
			child.queue_free()
	clear_connections()


func _node_name_for(guid: String) -> StringName:
	if _names_by_guid.has(guid):
		return _names_by_guid[guid]
	return &""


func _add_graph_node(node) -> void:
	var gn := GraphNode.new()
	var gn_name := StringName("n_" + node.guid.replace("-", "").substr(0, 20))
	if gn_name == &"":
		return
	gn.name = gn_name
	gn.title = _node_title(node)
	gn.resizable = false
	gn.draggable = true
	gn.selectable = true
	gn.position_offset = node.pos
	gn.custom_minimum_size = Vector2(_node_width(node), 0)
	add_child(gn)
	# 标题栏颜色块（区分节点类型；不用外部贴图）
	var hb := gn.get_titlebar_hbox()
	if hb != null:
		var strip := ColorRect.new()
		strip.color = _type_color(node.node_type)
		strip.custom_minimum_size = Vector2(10, 18)
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(strip)
		hb.move_child(strip, 0)
	_build_node_body(gn, node)
	_apply_slots(gn, node)
	_guids_by_name[gn_name] = node.guid
	_names_by_guid[node.guid] = gn_name
	_graph_nodes[node.guid] = gn
	_node_meta[node.guid] = {"type": node.node_type}
	gn.gui_input.connect(_on_graph_node_gui_input.bind(node.guid))
	gn.position_offset = node.pos


func _type_color(t: int) -> Color:
	match t:
		node_entry:
			return COLOR_ENTRY
		node_choice:
			return COLOR_CHOICE
		node_exit:
			return COLOR_EXIT
		_:
			return COLOR_SCRIPT


func _node_width(node) -> float:
	match node.node_type:
		node_choice:
			return 340.0
		node_exit:
			return 320.0
		_:
			return 300.0


func _node_title(node) -> String:
	match node.node_type:
		node_entry:
			return "入口 ▶"
		node_choice:
			var cnt: int = node.connections.size()
			return "选择 · %d 项" % cnt
		node_exit:
			if node.is_ending:
				return "出口 · 完（Ending）"
			return "出口 · 未完待续"
		_:
			var nm: String = node.node_name
			if nm.is_empty():
				return "脚本 · 未命名"
			return "脚本 · " + nm


func _build_node_body(gn: GraphNode, node) -> void:
	var body = _build_node_body_inner(node, gn)
	if body != null:
		gn.add_child(body)
		_body_nodes[node.guid] = body


func _build_node_body_inner(node, gn: GraphNode) -> Control:
	match node.node_type:
		node_entry:
			var box := VBoxContainer.new()
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_theme_constant_override("separation", 2)
			box.add_child(_row_label("序号 Header：" + (node.header if not node.header.is_empty() else "（空）")))
			box.add_child(_row_label("标题 Title：" + (node.title if not node.title.is_empty() else "（空）")))
			box.add_child(_row_label("入口唯一，不可删除", Color("#94a3b8"), 16))
			return box
		node_choice:
			# 每个直接子节点是一行，GraphNode 的端口按行对齐
			var head := _row_label("选项（右键从右侧端口拉线）：")
			gn.add_child(head)
			var count: int = node.connections.size()
			for i in count:
				var txt: String = ""
				if i < node.selection_texts.size():
					txt = str(node.selection_texts[i])
				if txt.is_empty():
					txt = "（未填写选项 %d）" % (i + 1)
				var row := HBoxContainer.new()
				row.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var num := _row_label("%d." % (i + 1), COLOR_CHOICE, 18)
				num.custom_minimum_size = Vector2(28, 0)
				row.add_child(num)
				var lab := _row_label(txt, Color("#f8fafc"), 18, 240)
				row.add_child(lab)
				gn.add_child(row)
			var add_row := HBoxContainer.new()
			add_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_row.add_child(_row_label("＋ 新选项", Color("#fde68a"), 18, 240))
			gn.add_child(add_row)
			return null
		node_exit:
			var box := VBoxContainer.new()
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if node.is_ending:
				box.add_child(_row_label("类型：完（Ending）", Color("#fecdd3")))
				box.add_child(_row_label("EndText：" + (node.end_text if not node.end_text.is_empty() else "（空）")))
			else:
				box.add_child(_row_label("类型：未完待续（To be continued）", Color("#fecdd3")))
				box.add_child(_row_label("下回预告：" + (node.ne_title if not node.ne_title.is_empty() else "（空）")))
			return box
		_:
			var box := VBoxContainer.new()
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_theme_constant_override("separation", 2)
			var scripts: Array = node.scripts
			box.add_child(_row_label("脚本 %d 条" % scripts.size(), Color("#bfdbfe"), 18))
			if scripts.is_empty():
				box.add_child(_row_label("（空节点，双击添加脚本）", Color("#94a3b8"), 16))
			else:
				var shown: int = mini(scripts.size(), 3)
				for i in shown:
					var line = scripts[i]
					var txt: String = str(line.text)
					if txt.is_empty():
						txt = "（无台词）"
					txt = txt.replace("\n", " ")
					if txt.length() > 22:
						txt = txt.substr(0, 22) + "…"
					box.add_child(_row_label("「" + txt + "」", Color("#e2e8f0"), 17, 270))
				if scripts.size() > shown:
					box.add_child(_row_label("…… 还有 %d 条" % (scripts.size() - shown), Color("#94a3b8"), 16))
			return box
	return null


func _row_label(text: String, color := Color("#e2e8f0"), size := 18, width := 0.0) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", size)
	lab.add_theme_color_override("font_color", color)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.clip_text = true
	lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if width > 0.0:
		lab.custom_minimum_size = Vector2(width, 0)
	return lab


## 端口：入口 1 出；脚本 1 入 1 出；选择 1 入 + N+1 出；出口 1 入
func _apply_slots(gn: GraphNode, node) -> void:
	var has_in: bool = node.node_type != node_entry
	var has_out: bool = node.node_type != node_exit
	match node.node_type:
		node_choice:
			gn.set_slot(0, true, 0, COLOR_PORT_IN, false, 0, COLOR_PORT_OUT)
			var count: int = node.connections.size()
			for i in count:
				gn.set_slot(i + 1, false, 0, COLOR_PORT_IN, true, 0, COLOR_PORT_OUT)
			gn.set_slot(count + 1, false, 0, COLOR_PORT_IN, true, 0, COLOR_CHOICE)
		_:
			gn.set_slot(0, has_in, 0, COLOR_PORT_IN, has_out, 0, COLOR_PORT_OUT)


# ---------------------------------------------------------------------------
# 从节点工厂拖拽进来创建节点
# ---------------------------------------------------------------------------

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("aa_node_type")


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not (data is Dictionary and data.has("aa_node_type")):
		return
	var node_type := int(data["aa_node_type"])
	var graph_pos: Vector2 = at_position / maxf(zoom, 0.01) + scroll_offset
	create_node_requested.emit(node_type, graph_pos)


# ---------------------------------------------------------------------------
# 数据 -> 显示 的局部刷新（检查器改属性后不重建整图，避免闪烁）
# ---------------------------------------------------------------------------

func refresh_node_visual(guid: String) -> void:
	if _project == null:
		return
	var node = _project.find_node(guid)
	if node == null or not _graph_nodes.has(guid):
		return
	# 选择节点增删连线会改变端口数量，必须重建整图
	if node.node_type == node_choice:
		rebuild()
		return
	var gn: GraphNode = _graph_nodes[guid]
	gn.title = _node_title(node)
	if _body_nodes.has(guid):
		var old_body = _body_nodes[guid]
		if old_body != null and is_instance_valid(old_body):
			if old_body.get_parent() != null:
				old_body.get_parent().remove_child(old_body)
			old_body.queue_free()
		_body_nodes.erase(guid)
	_build_node_body(gn, node)
	_apply_slots(gn, node)


func refresh_positions_from_graph() -> void:
	## 把 GraphNode 的位置写回模型（节点拖动 / 自动布局后调用）
	if _project == null:
		return
	for guid in _graph_nodes.keys():
		var node = _project.find_node(guid)
		if node == null:
			continue
		var gn: GraphNode = _graph_nodes[guid]
		node.pos = gn.position_offset


# ---------------------------------------------------------------------------
# 选择 / 定位
# ---------------------------------------------------------------------------

func get_selected_guid() -> String:
	return _selected_guid


func select_guid(guid: String, emit := true) -> void:
	if _selected_guid == guid:
		return
	if _graph_nodes.has(_selected_guid):
		(_graph_nodes[_selected_guid] as GraphNode).selected = false
	_selected_guid = guid
	if _graph_nodes.has(guid):
		(_graph_nodes[guid] as GraphNode).selected = true
		if emit:
			node_selection_changed.emit(guid)
	elif emit:
		node_selection_changed.emit("")


func clear_selection() -> void:
	select_guid("")


## 缩放并平移画布，让所有节点都进入视野（打开工程后调用）
func zoom_to_fit(margin := 64.0) -> void:
	if _graph_nodes.is_empty():
		return
	var min_p := Vector2(1e20, 1e20)
	var max_p := Vector2(-1e20, -1e20)
	for guid in _graph_nodes.keys():
		var node = _project.find_node(guid) if _project != null else null
		var pos: Vector2 = (node.pos if node != null else Vector2.ZERO)
		var est := Vector2(340.0, 180.0)
		if node != null and node.node_type == node_choice:
			est = Vector2(360.0, 120.0 + 44.0 * maxi(node.connections.size(), 1))
		min_p = min_p.min(pos - Vector2(20, 20))
		max_p = max_p.max(pos + est)
	var bbox := Rect2(min_p, max_p - min_p)
	var view := size
	if view.x > 20.0 and view.y > 20.0:
		var zx: float = (view.x - margin * 2.0) / maxf(bbox.size.x, 1.0)
		var zy: float = (view.y - margin * 2.0) / maxf(bbox.size.y, 1.0)
		zoom = clampf(minf(minf(zx, zy), 1.0), zoom_min, 1.0)
		# Godot 4.7 的 GraphEdit 变换：child.position = position_offset * zoom - scroll_offset
		# （GraphEdit 会把每个 GraphNode 的 scale 设为 zoom）
		scroll_offset = bbox.get_center() * zoom - view * 0.5
	else:
		# 尚未布局（headless/刚创建）：至少把入口放到原点附近
		scroll_offset = Vector2(-200, -200)


## 让某节点出现在画布中央附近
func focus_guid(guid: String) -> void:
	if not _graph_nodes.has(guid):
		return
	var gn: GraphNode = _graph_nodes[guid]
	var est := Vector2(maxf(gn.size.x, 280.0), maxf(gn.size.y, 120.0))
	# 4.7 变换：view = position_offset * zoom - scroll_offset
	scroll_offset = (gn.position_offset + est * 0.5) * zoom - size * 0.5


func node_count() -> int:
	return _graph_nodes.size()


# ---------------------------------------------------------------------------
# GraphEdit 内建信号
# ---------------------------------------------------------------------------

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if _project == null:
		return
	var from_guid: String = _guids_by_name.get(from_node, "")
	var to_guid: String = _guids_by_name.get(to_node, "")
	if from_guid.is_empty() or to_guid.is_empty() or from_guid == to_guid:
		return
	var from_data = _project.find_node(from_guid)
	if from_data == null:
		return
	if from_data.node_type == node_choice:
		var count: int = from_data.connections.size()
		if from_port == count:
			# 从「＋ 新选项」端口拉出 = 新增一个选项
			connect_requested.emit(from_guid, to_guid, -1)
		elif from_port >= 0 and from_port < count:
			connect_requested.emit(from_guid, to_guid, from_port)
	else:
		connect_requested.emit(from_guid, to_guid, -1)
	# 模型是唯一真源：editor 改完模型后会调用 rebuild() 重新画边


func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	var from_guid: String = _guids_by_name.get(from_node, "")
	var to_guid: String = _guids_by_name.get(to_node, "")
	if from_guid.is_empty() or to_guid.is_empty():
		return
	disconnect_requested.emit(from_guid, to_guid, from_port)


func _on_node_selected(node: Node) -> void:
	var gn := node as GraphNode
	if gn == null:
		return
	var guid: String = _guids_by_name.get(gn.name, "")
	if guid.is_empty():
		return
	if _selected_guid != guid:
		_selected_guid = guid
		node_selection_changed.emit(guid)


func _on_node_deselected(_node: Node) -> void:
	# GraphEdit 的取消选择不可靠（点击空白也要保留检查器内容），这里忽略
	pass


func _on_end_node_move() -> void:
	refresh_positions_from_graph()
	nodes_moved.emit()


func _on_delete_nodes_request(nodes: Array) -> void:
	var guids := PackedStringArray()
	for n in nodes:
		var guid: String = _guids_by_name.get(n, _guids_by_name.get(StringName(str(n)), ""))
		if not guid.is_empty():
			guids.append(guid)
	if not guids.is_empty():
		delete_requested.emit(guids)


# ---------------------------------------------------------------------------
# 自绘遮罩 + 鼠标交互（右键连线/剪刀、左键平移、双击打开、Delete 删除）
# ---------------------------------------------------------------------------

func _deselect_all_nodes() -> void:
	for guid in _graph_nodes.keys():
		(_graph_nodes[guid] as GraphNode).selected = false
	_selected_guid = ""
	node_selection_changed.emit("")


func _node_at_global(gp: Vector2) -> GraphNode:
	for child in get_children():
		if child is GraphNode:
			var gn := child as GraphNode
			if gn.get_global_rect().has_point(gp):
				return gn
	return null


func _guid_at_global(gp: Vector2) -> String:
	var gn := _node_at_global(gp)
	if gn == null:
		return ""
	return str(_guids_by_name.get(gn.name, ""))


func _is_upper_half(gn: GraphNode, gp: Vector2) -> bool:
	var rect := gn.get_global_rect()
	return gp.y < rect.position.y + rect.size.y * 0.5


func _graph_pos_to_local(gp: Vector2) -> Vector2:
	return gp - global_position


func _start_right_drag(guid: String, gp: Vector2, from_empty: bool) -> void:
	_drag_mode = "cut" if from_empty else "connect"
	_drag_from_guid = guid
	_drag_start_local = _graph_pos_to_local(gp)
	_drag_current_local = _drag_start_local
	_drag_is_output = true
	_drag_option_index = -1
	if not from_empty:
		var gn := _node_at_global(gp)
		if gn != null:
			_drag_is_output = not _is_upper_half(gn, gp)
		var node = _project.find_node(guid) if _project != null else null
		if node != null and node.node_type == node_choice and _drag_is_output:
			# 选择节点：从最近的端口拉；从下半部分拖 = 用下一个新选项端口
			_drag_option_index = node.connections.size()
	queue_redraw()


func _update_right_drag(gp: Vector2) -> void:
	_drag_current_local = _graph_pos_to_local(gp)
	queue_redraw()


func _finish_right_drag(gp: Vector2) -> void:
	var mode := _drag_mode
	var from_guid := _drag_from_guid
	var is_output := _drag_is_output
	var start := _drag_start_local
	var end := _graph_pos_to_local(gp)
	_drag_mode = ""
	_drag_from_guid = ""
	queue_redraw()
	if _project == null:
		return
	var target_guid := _guid_at_global(gp)

	if mode == "connect":
		if target_guid.is_empty() or target_guid == from_guid:
			status_message.emit("连线取消：请拖到另一个节点上")
			return
		if is_output:
			connect_requested.emit(from_guid, target_guid, _drag_option_index)
		else:
			# 从入端反向拖：目标节点 -> 当前节点
			var target_node = _project.find_node(target_guid)
			if target_node != null and target_node.node_type == node_choice:
				connect_requested.emit(target_guid, from_guid, target_node.connections.size())
			else:
				connect_requested.emit(target_guid, from_guid, -1)
	elif mode == "cut":
		var cut := _connections_crossing_segment(start, end)
		if cut.is_empty():
			status_message.emit("没有剪断任何连线（红线未穿过连线）")
		else:
			for c in cut:
				disconnect_requested.emit(c[0], c[1], c[2])
			status_message.emit("已剪断 %d 条连线" % cut.size())


## 计算与本地坐标线段相交的连线：[from_guid, to_guid, option_index]
func _connections_crossing_segment(a: Vector2, b: Vector2) -> Array:
	var out: Array = []
	if _project == null:
		return out
	for guid in _graph_nodes.keys():
		var node = _project.find_node(guid)
		if node == null:
			continue
		for i in node.connections.size():
			var target_guid: String = node.connections[i]
			if not _graph_nodes.has(target_guid):
				continue
			var p1 := _edge_start_local(guid, i)
			var p2 := _edge_end_local(target_guid)
			if _segments_intersect(a, b, p1, p2):
				out.append([guid, target_guid, i])
	return out


func _edge_start_local(guid: String, option_index: int) -> Vector2:
	var gn: GraphNode = _graph_nodes[guid]
	var node = _project.find_node(guid)
	var rect := Rect2(gn.position, gn.size)
	var y := rect.position.y + rect.size.y * 0.5
	if node != null and node.node_type == node_choice:
		var count: int = maxi(node.connections.size(), 1)
		var frac := float(option_index + 1) / float(count + 1)
		y = rect.position.y + rect.size.y * frac
	return Vector2(rect.end.x, y)


func _edge_end_local(guid: String) -> Vector2:
	var gn: GraphNode = _graph_nodes[guid]
	var rect := Rect2(gn.position, gn.size)
	return Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5)


static func _segments_intersect(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> bool:
	var d1 := p2 - p1
	var d2 := p4 - p3
	var den := d1.x * d2.y - d1.y * d2.x
	if absf(den) < 0.0001:
		return false
	var t := ((p3.x - p1.x) * d2.y - (p3.y - p1.y) * d2.x) / den
	var u := ((p3.x - p1.x) * d1.y - (p3.y - p1.y) * d1.x) / den
	return t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0


func _draw() -> void:
	if _drag_mode == "cut":
		draw_line(_drag_start_local, _drag_current_local, COLOR_CUT, 3.0)
		draw_circle(_drag_current_local, 6.0, COLOR_CUT)
	elif _drag_mode == "connect":
		draw_line(_drag_start_local, _drag_current_local, COLOR_CONNECT, 3.0)
		draw_circle(_drag_current_local, 6.0, COLOR_CONNECT)


func _gui_input(event: InputEvent) -> void:
	# 右键：空白处 = 划红线剪断；节点上由 GraphNode 的 gui_input 处理
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if _drag_mode != "" and mb.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_LEFT]:
			if not mb.pressed:
				# 拖拽过程中松手走这里（节点上松手则走 GraphNode 处理）
				_finish_right_drag(get_global_mouse_position())
				accept_event()
				return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var gp := get_global_mouse_position()
			var guid := _guid_at_global(gp)
			if guid.is_empty():
				_start_right_drag("", gp, true)
				accept_event()
				return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_panning = false
			var gp := get_global_mouse_position()
			if _guid_at_global(gp).is_empty():
				# 左键拖空白 = 平移视角
				_panning = true
				_pan_last = mb.position
				accept_event()
				return
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and _panning:
			_panning = false
			accept_event()
			return
	if event is InputEventMouseMotion and _panning:
		var mm := event as InputEventMouseMotion
		var delta := mm.position - _pan_last
		_pan_last = mm.position
		scroll_offset = scroll_offset - delta / zoom
		accept_event()
		return
	if event is InputEventMouseMotion and _drag_mode != "":
		_update_right_drag(get_global_mouse_position())
		accept_event()
		return
	# 双击空白 = 打开创建菜单（由 editor 弹出节点工厂提示）
	if event is InputEventMouseButton:
		var mb2 := event as InputEventMouseButton
		if mb2.button_index == MOUSE_BUTTON_LEFT and mb2.pressed and mb2.double_click:
			var gp2 := get_global_mouse_position()
			if _guid_at_global(gp2).is_empty():
				status_message.emit("双击空白：请从左侧节点工厂拖出节点创建")
			accept_event()
			return
	# Delete 删除
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_DELETE:
			if not _selected_guid.is_empty():
				delete_requested.emit(PackedStringArray([_selected_guid]))
			accept_event()
			return


func _on_graph_node_gui_input(event: InputEvent, guid: String) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var gn: GraphNode = _graph_nodes.get(guid, null)
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_start_right_drag(guid, get_global_mouse_position(), false)
				if gn != null:
					gn.accept_event()
			else:
				if _drag_mode == "connect":
					_finish_right_drag(get_global_mouse_position())
					if gn != null:
						gn.accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.double_click and mb.pressed:
				node_activated.emit(guid)
				if gn != null:
					gn.accept_event()
				return
			if mb.pressed:
				select_guid(guid)
	if _drag_mode != "" and event is InputEventMouseMotion:
		_update_right_drag(get_global_mouse_position())
		if _graph_nodes.has(guid):
			(_graph_nodes[guid] as GraphNode).accept_event()
