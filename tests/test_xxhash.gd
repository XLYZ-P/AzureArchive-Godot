extends RefCounted
## test_xxhash.gd —— AaHash（xxHash32）单元测试。
##
## AA 的背景 ID 不是查表，而是 `bgName = xxh32(utf8(bgFriendlyName), seed=0)`，
## 因此这个哈希是全项目「自定义背景」正确性的地基。断言两组：
##   1. 已知向量（含 16 字节分块边界、seed、UTF-8 中文、长串）——向量由独立 Python
##      参考实现算出，与核心模块实现交叉验证；
##   2. 真实样本 `fixtures/aap/sample_kei_01.aap` 全部 170 行 ScriptData 的
##      bgName == xxh32(bgFriendlyName) 全量校验（169 行正文 + 1 行 Exit.NeScriptDirty）。

const Fw = preload("res://tests/framework.gd")

const HASH_SCRIPT := "res://addons/aa_core/xxhash32.gd"
const SAMPLE_PATH := "res://fixtures/aap/sample_kei_01.aap"
const T_SCRIPT_DATA := "ScriptData, Assembly-CSharp"
const MASK32 := 0xFFFFFFFF

## [输入, 期望]；期望值来自独立 Python 参考实现（tests/make_fixtures.py 里的 xxh32()）。
const VECTORS := [
	["", 46947589],                       # 0x02CC5D05
	["a", 1426945110],                    # 0x550D7456
	["abc", 852579327],                   # 0x32D153FF
	["abcd", 2741253893],
	["Hello, world!", 834093149],
	["0123456789abcdef", 3267648361],     # 恰好 16 字节，走分块路径
	["0123456789abcdefg", 3430527511],    # 17 字节
	["背景测试", 2498957870],              # UTF-8 多字节
	["AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", 3943619364], # 31 字节
	["BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
			3612792432],                  # 100 字节
	["The quick brown fox jumps over the lazy dog", 3898516702],
]

## 背景名 -> xxh32(utf8, seed=0) 参考值（独立 Python 实现，交叉验证用）。
const BG_HASH_REFERENCE := {
	"BG_RuinUndergroundPassage": 3558049603,
	"BG_Black": 1047754314,
	"BG_CS_Millenium_01": 1391744589,
	"BG_CS_Millenium_10": 394798774,
	"BG_CS_Millenium_01_c": 2177189307,
	"BG_RuinCenter_Aris": 4027319041,
	"BG_RuinCenter": 2297697223,
	"BG_CS_Millenium_18": 1565563486,
}

## 已知的 AA「大小写漂移」脏数据：样本里这 5 行存的 bgName 与当前
## bgFriendlyName 的哈希不一致（AA 上游 bug，format-researcher 在 579 组中实测 2 例）。
## 这不是我们模块的 bug，测试按「已知例外」放行，但要求：不一致只允许出现在这些名字上、
## 且存储值必须等于下面记录的固定值。
const KNOWN_DRIFT := {
	"BG_CS_Millenium_01_c": 2434566677,
}
const DRIFT_LINE_COUNT := 5
const MATCH_LINE_COUNT := 165


func run(ctx: Fw.Ctx) -> void:
	var S := ctx.need(HASH_SCRIPT, "core-dev")
	if S == null:
		return
	if not ctx.need_methods(S, ["xxh32", "bg_id"], "core-dev"):
		return
	ctx.is_true(ctx.has_global_class("AaHash"), "AaHash 已在 class_name 全局缓存中（可由其他模块直接引用）")

	# ---------------------------------------------------------------- 1. 已知向量
	_h("xxh32 已知向量（seed=0）")
	for v in VECTORS:
		var text := String(v[0])
		var expected := int(v[1])
		var actual := int(ctx.static_call(S, "xxh32", [text.to_utf8_buffer()]))
		ctx.eq(actual, expected, "xxh32(%s)（UTF-8 %d 字节）" % [_short(text), text.to_utf8_buffer().size()])

	# 32 位无符号范围
	for v2 in VECTORS:
		var a2 := int(ctx.static_call(S, "xxh32", [String(v2[0]).to_utf8_buffer()]))
		ctx.is_true(a2 >= 0 and a2 <= MASK32, "返回值在 uint32 范围内（%s -> %d）" % [_short(String(v2[0])), a2])

	# seed 变体（向量仍是 Python 参考实现算的）
	ctx.eq(int(ctx.static_call(S, "xxh32", ["abc".to_utf8_buffer(), 1])), 2856167679, "xxh32(\"abc\", seed=1)")
	ctx.eq(int(ctx.static_call(S, "xxh32", ["abc".to_utf8_buffer(), 0xFFFFFFFF])), 2989167648,
			"xxh32(\"abc\", seed=0xFFFFFFFF)")

	# PackedByteArray 输入：显式构造二进制（含 0 字节）
	var bin := PackedByteArray([0x00, 0x01, 0x02, 0xFF, 0x80, 0x7F])
	var bin_hash := int(ctx.static_call(S, "xxh32", [bin]))
	ctx.is_true(bin_hash >= 0 and bin_hash <= MASK32, "二进制输入（含 0x00）结果合法：%d" % bin_hash)
	ctx.ne(bin_hash, int(ctx.static_call(S, "xxh32", [PackedByteArray([0x00, 0x01, 0x02, 0xFF, 0x80, 0x7E])])),
			"差 1 字节结果应不同")

	# ---------------------------------------------------------------- 2. bg_id 语义
	ctx.eq(int(ctx.static_call(S, "bg_id", [""])), 0, "bg_id(\"\") == 0（无背景约定）")
	for bg in BG_HASH_REFERENCE:
		ctx.eq(int(ctx.static_call(S, "bg_id", [String(bg)])), int(BG_HASH_REFERENCE[bg]),
				"bg_id(%s)（Python 参考值）" % bg)
	# bg_id == xxh32(utf8(name), 0)
	for bg2 in BG_HASH_REFERENCE:
		ctx.eq(int(ctx.static_call(S, "bg_id", [String(bg2)])),
				int(ctx.static_call(S, "xxh32", [String(bg2).to_utf8_buffer(), 0])),
				"bg_id(%s) == xxh32(utf8, 0)" % bg2)
	ctx.eq(int(ctx.static_call(S, "bg_id", ["BG_RuinUndergroundPassage"])), 3558049603,
			"DESIGN 文档示例：BG_RuinUndergroundPassage -> 3558049603")

	# ---------------------------------------------------------------- 3. 真实样本 170 行全量
	ctx.is_true(FileAccess.file_exists(SAMPLE_PATH), "真实样本存在")
	if not FileAccess.file_exists(SAMPLE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAMPLE_PATH))
	if not (parsed is Dictionary):
		ctx.fail("真实样本 JSON 解析失败")
		return
	var nodes: Array = ((parsed as Dictionary).get("nodes", {}) as Dictionary).get("$values", [])
	var lines: Array = []
	for node in nodes:
		var t := String((node as Dictionary).get("$type", ""))
		if t.contains("ScriptNodeData"):
			lines.append_array(((node as Dictionary).get("Scripts", {}) as Dictionary).get("$values", []))
		elif t.contains("ExitNodeData"):
			var ne: Variant = (node as Dictionary).get("NeScriptDirty")
			if ne is Dictionary and String((ne as Dictionary).get("$type", "")) == T_SCRIPT_DATA:
				lines.append(ne)
	ctx.eq(lines.size(), 170, "样本共 170 行 ScriptData（169 正文 + 1 出口预告）")

	var mismatches: Array = []
	var illegal_mismatches: Array = []
	var drift_lines := 0
	var empty_bg := 0
	var checked := 0
	var matched := 0
	for i in range(lines.size()):
		var line: Dictionary = lines[i]
		var name := String(line.get("bgFriendlyName", ""))
		var got := int(line.get("bgName", 0))
		var want := 0
		if not name.is_empty():
			want = int(ctx.static_call(S, "bg_id", [name]))
		else:
			empty_bg += 1
		checked += 1
		if got == want:
			matched += 1
		elif KNOWN_DRIFT.has(name):
			drift_lines += 1
			mismatches.append("第 %d 行 %s: 存储 %d / 哈希 %d（已知漂移）" % [i, name, got, want])
			if got != int(KNOWN_DRIFT[name]):
				illegal_mismatches.append("第 %d 行 %s 存储值 %d != 记录的漂移值 %d" % [i, name, got, int(KNOWN_DRIFT[name])])
		else:
			illegal_mismatches.append("第 %d 行 %s: 存储 %d != 哈希 %d" % [i, name, got, want])
	ctx.eq(checked, 170, "170 行全部完成 bgName 校验")
	ctx.eq(matched, MATCH_LINE_COUNT, "165 行 bgName == xxh32(bgFriendlyName)（样本中 165/170 精确命中）")
	ctx.eq(drift_lines, DRIFT_LINE_COUNT, "5 行属于已知 AA 大小写漂移（BG_CS_Millenium_01_c），按例外放行")
	ctx.eq(illegal_mismatches.size(), 0, "除已知漂移外没有任何 bgName 不匹配：%s" % str(illegal_mismatches.slice(0, 5)))
	ctx.eq(empty_bg, 0, "样本中没有空背景行（所有行都带 bgFriendlyName）")
	# 漂移行必须真的是「存储值 != 当前名字哈希」，锁死这份已知脏数据的行为
	for drift_name in KNOWN_DRIFT:
		ctx.ne(int(ctx.static_call(S, "bg_id", [String(drift_name)])), int(KNOWN_DRIFT[drift_name]),
				"漂移背景 %s 的存储值确实不等于当前名字哈希（AA 上游脏数据）" % drift_name)

	# 背景种类计数（防止只测了部分行）
	var seen := {}
	for line2 in lines:
		seen[String((line2 as Dictionary).get("bgFriendlyName", ""))] = true
	ctx.eq(seen.size(), BG_HASH_REFERENCE.size(), "样本共 %d 种背景，均已在交叉验证表内" % BG_HASH_REFERENCE.size())
	for nm in seen:
		ctx.is_true(BG_HASH_REFERENCE.has(String(nm)), "背景名在交叉验证表内：%s" % nm)


func _short(s: String) -> String:
	if s.length() > 24:
		return s.substr(0, 24) + "…"
	return s


func _h(title: String) -> void:
	print("  · " + title)
