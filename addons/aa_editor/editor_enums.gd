extends RefCounted
## 编辑器用的枚举/下拉表（UI 展示层）
##
## 优先使用 core-dev 的 `AaEnums`（addons/aa_core/enums.gd）；core 未就绪或字段缺失时，
## 回退到本文件里的最小表。这里只影响“下拉框显示什么”，不改变 .aap 写出的值。
## 数据来源：docs/DESIGN.md §5.1 / docs/spec/enums.md / research/halocue/docs__format.md。

const EMOTICONS := {
	-1: "无",
	0: "怒筋 [빠직]",
	1: "叽喳 [재잘]",
	2: "沉默 …",
	3: "惊叹 [!]",
	4: "爱心 [하트]",
	5: "音符 [음표]",
	6: "疑问 [?]",
	7: "反应 [반응]",
	8: "脸红 [///]",
	9: "惊疑 [?!]",
	10: "冷汗 [땀]",
	11: "闪亮 [반짝]",
	12: "难过 [속상함]",
	13: "走神 [딴생각]",
	14: "灵光 {Bulb}",
	15: "悲伤 {Sad}",
	16: "叹气 {Sigh}",
	17: "冒烟 {Steam}",
	18: "落泪 {Tear}",
	19: "瞌睡 {Zzz}",
}

const ACTIONS := {
	0: "无",
	1: "greeting 向下确认",
	2: "falldownl 向左倒",
	3: "falldownr 向右倒",
	4: "stiff 小颤抖",
	5: "shake 大颤抖",
	6: "jump 跳",
	7: "hophop 蹦跳",
}

const APPEAR := {
	0: "无（保持）",
	1: "al 从右入",
	2: "ar 从左入",
	3: "a 登场",
	4: "dl 向左退",
	5: "dr 向右退",
	6: "d 退场",
}

const SHAPES := {
	0: "无",
	1: "sig 剪影",
	2: "black 变暗",
	4: "closeup 特写",
}

const FACE_IDS := [
	"00", "01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "11", "12",
]

## 常见转场（AA 的 transition 是资源表主键，完整 61 项在 core 的 enums 里；这里只列常用值）。
const TRANSITIONS := {
	0: "无",
}

## 常见背景效果（完整表在 core 的 AaEnums.BG_EFFECTS；这里只列 0）。
const BG_EFFECTS := {
	0: "无",
}

const SLOT_LABELS := ["#0 发言", "#1 左", "#2 中偏左", "#3 中", "#4 中偏右", "#5 右"]

const BGM_MUTE := 999


static func table(kind: String) -> Dictionary:
	match kind:
		"emoticon":
			return EMOTICONS
		"action":
			return ACTIONS
		"appear":
			return APPEAR
		"shape":
			return SHAPES
		"transition":
			return TRANSITIONS
		"bg_effect":
			return BG_EFFECTS
		_:
			return {}


## 把 core 的枚举表（可能是 int -> 字典）归一化成 int -> 中文标签。
static func normalize(core_table: Dictionary) -> Dictionary:
	var out := {}
	for k in core_table.keys():
		var v = core_table[k]
		var label := str(v)
		if v is Dictionary:
			if v.has("zh"):
				label = str(v["zh"])
			elif v.has("name"):
				label = str(v["name"])
			elif v.has("id"):
				label = str(v["id"])
			if v is Dictionary and v.has("symbol"):
				label += " " + str(v["symbol"])
		out[int(k)] = label
	return out
