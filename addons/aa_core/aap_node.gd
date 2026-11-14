class_name AapNode
extends RefCounted
## `.aap` 节点图的节点（四种：Entry / Script / Selection / Exit）。
##
## 公共字段顺序：`Guid, ConnectionsTo, X, Y`
## 各类型特有字段（AA 写出顺序，不可改）：
## - Entry:     `Title, Header` + 公共；Guid 必须全 0
## - Script:    `Scripts, NodeName` + 公共
## - Selection: `selectionTexts`（固定 16 项）+ 公共；`ConnectionsTo[i]` = 第 i 个选项的跳转
## - Exit:      `IsEnding, EndText, NeHeader, NeTitle, NeScriptDirty` + 公共
##
## 读写约定：
## - 未知字段（以及整个未知 `$type` 节点）原样保留，round-trip 不丢数据；
## - `pos` 是 Vector2（Godot 标准构建里是 32 位 float），但 `.aap` 里 X/Y 是 double。
##   为让 round-trip 不丢精度，解析时额外记住原始 double（`_raw_x/_raw_y`），
##   `to_dict()` 在 pos 未被修改时输出原始 double，被修改后输出新值。

const TYPE_ENTRY := AaJson.T_ENTRY
const TYPE_SCRIPT := AaJson.T_SCRIPT_NODE
const TYPE_SELECTION := AaJson.T_SELECTION
const TYPE_EXIT := AaJson.T_EXIT

## 入口节点 Guid 必须全 0
const ENTRY_GUID := "00000000-0000-0000-0000-000000000000"
## 选项文本固定 16 槽
const SELECTION_SLOT_COUNT := 16

## AapProject.NODE_* 或 -1（未知类型，原样保留）
var node_type: int = -1
var guid: String = ""
var connections: PackedStringArray = PackedStringArray()
var pos: Vector2 = Vector2.ZERO

## ScriptNodeData
var node_name: String = ""
var scripts: Array = []

## EntryNodeData
var title: String = ""
var header: String = ""

## SelectionNodeData（固定 16 项，未用补 ""）
var selection_texts: PackedStringArray = PackedStringArray()

## ExitNodeData
var is_ending: bool = false
var end_text: String = ""
var ne_header: String = ""
var ne_title: String = ""
var ne_script: AaScriptLine = null

## 未知字段（向前兼容保留）
var extra: Dictionary = {}
## 源 JSON 中值为 null 的字符串字段
var _nulls: Dictionary = {}
## 未知 `$type` 时保留原始 dict
var _raw: Dictionary = {}
var _unknown_type: String = ""
## NeScriptDirty 在原文件里是否存在（缺字段时保持缺失）
var _ne_script_present := false
## 解析时 X/Y 的原始 double（保证 round-trip 精度）
var _raw_x: float = 0.0
var _raw_y: float = 0.0
var _has_raw_pos := false


const _COMMON_KEYS := {"$type": true, "Guid": true, "ConnectionsTo": true, "X": true, "Y": true}
const _KNOWN := {
	# common
	"$type": true, "Guid": true, "ConnectionsTo": true, "X": true, "Y": true,
	# entry
	"Title": true, "Header": true,
	# script
	"Scripts": true, "NodeName": true,
	# selection
	"selectionTexts": true,
	# exit
	"IsEnding": true, "EndText": true, "NeHeader": true, "NeTitle": true, "NeScriptDirty": true,
}


# ---------------------------------------------------------------------------
# 构造 / 解析 / 序列化
# ---------------------------------------------------------------------------

## 新建指定类型的节点（自动分配 Guid；Entry 用全 0 Guid）。
static func make(p_node_type: int, p_pos := Vector2.ZERO) -> AapNode:
	var node := AapNode.new()
	node.node_type = p_node_type
	node.pos = p_pos
	# 新建节点的坐标来自 Vector2（float32），写出时按 float32 最短表示格式化
	node._raw_x = p_pos.x
	node._raw_y = p_pos.y
	node._has_raw_pos = false
	match p_node_type:
		0:  # AapProject.NODE_ENTRY
			node.guid = ENTRY_GUID
		1:  # NODE_SCRIPT
			node.guid = new_guid()
		2:  # NODE_CHOICE
			node.guid = new_guid()
			node.selection_texts = _empty_selection_texts()
		3:  # NODE_EXIT
			node.guid = new_guid()
			node.ne_script = AaScriptLine.make_empty(false)
			node._ne_script_present = true
		_:
			node.guid = new_guid()
	return node


static func from_dict(d: Variant) -> AapNode:
	var node := AapNode.new()
	if not (d is Dictionary):
		return node
	var dd: Dictionary = d
	var type_string := AaJson.type_of(dd)
	node._unknown_type = type_string
	node.node_type = int(AaJson.NODE_TYPE_TABLE.get(type_string, -1))
	if node.node_type == -1:
		# 未知节点类型：整个 dict 原样保留，其余字段尽力解析供编辑器显示
		node._raw = dd.duplicate(true)
	# 公共字段
	node.guid = AaJson.get_str(dd, "Guid", "")
	var conns := PackedStringArray()
	for g in AaJson.values_of(dd.get("ConnectionsTo")):
		conns.append(str(g))
	node.connections = conns
	node._raw_x = AaJson.get_float(dd, "X", 0.0)
	node._raw_y = AaJson.get_float(dd, "Y", 0.0)
	node.pos = Vector2(node._raw_x, node._raw_y)
	node._has_raw_pos = dd.has("X") or dd.has("Y")
	# 各类型特有字段
	match node.node_type:
		0:
			node.title = AaJson.get_str(dd, "Title", "")
			node.header = AaJson.get_str(dd, "Header", "")
		1:
			node.node_name = AaJson.get_str(dd, "NodeName", "")
			for line in AaJson.values_of(dd.get("Scripts")):
				node.scripts.append(AaScriptLine.from_dict(line))
		2:
			var texts := PackedStringArray()
			for s in AaJson.values_of(dd.get("selectionTexts")):
				texts.append("" if s == null else str(s))
			texts.resize(SELECTION_SLOT_COUNT)
			node.selection_texts = texts
		3:
			node.is_ending = AaJson.get_bool(dd, "IsEnding", false)
			node.end_text = AaJson.get_str(dd, "EndText", "")
			node.ne_header = AaJson.get_str(dd, "NeHeader", "")
			node.ne_title = AaJson.get_str(dd, "NeTitle", "")
			node._ne_script_present = dd.has("NeScriptDirty")
			if dd.has("NeScriptDirty") and dd["NeScriptDirty"] is Dictionary:
				node.ne_script = AaScriptLine.from_dict(dd["NeScriptDirty"])
	# null 保留
	for key in ["NodeName", "Title", "Header", "EndText", "NeHeader", "NeTitle"]:
		if AaJson.is_null_field(dd, key):
			node._nulls[key] = true
	# 未知字段原样保留
	for key in dd.keys():
		if not _KNOWN.has(key):
			node.extra[key] = dd[key]
	return node


func to_dict() -> Dictionary:
	# 未知类型：原样写回（若编辑器改了公共字段，至少 Guid/X/Y 用新值）
	if node_type == -1 and not _raw.is_empty():
		var raw: Dictionary = _raw.duplicate(true)
		if raw.has("Guid"):
			raw["Guid"] = guid
		if raw.has("ConnectionsTo"):
			raw["ConnectionsTo"] = AaJson.wrap_guid_list(connections)
		if raw.has("X"):
			raw["X"] = _x_out()
		if raw.has("Y"):
			raw["Y"] = _y_out()
		return raw
	var d := {}
	match node_type:
		0:
			d["$type"] = TYPE_ENTRY
			d["Title"] = _out_str("Title", title)
			d["Header"] = _out_str("Header", header)
		1:
			d["$type"] = TYPE_SCRIPT
			var line_dicts: Array = []
			for line in scripts:
				if line is AaScriptLine:
					line_dicts.append(line.to_dict())
				elif line is Dictionary:
					line_dicts.append(line)
			d["Scripts"] = AaJson.wrap_list(AaJson.T_SCRIPT_LIST, line_dicts)
			d["NodeName"] = _out_str("NodeName", node_name)
		2:
			d["$type"] = TYPE_SELECTION
			var texts := selection_texts.duplicate()
			texts.resize(SELECTION_SLOT_COUNT)
			d["selectionTexts"] = AaJson.wrap_string_list(texts)
		3:
			d["$type"] = TYPE_EXIT
			d["IsEnding"] = is_ending
			d["EndText"] = _out_str("EndText", end_text)
			d["NeHeader"] = _out_str("NeHeader", ne_header)
			d["NeTitle"] = _out_str("NeTitle", ne_title)
			if ne_script != null:
				d["NeScriptDirty"] = ne_script.to_dict()
			elif _ne_script_present:
				d["NeScriptDirty"] = null
		_:
			d["$type"] = _unknown_type
	# 公共字段（顺序：Guid, ConnectionsTo, X, Y）
	d["Guid"] = guid
	d["ConnectionsTo"] = AaJson.wrap_guid_list(connections)
	d["X"] = _x_out()
	d["Y"] = _y_out()
	for key in extra.keys():
		d[key] = extra[key]
	return d


func _x_out() -> float:
	if _has_raw_pos and Vector2(_raw_x, _raw_y) == pos:
		return _raw_x
	return format_float32(pos.x)


func _y_out() -> float:
	if _has_raw_pos and Vector2(_raw_x, _raw_y) == pos:
		return _raw_y
	return format_float32(pos.y)


## 把 float32 坐标格式化成“能 round-trip 回同一个 float32 的最短十进制”。
## AA 的 X/Y 是 C# float（单精度），JSON 里写 `-200.7629` 而不是 `-200.7628936767578`。
static func format_float32(value: float) -> float:
	if value == 0.0 or is_nan(value) or is_inf(value):
		return value
	var ref := Vector2(value, 0.0).x
	for decimals in range(1, 10):
		var candidate := String.num(value, decimals)
		if Vector2(candidate.to_float(), 0.0).x == ref:
			return candidate.to_float()
	return value


func _out_str(key: String, value: String) -> Variant:
	if _nulls.has(key) and value.is_empty():
		return null
	return value


# ---------------------------------------------------------------------------
# 便利方法
# ---------------------------------------------------------------------------

## 节点类型中文名（编辑器 UI 用）。
func type_name_zh() -> String:
	match node_type:
		0:
			return "入口节点"
		1:
			return "脚本节点"
		2:
			return "选择节点"
		3:
			return "出口节点"
	return "未知节点"


## 是否是未知 `$type` 的节点（原样保留、不可编辑）。
func is_unknown() -> bool:
	return node_type == -1


func is_entry() -> bool:
	return node_type == 0


func is_script() -> bool:
	return node_type == 1


func is_choice() -> bool:
	return node_type == 2


func is_exit() -> bool:
	return node_type == 3


## 选项数量 = 出边数量（SelectionNodeData）。
func option_count() -> int:
	return connections.size()


## 取第 i 个选项文本（越界返回 ""）。
func get_selection_text(index: int) -> String:
	if index >= 0 and index < selection_texts.size():
		return selection_texts[index]
	return ""


## 写第 i 个选项文本（自动保证 16 槽）。
func set_selection_text(index: int, value: String) -> void:
	if index < 0 or index >= SELECTION_SLOT_COUNT:
		return
	var texts := selection_texts.duplicate()
	texts.resize(SELECTION_SLOT_COUNT)
	texts[index] = value
	selection_texts = texts


## 保证选项文本数组恰好 16 项（缺补空、多截断）。
func normalize_selection_texts() -> void:
	var texts := selection_texts.duplicate()
	texts.resize(SELECTION_SLOT_COUNT)
	selection_texts = texts


## 删除第 index 个出边，同时删掉对应选项文本（保持下标对应）。
func remove_connection_at(index: int) -> bool:
	if index < 0 or index >= connections.size():
		return false
	var conns := connections.duplicate()
	conns.remove_at(index)
	connections = conns
	if is_choice():
		var texts := selection_texts.duplicate()
		texts.resize(SELECTION_SLOT_COUNT)
		if index < texts.size():
			texts.remove_at(index)
		texts.resize(SELECTION_SLOT_COUNT)
		selection_texts = texts
	return true


## 追加一条出边。AA 允许选择节点连到同一目标两次（同一目标多个选项），
## 所以这里**允许重复**（读取器也不许去重）。
func add_connection(target_guid: String) -> bool:
	if target_guid.is_empty():
		return false
	var conns := connections.duplicate()
	conns.append(target_guid)
	connections = conns
	if is_choice():
		normalize_selection_texts()
	return true


## 深拷贝节点（编辑器复制 / 撤销用）。
func duplicate_node() -> AapNode:
	var node := AapNode.new()
	node.node_type = node_type
	node.guid = guid
	node.connections = connections.duplicate()
	node.pos = pos
	node.node_name = node_name
	node.scripts = []
	for line in scripts:
		if line is AaScriptLine:
			node.scripts.append(line.duplicate_line())
	node.title = title
	node.header = header
	node.selection_texts = selection_texts.duplicate()
	node.is_ending = is_ending
	node.end_text = end_text
	node.ne_header = ne_header
	node.ne_title = ne_title
	node.ne_script = ne_script.duplicate_line() if ne_script != null else null
	node.extra = extra.duplicate(true)
	node._nulls = _nulls.duplicate(true)
	node._raw = _raw.duplicate(true)
	node._unknown_type = _unknown_type
	node._ne_script_present = _ne_script_present
	node._raw_x = _raw_x
	node._raw_y = _raw_y
	node._has_raw_pos = _has_raw_pos
	return node


## 生成小写 UUID v4（AA 的 Guid 格式，如 b292a9b5-dd77-435e-b675-29b1b8ad0e92）。
## 生成小写 UUID v4（AA 的 Guid 格式）。
static func new_guid() -> String:
	return AaGuid.new_uuid()


## 判断 Guid 是否全 0（入口节点）。
static func guid_is_zero(value: String) -> bool:
	return AaGuid.is_zero(value)


static func _empty_selection_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	texts.resize(SELECTION_SLOT_COUNT)
	return texts
