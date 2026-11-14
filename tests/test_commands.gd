extends RefCounted
## test_commands.gd —— `#额外指令` 解析 + `[内联标记]` → BBCode / 纯文本。
##
## 覆盖 docs/DESIGN.md §5.1 `AaCommands` 与 docs/spec/commands.md：
##   * 额外指令：`#wait` / `#bgshake` / `#fx;AronaTouch` / `#zmc` / `#st/#stm` / `#clearST` /
##     `#hidemenu/#showmenu` / `#N;fx;{shot}` / `#N;m N` / `#N;hide` / `#N;al|ar|a|dl|dr|d` /
##     `#nextepisode;H;T`，多行、未知指令容错、空输入；
##   * 结构化解析：wait_ms / parse_zmc / parse_screen_text / parse_shot / parse_move /
##     parse_next_episode / parse_vec2；
##   * 内联标记：`[size=200]`、`[FF0000]颜色[-]`、`[ruby=注音]`、`[b][i][u][s]`、嵌套、
##     `[-]` 结束色、透明度标记、未知标记转义；to_bbcode 产物能被 RichTextLabel 正确渲染，
##     strip_inline 得到可读纯文本；ruby_pairs 提取注音对；
##   * 与真实样本 additionalPrompt（#bgshake / #wait;0）联调。
##
## 依赖 aa_core（core-dev）。

const Fw = preload("res://tests/framework.gd")

const SAMPLE := "res://fixtures/aap/sample_kei_01.aap"


func run(ctx: Fw.Ctx) -> void:
	var CS := ctx.need("res://addons/aa_core/command_parser.gd", "core-dev")
	if CS == null:
		return
	if not ctx.need_methods(CS, ["parse_extra", "parse_command", "parse_inline",
			"to_bbcode", "strip_inline", "ruby_pairs", "wait_ms", "parse_zmc",
			"parse_screen_text", "parse_shot", "parse_move", "parse_next_episode",
			"parse_vec2"], "core-dev"):
		return

	# ---------------------------------------------------------------- 1. 额外指令表
	# 每项：[prompt, 期望条数, 期望 name(小写), 期望 args(前缀匹配，空数组=不检查), slot, fx]
	var cases := [
		["#wait;5000", 1, "wait", ["5000"], -1, ""],
		["#bgshake", 1, "bgshake", [], -1, ""],
		["#fx;AronaTouch", 1, "fx", ["AronaTouch"], -1, "AronaTouch"],
		["#zmc;instant;300,-150;2160", 1, "zmc", ["instant", "300,-150", "2160"], -1, ""],
		["#st;[-1200,-430];serial;60;", 1, "st", ["[-1200,-430]", "serial", "60"], -1, ""],
		["#stm;[0,-430];instant;90;", 1, "stm", ["[0,-430]", "instant", "90"], -1, ""],
		["#clearST", 1, "clearst", [], -1, ""],
		["#hidemenu", 1, "hidemenu", [], -1, ""],
		["#showmenu", 1, "showmenu", [], -1, ""],
		["#3;fx;{shot}", 1, "fx", ["{shot}"], 3, "shot"],
		["#3;m 2", 1, "m", ["2"], 3, ""],
		["#4;m4", 1, "m", ["4"], 4, ""],
		["#2;hide", 1, "hide", [], 2, ""],
		["#1;al", 1, "al", [], 1, ""],
		["#2;ar", 1, "ar", [], 2, ""],
		["#3;a", 1, "a", [], 3, ""],
		["#4;dl", 1, "dl", [], 4, ""],
		["#5;dr", 1, "dr", [], 5, ""],
		["#1;d", 1, "d", [], 1, ""],
		["#nextepisode;Kei;下一话", 1, "nextepisode", ["Kei", "下一话"], -1, ""],
		["#2;em;[재잘]", 1, "em", ["[재잘]"], 2, ""],
		["#1;h", 1, "h", [], 1, ""],
	]
	for c in cases:
		var prompt := String(c[0])
		var cmds: Array = CS.parse_extra(prompt)
		ctx.eq(cmds.size(), int(c[1]), "parse_extra(%s) 条数" % prompt)
		if cmds.size() != int(c[1]) or cmds.is_empty():
			continue
		var cmd = cmds[0]
		var name := String(ctx.prop(cmd, "name", ""))
		var args: Array = _args(ctx, cmd)
		var raw := String(ctx.prop(cmd, "raw", ""))
		var slot := int(ctx.prop(cmd, "slot", -99))
		var fx := String(ctx.prop(cmd, "fx", ""))
		ctx.eq(name, String(c[2]), "指令名 %s" % prompt)
		ctx.eq(raw, prompt, "raw 保留原文 %s" % prompt)
		ctx.eq(slot, int(c[4]), "槽位 %s" % prompt)
		if not String(c[5]).is_empty():
			ctx.eq(fx, String(c[5]), "fx 去花括号 %s" % prompt)
		var expected_args: Array = c[3]
		if not expected_args.is_empty():
			ctx.gte(args.size(), expected_args.size(), "参数个数 %s" % prompt)
			for ai in range(mini(args.size(), expected_args.size())):
				ctx.eq(String(args[ai]), String(expected_args[ai]), "参数[%d] %s" % [ai, prompt])

	# 参数保留空串（#st 结尾分号）：args 末尾空串
	var st_cmd = CS.parse_extra("#st;[100,100];instant;200;")[0]
	var st_args: Array = _args(ctx, st_cmd)
	ctx.eq(st_args.size(), 4, "#st;...; 参数切分保留 4 段（含末尾空串）")
	if st_args.size() == 4:
		ctx.eq(String(st_args[3]), "", "#st 末尾分号 -> 空串参数")

	# 多行指令 / 未知指令 / 空输入 / 非 # 行
	var multi: Array = CS.parse_extra("#wait;5000\n#bgshake\n#clearST")
	ctx.eq(multi.size(), 3, "多行 additionalPrompt 解析 3 条")
	if multi.size() == 3:
		ctx.eq(String(ctx.prop(multi[0], "name", "")), "wait", "多行第 1 条 wait")
		ctx.eq(String(ctx.prop(multi[1], "name", "")), "bgshake", "多行第 2 条 bgshake")
		ctx.eq(String(ctx.prop(multi[2], "name", "")), "clearst", "多行第 3 条 clearst")
	ctx.eq(CS.parse_extra("").size(), 0, "空 prompt -> 0 条")
	ctx.eq(CS.parse_extra("   \n  ").size(), 0, "空白 prompt -> 0 条")
	var unknown: Array = CS.parse_extra("#weirdcmd;abc")
	ctx.eq(unknown.size(), 1, "未知指令也保留（容错）")
	if unknown.size() == 1:
		ctx.eq(String(ctx.prop(unknown[0], "name", "")), "weirdcmd", "未知指令 name 保留小写")
		ctx.eq(_args(ctx, unknown[0]).size(), 1, "未知指令参数保留")
	ctx.eq(CS.parse_extra("not-a-command").size(), 0, "不以 # 开头的行忽略")
	# 大小写不敏感
	var upper: Array = CS.parse_extra("#WAIT;200")
	ctx.eq(upper.size(), 1, "#WAIT 可解析")
	if upper.size() == 1:
		ctx.eq(String(ctx.prop(upper[0], "name", "")), "wait", "指令名规范化为小写")

	# ---------------------------------------------------------------- 2. 结构化解析工具
	var wait_cmd = CS.parse_extra("#wait;5000")[0]
	ctx.eq(int(CS.wait_ms(wait_cmd)), 5000, "wait_ms(#wait;5000) == 5000")
	ctx.eq(int(CS.wait_ms(CS.parse_extra("#bgshake")[0])), 0, "wait_ms(非 wait) == 0")

	var zmc: Dictionary = CS.parse_zmc(CS.parse_extra("#zmc;smooth;-650,-450;1860;500")[0])
	ctx.eq(String(zmc.get("mode", "")), "smooth", "parse_zmc mode")
	ctx.eq(zmc.get("center"), Vector2(-650, -450), "parse_zmc center")
	ctx.almost_eq(zmc.get("scale"), 1860.0, 1e-3, "parse_zmc scale")
	ctx.eq(int(zmc.get("duration", 0)), 500, "parse_zmc duration")

	var st: Dictionary = CS.parse_screen_text(CS.parse_extra("#st;[-1200,-430];serial;60;")[0])
	ctx.eq(bool(st.get("centered", true)), false, "parse_screen_text #st 非居中")
	ctx.eq(st.get("pos"), Vector2(-1200, -430), "parse_screen_text pos")
	ctx.eq(String(st.get("mode", "")), "serial", "parse_screen_text mode")
	ctx.almost_eq(st.get("font_size"), 60.0, 1e-3, "parse_screen_text font_size")
	var stm: Dictionary = CS.parse_screen_text(CS.parse_extra("#stm;[0,-430];instant;90;")[0])
	ctx.eq(bool(stm.get("centered", false)), true, "parse_screen_text #stm 居中")

	ctx.eq(int(CS.parse_shot(CS.parse_extra("#3;fx;{shot}")[0])), 3, "parse_shot 槽位 3")
	ctx.eq(int(CS.parse_shot(CS.parse_extra("#3;fx;AronaTouch")[0])), -1, "parse_shot 非 shot 返回 -1")
	ctx.eq(int(CS.parse_shot(CS.parse_extra("#fx;{shot}")[0])), -1, "parse_shot 无槽位返回 -1")

	var move: Dictionary = CS.parse_move(CS.parse_extra("#3;m 2")[0])
	ctx.eq(int(move.get("slot", -1)), 3, "parse_move slot")
	ctx.eq(int(move.get("pos", -1)), 2, "parse_move pos")

	var ne: Dictionary = CS.parse_next_episode(CS.parse_extra("#nextepisode;Kei;下一话")[0])
	ctx.eq(String(ne.get("header", "")), "Kei", "parse_next_episode header")
	ctx.eq(String(ne.get("title", "")), "下一话", "parse_next_episode title")

	ctx.eq(CS.parse_vec2("0,0"), Vector2.ZERO, "parse_vec2 0,0")
	ctx.eq(CS.parse_vec2("[100,100]"), Vector2(100, 100), "parse_vec2 带方括号")
	ctx.eq(CS.parse_vec2("-650,-450"), Vector2(-650, -450), "parse_vec2 负数")
	ctx.eq(CS.parse_vec2("bad"), Vector2.ZERO, "parse_vec2 非法输入不崩")

	# ---------------------------------------------------------------- 3. 内联标记：parse_inline
	var runs: Array = CS.parse_inline("[size=200]x[/size]")
	ctx.eq(runs.size(), 3, "parse_inline([size]) 3 个 run")
	if runs.size() == 3:
		ctx.eq(String(runs[0].get("type", "")), "open", "run0 open")
		ctx.eq(String(runs[0].get("tag", "")), "size", "run0 tag=size")
		ctx.eq(String(runs[1].get("type", "")), "text", "run1 text")
		ctx.eq(String(runs[1].get("text", "")), "x", "run1 内容 x")
		ctx.eq(String(runs[2].get("type", "")), "close", "run2 close")
	var color_runs: Array = CS.parse_inline("[FF0000]红[-]")
	ctx.eq(color_runs.size(), 3, "parse_inline(颜色) 3 个 run")
	if color_runs.size() == 3:
		ctx.eq(String(color_runs[0].get("tag", "")), "color", "颜色 open tag=color")
		ctx.eq(String(color_runs[0].get("value", "")), "FF0000", "颜色值规整大写")
		ctx.eq(String(color_runs[2].get("tag", "")), "color", "[-] 解析为 color close")
	var ruby_runs: Array = CS.parse_inline("[ruby=z]汉[/ruby]")
	ctx.eq(ruby_runs.size(), 3, "parse_inline(注音) 3 个 run")
	if ruby_runs.size() == 3:
		ctx.eq(String(ruby_runs[0].get("tag", "")), "ruby", "注音 open tag=ruby")
		ctx.eq(String(ruby_runs[0].get("value", "")), "z", "注音 value=z")
	# 未知标记保留结构化 raw
	var unk_runs: Array = CS.parse_inline("前[foo]后")
	ctx.gte(unk_runs.size(), 2, "未知标记产生 unknown run")
	var has_unknown := false
	for r in unk_runs:
		if String((r as Dictionary).get("type", "")) == "unknown":
			has_unknown = true
			ctx.eq(String((r as Dictionary).get("raw", "")), "[foo]", "unknown run 保留原文")
	ctx.is_true(has_unknown, "未知标记类型是 unknown（不崩）")

	# ---------------------------------------------------------------- 4. strip_inline
	var strip_cases := [
		["[size=200]x[/size]", "x"],
		["[FF0000]红[-]", "红"],
		["[ruby=z]汉[/ruby]", "汉"],
		["A[size=100][ruby=x]汉[/ruby][/size]B", "A汉B"],
		["[b]粗[/b][i]斜[/i][u]下[/u][s]删[/s]", "粗斜下删"],
		["普通文本", "普通文本"],
		["[00]透明字", "透明字"],
		["[foo]bar", "[foo]bar"],
		["", ""],
	]
	for sc in strip_cases:
		ctx.eq(String(CS.strip_inline(String(sc[0]))), String(sc[1]), "strip_inline(%s)" % sc[0])
	# 幂等：去标记后再去标记不变
	var once: String = CS.strip_inline("[size=200][FF0000]红[/size][-]")
	ctx.eq(CS.strip_inline(once), once, "strip_inline 幂等")

	# ---------------------------------------------------------------- 5. to_bbcode
	ctx.eq(CS.to_bbcode("[size=200]大[/size]", 60), "[font_size=200]大[/font_size]",
			"to_bbcode size 按 base=60 1:1 映射")
	var bb_default: String = CS.to_bbcode("[size=200]大[/size]", 48)
	ctx.contains(bb_default, "[font_size=160]", "to_bbcode 默认 base=48 时 200 -> 160px")
	ctx.contains(bb_default, "[/font_size]", "size 有闭合标签")

	var bb_color: String = CS.to_bbcode("[FF0000]红[-]")
	ctx.contains(bb_color, "[color=#FF0000]", "颜色标记 -> [color=#FF0000]")
	ctx.contains(bb_color, "[/color]", "[-] -> [/color]")
	ctx.contains(bb_color, "红", "颜色标记保留文字")
	ctx.contains(CS.to_bbcode("[aa00cc]字[-]"), "[color=#AA00CC]", "小写颜色规整为大写")

	var bb_ruby: String = CS.to_bbcode("[ruby=z]汉[/ruby]")
	ctx.eq(bb_ruby, "汉（z）", "ruby 降级为「文字（注音）」（Godot 不支持原生注音）")
	ctx.not_contains(bb_ruby, "[ruby", "ruby 不原样透传给 RichTextLabel")

	ctx.eq(CS.to_bbcode("[b]粗[/b]"), "[b]粗[/b]", "b 标记透传")
	ctx.eq(CS.to_bbcode("x[sup]2[/sup]"), "x2", "sup 标签丢弃、文字保留")
	ctx.eq(CS.to_bbcode("[00]淡"), "淡", "两字符透明度标记丢弃标签")
	var bb_nested: String = CS.to_bbcode("[size=200][FF0000]xxx[/size][-]", 60)
	ctx.contains(bb_nested, "[font_size=200]", "嵌套：size 生效")
	ctx.contains(bb_nested, "[color=#FF0000]", "嵌套：颜色生效")
	ctx.contains(bb_nested, "xxx", "嵌套：文字保留")
	# 未知标记转义，防止 RichTextLabel 吞字
	var bb_unknown: String = CS.to_bbcode("[foo]bar")
	ctx.contains(bb_unknown, "[lb]foo[rb]", "未知标记转义为 [lb]...[rb]")
	ctx.contains(bb_unknown, "bar", "未知标记后的文字保留")

	# RichTextLabel 实渲染验证：可见文字 == strip_inline（ruby 例外，会追加注音）
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	ctx.root_node().add_child(rt)
	var render_cases := [
		"[size=200]x[/size]",
		"[FF0000]红[-]",
		"[size=100][FF0000]红[-][/size]",   # 正确嵌套
		"普通文本",
	]
	for rc in render_cases:
		rt.text = ""
		rt.text = CS.to_bbcode(String(rc), 60)
		ctx.eq(rt.get_parsed_text(), CS.strip_inline(String(rc)),
				"RichTextLabel 渲染 %s 的可见文字正确" % rc)
	rt.text = ""
	rt.text = CS.to_bbcode("[ruby=z]汉[/ruby]")
	ctx.contains(rt.get_parsed_text(), "汉", "RichTextLabel 渲染注音保留正文")
	ctx.contains(rt.get_parsed_text(), "（z）", "RichTextLabel 渲染注音降级内容")
	# 交叉嵌套（size 先关、color 后关；AA 语料里实际不存在，但解析器应容错）：
	# Q-004 修复后 to_bbcode 会配平标签，RichTextLabel 必须渲染出干净的可见文字。
	rt.text = ""
	rt.text = CS.to_bbcode("[size=100][FF0000]红[/size][-]", 60)
	ctx.eq(rt.get_parsed_text(), "红", "交叉嵌套标记配平后 RichTextLabel 正确渲染（Q-004 已修复）")
	ctx.not_contains(rt.get_parsed_text(), "[/font_size]", "交叉嵌套不再把字面闭合标签当文字渲染")

	# 行为契约（不锁 to_bbcode 精确输出串，Q-004 修复后由 core-dev 建议）：
	# 1) 输出标签开/闭数量配平；
	# 2) RichTextLabel 可见文字 == strip_inline（不丢不增，ruby 会追加注音故单独测）；
	# 3) 未闭合标签不泄漏字面 [ / ]。
	var bb_inputs := [
		"[size=200]x[/size]", "[FF0000]红[-]", "[size=100][FF0000]红[/size][-]",
		"[b]粗[/b][i]斜[/i]", "[ruby=z]汉[/ruby]", "[size=200]xx", "前缀[AA00CC]色[-]后缀",
	]
	for bi in bb_inputs:
		var out_bb: String = CS.to_bbcode(String(bi), 60)
		var balance := _tag_balance(out_bb)
		var unbalanced: Array = []
		for tag in balance:
			if int(balance[tag]) != 0:
				unbalanced.append("%s=%d" % [str(tag), int(balance[tag])])
		ctx.eq(unbalanced.size(), 0, "to_bbcode(%s) 标签开闭配平：%s" % [bi, str(unbalanced)])
	for vi in bb_inputs:
		rt.text = ""
		rt.text = CS.to_bbcode(String(vi), 60)
		if String(vi).contains("[ruby="):
			continue  # ruby 降级会追加「（注音）」，可见文字与纯文本不同
		ctx.eq(rt.get_parsed_text(), CS.strip_inline(String(vi)),
				"RichTextLabel 可见文字 == strip_inline：%s" % vi)
	for ui in ["[size=200]xx", "[FF0000]红", "[b]粗"]:
		rt.text = ""
		rt.text = CS.to_bbcode(String(ui), 60)
		var unclosed_parsed: String = rt.get_parsed_text()
		ctx.not_contains(unclosed_parsed, "[", "未闭合标记渲染不泄漏字面 [：%s" % ui)
		ctx.not_contains(unclosed_parsed, "]", "未闭合标记渲染不泄漏字面 ]：%s" % ui)
	rt.queue_free()

	# ---------------------------------------------------------------- 6. ruby_pairs
	var pairs: Array = CS.ruby_pairs("前[ruby=zhuyin]汉[/ruby]后")
	ctx.eq(pairs.size(), 1, "ruby_pairs 找到 1 组注音")
	if pairs.size() == 1:
		ctx.eq(String((pairs[0] as Dictionary).get("text", "")), "汉", "ruby_pairs 正文")
		ctx.eq(String((pairs[0] as Dictionary).get("ruby", "")), "zhuyin", "ruby_pairs 注音")
	ctx.eq(CS.ruby_pairs("没有注音").size(), 0, "ruby_pairs 无注音 -> 空")

	# ---------------------------------------------------------------- 7. 与真实样本联调
	var sample_json: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAMPLE))
	ctx.is_true(sample_json is Dictionary, "真实样本可解析（联调）")
	if sample_json is Dictionary:
		var prompts: Array = []
		var inline_texts: Array = []
		var nodes: Array = (sample_json as Dictionary)["nodes"]["$values"]
		for n in nodes:
			if String((n as Dictionary).get("$type", "")).contains("ScriptNodeData"):
				for row in ((n as Dictionary).get("Scripts", {}) as Dictionary).get("$values", []):
					var ap := String((row as Dictionary).get("additionalPrompt", ""))
					if not ap.is_empty():
						prompts.append(ap)
					inline_texts.append(String((row as Dictionary).get("text", "")))
		ctx.eq(prompts.size(), 2, "样本里 2 条非空 additionalPrompt")
		var sample_cmds: Array = []
		for p in prompts:
			sample_cmds.append_array(CS.parse_extra(String(p)))
		ctx.eq(sample_cmds.size(), 2, "样本指令共 2 条（#wait;0 与 #bgshake）")
		var names: Array = []
		for c in sample_cmds:
			names.append(String(ctx.prop(c, "name", "")))
		ctx.is_true("wait" in names, "样本含 #wait")
		ctx.is_true("bgshake" in names, "样本含 #bgshake")
		# 样本台词没有内联标记，strip 后应等于原文
		var bad_strip := 0
		for t in inline_texts:
			if CS.strip_inline(String(t)) != String(t):
				bad_strip += 1
		ctx.eq(bad_strip, 0, "样本 169 行台词无内联标记，strip_inline 恒等")


## 兼容 ExtraCommand 是内部 class（Object）或 Dictionary 两种实现。
func _args(ctx: Fw.Ctx, cmd: Variant) -> Array:
	if cmd is Dictionary:
		return Array((cmd as Dictionary).get("args", []))
	var a: Variant = ctx.prop(cmd, "args", [])
	if a is PackedStringArray:
		return Array(a)
	if a is Array:
		return a
	return []


## 统计 BBCode 各标签的开/闭次数差（开 +1，闭 -1）；忽略 [lb]/[rb] 独立转义标签。
## 返回 {tag: delta}，配平则所有 delta == 0。
func _tag_balance(bbcode: String) -> Dictionary:
	var re := RegEx.new()
	re.compile("\\[(/?)([A-Za-z_]+)")
	var balance := {}
	for m in re.search_all(bbcode):
		var closing := m.get_string(1) == "/"
		var tag := m.get_string(2).to_lower()
		if tag == "lb" or tag == "rb":
			continue
		balance[tag] = int(balance.get(tag, 0)) + (-1 if closing else 1)
	return balance
