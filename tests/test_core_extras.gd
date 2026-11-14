extends RefCounted
## test_core_extras.gd —— aa_core 的辅助契约（枚举表 / 自动等待 / 新建工程 / 错误处理 / JSON 转义）。
##
## 这些行为不属于「格式 round-trip」主链路，但被播放器/编辑器依赖（docs/DESIGN.md §5.1）：
##   1. AaEnums 枚举表规模与查询（TRANSITIONS 61 / BG_EFFECTS 27 / 表情/动作/进出场/形状）；
##   2. AaScriptLine 自动等待规则：emoticon -> 2500，位移/进出场/动作 -> 1500，
##      `#wait` 显式覆盖（含 #wait;0）；空角色槽不触发；
##   3. AapProject.create()（入口+默认脚本）/ create_empty()（仅入口）结构；
##   4. load 失败返回 null 且 last_error 有原因，成功后清空；
##   5. 选择节点允许重复连线（AA 语义：不去重）；
##   6. JSON 转义：引号/反斜杠/换行/制表/控制字符 round-trip；
##   7. 节点中文名 / 行复制等便捷方法。
##
## 依赖 aa_core（core-dev）。

const Fw = preload("res://tests/framework.gd")

const TMP_SAVE := "user://qa_tmp/core_extras.aap"


func run(ctx: Fw.Ctx) -> void:
	var EN := ctx.need("res://addons/aa_core/enums.gd", "core-dev")
	var SL := ctx.need("res://addons/aa_core/script_line.gd", "core-dev")
	var AP := ctx.need("res://addons/aa_core/aap_project.gd", "core-dev")
	var AN := ctx.need("res://addons/aa_core/aap_node.gd", "core-dev")
	if EN == null or SL == null or AP == null or AN == null:
		return

	# ---------------------------------------------------------------- 1. 枚举表
	ctx.eq(int(EN.get_script_constant_map().get("TRANSITIONS", {}).size()), 61, "AaEnums.TRANSITIONS 61 条")
	ctx.eq(int(EN.get_script_constant_map().get("BG_EFFECTS", {}).size()), 27, "AaEnums.BG_EFFECTS 27 条（含 0=None）")
	ctx.eq(int(EN.get_script_constant_map().get("EMOTICONS", {}).size()), 21, "EMOTICONS 21 条（-1 无 + 0–19）")
	ctx.eq(int(EN.get_script_constant_map().get("ACTIONS", {}).size()), 8, "ACTIONS 8 条（0 无 + 1–7）")
	ctx.eq(int(EN.get_script_constant_map().get("APPEAR", {}).size()), 7, "APPEAR 7 条（0 无 + 1–6）")

	var t_info: Dictionary = AaEnums.transition_info(4004024664)
	ctx.contains(String(t_info.get("name", "")), "Crossfade", "transition_info(4004024664).name")
	ctx.eq(String(t_info.get("name", "")), "Crossfade 1000 >>", "Crossfade 1000 >> 英文名")
	ctx.is_true(not String(AaEnums.transition_zh(4004024664)).is_empty(), "transition_zh 非空（显示用）")
	ctx.eq(int(AaEnums.transition_duration(1122508889)), 2000, "Fade 1000+1000 总时长 2000ms")
	ctx.eq(int(AaEnums.transition_duration(0)), 0, "过渡 0 时长 0")

	var b_info: Dictionary = AaEnums.bg_effect_info(3134544579)
	ctx.eq(String(b_info.get("name", "")), "BG_UnderFire", "bg_effect_info(3134544579).name")
	ctx.eq(String(AaEnums.bg_effect_zh(3134544579)), "枪战", "bg_effect_zh(3134544579)")
	ctx.eq(String(AaEnums.bg_effect_info(0).get("name", "")), "None", "背景效果 0 = None")
	ctx.eq(String(AaEnums.bg_effect_zh(0)), "无", "背景效果 0 中文 = 无")

	# 中文/英文解析（ID 是权威，中文只做输入便利）
	ctx.eq(int(AaEnums.transition_resolve("淡入淡出 2000")), 2482233134, "transition_resolve(淡入淡出 2000)")
	ctx.eq(int(AaEnums.transition_resolve("交叉渐变 500")), 3854440696, "transition_resolve(交叉渐变 500)")
	ctx.eq(int(AaEnums.transition_resolve("Fade 1500 >> 1500")), 509674679, "transition_resolve(Fade 1500 >> 1500)")
	ctx.eq(int(AaEnums.transition_resolve("噪点")), 3344317924, "transition_resolve(噪点)")
	ctx.eq(int(AaEnums.bg_effect_resolve("集中线")), 3550865647, "bg_effect_resolve(集中线)")
	ctx.eq(int(AaEnums.transition_resolve("不存在的过渡")), 0, "未知过渡解析为 0（不崩）")
	ctx.gt(AaEnums.transition_choices().size(), 50, "transition_choices() 下拉项 > 50")
	ctx.gt(AaEnums.bg_effect_choices().size(), 20, "bg_effect_choices() 下拉项 > 20")

	ctx.eq(int(AaEnums.emoticon_id_by_zh("叽喳")), 1, "emoticon_id_by_zh(叽喳) == 1")
	ctx.contains(AaEnums.emoticon_symbol(1), "재잘", "emoticon_symbol(1) 是 [재잘]")
	ctx.eq(int(AaEnums.action_id_by_name("jump")), 6, "action_id_by_name(jump) == 6")
	ctx.eq(String(AaEnums.appear_token(3)), "a", "appear_token(3) == a")
	ctx.eq(int(AaEnums.appear_id_by_token("d")), 6, "appear_id_by_token(d) == 6")
	ctx.contains(AaEnums.shape_tokens(1), "sig", "shape 1 含 sig")
	ctx.eq(int(AaEnums.shape_id_by_token("closeup")), 4, "shape_id_by_token(closeup) == 4")

	# ---------------------------------------------------------------- 2. 自动等待规则
	var line := AaScriptLine.make_empty()
	# make_empty 不带角色槽，先补 6 个空槽
	for i in AaScriptLine.SLOT_COUNT:
		line.characters.append(AaCharacterRecord.new())
	ctx.eq(line.auto_wait_ms(), 0, "空角色行自动等待 0")
	ctx.eq(line.explicit_wait_ms(), -1, "无 #wait 时 explicit_wait_ms == -1")
	ctx.eq(line.effective_wait_ms(), 0, "无 #wait 时 effective == auto")

	line.characters[1].name = "QA_HERO"
	line.characters[1].emoticon = 3
	ctx.eq(line.auto_wait_ms(), AaScriptLine.AUTO_WAIT_EMOTICON, "有 emoticon -> 2500ms")
	ctx.eq(int(AaScriptLine.AUTO_WAIT_EMOTICON), 2500, "AUTO_WAIT_EMOTICON == 2500")

	line.characters[1].emoticon = -1
	line.characters[1].appear = 3
	ctx.eq(line.auto_wait_ms(), AaScriptLine.AUTO_WAIT_MOTION, "appear -> 1500ms")
	ctx.eq(int(AaScriptLine.AUTO_WAIT_MOTION), 1500, "AUTO_WAIT_MOTION == 1500")

	line.characters[1].appear = 0
	line.characters[1].starting_pos = 1
	line.characters[1].ending_pos = 2
	ctx.eq(line.auto_wait_ms(), 1500, "位移（starting != ending）-> 1500ms")

	line.characters[1].starting_pos = 1
	line.characters[1].ending_pos = 1
	line.characters[1].action = 6
	ctx.eq(line.auto_wait_ms(), 1500, "动作 action=6 -> 1500ms")

	# 空角色槽（name=="") 不触发
	var line_empty := AaScriptLine.make_empty()
	for i2 in AaScriptLine.SLOT_COUNT:
		line_empty.characters.append(AaCharacterRecord.new())
	line_empty.characters[2].appear = 3  # name 为空 -> 忽略
	ctx.eq(line_empty.auto_wait_ms(), 0, "空角色槽（name==\"\"）不触发自动等待")

	# 作者显式 #wait 覆盖自动等待
	line.set_additional_prompt("#wait;0")
	ctx.eq(line.explicit_wait_ms(), 0, "显式 #wait;0 -> explicit 0")
	ctx.eq(line.effective_wait_ms(), 0, "显式 #wait;0 覆盖自动 1500")
	line.set_additional_prompt("#wait;5000")
	ctx.eq(line.effective_wait_ms(), 5000, "显式 #wait;5000 覆盖自动")
	line.set_additional_prompt("")
	ctx.eq(line.effective_wait_ms(), 1500, "清空 #wait 后回到自动 1500")

	# ---------------------------------------------------------------- 3. create / create_empty
	var p2: AapProject = AapProject.create("QA 新工程")
	ctx.eq(p2.nodes.size(), 2, "AapProject.create() = 入口 + 默认脚本节点（2 节点）")
	ctx.not_null(p2.get_entry(), "create() 有入口")
	ctx.eq(p2.get_nodes_of_type(AapProject.NODE_SCRIPT).size(), 1, "create() 有 1 个脚本节点")
	if p2.get_entry() != null:
		ctx.eq(p2.get_entry().connections.size(), 1, "create() 入口已连到脚本节点")
	var starter: AapNode = p2.get_nodes_of_type(AapProject.NODE_SCRIPT)[0]
	ctx.eq(starter.scripts.size(), 1, "默认脚本节点带 1 条空行")
	ctx.eq(int(starter.scripts[0].bgm_id), 999, "默认空行 bgmId=999（静音）")
	ctx.is_true(not String(starter.scripts[0].voice).is_empty(), "默认空行 voice 是 GUID")

	var p3: AapProject = AapProject.create_empty("QA 空工程")
	ctx.eq(p3.nodes.size(), 1, "create_empty() 只有入口")
	ctx.eq(p3.get_nodes_of_type(AapProject.NODE_SCRIPT).size(), 0, "create_empty() 无脚本节点")

	# create() 工程保存/重载一致
	DirAccess.make_dir_recursive_absolute(TMP_SAVE.get_base_dir())
	ctx.eq(p2.save_to_file(TMP_SAVE), OK, "create() 工程可保存")
	var p2b: AapProject = AapProject.load_from_file(TMP_SAVE)
	ctx.not_null(p2b, "create() 工程可重载")
	if p2b != null:
		ctx.eq_deep_ordered(p2b.to_dict(), p2.to_dict(), "create() 工程 round-trip 深度+字段顺序一致")
	var ps = p2.compile()
	ctx.not_null(ps, "create() 工程可编译（默认 1 行空脚本）")
	if ps != null:
		ctx.gt(ps.get_node_count(), 0, "create() 编译节点数 > 0")

	# ---------------------------------------------------------------- 4. 错误处理 last_error
	var bad: AapProject = AapProject.load_from_file("res://fixtures/aap/不存在的工程.aap")
	ctx.is_null(bad, "载入不存在的工程返回 null")
	ctx.is_true(not String(AapProject.last_error).is_empty(), "失败后 last_error 有原因：%s" % String(AapProject.last_error))
	var good: AapProject = AapProject.load_from_file("res://fixtures/aap/sample_kei_01.aap")
	ctx.not_null(good, "成功载入真实样本")
	ctx.eq(String(AapProject.last_error), "", "成功后 last_error 清空")
	var bad_json: AapProject = AapProject.load_from_string("{ 这不是 JSON ")
	ctx.is_null(bad_json, "非法 JSON 返回 null")
	ctx.is_true(not String(AapProject.last_error).is_empty(), "非法 JSON 后 last_error 有原因")

	# ---------------------------------------------------------------- 5. 选择节点允许重复连线（AA 语义）
	var p4: AapProject = AapProject.create_empty("连线测试")
	var choice: AapNode = p4.add_node(AapProject.NODE_CHOICE, Vector2(0, -400))
	var s1: AapNode = p4.add_node(AapProject.NODE_SCRIPT, Vector2(-200, -600))
	var s2: AapNode = p4.add_node(AapProject.NODE_SCRIPT, Vector2(200, -600))
	var entry4: AapNode = p4.get_entry()
	ctx.not_null(choice, "添加选择节点")
	ctx.not_null(s1, "添加脚本节点 1")
	ctx.not_null(s2, "添加脚本节点 2")
	if choice != null and s1 != null and s2 != null and entry4 != null:
		ctx.is_true(p4.connect_nodes(entry4, choice), "入口 -> 选择节点")
		ctx.is_true(p4.connect_nodes(choice, s1), "选择 -> 脚本 1（选项 0）")
		ctx.is_true(p4.connect_nodes(choice, s1), "选择 -> 脚本 1 再连一次（AA 允许重复连线）")
		ctx.eq(choice.connections.size(), 2, "选择节点有 2 条出边（重复目标保留）")
		ctx.eq(String(choice.connections[0]), String(choice.connections[1]), "两条出边指向同一目标")
		ctx.eq(choice.selection_texts.size(), 16, "选择节点 selection 仍是 16 槽")
		var opts: Array = p4.get_choice_options(choice)
		ctx.eq(opts.size(), 2, "get_choice_options 返回 2 个选项")
		# 出口节点（让工程合法可编译）
		var ex: AapNode = p4.add_node(AapProject.NODE_EXIT, Vector2(0, -800))
		if ex != null:
			p4.connect_nodes(s1, ex)
			p4.connect_nodes(s2, ex)
		ctx.eq(choice.type_name_zh(), "选择节点", "type_name_zh(choice)")
		ctx.eq(entry4.type_name_zh(), "入口节点", "type_name_zh(entry)")

	# ---------------------------------------------------------------- 6. JSON 转义 round-trip
	var p5: AapProject = AapProject.create("转义测试")
	var esc_line: AaScriptLine = p5.get_nodes_of_type(AapProject.NODE_SCRIPT)[0].scripts[0]
	var tricky := "引号\" 反斜杠\\ 换行\n 制表\t 控制" + String.chr(1) + " 结束"
	esc_line.set_text(tricky)
	var esc_text: String = p5.to_json_text(false)
	ctx.not_contains(esc_text, "\n", "紧凑 JSON 不包含真实换行（换行已转义）")
	ctx.contains(esc_text, "\\\"", "JSON 中双引号被转义")
	ctx.contains(esc_text, "\\\\", "JSON 中反斜杠被转义")
	var esc_path := TMP_SAVE.get_base_dir().path_join("escape.aap")
	ctx.eq(p5.save_to_file(esc_path), OK, "含特殊字符的工程可保存")
	var p5b: AapProject = AapProject.load_from_file(esc_path)
	ctx.not_null(p5b, "含特殊字符的工程可重载")
	if p5b != null:
		var esc_line2: AaScriptLine = p5b.get_nodes_of_type(AapProject.NODE_SCRIPT)[0].scripts[0]
		ctx.eq(esc_line2.text, tricky, "引号/反斜杠/换行/制表/控制字符 round-trip 一致")
	# 行复制
	var dup: AaScriptLine = esc_line.duplicate_line()
	ctx.eq(dup.text, esc_line.text, "duplicate_line 文本一致")
	ctx.ne(dup.get_instance_id(), esc_line.get_instance_id(), "duplicate_line 是不同实例")


	# ---------------------------------------------------------------- 7. 表情/槽位/BGM 枚举补充
	ctx.eq(AaEnums.FACE_IDS.size(), 14, "FACE_IDS 14 个常用表情")
	ctx.contains(AaEnums.FACE_IDS, "00", "FACE_IDS 含 00")
	ctx.contains(AaEnums.FACE_IDS, "99", "FACE_IDS 含 99（特殊/占位）")
	ctx.eq(String(AaEnums.face_zh("03")), "微笑", "face_zh(03) == 微笑")
	ctx.eq(String(AaEnums.face_zh("06")), "低落", "face_zh(06) == 低落")
	ctx.eq(String(AaEnums.face_semantic_name("05")), "serious", "face_semantic_name(05) == serious")
	ctx.eq(String(AaEnums.face_semantic_name("00")), "default", "face_semantic_name(00) == default")
	ctx.eq(String(AaEnums.face_normalize("embarassed")), "embarrassed", "FACE_ALIAS: embarassed -> embarrassed")
	ctx.eq(String(AaEnums.face_normalize("nomal")), "normal", "FACE_ALIAS: nomal -> normal")
	ctx.eq(String(AaEnums.face_normalize("03")), "03", "未知/标准 faceId 归一化不改变")
	ctx.eq(String(AaEnums.slot_label(0)), "#0 发言", "slot_label(0)")
	ctx.eq(String(AaEnums.slot_label(5)), "#5 右", "slot_label(5)")
	ctx.contains(AaEnums.slot_label(9), "9", "越界槽位显示编号不崩")
	ctx.eq(int(AaEnums.BGM_MUTE), 999, "BGM_MUTE == 999")
	# 背景效果中文名（docs/spec/enums.md 校准后）
	ctx.eq(String(AaEnums.bg_effect_zh(2174743540)), "红滤镜（无背景）", "bg_effect_zh(红滤镜·无背景)")
	ctx.eq(String(AaEnums.bg_effect_zh(1566732214)), "闪电（含音效）", "bg_effect_zh(闪电含音效)")
	ctx.eq(String(AaEnums.bg_effect_zh(442565896)), "向右滚动 1.0", "bg_effect_zh(向右滚动)")
	ctx.eq(String(AaEnums.bg_effect_zh(2551519896)), "烟花 01（无背景）", "bg_effect_zh(烟花01)")

	# ---------------------------------------------------------------- 8. 自动指令推导（真实样本）
	var sample2: AapProject = AapProject.load_from_file("res://fixtures/aap/sample_kei_01.aap")
	ctx.not_null(sample2, "载入真实样本（自动推导用）")
	if sample2 != null:
		var node2: AapNode = sample2.find_node("b292a9b5-dd77-435e-b675-29b1b8ad0e92")
		ctx.not_null(node2, "找到真实样本节点 b292a9b5")
		if node2 != null and node2.scripts.size() >= 6:
			var l0: AaScriptLine = node2.scripts[0]
			var l1: AaScriptLine = node2.scripts[1]
			var l2: AaScriptLine = node2.scripts[2]
			var events: Array = l1.derive_stage_events(l0)
			ctx.gt(events.size(), 0, "第 2 行 derive_stage_events 非空")
			var appears := 0
			var actions := 0
			var first_kind := ""
			var kinds_list: Array = []
			for e in events:
				var kind := String((e as Dictionary).get("kind", ""))
				if first_kind.is_empty():
					first_kind = kind
				kinds_list.append(kind)
				if kind == "appear":
					appears += 1
				elif kind == "action":
					actions += 1
					ctx.eq(int((e as Dictionary).get("slot", -1)), 1, "action 事件槽位 1")
					ctx.eq(int((e as Dictionary).get("value", -1)), 4, "action=4（stiff 小颤抖）")
				ctx.is_true(not String((e as Dictionary).get("raw", "")).is_empty(),
						"事件带可读 raw 指令（%s）" % kind)
			ctx.eq(appears, 2, "第 2 行推导 2 个 appear（槽 1/5 首次登场）")
			ctx.eq(actions, 1, "第 2 行推导 1 个 action")
			ctx.eq(first_kind, "appear", "事件顺序：appear 优先于 action")
			ctx.is_true("appear" in kinds_list, "事件列表含 appear")

			var env: Dictionary = l1.derive_environment(l0)
			ctx.eq(bool(env.get("bg_changed", true)), false, "同背景：bg_changed == false")
			ctx.eq(String(env.get("bg_friendly_name", "")), "BG_RuinUndergroundPassage", "环境：背景名")
			ctx.eq(bool(env.get("transition_changed", false)), true, "环境：transition 变化")
			ctx.eq(bool(env.get("bgm_changed", false)), true, "环境：bgm 变化")
			ctx.eq(int(env.get("bgm_id", 0)), 64, "环境：bgm_id 64")
			ctx.eq(bool(env.get("bgm_muted", true)), false, "环境：非静音")
			var env0: Dictionary = l0.derive_environment(null)
			ctx.eq(bool(env0.get("bg_changed", false)), true, "prev=null 视为背景变化")
			ctx.eq(bool(env0.get("bgm_muted", false)), true, "首行 bgmId=999 -> bgm_muted")

			ctx.eq(int(l1.derive_wait_ms()), 1500, "有动作/出场且无 #wait -> 自动等待 1500")
			ctx.eq(int(l2.derive_wait_ms()), -1, "无运动/气泡/显式 wait -> -1（等点击）")
			ctx.eq(int(node2.scripts[5].derive_wait_ms()), 2500, "气泡行自动等待 2500（优先于运动）")

			var built: Array = l0.build_events(null)
			ctx.gt(built.size(), 2, "build_events 事件数 > 2")
			var built_kinds: Array = []
			for e2 in built:
				built_kinds.append(String((e2 as Dictionary).get("kind", "")))
			ctx.contains(built_kinds, "environment", "build_events 含 environment")
			ctx.contains(built_kinds, "text", "build_events 含 text")
			ctx.contains(built_kinds, "wait", "build_events 含 wait")
			var last_event: Dictionary = built[built.size() - 1]
			ctx.eq(String(last_event.get("kind", "")), "wait", "build_events 最后一个事件是 wait")
			var text_event: Dictionary = {}
			for e3 in built:
				if String((e3 as Dictionary).get("kind", "")) == "text":
					text_event = e3
			ctx.eq(String(text_event.get("text", "")), l0.text, "text 事件带原文")
			ctx.eq(String(text_event.get("speaker_name", "")), "", "纯旁白行 speaker_name 为空")
			# 第 2 行说话槽 0 是「02」（无立绘说话槽），speaker_name 应为 02
			var built1: Array = l1.build_events(l0)
			var text_event1: Dictionary = {}
			for e4 in built1:
				if String((e4 as Dictionary).get("kind", "")) == "text":
					text_event1 = e4
			ctx.eq(String(text_event1.get("speaker_name", "")), "02", "第 2 行 speaker_name == 02")

		# PlayScript 入口标题/页眉（标题卡用）
		var ps2: PlayScript = sample2.compile()
		ctx.not_null(ps2, "真实样本可编译（入口信息用）")
		if ps2 != null:
			ctx.eq(String(ps2.entry_title), "初遇", "PlayScript.entry_title == 初遇")
			ctx.eq(String(ps2.entry_header), "Kei", "PlayScript.entry_header == Kei")
			var ps2b: PlayScript = PlayScript.from_dict(ps2.to_dict())
			ctx.not_null(ps2b, "PlayScript .aac round-trip 再解析")
			if ps2b != null:
				ctx.eq(String(ps2b.entry_title), "初遇", ".aac 往返保留 entry_title")
				ctx.eq(String(ps2b.entry_header), "Kei", ".aac 往返保留 entry_header")
