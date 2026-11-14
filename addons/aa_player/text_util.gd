class_name AaText
extends RefCounted
## 额外指令 `#...` 与台词内联标记 `[size]/[颜色]/[ruby]` 的解析工具。
## 优先使用 aa_core 的 AaCommands（to_bbcode/parse_extra）与 AaEnums；core 未就绪/表缺项时
## 用本文件的兜底实现，保证播放器单独也能跑。

## 过渡 ID -> 名字的兜底（完整 61 条由 aa_core 的 AaEnums.TRANSITIONS 提供；这里只放兜底）
const TRANSITION_FALLBACK := {
	0: "None",
	4004024664: "Crossfade 1000 >>",
	3854440696: "Crossfade 500 >>",
	1408872282: "Fade 250 >> 250",
	2130373248: "Fade 500 >> 500",
	1122508889: "Fade 1000 >> 1000",
	509674679: "Fade 1500 >> 1500",
	2482233134: "Fade 2000 >> 2000",
	1606908815: "Fade 2500 >> 2500",
	2752031158: "Fade 3000 >> 3000",
	1238175709: "Fade 4000 >> 4000",
	3411222921: "Fade 5000 >> 5000",
	259497043: "Fade >> 4000", 1272583944: "Fade 4000 >>",
	2457385855: "Fade >> 2000", 2243764445: "Fade 2000 >>",
	2127590351: "Fade >> 1500", 4203358158: "Fade 1500 >>",
	2136104277: "Fade >> 1000", 348351892: "Fade 1000 >>",
	1974926776: "Fade >> 500", 2046503352: "Fade 500 >>",
	326824049: "Fade >> 250", 2089682509: "Fade 250 >>",
	3868567233: "Fade White 250 >> 250", 2246884625: "Fade White 500 >> 500",
	3182852162: "Fade White 1000 >> 1000", 1289388507: "Fade White 1500 >> 1500",
	3785883235: "Fade White 2000 >> 2000", 3181383424: "Fade White 2500 >> 2500",
	1346493585: "Fade White 3000 >> 3000", 4075662009: "Fade White 4000 >> 4000",
	3539052749: "Fade White 5000 >> 5000",
	375948222: "Crossfade 200 >>", 4187997050: "Crossfade 300 >>",
	1173843909: "Crossfade 1500 >>", 1369285246: "Crossfade 2000 >>",
	3054018111: "Crossfade 2500 >>", 1027503790: "Crossfade 3000 >>",
	3196842123: "Crossfade 3500 >>", 2091508330: "Crossfade 4000 >>",
	1127535352: "Swipe R", 3957412172: "Swipe L",
	3029168926: "Swipe D", 4152299906: "Swipe U",
	3344317924: "Noise", 1914875660: "Circle",
}
const DEFAULT_BASE_FONT_SIZE := 34

## aa_core 脚本缓存：{path: Script 或 null}
static var _core_scripts: Dictionary = {}
## to_bbcode 递归保护（core 的 to_bbcode 内部若回调本文件时避免死循环）
static var _in_bbcode := false

## 解析 additionalPrompt，返回 [{name,args,raw,slot,fx}]。
## 支持两种写法：
##   环境指令   #wait;500 / #bgshake / #st;[0,-400];serial;60;
##   栏位指令   #1;hide / #2;m4 / #3;al / #4;fx;{shot}
static func parse_extra(prompt: Variant) -> Array:
	var out: Array = []
	if prompt == null:
		return out
	var text := String(prompt)
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty() or not line.begins_with("#"):
			continue
		var body := line.substr(1)
		var parts := body.split(";")
		if parts.is_empty():
			continue
		var cmd := {"name": "", "args": [], "raw": line, "slot": -1, "fx": ""}
		var first := parts[0].strip_edges()
		if first.is_valid_int():
			cmd["slot"] = int(first)
			if parts.size() > 1:
				cmd["name"] = parts[1].strip_edges()
			cmd["args"] = _tail(parts, 2)
		else:
			cmd["name"] = first
			cmd["args"] = _tail(parts, 1)
		if cmd["name"] == "fx" and cmd["args"].size() > 0:
			cmd["fx"] = String(cmd["args"][0]).strip_edges().replace("{", "").replace("}", "")
		out.append(cmd)
	return out


static func _tail(parts: PackedStringArray, from: int) -> Array:
	var out: Array = []
	for i in range(from, parts.size()):
		out.append(parts[i].strip_edges())
	return out


static func find_command(commands: Array, name: String) -> Dictionary:
	for c in commands:
		if c is Dictionary and c.get("name", "") == name:
			return c
	return {}


static func has_command(commands: Array, name: String) -> bool:
	return not find_command(commands, name).is_empty()


## 内联标记 -> Godot RichTextLabel BBCode（兜底实现，等价于 AaCommands.to_bbcode）。
## 支持：[RRGGBB]/[RRGGBBAA] 颜色 + [-] 结束、[size=N] 60=原大小、[ruby=注音]、
## [b]/[i]/[u]/[s]、[sup]/[sub]、AA 透明度 [a0]-[f9]（近似处理）。
static func to_bbcode(text: Variant, base_size: int = DEFAULT_BASE_FONT_SIZE) -> String:
	if text == null:
		return ""
	if not _in_bbcode:
		# 优先 aa_core 的 AaCommands.to_bbcode；不可用/为空时用下面的兜底实现
		var core := core_to_bbcode(String(text), base_size)
		if not core.is_empty() or String(text).is_empty():
			return core
	var src := String(text)
	var out := ""
	var i := 0
	var n := src.length()
	var ruby_stack: Array = []
	while i < n:
		var ch := src[i]
		if ch != "[":
			out += ch
			i += 1
			continue
		var close := src.find("]", i)
		if close < 0:
			out += "[lb]"
			i += 1
			continue
		var tag := src.substr(i + 1, close - i - 1)
		var consumed := true
		if tag == "-":
			out += "[/color]"
		elif tag == "/size":
			out += "[/font_size]"
		elif tag.begins_with("size="):
			var v := tag.substr(5)
			if v.is_valid_float():
				var px := int(round(float(base_size) * float(v) / 60.0))
				out += "[font_size=%d]" % clampi(px, 6, 240)
			else:
				out += "[lb]" + tag + "]"
		elif tag.begins_with("ruby="):
			ruby_stack.append(tag.substr(5))
		elif tag == "/ruby":
			var label := ""
			if ruby_stack.size() > 0:
				label = String(ruby_stack.pop_back())
			if not label.is_empty():
				out += "[color=#9ecbff][font_size=%d]（%s）[/font_size][/color]" % [
					int(base_size * 0.55), label]
		elif tag == "b":
			out += "[b]"
		elif tag == "/b":
			out += "[/b]"
		elif tag == "i":
			out += "[i]"
		elif tag == "/i":
			out += "[/i]"
		elif tag == "u":
			out += "[u]"
		elif tag == "/u":
			out += "[/u]"
		elif tag == "s":
			out += "[s]"
		elif tag == "/s":
			out += "[/s]"
		elif tag == "sup":
			out += "[font_size=%d]" % int(base_size * 0.6)
		elif tag == "sub":
			out += "[font_size=%d]" % int(base_size * 0.6)
		elif tag == "/sup" or tag == "/sub":
			out += "[/font_size]"
		elif _is_hex_color(tag):
			out += "[color=#%s]" % tag
		elif _is_alpha_tag(tag):
			out += "[color=#ffffff%s]" % tag
		else:
			# 未知标记按字面显示，避免 RichTextLabel 报错
			out += "[lb]" + tag + "]"
		if consumed:
			i = close + 1
	return out


static func _is_hex_color(tag: String) -> bool:
	if tag.length() != 6 and tag.length() != 8:
		return false
	for c in tag:
		if not ((c >= "0" and c <= "9") or (c >= "a" and c <= "f") or (c >= "A" and c <= "F")):
			return false
	return true


static func _is_alpha_tag(tag: String) -> bool:
	if tag.length() != 2:
		return false
	return _is_hex_color("000000" + tag) and (tag[0].to_lower() == "a" or (tag[0] >= "0" and tag[0] <= "9") or (tag[0].to_lower() >= "a" and tag[0].to_lower() <= "f"))


## 去掉内联标记得到纯文本（用于打字机长度估算/历史记录搜索）。
static func strip_inline(text: Variant) -> String:
	if text == null:
		return ""
	var src := String(text)
	var out := ""
	var i := 0
	var n := src.length()
	while i < n:
		var ch := src[i]
		if ch == "[":
			var close := src.find("]", i)
			if close >= 0:
				var tag := src.substr(i + 1, close - i - 1)
				if _is_known_tag(tag):
					i = close + 1
					continue
		out += ch
		i += 1
	return out


static func _is_known_tag(tag: String) -> bool:
	if tag in ["-", "/size", "/ruby", "/b", "/i", "/u", "/s", "/sup", "/sub", "b", "i", "u", "s", "sup", "sub"]:
		return true
	if tag.begins_with("size=") or tag.begins_with("ruby="):
		return true
	return _is_hex_color(tag) or _is_alpha_tag(tag)


static func plain_length(text: Variant) -> int:
	return strip_inline(text).length()


## #zmc 参数解析：#zmc;mode;X,Y;缩放系数;持续时间
## 返回 {mode, center:Vector2, zoom:float, duration:float}
static func parse_zmc(cmd: Dictionary) -> Dictionary:
	var args: Array = cmd.get("args", [])
	var mode := "instant"
	var center := Vector2.ZERO
	var zoom := 1.0
	var duration := 0.0
	if args.size() > 0 and not String(args[0]).is_empty():
		mode = String(args[0])
	if args.size() > 1:
		var xy := String(args[1]).replace("[", "").replace("]", "").split(",")
		if xy.size() >= 2:
			center = Vector2(float(xy[0]), float(xy[1]))
	if args.size() > 2 and String(args[2]).is_valid_float():
		var coeff := float(args[2])
		if coeff > 1.0:
			zoom = 3160.0 / coeff
	if args.size() > 3 and String(args[3]).is_valid_float():
		duration = float(args[3]) / 1000.0
	return {"mode": mode, "center": center, "zoom": zoom, "duration": duration}


## #st / #stm 参数解析：#st;[X,Y];mode;字体大小;
## 返回 {center:Vector2, mode, size:int}
static func parse_screen_text(cmd: Dictionary) -> Dictionary:
	var args: Array = cmd.get("args", [])
	var pos := Vector2.ZERO
	var mode := "instant"
	var font_size := 50
	if args.size() > 0:
		var xy := String(args[0]).replace("[", "").replace("]", "").split(",")
		if xy.size() >= 2:
			pos = Vector2(float(xy[0]), float(xy[1]))
	if args.size() > 1 and not String(args[1]).is_empty():
		mode = String(args[1])
	if args.size() > 2 and String(args[2]).is_valid_int():
		font_size = int(args[2])
	return {"pos": pos, "mode": mode, "size": font_size, "centered": cmd.get("name", "st") == "stm"}


## 表情符号 ID -> 占位文本（无资源时显示；AaEnums 就绪后优先用其 symbol/zh）。
const EMOTICONS := {
	0: "怒筋", 1: "叽喳", 2: "…", 3: "!", 4: "♥", 5: "♪", 6: "?",
	7: "反应", 8: "///", 9: "?!", 10: "冷汗", 11: "闪亮", 12: "难过",
	13: "走神", 14: "灵光", 15: "悲伤", 16: "叹气", 17: "蒸汽", 18: "落泪", 19: "ZZZ",
}



# ---------------------------------------------------------------- aa_core 桥接

static func _core_script(path: String) -> Script:
	if _core_scripts.has(path):
		return _core_scripts[path]
	var script: Script = null
	if FileAccess.file_exists(path):
		script = load(path)
	_core_scripts[path] = script
	return script


static func _core_const(table_name: String) -> Dictionary:
	var script := _core_script("res://addons/aa_core/enums.gd")
	if script == null:
		return {}
	var map: Dictionary = script.get_script_constant_map()
	var table: Variant = map.get(table_name, {})
	return table if table is Dictionary else {}


## aa_core 的 AaCommands.to_bbcode；core 未就绪或调用失败返回空串由调用方兜底。
static func core_to_bbcode(text: String, base_size: int = DEFAULT_BASE_FONT_SIZE) -> String:
	var script := _core_script("res://addons/aa_core/command_parser.gd")
	if script == null:
		return ""
	if not _script_has_static(script, "to_bbcode"):
		return ""
	_in_bbcode = true
	var r: Variant = script.call("to_bbcode", text, base_size)
	_in_bbcode = false
	return str(r) if r != null else ""


static func _script_has_static(script: Script, method_name: String) -> bool:
	if not (script is GDScript):
		return false
	for m in script.get_script_method_list():
		if str(m.get("name", "")) == method_name:
			return true
	return false


# ---------------------------------------------------------------- 枚举显示

## 表情符号 -> 气泡文本（优先 AaEnums 的中文名，字体一定包含；否则用内置表）
static func emoticon_text(emoticon_id: int) -> String:
	if emoticon_id < 0:
		return ""
	var table := _core_const("EMOTICONS")
	if table.has(emoticon_id):
		var item: Variant = table[emoticon_id]
		if item is Dictionary:
			var zh := str(item.get("zh", ""))
			if not zh.is_empty():
				return zh
	var fallback: Dictionary = EMOTICONS
	return str(fallback.get(emoticon_id, str(emoticon_id)))


## 背景效果 -> 显示名（优先 AaEnums.BG_EFFECTS）
static func bg_effect_label(effect_id: int) -> String:
	if effect_id <= 0:
		return ""
	var table := _core_const("BG_EFFECTS")
	if table.has(effect_id):
		var item: Variant = table[effect_id]
		if item is Dictionary:
			var zh := str(item.get("zh", ""))
			var en := str(item.get("name", ""))
			if not zh.is_empty() and zh != "未知背景效果(%d)" % effect_id:
				return zh
			if not en.is_empty() and not en.begins_with("Unknown"):
				return en
	return "背景效果 #%d（占位）" % effect_id


## 过渡 ID -> 视觉参数 {kind, duration, name}。
## kind: cut / fade(黑) / fade_white / crossfade(溶解) / swipe_l/r/u/d / noise / circle
static func transition_info(transition_id: int) -> Dictionary:
	if transition_id == 0:
		return {"kind": "cut", "duration": 0.0, "name": "None"}
	var name := ""
	var duration := 0.0
	var table := _core_const("TRANSITIONS")
	if table.has(transition_id):
		var item: Variant = table[transition_id]
		if item is Dictionary:
			var it: Dictionary = item
			name = str(it.get("name", ""))
			var g := str(it.get("group", ""))
			if g.is_empty() or g == "unknown":
				name = ""
			else:
				duration = float(it.get("duration", 0)) / 1000.0
	if name.is_empty():
		name = str(TRANSITION_FALLBACK.get(transition_id, ""))
	if name.is_empty():
		return {"kind": "fade", "duration": 0.45, "name": "Unknown_%d" % transition_id}
	var kind := "fade"
	var low := name.to_lower()
	if low.begins_with("crossfade"):
		kind = "crossfade"
	elif low.begins_with("fade white"):
		kind = "fade_white"
	elif low.begins_with("fade"):
		kind = "fade"
	elif low.begins_with("swipe r"):
		kind = "swipe_r"
	elif low.begins_with("swipe l"):
		kind = "swipe_l"
	elif low.begins_with("swipe d"):
		kind = "swipe_d"
	elif low.begins_with("swipe u"):
		kind = "swipe_u"
	elif low.begins_with("noise"):
		kind = "noise"
	elif low.begins_with("circle"):
		kind = "circle"
	if duration <= 0.0:
		# 从名字里抠时长："Crossfade 1000 >>" / "Fade 500 >> 500" / "Fade >> 2000"
		var nums: Array = []
		for token in name.replace(">>", " ").split(" "):
			if token.is_valid_int():
				nums.append(int(token))
		if nums.size() > 0:
			duration = float(nums[nums.size() - 1]) / 1000.0
		else:
			duration = 0.5
	return {"kind": kind, "duration": clampf(duration, 0.15, 5.0), "name": name}
