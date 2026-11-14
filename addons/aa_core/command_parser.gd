class_name AaCommands
extends RefCounted
## AA 的两种“文本内语法”解析：
## 1. `additionalPrompt` 里的 `#额外指令`（多条用 `\n` 分隔）；
## 2. 台词 `text` 里的 `[内联标记]`（size/color/ruby/粗斜体/透明度）。
##
## 文档来源：`research/halocue/docs__commands.md`、`research/aa-docs/p17/p18`。
##
## 额外指令语法：`#指令名;参数;参数...`；以数字开头是**角色槽位**形式
## （`#3;fx;{shot}` / `#2;m 4` / `#1;hide` / `#2;al`，槽位 1–5，0 号槽不发角色指令）。
## 解析结果统一为 `AaCommands.ExtraCommand`：
##   name: String            规范化小写指令名（如 "wait" / "clearst" / "fx"）
##   args: PackedStringArray 分号分隔的参数（保留空串，含 `#st` 结尾的空参数）
##   raw:  String           原始整条指令（含 `#`）
##   slot: int              角色槽位 N（无槽位形式为 -1）
##   fx:   String           `#N;fx;{shot}` / `#fx;AronaTouch` 的效果名（去花括号）
##
## 内联标记解析结果：Array，元素为 Dictionary：
##   {"type":"text", "text": "..."}
##   {"type":"open", "tag": "size"|"color"|"ruby"|"b"|"i"|"u"|"s"|"sup"|"sub"|"alpha",
##    "value": "...", "raw": "[...]"}
##   {"type":"close", "tag": "...", "raw": "[/...]"}   （`[-]` 的 tag 是 "color"）
##   {"type":"unknown", "raw": "[...]"}                 （无法识别的方括号内容，按原文保留）

# ---------------------------------------------------------------------------
# 指令名常量（避免运行时拼错）
# ---------------------------------------------------------------------------
const CMD_WAIT := "wait"
const CMD_BGSHAKE := "bgshake"
const CMD_FX := "fx"
const CMD_ZMC := "zmc"
const CMD_ST := "st"
const CMD_STM := "stm"
const CMD_CLEARST := "clearst"
const CMD_HIDEMENU := "hidemenu"
const CMD_SHOWMENU := "showmenu"
const CMD_NEXT_EPISODE := "nextepisode"
const CMD_MOVE := "m"
const CMD_HIDE := "hide"
const CMD_HIGHLIGHT := "h"
const CMD_EMOTICON := "em"
const CMD_CLOSEUP := "closeup"
const CMD_JUMP := "jump"
const CMD_NARRATION := "na"
const CMD_TITLE := "title"
const CMD_PLACE := "place"
const CMD_CONTINUED := "continued"
## 角色进出场指令名（appear 表里的 id）
const CMD_APPEAR_IDS := ["al", "ar", "a", "dl", "dr", "d"]


# ---------------------------------------------------------------------------
# ExtraCommand
# ---------------------------------------------------------------------------
class ExtraCommand extends RefCounted:
	var name: String = ""
	var args: PackedStringArray = PackedStringArray()
	var raw: String = ""
	var slot: int = -1
	var fx: String = ""

	func get_arg(index: int, fallback := "") -> String:
		if index >= 0 and index < args.size():
			return args[index]
		return fallback

	func arg_int(index: int, fallback := 0) -> int:
		var s := get_arg(index)
		if s.is_empty():
			return fallback
		return s.to_int()

	func arg_float(index: int, fallback := 0.0) -> float:
		var s := get_arg(index)
		if s.is_empty():
			return fallback
		return s.to_float()

	func has_args() -> bool:
		return args.size() > 0

	## 是否是角色槽位指令（#N;...）。
	func has_slot() -> bool:
		return slot >= 0

	func to_dict() -> Dictionary:
		return {
			"name": name,
			"args": Array(args),
			"raw": raw,
			"slot": slot,
			"fx": fx,
		}

	func _to_string() -> String:
		return raw


# ---------------------------------------------------------------------------
# 额外指令解析
# ---------------------------------------------------------------------------

## 解析 `additionalPrompt`。返回 Array[AaCommands.ExtraCommand]（不做去重，保持顺序）。
## 容错：空行忽略；不以 `#` 开头的行忽略并告警；未知指令名也保留（name = 原文小写）。
static func parse_extra(prompt: String) -> Array:
	var out: Array = []
	if prompt.is_empty():
		return out
	for raw_line in prompt.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty():
			continue
		if not line.begins_with("#"):
			push_warning("AaCommands: 额外的指令行不以 # 开头，已忽略：" + line)
			continue
		var cmd := parse_command(line)
		if cmd != null:
			out.append(cmd)
	return out


## 解析单条指令字符串（必须带 `#`；不合法返回 null）。
static func parse_command(raw: String) -> ExtraCommand:
	var line := raw.strip_edges()
	if not line.begins_with("#"):
		return null
	var cmd := ExtraCommand.new()
	cmd.raw = line
	var body := line.substr(1)
	# 槽位形式：#N;...
	var digit_end := 0
	while digit_end < body.length() and _is_digit(body.unicode_at(digit_end)):
		digit_end += 1
	if digit_end > 0:
		var after := ""
		if digit_end < body.length():
			if body.unicode_at(digit_end) == 0x3B:  # ';'
				after = body.substr(digit_end + 1)
			else:
				# 形如 #3m 4 之类：不是标准槽位写法，按普通指令名处理
				digit_end = 0
		if digit_end > 0:
			cmd.slot = body.substr(0, digit_end).to_int()
			body = after
	# 按 ';' 分段
	var parts := body.split(";", true)
	var head := ""
	if parts.size() > 0:
		head = parts[0].strip_edges()
	var args := PackedStringArray()
	if parts.size() > 1:
		for i in range(1, parts.size()):
			args.append(parts[i].strip_edges())
	# 指令名 + 内联参数（如 "m 4" / "em [재잘]" / "fx {shot}"）
	var command_name := head
	var inline_arg := ""
	var space := head.find(" ")
	if space >= 0:
		command_name = head.substr(0, space).strip_edges()
		inline_arg = head.substr(space + 1).strip_edges()
		if not inline_arg.is_empty():
			args.insert(0, inline_arg)
	cmd.name = command_name.to_lower()
	# 形如 m4 / h2 的紧凑写法
	if cmd.name.length() > 1 and (cmd.name.begins_with("m") or cmd.name.begins_with("h")):
		var rest := cmd.name.substr(1)
		if _is_all_digits(rest):
			cmd.name = cmd.name.substr(0, 1)
			args.insert(0, rest)
	cmd.args = args
	# fx 效果名（去 {}）
	if cmd.name == CMD_FX and args.size() > 0:
		cmd.fx = args[0].strip_edges().trim_prefix("{").trim_suffix("}")
	return cmd


static func _is_digit(c: int) -> bool:
	return c >= 0x30 and c <= 0x39


static func _is_all_digits(s: String) -> bool:
	if s.is_empty():
		return false
	for i in s.length():
		if not _is_digit(s.unicode_at(i)):
			return false
	return true


# ---------------------------------------------------------------------------
# 指令参数 -> 结构化数据（给 Player 用）
# ---------------------------------------------------------------------------

## `#wait;毫秒` -> 毫秒（缺省 0）。
static func wait_ms(cmd: ExtraCommand) -> int:
	return cmd.arg_int(0, 0)


## `#zmc;模式;X,Y;缩放系数;持续时间`
## -> {mode: "instant"|"smooth", center: Vector2, scale: float, duration: int}
## 缩放系数语义：实际放大倍数 = 3160 / 系数。
static func parse_zmc(cmd: ExtraCommand) -> Dictionary:
	return {
		"mode": cmd.get_arg(0, "instant").to_lower(),
		"center": parse_vec2(cmd.get_arg(1, "0,0")),
		"scale": cmd.arg_float(2, 3160.0),
		"duration": cmd.arg_int(3, 0),
	}


## `#st;[X,Y];模式;字体大小;` / `#stm;...`
## -> {centered: bool, pos: Vector2, mode: String, font_size: float}
## 屏幕文字内容在 ScriptData.text 里（不走 additionalPrompt）。
static func parse_screen_text(cmd: ExtraCommand) -> Dictionary:
	return {
		"centered": cmd.name == CMD_STM,
		"pos": parse_vec2(cmd.get_arg(0, "0,0")),
		"mode": cmd.get_arg(1, "instant").to_lower(),
		"font_size": cmd.arg_float(2, 60.0),
	}


## `#N;fx;{shot}` -> 槽位（无槽位/非 fx 返回 -1）。
static func parse_shot(cmd: ExtraCommand) -> int:
	if cmd.name == CMD_FX and cmd.slot >= 0 and cmd.fx == "shot":
		return cmd.slot
	return -1


## `#N;m 4` -> {slot, pos}
static func parse_move(cmd: ExtraCommand) -> Dictionary:
	return {"slot": cmd.slot, "pos": cmd.arg_int(0, 0)}


## `#N;hide` / `#N;al` 等 -> {slot, token}
static func parse_slot_action(cmd: ExtraCommand) -> Dictionary:
	return {"slot": cmd.slot, "token": cmd.name}


## `#nextepisode;Header;Title` -> {header, title}
static func parse_next_episode(cmd: ExtraCommand) -> Dictionary:
	return {"header": cmd.get_arg(0, ""), "title": cmd.get_arg(1, "")}


## "0,0" / "[100,100]" / "-650,-450" -> Vector2
static func parse_vec2(text: String) -> Vector2:
	var s := text.strip_edges().trim_prefix("[").trim_suffix("]")
	var parts := s.split(",", false)
	if parts.size() < 2:
		return Vector2.ZERO
	return Vector2(parts[0].strip_edges().to_float(), parts[1].strip_edges().to_float())


# ---------------------------------------------------------------------------
# 内联标记解析
# ---------------------------------------------------------------------------

const _SIMPLE_TAGS := {
	"b": true, "i": true, "u": true, "s": true, "sup": true, "sub": true,
}
const _CLOSE_TAGS := {
	"b": true, "i": true, "u": true, "s": true, "sup": true, "sub": true,
	"size": true, "ruby": true,
}


## 解析台词里的内联标记，返回扁平 run 列表（见文件头说明）。
static func parse_inline(text: String) -> Array:
	var runs: Array = []
	if text.is_empty():
		return runs
	var buffer := ""
	var i := 0
	var n := text.length()
	while i < n:
		var ch := text.unicode_at(i)
		if ch != 0x5B:  # '['
			buffer += text[i]
			i += 1
			continue
		var close := text.find("]", i)
		if close < 0:
			buffer += text.substr(i)
			break
		var inner := text.substr(i + 1, close - i - 1)
		var tag := _classify_tag(inner)
		if tag.get("type", "") == "unknown":
			# 无法识别：按原文保留（不参与样式，to_bbcode 会转义方括号）
			if not buffer.is_empty():
				runs.append({"type": "text", "text": buffer})
				buffer = ""
			tag["raw"] = text.substr(i, close - i + 1)
			runs.append(tag)
			i = close + 1
			continue
		if not buffer.is_empty():
			runs.append({"type": "text", "text": buffer})
			buffer = ""
		tag["raw"] = text.substr(i, close - i + 1)
		runs.append(tag)
		i = close + 1
	if not buffer.is_empty():
		runs.append({"type": "text", "text": buffer})
	return runs


## 单个 `[...]` 的内容分类。
static func _classify_tag(inner: String) -> Dictionary:
	var t := inner.strip_edges()
	if t.is_empty():
		return {"type": "unknown"}
	if t.begins_with("/"):
		var close_name := t.substr(1).strip_edges().to_lower()
		if _CLOSE_TAGS.has(close_name):
			return {"type": "close", "tag": close_name}
		return {"type": "unknown"}
	if t == "-":
		return {"type": "close", "tag": "color"}
	var lower := t.to_lower()
	if lower.begins_with("size="):
		var value := t.substr(5).strip_edges()
		if value.is_valid_float():
			return {"type": "open", "tag": "size", "value": value}
		return {"type": "unknown"}
	if lower.begins_with("ruby="):
		return {"type": "open", "tag": "ruby", "value": t.substr(5).strip_edges()}
	if _SIMPLE_TAGS.has(lower):
		return {"type": "open", "tag": lower}
	# 颜色 / 透明度：全十六进制
	if _is_hex(t):
		if t.length() == 6 or t.length() == 8:
			return {"type": "open", "tag": "color", "value": t.to_upper()}
		if t.length() == 2:
			# AA 文档里的“[两位数]”透明度标记（00 最透明）
			return {"type": "open", "tag": "alpha", "value": t.to_lower()}
	return {"type": "unknown"}


static func _is_hex(s: String) -> bool:
	if s.is_empty():
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		var ok := (c >= 0x30 and c <= 0x39) or (c >= 0x41 and c <= 0x46) or (c >= 0x61 and c <= 0x66)
		if not ok:
			return false
	return true


# ---------------------------------------------------------------------------
# 内联标记 -> BBCode（RichTextLabel）/ 纯文本
# ---------------------------------------------------------------------------

## 转成 Godot RichTextLabel 的 BBCode。
## - `[size=N]`：AA 的 60 = 原大小，这里按 base_font_size 换算成 `[font_size=...]`
##   （默认 base_font_size = 48，即 AA 60 号字对应 48px；传 60 可得到 1:1 数字映射）。
## - `[RRGGBB]` / `[RRGGBBAA]` -> `[color=#...]`，`[-]` -> `[/color]`。
## - `[ruby=注音]文字[/ruby]`：Godot 无原生注音，降级为“文字（注音）”。
## - `[sup]/[sub]`：Godot 不支持，丢弃标签保留文字。
## - AA 的两字符透明度标记：无对应 BBCode，丢弃（parse_inline 仍保留结构化信息）。
static func to_bbcode(text: String, base_font_size := 48) -> String:
	var out := PackedStringArray()
	# 标签栈：{tag, open, close}。交叉嵌套（如 [size][color]..[/size][-]）时
	# 先关闭中间标签、关闭目标标签、再重新打开中间标签，保证输出是合法且配平的 BBCode。
	var stack: Array = []
	var ruby_stack: Array = []
	for run in parse_inline(text):
		match str(run.get("type", "")):
			"text":
				out.append(str(run.get("text", "")))
			"open":
				var tag := str(run.get("tag", ""))
				match tag:
					"size":
						var aa_size := str(run.get("value", "")).to_float()
						var px := roundi(aa_size * base_font_size / 60.0)
						_push_bbcode_tag(stack, out, "size", "[font_size=%d]" % px, "[/font_size]")
					"color":
						_push_bbcode_tag(stack, out, "color", "[color=#%s]" % run.get("value", ""), "[/color]")
					"ruby":
						# Godot 无原生注音：不产生 BBCode 标签，关闭时降级为“（注音）”
						ruby_stack.append(str(run.get("value", "")))
					"b", "i", "u", "s":
						_push_bbcode_tag(stack, out, tag, "[%s]" % tag, "[/%s]" % tag)
					# alpha / sup / sub：RichTextLabel 无对应效果，丢弃标签
			"close":
				var tag := str(run.get("tag", ""))
				if tag == "ruby":
					var note := ""
					if not ruby_stack.is_empty():
						note = ruby_stack.pop_back()
					if not note.is_empty():
						out.append("（%s）" % note)
				else:
					_close_bbcode_tag(stack, out, tag)
			"unknown":
				# 未知方括号内容按字面量输出，避免 RichTextLabel 误解析
				out.append(_escape_bbcode_literal(str(run.get("raw", ""))))
	# 收尾：把没闭合的标签补上闭合（保持 BBCode 合法）
	while not stack.is_empty():
		out.append(stack.pop_back().get("close", ""))
	return "".join(out)


static func _push_bbcode_tag(stack: Array, out: PackedStringArray, tag: String,
		open: String, close: String) -> void:
	stack.append({"tag": tag, "open": open, "close": close})
	out.append(open)


## 关闭 tag：若它不是栈顶，先关闭上面的标签、关闭它、再重新打开上面的标签（配平交叉嵌套）。
static func _close_bbcode_tag(stack: Array, out: PackedStringArray, tag: String) -> void:
	var index := -1
	for i in range(stack.size() - 1, -1, -1):
		if str(stack[i].get("tag", "")) == tag:
			index = i
			break
	if index < 0:
		return  # 没有对应开标签：忽略
	var above: Array = []
	for i in range(index + 1, stack.size()):
		above.append(stack[i])
	# 从栈顶关到 index
	for i in range(stack.size() - 1, index - 1, -1):
		out.append(str(stack[i].get("close", "")))
	stack.resize(index)
	# 重新打开原本在 index 之上的标签
	for entry in above:
		stack.append(entry)
		out.append(str(entry.get("open", "")))


static func _escape_bbcode_literal(s: String) -> String:
	var out := PackedStringArray()
	for i in s.length():
		var ch := s[i]
		if ch == "[":
			out.append("[lb]")
		elif ch == "]":
			out.append("[rb]")
		else:
			out.append(ch)
	return "".join(out)


## 去掉所有内联标记，返回纯文本（backlog / 日志用）。
## 注音标记只保留正文（去掉注音），未知方括号内容原样保留。
static func strip_inline(text: String) -> String:
	var out := PackedStringArray()
	for run in parse_inline(text):
		match run.get("type", ""):
			"text":
				out.append(run.get("text", ""))
			"unknown":
				out.append(str(run.get("raw", "")))
	return "".join(out)


## 收集台词里出现的注音对：[{text, ruby}]（给需要叠加注音的播放器用）。
static func ruby_pairs(text: String) -> Array:
	var out: Array = []
	var buffer := PackedStringArray()
	var stack: Array = []
	for run in parse_inline(text):
		match run.get("type", ""):
			"text":
				buffer.append(str(run.get("text", "")))
			"open":
				if run.get("tag", "") == "ruby":
					buffer = PackedStringArray()
					stack.append(str(run.get("value", "")))
			"close":
				if run.get("tag", "") == "ruby" and not stack.is_empty():
					var note: String = stack.pop_back()
					var body := "".join(buffer)
					buffer = PackedStringArray()
					if not body.is_empty():
						out.append({"text": body, "ruby": note})
	return out
