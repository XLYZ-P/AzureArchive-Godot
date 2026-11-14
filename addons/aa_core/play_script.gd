class_name PlayScript
extends RefCounted
## `AapProject.compile()` 的产物：把节点图“编译”成 Player 可直接执行的数据。
##
## - 节点按 guid 铺平（Script 节点的多行 `scripts` 已合并成一个 `PlayNode.lines` 序列）；
## - 选择节点的选项跳转表在 `PlayNode.options`（每项 = 选项文本 + 目标 guid）；
## - 出口节点标注类型：Ending / To be continued / `#nextepisode` 下一话衔接。
##
## Player 的推进规则：
## [codeblock]
## var node := script.get_start_node()
## while node != null:
##     match node.kind:
##         PlayNode.KIND_ENTRY:  node = script.get_node(node.next_guid)
##         PlayNode.KIND_SCRIPT: 逐行播 node.lines；播完 node = script.get_node(node.next_guid)
##         PlayNode.KIND_CHOICE: 展示 node.options；选择后 node = script.get_node(option.target_guid)
##         PlayNode.KIND_EXIT:   按 node.exit_type 收尾，结束
## [/codeblock]
##
## 另外提供 `to_dict()/from_dict()` + `save_to_file()/load_from_file()`，
## 用来写 DESIGN 里说的 `.aac`（JSON 编译缓存，不是 AA 的 .aas）。

const FORMAT_TYPE := "AaPlayScript, AaCore"
const FORMAT_VERSION := 1

## 起始节点 guid（入口节点；坏工程时退化为第一个节点）
var start_guid: String = ""
var project_name: String = ""
## 入口节点（EntryNodeData）的 Title / Header —— Player 用来显示标题卡。
var entry_title: String = ""
var entry_header: String = ""
## guid -> PlayNode
var nodes: Dictionary = {}
## 编译期问题（人类可读；Player/编辑器可展示，不影响播放）
var warnings: Array = []
## 源工程（不一定有；.aac 反序列化后为 null）
var project: AapProject = null


func get_node(guid: String) -> PlayNode:
	var node: Variant = nodes.get(guid)
	if node is PlayNode:
		return node
	return null


func get_start_node() -> PlayNode:
	return get_node(start_guid)


func get_node_count() -> int:
	return nodes.size()


func all_nodes() -> Array:
	return nodes.values()


func is_empty() -> bool:
	return nodes.is_empty()


func has_warnings() -> bool:
	return not warnings.is_empty()


## 第一个出口节点（编辑器“预览到结尾”用；没有返回 null）。
func first_exit_node() -> PlayNode:
	for node in nodes.values():
		if node is PlayNode and node.is_exit():
			return node
	return null


# ---------------------------------------------------------------------------
# .aac（JSON 编译缓存；不是 AA 的 .aas）
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var node_dicts := {}
	for guid in nodes.keys():
		var node: Variant = nodes[guid]
		if node is PlayNode:
			node_dicts[guid] = node.to_dict()
	return {
		"$type": FORMAT_TYPE,
		"version": FORMAT_VERSION,
		"project_name": project_name,
		"entry_title": entry_title,
		"entry_header": entry_header,
		"start_guid": start_guid,
		"warnings": warnings.duplicate(),
		"nodes": node_dicts,
	}


static func from_dict(d: Variant) -> PlayScript:
	var script := PlayScript.new()
	if not (d is Dictionary):
		return script
	var dd: Dictionary = d
	script.project_name = AaJson.get_str(dd, "project_name", "")
	script.entry_title = AaJson.get_str(dd, "entry_title", "")
	script.entry_header = AaJson.get_str(dd, "entry_header", "")
	script.start_guid = AaJson.get_str(dd, "start_guid", "")
	if dd.get("warnings") is Array:
		script.warnings = dd["warnings"].duplicate()
	var node_dicts: Variant = dd.get("nodes")
	if node_dicts is Dictionary:
		for guid in node_dicts.keys():
			var nd: Variant = node_dicts[guid]
			if nd is Dictionary:
				script.nodes[guid] = PlayNode.from_dict(nd)
	return script


func to_json_text(pretty := false) -> String:
	return AaJson.stringify(to_dict(), pretty)


func save_to_file(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		var base := path.get_base_dir()
		if not base.is_empty():
			DirAccess.make_dir_recursive_absolute(base)
			f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(to_json_text(false).to_utf8_buffer())
	f.close()
	return OK


static func load_from_file(path: String) -> PlayScript:
	if not FileAccess.file_exists(path):
		return null
	var value: Variant = AaJson.parse_file(path)
	if not (value is Dictionary):
		return null
	return from_dict(value)
