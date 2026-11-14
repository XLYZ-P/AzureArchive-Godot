class_name AapProject
extends RefCounted
## AzureArchive `.aap` 工程（Newtonsoft JSON 文档模型）。
##
## 顶层字段顺序：`$type, ProjectName, PreviewBgName, PreviewHeader, PreviewTitle, nodes`
## （nodes 是 `List`1[[NodeData]]` 包装，`$values` 顺序 = 编辑器里的节点顺序）。
##
## 用法：
## [codeblock]
## var project := AapProject.load_from_file("res://fixtures/aap/sample_kei_01.aap")
## print(project.project_name, " 节点数 ", project.nodes.size())
## var entry := project.get_entry()
## project.save_to_file("user://copy.aap")
## var script := project.compile()   # PlayScript，给 Player 用
## [/codeblock]
##
## 读写保证：
## - 读：未知字段、未知 `$type` 节点、JSON null、X/Y 的 double 精度都原样保留；
## - 写：`$type` 字符串与字段顺序逐字节与 AA 一致；`save_to_file` 写紧凑 JSON（AA 实际风格），
##   `to_json_text(true)` 输出 2 空格缩进便于调试。

const NODE_ENTRY := 0
const NODE_SCRIPT := 1
const NODE_CHOICE := 2
const NODE_EXIT := 3
## 未知 `$type` 的节点（原样保留，不能编辑）
const NODE_UNKNOWN := -1

const ENTRY_GUID := AapNode.ENTRY_GUID
## AA 默认的“无背景”ID
const EMPTY_BG_ID := AaHash.EMPTY_BG_ID
## BGM 静音 ID
const BGM_MUTE := 999

var project_name: String = ""
var preview_bg_name: int = 0
## String 或 null（AA 未设置时写 null）
var preview_header: Variant = null
var preview_title: Variant = null
var nodes: Array = []

## 未知顶层字段（向前兼容保留）
var extra: Dictionary = {}
## 最近一次 load/save 的路径（编辑器“保存”用）
var source_path: String = ""
## 最近一次静态 load 失败原因（成功为空）——静态方法返回 null 时用它取详情
static var last_error: String = ""


# ---------------------------------------------------------------------------
# 构造 / 加载
# ---------------------------------------------------------------------------

## 新建工程。默认带「全 0 Guid 的入口节点 + 一个空脚本节点（含 1 条空行）」
## 并已连好线，保存后即可被 AA 打开；编辑器/目录界面的「新建工程」直接用这个。
## with_starter_script = false 时只创建入口节点。
static func create(p_name := "新工程", with_starter_script := true) -> AapProject:
	var project := AapProject.new()
	project.project_name = p_name
	project.preview_bg_name = 0
	project.preview_header = null
	project.preview_title = null
	var entry := AapNode.make(NODE_ENTRY)
	project.nodes = [entry]
	if with_starter_script:
		var starter := AapNode.make(NODE_SCRIPT, Vector2(0, -200))
		starter.scripts.append(AaScriptLine.make_empty())
		project.nodes.append(starter)
		entry.connections = PackedStringArray([starter.guid])
	return project


## 只带入口节点的空工程（测试/特殊场景用）。
static func create_empty(p_name := "新工程") -> AapProject:
	return create(p_name, false)


static func load_from_file(path: String) -> AapProject:
	last_error = ""
	if not FileAccess.file_exists(path):
		last_error = "文件不存在：" + path
		push_error("AapProject: " + last_error)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		last_error = "无法打开：%s（错误码 %d）" % [path, FileAccess.get_open_error()]
		push_error("AapProject: " + last_error)
		return null
	var text := f.get_as_text()
	f.close()
	var project := load_from_string(text)
	if project != null:
		project.source_path = path
	return project


static func load_from_string(text: String) -> AapProject:
	last_error = ""
	var data: Variant = AaJson.parse(text)
	if data == null:
		last_error = "JSON 解析失败"
		push_error("AapProject: " + last_error)
		return null
	if not (data is Dictionary):
		last_error = "顶层不是 JSON 对象"
		push_error("AapProject: " + last_error)
		return null
	return from_dict(data)


static func from_dict(d: Variant) -> AapProject:
	var project := AapProject.new()
	if not (d is Dictionary):
		return project
	var dd: Dictionary = d
	var type_string := AaJson.type_of(dd)
	if not type_string.is_empty() and type_string != AaJson.T_PROJECT:
		push_warning("AapProject: 顶层 $type 不是 ProjectData：" + type_string)
	project.project_name = AaJson.get_str(dd, "ProjectName", "")
	project.preview_bg_name = AaJson.get_int(dd, "PreviewBgName", 0)
	if dd.has("PreviewHeader"):
		var ph: Variant = dd["PreviewHeader"]
		project.preview_header = null if ph == null else str(ph)
	if dd.has("PreviewTitle"):
		var pt: Variant = dd["PreviewTitle"]
		project.preview_title = null if pt == null else str(pt)
	var node_dicts: Array = AaJson.values_of(dd.get("nodes"))
	for nd in node_dicts:
		project.nodes.append(AapNode.from_dict(nd))
	# 未知顶层字段保留
	for key in dd.keys():
		if not _TOP_KNOWN.has(key):
			project.extra[key] = dd[key]
	return project


const _TOP_KNOWN := {
	"$type": true, "ProjectName": true, "PreviewBgName": true,
	"PreviewHeader": true, "PreviewTitle": true, "nodes": true,
}


# ---------------------------------------------------------------------------
# 序列化 / 保存
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var d := {}
	d["$type"] = AaJson.T_PROJECT
	d["ProjectName"] = project_name
	d["PreviewBgName"] = preview_bg_name
	d["PreviewHeader"] = preview_header
	d["PreviewTitle"] = preview_title
	var node_dicts: Array = []
	for node in nodes:
		if node is AapNode:
			node_dicts.append(node.to_dict())
		elif node is Dictionary:
			node_dicts.append(node)
	d["nodes"] = AaJson.wrap_list(AaJson.T_NODE_LIST, node_dicts)
	for key in extra.keys():
		d[key] = extra[key]
	return d


## 序列化成 JSON 文本。pretty = false 时与 AA 实际产物一致（紧凑、无换行）。
func to_json_text(pretty := true) -> String:
	return AaJson.stringify(to_dict(), pretty)


## 保存为 `.aap`（UTF-8 无 BOM，紧凑 JSON，与 AA 写出风格一致）。
func save_to_file(path: String) -> Error:
	if path.is_empty():
		return ERR_INVALID_PARAMETER
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		# 目录可能不存在：尝试创建后重试
		var base := path.get_base_dir()
		if not base.is_empty():
			DirAccess.make_dir_recursive_absolute(base)
			f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		var err := FileAccess.get_open_error()
		push_error("AapProject: 保存失败 " + path + "，错误码 " + str(err))
		return err
	f.store_buffer(to_json_text(false).to_utf8_buffer())
	f.close()
	source_path = path
	return OK


# ---------------------------------------------------------------------------
# 节点查询
# ---------------------------------------------------------------------------

## 入口节点（Guid 全 0 的第一个 EntryNodeData）；没有则返回 null。
func get_entry() -> AapNode:
	for node in nodes:
		if node is AapNode and node.is_entry():
			return node
	for node in nodes:
		if node is AapNode and node.guid == ENTRY_GUID:
			return node
	return null


## 按 Guid 找节点；找不到返回 null。
func find_node(guid: String) -> AapNode:
	for node in nodes:
		if node is AapNode and node.guid == guid:
			return node
	return null


func index_of_node(node: AapNode) -> int:
	if node == null:
		return -1
	for i in nodes.size():
		if nodes[i] == node:
			return i
	return -1


## 某类型的所有节点。
func get_nodes_of_type(p_node_type: int) -> Array:
	var out: Array = []
	for node in nodes:
		if node is AapNode and node.node_type == p_node_type:
			out.append(node)
	return out


## 所有剧本行（Script 节点的行 + 可选 Exit 的 NeScriptDirty），方便 QA/统计。
func iter_lines(include_exit_ne := true) -> Array:
	var out: Array = []
	for node in nodes:
		if not (node is AapNode):
			continue
		if node.is_script():
			out.append_array(node.scripts)
		elif node.is_exit() and include_exit_ne and node.ne_script != null:
			out.append(node.ne_script)
	return out


# ---------------------------------------------------------------------------
# 节点增删 / 连线
# ---------------------------------------------------------------------------

## 新增节点。Entry 只能有一个（已存在时返回 null）。
func add_node(p_node_type: int, p_pos := Vector2.ZERO) -> AapNode:
	if p_node_type == NODE_ENTRY and get_entry() != null:
		push_warning("AapProject: 工程已存在入口节点")
		return null
	var node := AapNode.make(p_node_type, p_pos)
	# 保证 Guid 唯一
	var tries := 0
	while find_node(node.guid) != null and tries < 100:
		node.guid = AapNode.new_guid()
		tries += 1
	nodes.append(node)
	return node


## 删除节点（Entry 不可删），同时清理其它节点指向它的连线（选项文本同步下移）。
func remove_node(node: AapNode) -> bool:
	if node == null or node.is_entry():
		return false
	var index := index_of_node(node)
	if index < 0:
		return false
	nodes.remove_at(index)
	for other in nodes:
		if not (other is AapNode):
			continue
		var i: int = other.connections.size() - 1
		while i >= 0:
			if other.connections[i] == node.guid:
				other.remove_connection_at(i)
			i -= 1
	return true


## 连线。Choice 节点：追加一个选项（选项文本补空槽）；其它节点：单出边，替换。
func connect_nodes(from: AapNode, to: AapNode) -> bool:
	if from == null or to == null or from == to:
		return false
	if index_of_node(from) < 0 or index_of_node(to) < 0:
		return false
	if from.is_entry() and from.connections.size() > 0:
		# 入口也只能有一条出边：连线相同返回 false，否则替换
		if from.connections.size() == 1 and from.connections[0] == to.guid:
			return false
		from.connections = PackedStringArray([to.guid])
		return true
	if from.is_choice():
		if from.connections.size() >= AapNode.SELECTION_SLOT_COUNT:
			push_warning("AapProject: 选择节点选项已达 %d 上限" % AapNode.SELECTION_SLOT_COUNT)
			return false
		return from.add_connection(to.guid)
	if from.is_exit():
		return false
	# Script 节点：单出边
	if from.connections.size() == 1 and from.connections[0] == to.guid:
		return false
	from.connections = PackedStringArray([to.guid])
	return true


## 断连线。option_index >= 0 时只断开该选项（并删掉对应选项文本）；
## -1 时断开 from 到 to 的所有连线。
func disconnect_nodes(from: AapNode, to: AapNode, option_index := -1) -> bool:
	if from == null or to == null:
		return false
	if option_index >= 0:
		if option_index >= from.connections.size() or from.connections[option_index] != to.guid:
			return false
		return from.remove_connection_at(option_index)
	var removed := false
	var i := from.connections.size() - 1
	while i >= 0:
		if from.connections[i] == to.guid:
			if from.remove_connection_at(i):
				removed = true
		i -= 1
	return removed


## 选择节点的选项列表（Player 编译 / 编辑器检查器用）：
## [{index, text, target_guid, target: AapNode}]
func get_choice_options(node: AapNode) -> Array:
	var out: Array = []
	if node == null or not node.is_choice():
		return out
	for i in node.connections.size():
		var target := node.connections[i]
		out.append({
			"index": i,
			"text": node.get_selection_text(i),
			"target_guid": target,
			"target": find_node(target),
		})
	return out


# ---------------------------------------------------------------------------
# 校验 / 修复
# ---------------------------------------------------------------------------

## 结构校验，返回人类可读的问题列表（空 = 没问题）。
func validate() -> Array:
	var problems: Array = []
	var entry := get_entry()
	if entry == null:
		problems.append("缺少入口节点（EntryNodeData，Guid 应为全 0）")
	else:
		if not AapNode.guid_is_zero(entry.guid):
			problems.append("入口节点 Guid 不是全 0：" + entry.guid)
		if entry.connections.is_empty():
			problems.append("入口节点没有出边")
	var entries := get_nodes_of_type(NODE_ENTRY)
	if entries.size() > 1:
		problems.append("入口节点数量为 %d（应为 1）" % entries.size())
	var seen := {}
	for node in nodes:
		if not (node is AapNode):
			problems.append("nodes 里有非 AapNode 元素")
			continue
		if seen.has(node.guid):
			problems.append("Guid 重复：" + node.guid)
		seen[node.guid] = true
	for node in nodes:
		if not (node is AapNode):
			continue
		for target in node.connections:
			if find_node(target) == null:
				problems.append("%s（%s）的出边指向不存在的节点 %s" % [
					_node_label(node), node.guid, target
				])
		if node.is_choice():
			var visible := 0
			for i in node.connections.size():
				if not node.get_selection_text(i).is_empty():
					visible += 1
			if visible < node.connections.size():
				problems.append("%s 有 %d 个选项文本为空但存在出边" % [
					_node_label(node), node.connections.size() - visible
				])
			if node.connections.size() > AapNode.SELECTION_SLOT_COUNT:
				problems.append("%s 选项数超过 16" % _node_label(node))
	if get_nodes_of_type(NODE_EXIT).is_empty():
		problems.append("没有出口节点（ExitNodeData）")
	# 可达性（从入口 BFS）
	if entry != null:
		var reachable := _collect_reachable(entry)
		for node in nodes:
			if node is AapNode and not reachable.has(node.guid) \
					and node.node_type != NODE_UNKNOWN:
				problems.append("%s 不可达（没有从入口连过来）" % _node_label(node))
	return problems


## 从入口 BFS 收集可达 guid。
func _collect_reachable(start: AapNode) -> Dictionary:
	var seen := {}
	if start == null:
		return seen
	var queue: Array = [start.guid]
	while not queue.is_empty():
		var guid: String = queue.pop_front()
		if seen.has(guid):
			continue
		seen[guid] = true
		var node := find_node(guid)
		if node == null:
			continue
		for target in node.connections:
			if not seen.has(target):
				queue.append(target)
	return seen


## 检查所有行的 bgName == xxh32(bgFriendlyName)。
## 返回 {total: int, matched: int, mismatched: Array[{node_guid, line_index, friendly, stored, computed}]}
func check_bg_ids() -> Dictionary:
	var total := 0
	var matched := 0
	var mismatched: Array = []
	for node in nodes:
		if not (node is AapNode):
			continue
		var lines: Array = []
		if node.is_script():
			lines = node.scripts
		elif node.is_exit() and node.ne_script != null:
			lines = [node.ne_script]
		for i in lines.size():
			var line = lines[i]
			if not (line is AaScriptLine):
				continue
			total += 1
			if line.bg_id_matches():
				matched += 1
			else:
				mismatched.append({
					"node_guid": node.guid,
					"line_index": i,
					"friendly": line.bg_friendly_name,
					"stored": line.bg_name,
					"computed": line.computed_bg_id(),
				})
	return {"total": total, "matched": matched, "mismatched": mismatched}


## 重新计算所有行的 bgName，返回修复的行数。
func repair_bg_ids() -> int:
	var fixed := 0
	for line in iter_lines(true):
		if line is AaScriptLine and line.repair_bg_id():
			fixed += 1
	return fixed


# ---------------------------------------------------------------------------
# 编译
# ---------------------------------------------------------------------------

## 编译成 PlayScript（给 Player 直接播放）。具体逻辑见 aap_compiler.gd。
func compile() -> PlayScript:
	return AapCompiler.new().compile(self)


func _node_label(node: AapNode) -> String:
	if node.is_script() and not node.node_name.is_empty():
		return "脚本节点「%s」" % node.node_name
	if node.is_entry():
		return "入口节点"
	if node.is_choice():
		return "选择节点"
	if node.is_exit():
		return "出口节点"
	return "节点"
