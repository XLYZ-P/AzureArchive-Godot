extends RefCounted
## test_fixtures.gd —— 真实样本 `fixtures/aap/sample_kei_01.aap` 的静态结构契约校验。
##
## 本用例**不依赖任何其他模块**（不用 AapProject/AaRawLoader），只用
## FileAccess + JSON，因此从项目第一天起就应该 PASS；它守护的是：
##   1. 样本文件本身没被误改（17 节点 / 170 行 / 169+1）；
##   2. AA Newtonsoft.Json 的字段顺序契约（顶层/四类节点/ScriptData/CharacterRecordData）；
##   3. `$type` 字符串逐字正确（round-trip 会照抄，写错就丢数据）；
##   4. 选择节点固定 16 槽；characters 固定 6 项；
##   5. 节点图连通性（ConnectionsTo 都指向存在的节点）。
##
## 这些事实来自 docs/DESIGN.md §4 与 docs/spec/aap.md（format-researcher 实测）。

const Fw = preload("res://tests/framework.gd")

const SAMPLE_PATH := "res://fixtures/aap/sample_kei_01.aap"
const MANIFEST_PATH := "res://fixtures/aap/sample_kei_01.manifest.json"

const T_PROJECT := "ProjectData, Assembly-CSharp"
const T_NODES := "System.Collections.Generic.List`1[[NodeData, Assembly-CSharp]], mscorlib"
const T_ENTRY := "EntryNodeData, Assembly-CSharp"
const T_SCRIPT := "ScriptNodeData, Assembly-CSharp"
const T_CHOICE := "SelectionNodeData, Assembly-CSharp"
const T_EXIT := "ExitNodeData, Assembly-CSharp"
const T_SCRIPT_DATA := "ScriptData, Assembly-CSharp"
const T_CHARACTER := "ScriptData+CharacterRecordData, Assembly-CSharp"
const T_GUID_LIST := "System.Collections.Generic.List`1[[System.Guid, mscorlib]], mscorlib"
const T_SCRIPT_LIST := "System.Collections.Generic.List`1[[ScriptData, Assembly-CSharp]], mscorlib"
const T_CHARACTER_LIST := "System.Collections.Generic.List`1[[ScriptData+CharacterRecordData, Assembly-CSharp]], mscorlib"
const T_INT_LIST := "System.Collections.Generic.List`1[[System.Int32, mscorlib]], mscorlib"
const T_STRING_LIST := "System.Collections.Generic.List`1[[System.String, mscorlib]], mscorlib"

const TOP_KEYS := ["$type", "ProjectName", "PreviewBgName", "PreviewHeader", "PreviewTitle", "nodes"]
const ENTRY_KEYS := ["$type", "Title", "Header", "Guid", "ConnectionsTo", "X", "Y"]
const SCRIPT_NODE_KEYS := ["$type", "Scripts", "NodeName", "Guid", "ConnectionsTo", "X", "Y"]
const CHOICE_NODE_KEYS := ["$type", "selectionTexts", "Guid", "ConnectionsTo", "X", "Y"]
const EXIT_NODE_KEYS := ["$type", "IsEnding", "EndText", "NeHeader", "NeTitle", "NeScriptDirty", "Guid", "ConnectionsTo", "X", "Y"]
const SCRIPT_DATA_KEYS := [
	"$type", "text", "popup", "bgEffect", "bgName", "bgFriendlyName", "sound", "voice",
	"transition", "bgmId", "selectionGroup", "additionalPrompt", "characters",
	"speakerSlotNum", "highlightedSlotNums", "isDialogScript", "placeText",
]
const CHARACTER_KEYS := [
	"$type", "name", "faceId", "startingPos", "endingPos", "emoticon",
	"action", "effect", "appear", "shapeOverride",
]
const ZERO_GUID := "00000000-0000-0000-0000-000000000000"
const GUID_RE := "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"


func run(ctx: Fw.Ctx) -> void:
	# ---------------------------------------------------------------- 0. 文件
	ctx.is_true(FileAccess.file_exists(SAMPLE_PATH), "真实样本存在：%s" % SAMPLE_PATH)
	if not FileAccess.file_exists(SAMPLE_PATH):
		return
	var raw := FileAccess.get_file_as_bytes(SAMPLE_PATH)
	ctx.gt(raw.size(), 100_000, "样本大小合理（>100KB）")
	ctx.ne(raw.slice(0, 3).get_string_from_ascii(), "\u00ef\u00bb\u00bf", "UTF-8 无 BOM") # EF BB BF
	ctx.is_true(raw.size() > 3 and raw[0] == 0x7B, "文件以 '{' 开头（紧凑 JSON）")

	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	ctx.is_true(parsed is Dictionary, "顶层 JSON 可解析为 Dictionary")
	if not (parsed is Dictionary):
		return
	var d: Dictionary = parsed

	# ---------------------------------------------------------------- 1. 顶层
	ctx.eq_keys(d, TOP_KEYS, "顶层字段顺序")
	ctx.eq(String(d.get("$type", "")), T_PROJECT, "顶层 $type")
	ctx.eq(String(d.get("ProjectName", "")), "Kei-初遇", "ProjectName")
	ctx.eq(int(d.get("PreviewBgName", 0)), 3558049603, "PreviewBgName（= xxh32(BG_RuinUndergroundPassage)）")
	ctx.eq(d.get("PreviewHeader"), "Kei", "PreviewHeader")
	ctx.eq(d.get("PreviewTitle"), "初遇", "PreviewTitle")

	ctx.is_true(d.get("nodes") is Dictionary, "nodes 是 Dictionary")
	var nodes_list: Dictionary = d.get("nodes", {})
	ctx.eq_keys(nodes_list, ["$type", "$values"], "nodes 列表字段顺序")
	ctx.eq(String(nodes_list.get("$type", "")), T_NODES, "nodes 列表 $type")
	var nodes: Array = nodes_list.get("$values", [])
	ctx.eq(nodes.size(), 17, "节点数 = 17")

	# ---------------------------------------------------------------- 2. 节点类型分布
	var counts := {T_ENTRY: 0, T_SCRIPT: 0, T_CHOICE: 0, T_EXIT: 0}
	var guids: Array = []
	var entry_count := 0
	for i in range(nodes.size()):
		var node: Dictionary = nodes[i]
		var t := String(node.get("$type", ""))
		if counts.has(t):
			counts[t] = int(counts[t]) + 1
		else:
			ctx.fail("nodes[%d] 未知节点类型：%s" % [i, t])
		guids.append(String(node.get("Guid", "")))
		if t == T_ENTRY:
			entry_count += 1
			ctx.eq(String(node.get("Guid", "")), ZERO_GUID, "Entry 节点 Guid 必须全 0")
	ctx.eq(int(counts[T_ENTRY]), 1, "入口节点恰好 1 个")
	ctx.eq(int(counts[T_SCRIPT]), 10, "ScriptNodeData 数量 10")
	ctx.eq(int(counts[T_CHOICE]), 5, "SelectionNodeData 数量 5")
	ctx.eq(int(counts[T_EXIT]), 1, "ExitNodeData 数量 1")
	ctx.eq(entry_count, 1, "全工程恰好一个全 0 Guid 入口")
	ctx.eq(String(nodes[0].get("$type", "")), T_ENTRY, "nodes[0] 是入口（AA 写出顺序）")

	var guid_set := {}
	for g in guids:
		guid_set[g] = true
	ctx.eq(guid_set.size(), 17, "17 个 Guid 互不重复")

	# ---------------------------------------------------------------- 3. 每类节点字段顺序 + 连通性
	var total_lines := 0
	var script_nodes := 0
	var nonempty_script_nodes := 0
	var empty_script_nodes := 0
	var choice_slots_ok := true
	var all_connections_resolve := true
	var regex := RegEx.new()
	regex.compile(GUID_RE)
	var script_lines: Array = []
	for i in range(nodes.size()):
		var node: Dictionary = nodes[i]
		var t := String(node.get("$type", ""))
		match t:
			T_ENTRY:
				ctx.eq_keys(node, ENTRY_KEYS, "nodes[%d] Entry 字段顺序" % i)
				ctx.contains(node, "Title", "Entry 有 Title")
				ctx.contains(node, "Header", "Entry 有 Header")
			T_SCRIPT:
				ctx.eq_keys(node, SCRIPT_NODE_KEYS, "nodes[%d] Script 字段顺序" % i)
				ctx.is_true(node.get("Scripts") is Dictionary, "nodes[%d].Scripts 是 List 包装" % i)
				var scripts: Dictionary = node.get("Scripts", {})
				ctx.eq_keys(scripts, ["$type", "$values"], "nodes[%d].Scripts 字段顺序" % i)
				ctx.eq(String(scripts.get("$type", "")), T_SCRIPT_LIST, "nodes[%d].Scripts $type" % i)
				var vals: Array = scripts.get("$values", [])
				script_nodes += 1
				if vals.is_empty():
					empty_script_nodes += 1
				else:
					nonempty_script_nodes += 1
				total_lines += vals.size()
				script_lines.append_array(vals)
				# NodeName 可为 null（AA 对空脚本节点不写名字），类型只允许 String/null
				var nn: Variant = node.get("NodeName")
				ctx.is_true(nn == null or nn is String, "nodes[%d].NodeName 是 String 或 null" % i)
			T_CHOICE:
				ctx.eq_keys(node, CHOICE_NODE_KEYS, "nodes[%d] Selection 字段顺序" % i)
				var texts: Dictionary = node.get("selectionTexts", {})
				ctx.is_true(texts is Dictionary, "nodes[%d].selectionTexts 是 List 包装" % i)
				ctx.eq_keys(texts, ["$type", "$values"], "nodes[%d].selectionTexts 字段顺序" % i)
				ctx.eq(String(texts.get("$type", "")), T_STRING_LIST, "nodes[%d].selectionTexts $type" % i)
				var sel: Array = texts.get("$values", [])
				if sel.size() != 16:
					choice_slots_ok = false
					ctx.fail("nodes[%d] selectionTexts 应为固定 16 槽，实际 %d" % [i, sel.size()])
				var conns: Array = (node.get("ConnectionsTo", {}) as Dictionary).get("$values", [])
				# 有出边的槽必须有选项文本，未用槽补 ""
				for k in range(sel.size()):
					if k < conns.size():
						ctx.is_true(String(sel[k]).length() > 0, "nodes[%d] 选项 %d 文本非空" % [i, k])
					else:
						ctx.eq(String(sel[k]), "", "nodes[%d] 未用槽 %d 补空串" % [i, k])
			T_EXIT:
				ctx.eq_keys(node, EXIT_NODE_KEYS, "nodes[%d] Exit 字段顺序" % i)
				ctx.eq(typeof(node.get("IsEnding")), TYPE_BOOL, "Exit.IsEnding 是 bool")
				ctx.is_true(node.get("NeScriptDirty") is Dictionary, "Exit.NeScriptDirty 是 ScriptData")
				ctx.eq(String((node.get("NeScriptDirty", {}) as Dictionary).get("$type", "")), T_SCRIPT_DATA,
						"Exit.NeScriptDirty $type")
				var ne: Dictionary = node.get("NeScriptDirty", {})
				ctx.eq_keys(ne, SCRIPT_DATA_KEYS, "Exit.NeScriptDirty 字段顺序")
				ctx.eq(String(ne.get("bgFriendlyName", "")), "BG_CS_Millenium_18", "Exit.NeScriptDirty 背景名")
				ctx.eq(int(ne.get("bgName", 0)), 1565563486, "Exit.NeScriptDirty bgName = xxh32(背景名)")
				total_lines += 1  # NeScriptDirty 也是一行 ScriptData
			_:
				ctx.fail("nodes[%d] 未知 $type：%s" % [i, t])

		# 公共字段：Guid / ConnectionsTo / X / Y
		var guid := String(node.get("Guid", ""))
		ctx.is_true(regex.search(guid) != null, "nodes[%d].Guid 是小写 UUID：%s" % [i, guid])
		var ct: Dictionary = node.get("ConnectionsTo", {})
		ctx.is_true(ct is Dictionary, "nodes[%d].ConnectionsTo 是 List 包装" % i)
		ctx.eq_keys(ct, ["$type", "$values"], "nodes[%d].ConnectionsTo 字段顺序" % i)
		ctx.eq(String(ct.get("$type", "")), T_GUID_LIST, "nodes[%d].ConnectionsTo $type" % i)
		var conns2: Array = ct.get("$values", [])
		for target in conns2:
			if not guid_set.has(String(target)):
				all_connections_resolve = false
				ctx.fail("nodes[%d] 连线目标不存在：%s" % [i, target])
		ctx.contains(node, "X", "nodes[%d] 有 X" % i)
		ctx.contains(node, "Y", "nodes[%d] 有 Y" % i)
		if node.has("X"):
			ctx.eq(typeof(node["X"]), TYPE_FLOAT, "nodes[%d].X 是 float" % i)
		if node.has("Y"):
			ctx.eq(typeof(node["Y"]), TYPE_FLOAT, "nodes[%d].Y 是 float" % i)

	ctx.eq(script_nodes, 10, "ScriptNode 节点 10 个")
	ctx.eq(nonempty_script_nodes, 6, "其中 6 个有台词（27+60+58+22+1+1=169 行）")
	ctx.eq(empty_script_nodes, 4, "其中 4 个是空脚本节点（AA 允许 0 行）")
	ctx.eq(total_lines, 170, "ScriptNode 行数 169 + Exit.NeScriptDirty 1 = 170")
	ctx.is_true(choice_slots_ok, "所有选择节点都是固定 16 槽")
	ctx.is_true(all_connections_resolve, "所有 ConnectionsTo 都指向存在的节点")

	# 入口出边、出口无出边
	ctx.eq((nodes[0].get("ConnectionsTo", {}) as Dictionary).get("$values", []).size(), 1, "入口恰好 1 条出边")
	for i in range(nodes.size()):
		var t2 := String(nodes[i].get("$type", ""))
		var nconn: int = (nodes[i].get("ConnectionsTo", {}) as Dictionary).get("$values", []).size()
		if t2 == T_EXIT:
			ctx.eq(nconn, 0, "出口节点无出边")
		else:
			ctx.is_true(nconn >= 1, "非出口节点至少 1 条出边（nodes[%d]）" % i)
		if t2 == T_CHOICE:
			var sel_count: int = (nodes[i].get("selectionTexts", {}) as Dictionary).get("$values", []).size()
			ctx.eq(sel_count, 16, "选择节点 16 槽（nodes[%d]）" % i)
			ctx.gte(nconn, 1, "选择节点至少 1 个选项（nodes[%d]）" % i)

	# ---------------------------------------------------------------- 4. ScriptData 字段顺序（170 行全量）
	var bad_script_lines := 0
	var bad_character_lines := 0
	for idx in range(script_lines.size()):
		var line: Dictionary = script_lines[idx]
		if not _keys_match(line, SCRIPT_DATA_KEYS):
			bad_script_lines += 1
			if bad_script_lines <= 3:
				ctx.fail("第 %d 行 ScriptData 字段顺序不符：%s" % [idx, str(line.keys())])
		var chars: Dictionary = line.get("characters", {})
		if String(chars.get("$type", "")) != T_CHARACTER_LIST:
			bad_character_lines += 1
			if bad_character_lines <= 3:
				ctx.fail("第 %d 行 characters $type 不符：%s" % [idx, str(chars.get("$type", ""))])
		var records: Array = chars.get("$values", [])
		if records.size() != 6:
			bad_character_lines += 1
		elif not _keys_match(records[0], CHARACTER_KEYS):
			bad_character_lines += 1
		var hl: Dictionary = line.get("highlightedSlotNums", {})
		if String(hl.get("$type", "")) != T_INT_LIST:
			ctx.fail("第 %d 行 highlightedSlotNums $type 不符" % idx)
	ctx.eq(bad_script_lines, 0, "169 行 ScriptNode.ScriptData 字段顺序全部正确")
	ctx.eq(bad_character_lines, 0, "169×6 个 CharacterRecordData 结构全部正确（6 项/字段顺序）")

	# 抽查一行真实内容（防样本被替换）
	var first: Dictionary = script_lines[0]
	ctx.eq(String(first.get("text", "")), "不知道过了多久，画面总算有了新的事物出现……", "首行台词")
	ctx.eq(String(first.get("bgFriendlyName", "")), "BG_RuinUndergroundPassage", "首行背景名")
	ctx.eq(int(first.get("bgName", 0)), 3558049603, "首行 bgName")
	ctx.eq(String(first.get("voice", "")), "421e3665-33e2-4c36-90a1-8747e2b9db28", "首行语音 GUID")
	ctx.eq(String(first.get("sound", "")), "SE_Beep_02", "首行音效")
	ctx.eq(int(first.get("bgmId", -1)), 999, "首行 bgmId（静音）")
	ctx.eq((first.get("characters", {}) as Dictionary).get("$values", []).size(), 6, "首行 characters 6 槽")

	# 出口节点内容
	var exit_node: Dictionary = {}
	for n in nodes:
		if String(n.get("$type", "")) == T_EXIT:
			exit_node = n
			break
	ctx.eq(bool(exit_node.get("IsEnding", true)), false, "样本出口是「未完待续」而非 Ending")
	ctx.eq(String(exit_node.get("NeHeader", "")), "Kei", "出口 NeHeader")
	ctx.eq(String(exit_node.get("NeTitle", "")), "我，有名字了？", "出口 NeTitle")

	# ---------------------------------------------------------------- 5. manifest.json
	ctx.is_true(FileAccess.file_exists(MANIFEST_PATH), "样本 manifest.json 存在")
	if FileAccess.file_exists(MANIFEST_PATH):
		var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		ctx.is_true(m is Dictionary, "manifest.json 可解析")
		if m is Dictionary:
			ctx.is_true((m as Dictionary).has("CharacterOverrides"), "manifest 有 CharacterOverrides")
			ctx.is_true((m as Dictionary).has("VoiceOverrides"), "manifest 有 VoiceOverrides")
			var char_ov: Array = (m as Dictionary).get("CharacterOverrides", [])
			ctx.eq(char_ov.size(), 5, "manifest 角色覆盖 5 个")
			var voice_ov: Array = (m as Dictionary).get("VoiceOverrides", [])
			ctx.gt(voice_ov.size(), 100, "manifest 语音覆盖 >100 条")
			if not char_ov.is_empty():
				var c0: Dictionary = char_ov[0]
				ctx.eq_keys(c0, ["Identifier", "Name", "Nickname", "CharacterReference",
						"OriginalIdentifier", "SpinePortraitPath", "SmallPortraitPath"],
						"CharacterOverrides 条目字段顺序")


func _keys_match(d: Variant, expected: Array) -> bool:
	if not (d is Dictionary):
		return false
	var actual: Array = (d as Dictionary).keys()
	if actual.size() != expected.size():
		return false
	for i in range(actual.size()):
		if String(actual[i]) != String(expected[i]):
			return false
	return true
