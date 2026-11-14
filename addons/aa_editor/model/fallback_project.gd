extends RefCounted
## Fallback 版 AapProject：核心 API 契约（docs/DESIGN.md §5.1）的最小可运行实现。
##
## 用途：aa_core 尚未就绪时驱动编辑器 UI / headless 自测；写法与 AA 的 .aap 完全兼容
## （Newtonsoft `$type`、字段顺序、UTF-8 无 BOM）。aa_core/aap_project.gd 出现后
## AaEditorBackend 会自动切换到 core 的实现，本文件仅作兜底。
##
## 注意：字段顺序与 docs/DESIGN.md §4 一致；Dictionary 在 Godot 中保持插入顺序，
## JSON.stringify(..., sort_keys=false) 因此能原样输出。

const Uuid = preload("res://addons/aa_editor/model/fallback_uuid.gd")
const NodeData = preload("res://addons/aa_editor/model/fallback_node.gd")
const LineScript = preload("res://addons/aa_editor/model/fallback_script_line.gd")

const NODE_ENTRY := 0
const NODE_SCRIPT := 1
const NODE_CHOICE := 2
const NODE_EXIT := 3

const TYPE_PROJECT := "ProjectData, Assembly-CSharp"
const TYPE_NODES := "System.Collections.Generic.List`1[[NodeData, Assembly-CSharp]], mscorlib"

var project_name := "新建工程"
var preview_bg_name := 0
var preview_header = null
var preview_title = null
var nodes: Array = []

var extra: Dictionary = {}


# ---------------------------------------------------------------- 构造/读取

func _init() -> void:
	project_name = "新建工程"
	preview_bg_name = 0
	preview_header = null
	preview_title = null
	nodes = []


static func new_project():
	return load("res://addons/aa_editor/model/fallback_project.gd").new()


static func load_from_file(path: String):
	if not FileAccess.file_exists(path):
		push_error("AapProject.load_from_file: 文件不存在 " + path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("AapProject.load_from_file: 打不开 " + path)
		return null
	var text := f.get_as_text()
	f.close()
	return load_from_string(text, path)


static func load_from_string(text: String, source_path := ""):
	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		push_error("AapProject.load_from_string: 不是合法 JSON " + source_path)
		return null
	var p = load("res://addons/aa_editor/model/fallback_project.gd").new()
	p.project_name = str(parsed.get("ProjectName", "未命名工程"))
	p.preview_bg_name = int(parsed.get("PreviewBgName", 0))
	p.preview_header = parsed.get("PreviewHeader", null)
	p.preview_title = parsed.get("PreviewTitle", null)
	var nd = parsed.get("nodes", {})
	var vals = []
	if nd is Dictionary:
		vals = nd.get("$values", [])
	elif nd is Array:
		vals = nd
	p.nodes.clear()
	for nv in vals:
		if nv is Dictionary:
			p.nodes.append(NodeData.from_dict(nv))
	var known := ["$type", "ProjectName", "PreviewBgName", "PreviewHeader", "PreviewTitle", "nodes"]
	for k in parsed.keys():
		if not known.has(k):
			p.extra[k] = parsed[k]
	return p


# ---------------------------------------------------------------- 序列化

func to_dict() -> Dictionary:
	var arr := []
	for n in nodes:
		arr.append(n.to_dict())
	var d := {
		"$type": TYPE_PROJECT,
		"ProjectName": project_name,
		"PreviewBgName": preview_bg_name,
		"PreviewHeader": preview_header,
		"PreviewTitle": preview_title,
		"nodes": {"$type": TYPE_NODES, "$values": arr},
	}
	for k in extra.keys():
		d[k] = extra[k]
	return d


func to_json_text(pretty := true) -> String:
	var out := PackedStringArray()
	_json_write(to_dict(), out, pretty, 0)
	return "".join(out)


## 手写 JSON 序列化：保证字段顺序 + null 保留 + 最短浮点表示（AA 的 X/Y 是 double 字段）
static func _json_write(value: Variant, out: PackedStringArray, pretty: bool, level: int) -> void:
	match typeof(value):
		TYPE_NIL:
			out.append("null")
		TYPE_BOOL:
			out.append("true" if value else "false")
		TYPE_INT:
			out.append(str(value))
		TYPE_FLOAT:
			out.append(_json_float(value))
		TYPE_STRING, TYPE_STRING_NAME:
			out.append(JSON.stringify(str(value), "", false, true))
		TYPE_DICTIONARY:
			_json_object(value, out, pretty, level)
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY:
			_json_array(value, out, pretty, level)
		_:
			out.append(JSON.stringify(str(value), "", false, true))


static func _json_object(value: Dictionary, out: PackedStringArray, pretty: bool, level: int) -> void:
	var keys := value.keys()
	if keys.is_empty():
		out.append("{}")
		return
	out.append("{")
	for i in keys.size():
		if i > 0:
			out.append(",")
		if pretty:
			out.append("\n")
			out.append("  ".repeat(level + 1))
		out.append(JSON.stringify(str(keys[i]), "", false, true))
		out.append(": " if pretty else ":")
		_json_write(value[keys[i]], out, pretty, level + 1)
	if pretty:
		out.append("\n")
		out.append("  ".repeat(level))
	out.append("}")


static func _json_array(value, out: PackedStringArray, pretty: bool, level: int) -> void:
	var n: int = value.size()
	if n == 0:
		out.append("[]")
		return
	out.append("[")
	for i in n:
		if i > 0:
			out.append(",")
		if pretty:
			out.append("\n")
			out.append("  ".repeat(level + 1))
		_json_write(value[i], out, pretty, level + 1)
	if pretty:
		out.append("\n")
		out.append("  ".repeat(level))
	out.append("]")


## 最短浮点字符串：整数值写 x.0，其余写能精确回读的最短小数（对齐 AA/Newtonsoft 风格）
static func _json_float(f: float) -> String:
	if is_nan(f) or is_inf(f):
		return "0.0"
	if f == 0.0:
		return "-0.0" if str(f).begins_with("-") else "0.0"
	var as_int := int(f)
	if float(as_int) == f and absf(f) < 9007199254740992.0:
		return str(as_int) + ".0"
	for decimals in range(1, 18):
		var s := String.num(f, decimals)
		if s.to_float() == f:
			if not s.contains(".") and not s.contains("e") and not s.contains("E"):
				s += ".0"
			return s
	return str(f)


func save_to_file(path: String) -> Error:
	var dir := path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(to_json_text(true))
	f.close()
	return OK


# ---------------------------------------------------------------- 查询

func get_entry():
	for n in nodes:
		if n.node_type == NODE_ENTRY:
			return n
	return null


func find_node(guid: String):
	for n in nodes:
		if n.guid == guid:
			return n
	return null


func node_index(node) -> int:
	for i in nodes.size():
		if nodes[i] == node:
			return i
	return -1


# ---------------------------------------------------------------- 编辑

func add_node(node_type: int, pos := Vector2.ZERO):
	if node_type == NODE_ENTRY and get_entry() != null:
		return null
	if node_type == NODE_CHOICE:
		var n_node = NodeData.make(node_type, pos)
		nodes.append(n_node)
		return n_node
	var n_node = NodeData.make(node_type, pos)
	nodes.append(n_node)
	return n_node


func remove_node(node) -> bool:
	if node == null:
		return false
	if node.node_type == NODE_ENTRY:
		return false
	if not node.connections.is_empty():
		return false
	# 仍有入边时不允许删除
	for n in nodes:
		if n == node:
			continue
		if node.guid in n.connections:
			return false
	nodes.erase(node)
	return true


func connect_nodes(from, to) -> bool:
	if from == null or to == null or from == to:
		return false
	if to.node_type == NODE_ENTRY:
		return false       # 入口没有入端
	if from.node_type == NODE_EXIT:
		return false       # 出口没有出端
	if from.node_type == NODE_SCRIPT or from.node_type == NODE_ENTRY:
		from.connections = PackedStringArray([to.guid])
		return true
	if from.node_type == NODE_CHOICE:
		if from.connections.size() >= 16:
			return false
		from.connections.append(to.guid)
		return true
	return false


func disconnect_nodes(from, to, option_index := -1) -> bool:
	if from == null or to == null:
		return false
	if from.node_type == NODE_CHOICE:
		var idx := option_index
		if idx < 0:
			idx = from.connections.find(to.guid)
		if idx < 0 or idx >= from.connections.size():
			return false
		from.connections.remove_at(idx)
		if idx < from.selection_texts.size():
			from.selection_texts.remove_at(idx)
			from.selection_texts.append("")
			# 把后续选项左移一位
			for i in range(idx, 15):
				from.selection_texts[i] = from.selection_texts[i + 1]
			from.selection_texts[15] = ""
		return true
	var found := false
	var kept := PackedStringArray()
	for c in from.connections:
		if c == to.guid and not found:
			found = true
			continue
		kept.append(c)
	from.connections = kept
	return found


func get_outgoing(node) -> Array:
	var out: Array = []
	if node == null:
		return out
	for g in node.connections:
		var t = find_node(g)
		if t != null:
			out.append(t)
	return out


func get_incoming(node) -> Array:
	var out: Array = []
	for n in nodes:
		if node != null and node.guid in n.connections:
			out.append(n)
	return out


func is_connected_between(from, to) -> bool:
	if from == null or to == null:
		return false
	return to.guid in from.connections


# ---------------------------------------------------------------- 编译（fallback 简化版）

func compile():
	## 返回与 PlayScript 结构接近的对象（core 就绪后由 core 实现返回 PlayScript）。
	## fallback 只做最基本的线性展开，供编辑器“编译”按钮显示统计信息。
	var entry = get_entry()
	var script = load("res://addons/aa_editor/model/fallback_play_script.gd").new()
	script.start_guid = entry.guid if entry != null else ""
	var visited: Dictionary = {}
	var queue: Array = []
	if entry != null:
		queue = entry.connections.duplicate()
	var order := 0
	while not queue.is_empty() and order < 10000:
		var g: String = queue.pop_front()
		if visited.has(g):
			continue
		var n = find_node(g)
		if n == null:
			continue
		visited[g] = true
		var pn = {"guid": n.guid, "type": n.node_type, "lines": [], "choices": []}
		match n.node_type:
			NODE_SCRIPT:
				for line in n.scripts:
					pn["lines"].append(line)
			NODE_CHOICE:
				var texts: Array = []
				for i in n.connections.size():
					texts.append(n.selection_texts[i] if i < n.selection_texts.size() else "")
				pn["choices"] = n.connections.duplicate()
				pn["choice_texts"] = texts
			NODE_EXIT:
				pn["is_ending"] = n.is_ending
				pn["end_text"] = n.end_text
				pn["ne_header"] = n.ne_header
				pn["ne_title"] = n.ne_title
		script.nodes[n.guid] = pn
		for c in n.connections:
			if not visited.has(c):
				queue.append(c)
		order += 1
	script.node_count = script.nodes.size()
	return script
