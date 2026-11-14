extends RefCounted
## Fallback 版 NodeData（入口/脚本/选择/出口，字段顺序与 AA 一致）
## core-dev 的 AapNode 就绪后编辑器优先用 core。

const Uuid = preload("res://addons/aa_editor/model/fallback_uuid.gd")
const LineScript = preload("res://addons/aa_editor/model/fallback_script_line.gd")

const NODE_ENTRY := 0
const NODE_SCRIPT := 1
const NODE_CHOICE := 2
const NODE_EXIT := 3

const TYPE_ENTRY := "EntryNodeData, Assembly-CSharp"
const TYPE_SCRIPT := "ScriptNodeData, Assembly-CSharp"
const TYPE_CHOICE := "SelectionNodeData, Assembly-CSharp"
const TYPE_EXIT := "ExitNodeData, Assembly-CSharp"

var node_type := NODE_SCRIPT
var guid := ""
var connections: PackedStringArray = PackedStringArray()
var pos := Vector2.ZERO

# Script 节点
var node_name := ""
var scripts: Array = []
# Entry 节点
var title := ""
var header := ""
# Choice 节点（固定 16 槽，未用补空串）
var selection_texts: PackedStringArray = PackedStringArray()
# Exit 节点
var is_ending := false
var end_text := ""
var ne_header := ""
var ne_title := ""
var ne_script = null
var ne_script_dirty = null

var extra: Dictionary = {}
## 源 JSON 中为 null 的可选字符串字段（AA 会写 null，round-trip 必须保留）
var nulls: Dictionary = {}


func _init() -> void:
	for i in 16:
		selection_texts.append("")


static func make(p_node_type: int, p_pos := Vector2.ZERO):
	var n = load("res://addons/aa_editor/model/fallback_node.gd").new()
	n.node_type = p_node_type
	n.pos = p_pos
	if p_node_type == NODE_ENTRY:
		n.guid = "00000000-0000-0000-0000-000000000000"
		n.title = "序章"
		n.header = ""
	else:
		n.guid = Uuid.random_guid()
		if p_node_type == NODE_CHOICE:
			n.selection_texts = PackedStringArray()
			for i in 16:
				n.selection_texts.append("")
		elif p_node_type == NODE_EXIT:
			n.ne_script = LineScript.new()
			n.ne_script_dirty = LineScript.new()
	return n


static func _parse_nullable(n, d: Dictionary, key: String) -> void:
	if d.has(key) and d[key] == null:
		n.nulls[key] = true


static func type_json_name(p_type: int) -> String:
	match p_type:
		NODE_ENTRY:
			return TYPE_ENTRY
		NODE_CHOICE:
			return TYPE_CHOICE
		NODE_EXIT:
			return TYPE_EXIT
		_:
			return TYPE_SCRIPT


func type_str() -> String:
	return type_json_name(node_type)


func type_name_zh() -> String:
	match node_type:
		NODE_ENTRY:
			return "入口节点"
		NODE_CHOICE:
			return "选择节点"
		NODE_EXIT:
			return "出口节点"
		_:
			return "脚本节点"


func to_dict() -> Dictionary:
	var d := {"$type": type_str()}
	match node_type:
		NODE_ENTRY:
			d["Title"] = null if nulls.has("Title") else title
			d["Header"] = null if nulls.has("Header") else header
		NODE_SCRIPT:
			var arr := []
			for s in scripts:
				arr.append(s.to_dict())
			d["Scripts"] = {"$type": "System.Collections.Generic.List`1[[ScriptData, Assembly-CSharp]], mscorlib", "$values": arr}
			d["NodeName"] = null if nulls.has("NodeName") else node_name
		NODE_CHOICE:
			var arr: Array = []
			for t in selection_texts:
				arr.append(t)
			d["selectionTexts"] = {"$type": "System.Collections.Generic.List`1[[System.String, mscorlib]], mscorlib", "$values": arr}
		NODE_EXIT:
			d["IsEnding"] = is_ending
			d["EndText"] = null if nulls.has("EndText") else end_text
			d["NeHeader"] = null if nulls.has("NeHeader") else ne_header
			d["NeTitle"] = null if nulls.has("NeTitle") else ne_title
			d["NeScriptDirty"] = (ne_script_dirty.to_dict() if ne_script_dirty != null else LineScript.new().to_dict())
	d["Guid"] = guid
	var conn: Array = []
	for c in connections:
		conn.append(c)
	d["ConnectionsTo"] = {"$type": "System.Collections.Generic.List`1[[System.Guid, mscorlib]], mscorlib", "$values": conn}
	d["X"] = pos.x
	d["Y"] = pos.y
	for k in extra.keys():
		d[k] = extra[k]
	return d


static func from_dict(d: Dictionary):
	var n = load("res://addons/aa_editor/model/fallback_node.gd").new()
	var t := str(d.get("$type", ""))
	if t.begins_with("EntryNodeData"):
		n.node_type = NODE_ENTRY
	elif t.begins_with("SelectionNodeData"):
		n.node_type = NODE_CHOICE
	elif t.begins_with("ExitNodeData"):
		n.node_type = NODE_EXIT
	else:
		n.node_type = NODE_SCRIPT
	n.guid = str(d.get("Guid", ""))
	n.pos = Vector2(float(d.get("X", 0.0)), float(d.get("Y", 0.0)))
	n.connections = PackedStringArray()
	var conn = d.get("ConnectionsTo", {})
	var conn_vals = []
	if conn is Dictionary:
		conn_vals = conn.get("$values", [])
	for c in conn_vals:
		n.connections.append(str(c))

	match n.node_type:
		NODE_ENTRY:
			_parse_nullable(n, d, "Title")
			_parse_nullable(n, d, "Header")
			n.title = str(d.get("Title", ""))
			n.header = str(d.get("Header", ""))
			n.guid = "00000000-0000-0000-0000-000000000000"
		NODE_SCRIPT:
			_parse_nullable(n, d, "NodeName")
			n.node_name = str(d.get("NodeName", ""))
			var s = d.get("Scripts", {})
			var vals = []
			if s is Dictionary:
				vals = s.get("$values", [])
			n.scripts.clear()
			for sv in vals:
				if sv is Dictionary:
					n.scripts.append(LineScript.from_dict(sv))
		NODE_CHOICE:
			var st = d.get("selectionTexts", {})
			var texts = []
			if st is Dictionary:
				texts = st.get("$values", [])
			n.selection_texts = PackedStringArray()
			for i in 16:
				if i < texts.size() and texts[i] != null:
					n.selection_texts.append(str(texts[i]))
				else:
					n.selection_texts.append("")
		NODE_EXIT:
			n.is_ending = bool(d.get("IsEnding", false))
			for k in ["EndText", "NeHeader", "NeTitle"]:
				_parse_nullable(n, d, k)
			n.end_text = str(d.get("EndText", ""))
			n.ne_header = str(d.get("NeHeader", ""))
			n.ne_title = str(d.get("NeTitle", ""))
			var ns = d.get("NeScriptDirty", {})
			n.ne_script = (LineScript.from_dict(ns) if ns is Dictionary else LineScript.new())
			n.ne_script_dirty = (LineScript.from_dict(ns) if ns is Dictionary else LineScript.new())
	var known := ["$type", "Guid", "ConnectionsTo", "X", "Y"]
	if n.node_type == NODE_ENTRY:
		known.append_array(["Title", "Header"])
	elif n.node_type == NODE_SCRIPT:
		known.append_array(["Scripts", "NodeName"])
	elif n.node_type == NODE_CHOICE:
		known.append_array(["selectionTexts"])
	elif n.node_type == NODE_EXIT:
		known.append_array(["IsEnding", "EndText", "NeHeader", "NeTitle", "NeScriptDirty"])
	for k in d.keys():
		if not known.has(k):
			n.extra[k] = d[k]
	return n
