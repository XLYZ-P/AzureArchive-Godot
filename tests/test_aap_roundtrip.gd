extends RefCounted
## test_aap_roundtrip.gd —— `.aap` 模型载入 / 序列化 / 再载入 的 round-trip 契约。
##
## 用真实样本 `fixtures/aap/sample_kei_01.aap`（17 节点 / 170 行）验证 docs/DESIGN.md §4：
##   1. 载入后模型字段（ProjectName/Preview*/节点统计/选择 16 槽/角色 6 槽）正确；
##   2. `to_json_text()` 输出再解析后与原文件**深度语义相等**（含 Dictionary key 顺序）；
##   3. `to_dict()` 的字段顺序逐层符合 AA 契约；`$type` 字符串逐字一致；
##   4. `save_to_file()` → `load_from_file()` 幂等稳定（两次序列化文本完全相同，UTF-8 无 BOM）；
##   5. 未知字段 / 未知节点 `$type` 容错保留（round-trip 不丢数据）；
##   6. bgName 脏数据：170 行中 165 命中，5 行已知漂移（BG_CS_Millenium_01_c），
##      `check_bg_ids()` / `repair_bg_ids()` 行为符合预期；
##   7. `compile()` 产出的 PlayScript 结构基本合理。
##
## 依赖 aa_core（core-dev）。若模块缺失自动 PENDING。

const Fw = preload("res://tests/framework.gd")

const SAMPLE := "res://fixtures/aap/sample_kei_01.aap"
const TMP_DIR := "user://qa_tmp"
const TMP_SAVE := "user://qa_tmp/roundtrip_qa.aap"

const EXPECT_TOP_KEYS := ["$type", "ProjectName", "PreviewBgName", "PreviewHeader", "PreviewTitle", "nodes"]
const EXPECT_ENTRY_KEYS := ["$type", "Title", "Header", "Guid", "ConnectionsTo", "X", "Y"]
const EXPECT_SCRIPT_KEYS := ["$type", "Scripts", "NodeName", "Guid", "ConnectionsTo", "X", "Y"]
const EXPECT_CHOICE_KEYS := ["$type", "selectionTexts", "Guid", "ConnectionsTo", "X", "Y"]
const EXPECT_EXIT_KEYS := ["$type", "IsEnding", "EndText", "NeHeader", "NeTitle", "NeScriptDirty", "Guid", "ConnectionsTo", "X", "Y"]
const EXPECT_LINE_KEYS := [
	"$type", "text", "popup", "bgEffect", "bgName", "bgFriendlyName", "sound", "voice",
	"transition", "bgmId", "selectionGroup", "additionalPrompt", "characters",
	"speakerSlotNum", "highlightedSlotNums", "isDialogScript", "placeText",
]
const EXPECT_CHAR_KEYS := ["$type", "name", "faceId", "startingPos", "endingPos", "emoticon",
		"action", "effect", "appear", "shapeOverride"]
const ZERO_GUID := "00000000-0000-0000-0000-000000000000"
const DRIFT_BG := "BG_CS_Millenium_01_c"
const DRIFT_STORED := 2434566677
const DRIFT_COMPUTED := 2177189307


func run(ctx: Fw.Ctx) -> void:
	var AP := ctx.need("res://addons/aa_core/aap_project.gd", "core-dev")
	if AP == null:
		return
	if not ctx.need_methods(AP, ["load_from_file", "load_from_string", "to_json_text",
			"to_dict", "save_to_file", "get_entry", "find_node", "iter_lines",
			"check_bg_ids", "repair_bg_ids", "compile"], "core-dev"):
		return
	ctx.is_true(FileAccess.file_exists(SAMPLE), "真实样本存在")
	if not FileAccess.file_exists(SAMPLE):
		return
	var original_text := FileAccess.get_file_as_string(SAMPLE)
	var original_json: Variant = JSON.parse_string(original_text)
	ctx.is_true(original_json is Dictionary, "样本原始 JSON 可解析")

	var proj: AapProject = AP.load_from_file(SAMPLE)
	ctx.not_null(proj, "AapProject.load_from_file 成功")
	if proj == null:
		return
	ctx.eq(proj.project_name, "Kei-初遇", "project_name")
	ctx.eq(proj.preview_bg_name, 3558049603, "preview_bg_name")
	ctx.eq(proj.preview_header, "Kei", "preview_header")
	ctx.eq(proj.preview_title, "初遇", "preview_title")

	# ---------------------------------------------------------------- 1. 节点统计
	ctx.eq(proj.nodes.size(), 17, "nodes 17 个")
	var entry := proj.get_entry()
	ctx.not_null(entry, "get_entry() 非空")
	if entry != null:
		ctx.eq(entry.guid, ZERO_GUID, "入口 Guid 全 0")
		ctx.eq(entry.node_type, AapProject.NODE_ENTRY, "入口 node_type == NODE_ENTRY")
		ctx.eq(entry.connections.size(), 1, "入口 1 条出边")
		ctx.eq(entry.pos, Vector2.ZERO, "入口坐标 (0,0)")
	ctx.eq(proj.get_nodes_of_type(AapProject.NODE_ENTRY).size(), 1, "NODE_ENTRY 1 个")
	ctx.eq(proj.get_nodes_of_type(AapProject.NODE_SCRIPT).size(), 10, "NODE_SCRIPT 10 个")
	ctx.eq(proj.get_nodes_of_type(AapProject.NODE_CHOICE).size(), 5, "NODE_CHOICE 5 个")
	ctx.eq(proj.get_nodes_of_type(AapProject.NODE_EXIT).size(), 1, "NODE_EXIT 1 个")

	# 节点字段顺序 / $type（模型 to_dict 层）
	ctx.eq_keys(proj.to_dict(), EXPECT_TOP_KEYS, "AapProject.to_dict 顶层字段顺序")
	ctx.eq(String(proj.to_dict().get("$type", "")), "ProjectData, Assembly-CSharp", "项目 $type")
	var script_nodes := proj.get_nodes_of_type(AapProject.NODE_SCRIPT)
	ctx.eq_keys(script_nodes[0].to_dict(), EXPECT_SCRIPT_KEYS, "ScriptNode.to_dict 字段顺序")
	ctx.eq(String(script_nodes[0].to_dict().get("$type", "")), "ScriptNodeData, Assembly-CSharp",
			"ScriptNode $type")
	ctx.eq_keys(entry.to_dict(), EXPECT_ENTRY_KEYS, "EntryNode.to_dict 字段顺序")
	ctx.eq_keys(proj.get_nodes_of_type(AapProject.NODE_CHOICE)[0].to_dict(), EXPECT_CHOICE_KEYS,
			"SelectionNode.to_dict 字段顺序")
	ctx.eq_keys(proj.get_nodes_of_type(AapProject.NODE_EXIT)[0].to_dict(), EXPECT_EXIT_KEYS,
			"ExitNode.to_dict 字段顺序")

	# 坐标：pos 是 float32（Vector2），原始 double 值在 to_dict 里保留
	ctx.almost_eq(script_nodes[0].pos.y, -200.7629, 1e-3, "第一个 Script 节点 pos.y")
	ctx.eq(script_nodes[0].to_dict().get("Y"), -200.7629, "to_dict Y 保留 double 精度")
	ctx.is_true(script_nodes[0].pos is Vector2, "node.pos 是 Vector2")

	# 选择节点：16 槽 + 出边数 == 非空选项数
	for choice in proj.get_nodes_of_type(AapProject.NODE_CHOICE):
		ctx.eq(choice.selection_texts.size(), 16, "选择节点 selection_texts 固定 16 槽")
		var visible := 0
		for i in range(choice.selection_texts.size()):
			if not String(choice.selection_texts[i]).is_empty():
				visible += 1
		ctx.eq(visible, choice.connections.size(), "选项文本数 == 出边数（%s）" % choice.guid.substr(0, 8))

	# 图完整性 + 连线总数
	var problems: Array = proj.validate()
	ctx.eq(problems.size(), 0, "project.validate() 无问题：%s" % str(problems))
	var total_conn := 0
	for node in proj.nodes:
		total_conn += node.connections.size()
		for target in node.connections:
			ctx.not_null(proj.find_node(target), "连线目标存在：%s" % target)
	ctx.eq(total_conn, 18, "全工程连线 18 条")

	# ---------------------------------------------------------------- 2. 行级模型
	var lines: Array = proj.iter_lines(true)
	ctx.eq(lines.size(), 170, "iter_lines(true) 170 行（169 正文 + 1 出口预告）")
	var first: AaScriptLine = lines[0]
	ctx.eq(first.text, "不知道过了多久，画面总算有了新的事物出现……", "首行台词")
	ctx.eq(first.bg_friendly_name, "BG_RuinUndergroundPassage", "首行背景名")
	ctx.eq(first.bg_name, 3558049603, "首行 bgName")
	ctx.eq(first.voice, "421e3665-33e2-4c36-90a1-8747e2b9db28", "首行语音 GUID")
	ctx.eq(first.sound, "SE_Beep_02", "首行音效")
	ctx.eq(first.bgm_id, 999, "首行 bgmId（静音）")
	ctx.eq(first.characters.size(), 6, "首行 characters 6 槽")
	ctx.eq_keys(first.to_dict(), EXPECT_LINE_KEYS, "ScriptLine.to_dict 字段顺序")
	ctx.eq(String(first.to_dict().get("$type", "")), "ScriptData, Assembly-CSharp", "ScriptData $type")
	var char1: AaCharacterRecord = first.get_character(1)
	ctx.not_null(char1, "get_character(1) 非空（越界也应返回空记录）")
	if char1 != null:
		ctx.eq_keys(char1.to_dict(), EXPECT_CHAR_KEYS, "CharacterRecordData.to_dict 字段顺序")
		ctx.eq(String(char1.to_dict().get("$type", "")), "ScriptData+CharacterRecordData, Assembly-CSharp",
				"CharacterRecordData $type")
	# 越界访问不崩
	ctx.not_null(first.get_character(99), "get_character(越界) 返回空记录不崩")

	# 选择节点的选项文本 / 出口
	var choice0: AapNode = proj.get_nodes_of_type(AapProject.NODE_CHOICE)[0]
	ctx.eq(choice0.get_selection_text(0), "既然机器人没有追过来，还是挺安全的", "选择节点选项 0 文本")
	var exit_node = proj.get_nodes_of_type(AapProject.NODE_EXIT)[0]
	ctx.eq(exit_node.is_ending, false, "出口是未完待续")
	ctx.eq(exit_node.ne_header, "Kei", "出口 NeHeader")
	ctx.eq(exit_node.ne_title, "我，有名字了？", "出口 NeTitle")

	# ---------------------------------------------------------------- 3. 序列化 round-trip（语义 + 字段顺序）
	var text_compact: String = proj.to_json_text(false)
	var text_pretty: String = proj.to_json_text(true)
	ctx.gt(text_compact.length(), 100_000, "紧凑序列化文本长度合理")
	ctx.not_contains(text_compact, "\n", "pretty=false 时无换行（与 AA 紧凑风格一致）")
	ctx.contains(text_pretty, "\n", "pretty=true 时有换行")
	ctx.eq(proj.to_json_text(false), text_compact, "to_json_text 稳定（两次输出相同）")
	var rejson: Variant = JSON.parse_string(text_compact)
	ctx.is_true(rejson is Dictionary, "序列化结果可被 JSON 解析")
	if rejson is Dictionary:
		ctx.eq_deep_ordered(rejson, original_json, "序列化 JSON 与原文件深度语义 + key 顺序完全一致")
		ctx.eq_keys(rejson, EXPECT_TOP_KEYS, "序列化顶层字段顺序")
		# $type 逐节点逐行逐字一致
		var orig_nodes: Array = (original_json as Dictionary)["nodes"]["$values"]
		var new_nodes: Array = (rejson as Dictionary)["nodes"]["$values"]
		var type_mismatch: Array = []
		for i in range(mini(orig_nodes.size(), new_nodes.size())):
			if String(orig_nodes[i].get("$type", "")) != String(new_nodes[i].get("$type", "")):
				type_mismatch.append("node %d" % i)
		ctx.eq(type_mismatch.size(), 0, "17 个节点 $type 逐字一致：%s" % str(type_mismatch))
		var orig_lines: Array = []
		for n in orig_nodes:
			if String(n.get("$type", "")).contains("ScriptNodeData"):
				orig_lines.append_array(n["Scripts"]["$values"])
			elif String(n.get("$type", "")).contains("ExitNodeData"):
				orig_lines.append(n["NeScriptDirty"])
		var new_lines: Array = []
		for n in new_nodes:
			if String(n.get("$type", "")).contains("ScriptNodeData"):
				new_lines.append_array(n["Scripts"]["$values"])
			elif String(n.get("$type", "")).contains("ExitNodeData"):
				new_lines.append(n["NeScriptDirty"])
		ctx.eq(new_lines.size(), 170, "序列化后 170 行")
		ctx.eq_keys(new_lines[0], EXPECT_LINE_KEYS, "序列化第 1 行字段顺序")

	# 再解析回模型，再序列化：稳定
	var proj2: AapProject = AP.load_from_string(text_compact)
	ctx.not_null(proj2, "load_from_string 成功")
	if proj2 != null:
		ctx.eq(proj2.nodes.size(), 17, "再解析后节点数 17")
		ctx.eq(proj2.to_json_text(false), text_compact, "round-trip 两次序列化文本完全相同（幂等）")
		ctx.eq_deep(proj2.to_dict(), proj.to_dict(), "round-trip 后 to_dict 深度相等")

	# ---------------------------------------------------------------- 4. save_to_file / load_from_file
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var err: int = proj.save_to_file(TMP_SAVE)
	ctx.eq(err, OK, "save_to_file 返回 OK（err=%d）" % err)
	ctx.is_true(FileAccess.file_exists(TMP_SAVE), "保存文件存在：%s" % TMP_SAVE)
	if FileAccess.file_exists(TMP_SAVE):
		var saved_bytes := FileAccess.get_file_as_bytes(TMP_SAVE)
		ctx.ne(saved_bytes.slice(0, 3).get_string_from_ascii(), "\u00ef\u00bb\u00bf", "保存文件无 BOM")
		ctx.eq(saved_bytes.get_string_from_utf8(), text_compact, "保存内容 == to_json_text(false)")
		var proj3: AapProject = AP.load_from_file(TMP_SAVE)
		ctx.not_null(proj3, "保存后可重新载入")
		if proj3 != null:
			ctx.eq_deep(proj3.to_dict(), proj.to_dict(), "保存→载入 后 to_dict 深度相等")
			ctx.eq(proj3.to_json_text(false), text_compact, "保存→载入 后序列化文本稳定")

	# ---------------------------------------------------------------- 5. 未知字段 / 未知节点类型容错保留
	if original_json is Dictionary:
		var mutated: Dictionary = (original_json as Dictionary).duplicate(true)
		mutated["FutureTopField"] = {"hello": 1}
		var m_nodes: Array = mutated["nodes"]["$values"]
		m_nodes[1]["FutureNodeField"] = 42
		m_nodes[1]["Scripts"]["$values"][0]["FutureLineField"] = "keep-me"
		# 未知 $type 节点（未来 AA 版本新增类型）
		m_nodes.append({
			"$type": "FutureNodeData, Assembly-CSharp",
			"Guid": "abcdefab-1234-4abc-8def-abcdefabcdef",
			"ConnectionsTo": {"$type": "System.Collections.Generic.List`1[[System.Guid, mscorlib]], mscorlib", "$values": []},
			"X": 1.5,
			"Y": -2.5,
			"FutureNodeOnlyField": [1, 2, 3],
		})
		var mutated_text := JSON.stringify(mutated)
		var proj_u: AapProject = AP.load_from_string(mutated_text)
		ctx.not_null(proj_u, "含未知字段/未知类型的 .aap 可载入")
		if proj_u != null:
			var ud: Dictionary = proj_u.to_dict()
			ctx.eq_deep(ud.get("FutureTopField"), {"hello": 1}, "未知顶层字段保留")
			var unodes: Array = ud["nodes"]["$values"]
			ctx.eq(unodes.size(), 18, "未知类型节点保留在 nodes 中")
			ctx.eq_deep(unodes[1].get("FutureNodeField"), 42, "未知节点字段保留")
			ctx.eq_deep(unodes[1]["Scripts"]["$values"][0].get("FutureLineField"), "keep-me", "未知行字段保留")
			var unknown_node: Dictionary = unodes[unodes.size() - 1]
			ctx.eq(String(unknown_node.get("$type", "")), "FutureNodeData, Assembly-CSharp", "未知节点 $type 保留")
			ctx.eq_deep(unknown_node.get("FutureNodeOnlyField"), [1, 2, 3], "未知节点自定义字段保留")

	# ---------------------------------------------------------------- 6. bgName 脏数据 / check / repair
	var bg_check: Dictionary = proj.check_bg_ids()
	ctx.eq(int(bg_check.get("total", 0)), 170, "check_bg_ids total == 170")
	ctx.eq(int(bg_check.get("matched", 0)), 165, "check_bg_ids matched == 165（5 行 AA 历史脏数据）")
	var mismatched: Array = bg_check.get("mismatched", [])
	ctx.eq(mismatched.size(), 5, "mismatched 5 行")
	for mm in mismatched:
		ctx.eq(String(mm.get("friendly", "")), DRIFT_BG, "脏数据行背景名均为 BG_CS_Millenium_01_c")
		ctx.eq(int(mm.get("stored", 0)), DRIFT_STORED, "脏数据存储值 2434566677")
		ctx.eq(int(mm.get("computed", 0)), DRIFT_COMPUTED, "脏数据计算值 2177189307")
	var proj_repair: AapProject = AP.load_from_file(SAMPLE)
	if proj_repair != null:
		var before_text := proj_repair.to_json_text(false)
		var fixed: int = proj_repair.repair_bg_ids()
		ctx.eq(fixed, 5, "repair_bg_ids 修复 5 行")
		ctx.eq(int(proj_repair.check_bg_ids().get("matched", 0)), 170, "修复后 170/170 命中")
		ctx.eq(proj_repair.repair_bg_ids(), 0, "再次 repair 返回 0（幂等）")
		# 修复只改 bgName，不动其他字段
		var after_dict: Dictionary = proj_repair.to_dict()
		var before_dict: Dictionary = proj.to_dict()
		var after_nodes: Array = after_dict["nodes"]["$values"]
		var before_nodes: Array = before_dict["nodes"]["$values"]
		var before_lines: Array = []
		var after_lines: Array = []
		for n in before_nodes:
			if String(n.get("$type", "")).contains("ScriptNodeData"):
				before_lines.append_array(n["Scripts"]["$values"])
		for n in after_nodes:
			if String(n.get("$type", "")).contains("ScriptNodeData"):
				after_lines.append_array(n["Scripts"]["$values"])
		var other_diff := 0
		for i in range(before_lines.size()):
			var bl: Dictionary = (before_lines[i] as Dictionary).duplicate(true)
			var al: Dictionary = (after_lines[i] as Dictionary).duplicate(true)
			bl.erase("bgName")
			al.erase("bgName")
			if JSON.stringify(bl) != JSON.stringify(al):
				other_diff += 1
		ctx.eq(other_diff, 0, "repair 只改 bgName，不破坏其他字段")
		ctx.ne(before_text, proj_repair.to_json_text(false), "repair 后文本确有变化")
		ctx.eq_deep(proj.to_dict(), before_dict, "原工程对象未被 repair 污染（repair 作用于副本）")

	# ---------------------------------------------------------------- 7. 参数化：另外 4 个真实样本
	# 每个样本 load → to_json_text(false) → 再解析：JSON 深度语义 + key 顺序与原始文件一致；
	# 再 load_from_string 后 to_dict 深度相等。它们不应有 bgName 脏数据（100% 命中）。
	var other_samples := [
		["res://fixtures/aap/sample_kei_02_multi_branch.aap", 6, 310],
		["res://fixtures/aap/sample_keiend_03_ending.aap", 3, 98],
		["res://fixtures/aap/sample_kei_04_small.aap", 7, 47],
		["res://fixtures/aap/sample_kei_05_large.aap", 37, 438],
	]
	for spec in other_samples:
		var spath := String(spec[0])
		var expected_nodes := int(spec[1])
		var expected_lines := int(spec[2])
		if not FileAccess.file_exists(spath):
			ctx.note("样本缺失，跳过：%s" % spath)
			continue
		var sp: AapProject = AP.load_from_file(spath)
		ctx.not_null(sp, "载入样本 %s" % spath.get_file())
		if sp == null:
			continue
		ctx.eq(sp.nodes.size(), expected_nodes, "%s 节点数 %d" % [spath.get_file(), expected_nodes])
		ctx.eq(sp.iter_lines(true).size(), expected_lines, "%s 行数 %d" % [spath.get_file(), expected_lines])
		# bgName：这些样本应 100% 命中
		var bgc: Dictionary = sp.check_bg_ids()
		ctx.eq(int(bgc.get("matched", 0)), int(bgc.get("total", -1)),
				"%s bgName 100%% 命中（%d/%d）" % [spath.get_file(), int(bgc.get("matched", 0)), int(bgc.get("total", 0))])
		# round-trip 文本稳定 + 再解析深度相等
		var stext: String = sp.to_json_text(false)
		var sp2: AapProject = AP.load_from_string(stext)
		ctx.not_null(sp2, "%s round-trip 再解析" % spath.get_file())
		if sp2 != null:
			ctx.eq_deep(sp2.to_dict(), sp.to_dict(), "%s round-trip to_dict 深度相等" % spath.get_file())
			ctx.eq(sp2.to_json_text(false), stext, "%s round-trip 序列化稳定" % spath.get_file())
		# 序列化 JSON 与原始文件：字段顺序 + 语义一致
		var raw_text := FileAccess.get_file_as_string(spath)
		var raw_json: Variant = JSON.parse_string(raw_text)
		var new_json: Variant = JSON.parse_string(stext)
		if raw_json is Dictionary and new_json is Dictionary:
			ctx.eq_deep_ordered(new_json, raw_json, "%s 序列化后 key 顺序/语义与原始文件一致" % spath.get_file())
			# 图连通性
			var snodes: Array = (new_json as Dictionary)["nodes"]["$values"]
			var sguids := {}
			for sn in snodes:
				sguids[String((sn as Dictionary).get("Guid", ""))] = true
			var dangling := 0
			for sn2 in snodes:
				for target2 in ((sn2 as Dictionary).get("ConnectionsTo", {}) as Dictionary).get("$values", []):
					if not sguids.has(String(target2)):
						dangling += 1
			ctx.eq(dangling, 0, "%s 无悬空连线" % spath.get_file())
		# 出口数量恰好 1
		ctx.eq(sp.get_nodes_of_type(AapProject.NODE_EXIT).size(), 1, "%s 恰好 1 个出口" % spath.get_file())

	# ---------------------------------------------------------------- 8. compile() 结构
	var ps: PlayScript = proj.compile()
	ctx.not_null(ps, "compile() 返回 PlayScript")
	if ps != null:
		ctx.eq(ps.start_guid, ZERO_GUID, "PlayScript.start_guid == 入口 guid（全 0）")
		var start_pn: PlayNode = ps.get_start_node()
		ctx.not_null(start_pn, "get_start_node() 非空")
		if start_pn != null:
			ctx.eq(start_pn.kind, PlayNode.KIND_ENTRY, "PlayScript 起始节点 kind == ENTRY")
			ctx.eq(start_pn.next_guid, entry.connections[0], "起始节点 next_guid == 入口第一条出边")
		ctx.gt(ps.get_node_count(), 10, "PlayScript 节点数 > 10（17 节点全部铺平）")
		var script_line_count := 0
		var play_choices := 0
		var play_exits := 0
		for pn in ps.all_nodes():
			if pn.kind == PlayNode.KIND_SCRIPT:
				script_line_count += pn.line_count()
			elif pn.kind == PlayNode.KIND_CHOICE:
				play_choices += 1
				ctx.gt(pn.valid_options().size(), 0, "选择 PlayNode 有有效选项")
			elif pn.kind == PlayNode.KIND_EXIT:
				play_exits += 1
		ctx.eq(script_line_count, 169, "PlayScript 正文行数 169")
		ctx.eq(play_choices, 5, "PlayScript 选择节点 5")
		ctx.eq(play_exits, 1, "PlayScript 出口节点 1")
		# .aac 编译缓存 round-trip
		var aac_text: String = ps.to_json_text() if ps.has_method("to_json_text") else JSON.stringify(ps.to_dict())
		var ps2: Variant = PlayScript.from_dict(JSON.parse_string(aac_text)) if ps.has_method("from_dict") else null
		if ps2 != null:
			ctx.eq(ps2.start_guid, ps.start_guid, ".aac round-trip start_guid")
			ctx.eq(ps2.get_node_count(), ps.get_node_count(), ".aac round-trip 节点数")
