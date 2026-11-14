class_name PlayNode
extends RefCounted
## 编译后的可执行节点（`AapProject.compile()` 的产物，Player 直接消费）。
##
## 与 `.aap` 节点的对应关系：
## - EntryNodeData  -> KIND_ENTRY：直接跳到 next_guid；
## - ScriptNodeData -> KIND_SCRIPT：顺序播放 lines，播完跳 next_guid；
## - SelectionNodeData -> KIND_CHOICE：展示 options，按选择跳 target_guid；
## - ExitNodeData   -> KIND_EXIT：按 exit_type 显示 Ending / To be continued / 下一话衔接。
##
## 这是**只读**数据（lines 直接引用 AapProject 里的 AaScriptLine 对象），
## 不要在 Player 里修改。

# 节点种类
const KIND_ENTRY := 0
const KIND_SCRIPT := 1
const KIND_CHOICE := 2
const KIND_EXIT := 3

# 出口类型
const EXIT_ENDING := 0             ## Ending（IsEnding=true）
const EXIT_TO_BE_CONTINUED := 1    ## To be continued（无下一话信息）
const EXIT_NEXT_EPISODE := 2       ## #nextepisode;Header;Title 场景衔接

## 选项（SelectionNodeData 的一条出边）
class Choice extends RefCounted:
	var index: int = 0
	var text: String = ""
	var target_guid: String = ""
	## 目标节点是否存在（坏连线时为 false，Player 应跳过/提示）
	var valid: bool = true

	func to_dict() -> Dictionary:
		return {"index": index, "text": text, "target_guid": target_guid, "valid": valid}

	static func from_dict(d: Dictionary) -> Choice:
		var c := Choice.new()
		c.index = AaJson.get_int(d, "index", 0)
		c.text = AaJson.get_str(d, "text", "")
		c.target_guid = AaJson.get_str(d, "target_guid", "")
		c.valid = AaJson.get_bool(d, "valid", true)
		return c


var guid: String = ""
var kind: int = KIND_SCRIPT
## 编辑器画布坐标（调试/位置显示用）
var pos: Vector2 = Vector2.ZERO

## KIND_SCRIPT：本节点要顺序播放的行（AaScriptLine）
var lines: Array = []
## KIND_ENTRY / KIND_SCRIPT：播完后的下一个节点 guid（"" = 流程结束）
var next_guid: String = ""

## KIND_CHOICE：选项列表（Array[PlayNode.Choice]）
var options: Array = []

## KIND_EXIT：
var exit_type: int = EXIT_TO_BE_CONTINUED
## Ending 的文本 / To be continued 的文本（AA 的 EndText）
var end_text: String = ""
## 下一话衔接（#nextepisode 覆盖后的结果）
var ne_header: String = ""
var ne_title: String = ""
## 出口节点自带的 ScriptData（背景/BGM/演出，给结尾卡用）
var ne_line: AaScriptLine = null
## 结局画面文字 = NeScriptDirty.text。
## `[实]` 它有三种内容：""/"<Header>;<Title>"/"<工程名>;<标题>"，是 AA 结局画面要显示的文字，
## 不是普通台词；背景/BGM 也取自 `ne_line`。
var ne_text: String = ""

## ---- 兼容字段：供 Player 侧 duck-type 适配层（如 aap_mock.gd）直接读取 ----
## 由 sync_compat() 在编译/反序列化后自动同步，正常请用上面的正式字段。
var connections: PackedStringArray = PackedStringArray()
var selection_texts: PackedStringArray = PackedStringArray()
var is_ending: bool = false
var ne_script: AaScriptLine = null
## "entry" / "script" / "choice" / "exit"（字符串判别，避免不同模块的 kind 常量错位）
var kind_name: String = ""


static func make(p_kind: int, p_guid: String) -> PlayNode:
	var node := PlayNode.new()
	node.kind = p_kind
	node.guid = p_guid
	node.sync_compat()
	return node


## 把正式字段同步到兼容字段（编译后 / from_dict 后调用）。
func sync_compat() -> void:
	var conns := PackedStringArray()
	var texts := PackedStringArray()
	match kind:
		KIND_ENTRY, KIND_SCRIPT:
			kind_name = "entry" if kind == KIND_ENTRY else "script"
			if not next_guid.is_empty():
				conns.append(next_guid)
		KIND_CHOICE:
			kind_name = "choice"
			for option in options:
				if option is Choice:
					conns.append(option.target_guid)
					texts.append(option.text)
		KIND_EXIT:
			kind_name = "exit"
			is_ending = exit_type == EXIT_ENDING
			ne_script = ne_line
	connections = conns
	selection_texts = texts


# ---------------------------------------------------------------------------
# 查询
# ---------------------------------------------------------------------------

func is_entry() -> bool:
	return kind == KIND_ENTRY


func is_script() -> bool:
	return kind == KIND_SCRIPT


func is_choice() -> bool:
	return kind == KIND_CHOICE


func is_exit() -> bool:
	return kind == KIND_EXIT


## 是否终端节点（没有后续可走）。
## 出口要显示的文字（优先 EndText / NeTitle，退回 NeScriptDirty.text）。
func display_text() -> String:
	match exit_type:
		EXIT_ENDING:
			return end_text if not end_text.is_empty() else ne_text
		EXIT_TO_BE_CONTINUED:
			# NeScriptDirty.text 是结局画面要显示的文字，没有才用固定文案
			return ne_text if not ne_text.is_empty() else "To be continued"
		_:
			if not ne_title.is_empty():
				return ne_title
			return ne_text


func is_terminal() -> bool:
	if is_exit():
		return true
	if is_entry() or is_script():
		return next_guid.is_empty()
	return false


func line_count() -> int:
	return lines.size()


func get_line(index: int) -> AaScriptLine:
	if index >= 0 and index < lines.size() and lines[index] is AaScriptLine:
		return lines[index]
	return null


## 选择节点的有效选项（目标存在的）。
func valid_options() -> Array:
	var out: Array = []
	for option in options:
		if option is Choice and option.valid:
			out.append(option)
	return out


## 用 guid 取选项。
func find_option_by_target(target_guid: String) -> Choice:
	for option in options:
		if option is Choice and option.target_guid == target_guid:
			return option
	return null


# ---------------------------------------------------------------------------
# .aac 缓存序列化（PlayScript 用）
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var d := {}
	d["guid"] = guid
	d["kind"] = kind
	d["pos"] = [pos.x, pos.y]
	d["next_guid"] = next_guid
	match kind:
		KIND_SCRIPT:
			var line_dicts: Array = []
			for line in lines:
				if line is AaScriptLine:
					line_dicts.append(line.to_dict())
			d["lines"] = line_dicts
		KIND_CHOICE:
			var option_dicts: Array = []
			for option in options:
				if option is Choice:
					option_dicts.append(option.to_dict())
			d["options"] = option_dicts
			d["lines"] = []
		KIND_EXIT:
			d["exit_type"] = exit_type
			d["end_text"] = end_text
			d["ne_header"] = ne_header
			d["ne_title"] = ne_title
			d["ne_text"] = ne_text
			d["ne_line"] = ne_line.to_dict() if ne_line != null else null
		_:
			d["lines"] = []
	return d


static func from_dict(d: Dictionary) -> PlayNode:
	var node := PlayNode.new()
	node.guid = AaJson.get_str(d, "guid", "")
	node.kind = AaJson.get_int(d, "kind", KIND_SCRIPT)
	var p: Variant = d.get("pos")
	if p is Array and p.size() >= 2:
		node.pos = Vector2(float(p[0]), float(p[1]))
	node.next_guid = AaJson.get_str(d, "next_guid", "")
	if d.get("lines") is Array:
		for line_dict in d["lines"]:
			node.lines.append(AaScriptLine.from_dict(line_dict))
	if d.get("options") is Array:
		for option_dict in d["options"]:
			if option_dict is Dictionary:
				node.options.append(Choice.from_dict(option_dict))
	node.exit_type = AaJson.get_int(d, "exit_type", EXIT_TO_BE_CONTINUED)
	node.end_text = AaJson.get_str(d, "end_text", "")
	node.ne_header = AaJson.get_str(d, "ne_header", "")
	node.ne_title = AaJson.get_str(d, "ne_title", "")
	node.ne_text = AaJson.get_str(d, "ne_text", "")
	if d.get("ne_line") is Dictionary:
		node.ne_line = AaScriptLine.from_dict(d["ne_line"])
	node.sync_compat()
	return node
