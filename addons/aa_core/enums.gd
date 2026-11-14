class_name AaEnums
extends RefCounted
## AA 的枚举表（表情符号 / 动作 / 进出场 / 立绘效果 / 过渡 / 背景效果）。
##
## 数据来源：`research/halocue/docs__format.md`（由 139 个真实工程 + .aas 配对反推）
## 与 `research/aa-docs/p15~p18`。数值含义已验证；**过渡 / 背景效果的完整 ID 表
## 尚缺**（见 TODO），未知 ID 会返回“未知过渡(id)”而不是崩溃。
##
## 表结构（与 DESIGN §5.1 一致）：
## - `EMOTICONS`：int -> {symbol, zh, en, keynote}；-1 = 无，0 是真实值（怒筋）
## - `ACTIONS`：int -> {id, zh, en}；0 = 无
## - `APPEAR`：int -> {id, zh}；0 = 无
## - `SHAPES`：int -> {id, zh, en}；1 sig / 2 black / 4 closeup，可按位组合
## - `TRANSITIONS`：int -> {name, zh, group, duration, fade_in, fade_out}；0 = 无过渡
## - `BG_EFFECTS`：int -> {name, zh}；0 = 无

# ---------------------------------------------------------------------------
# 表情符号（emoticon）
# ---------------------------------------------------------------------------
const EMOTICONS := {
	-1: {"symbol": "", "zh": "无", "en": "none", "keynote": "None"},
	0: {"symbol": "[빠직]", "zh": "怒筋", "en": "anger", "keynote": "Anger"},
	1: {"symbol": "[재잘]", "zh": "叽喳", "en": "chat", "keynote": "Chat"},
	2: {"symbol": "…", "zh": "沉默", "en": "silence", "keynote": "Silence"},
	3: {"symbol": "[!]", "zh": "惊叹", "en": "exclaim", "keynote": "Exclaim"},
	4: {"symbol": "[하트]", "zh": "爱心", "en": "heart", "keynote": "Heart"},
	5: {"symbol": "[음표]", "zh": "音符", "en": "note", "keynote": "Note"},
	6: {"symbol": "[?]", "zh": "疑问", "en": "question", "keynote": "Question"},
	7: {"symbol": "[반응]", "zh": "反应", "en": "respond", "keynote": "Respond"},
	8: {"symbol": "[///]", "zh": "脸红", "en": "blush", "keynote": "Blush"},
	9: {"symbol": "[?!]", "zh": "惊疑", "en": "surprise", "keynote": "Surprise"},
	10: {"symbol": "[땀]", "zh": "冷汗", "en": "sweat", "keynote": "Sweat"},
	11: {"symbol": "[반짝]", "zh": "闪亮", "en": "sparkle", "keynote": "Sparkle"},
	12: {"symbol": "[속상함]", "zh": "难过", "en": "upset", "keynote": "Upset"},
	13: {"symbol": "[딴생각]", "zh": "走神", "en": "thinking", "keynote": "Thinking"},
	14: {"symbol": "{Bulb}", "zh": "灵光一闪", "en": "bulb", "keynote": "Bulb"},
	15: {"symbol": "{Sad}", "zh": "悲伤", "en": "sad", "keynote": "Sad"},
	16: {"symbol": "{Sigh}", "zh": "叹气", "en": "sigh", "keynote": "Sigh"},
	17: {"symbol": "{Steam}", "zh": "冒烟", "en": "steam", "keynote": "Steam"},
	18: {"symbol": "{Tear}", "zh": "落泪", "en": "tear", "keynote": "Tear"},
	19: {"symbol": "{Zzz}", "zh": "瞌睡", "en": "sleep", "keynote": "Zzz"},
}

# ---------------------------------------------------------------------------
# 动作（action）
# ---------------------------------------------------------------------------
const ACTIONS := {
	0: {"id": "none", "zh": "无", "en": ""},
	1: {"id": "greeting", "zh": "向下确认", "en": "Greeting"},
	2: {"id": "falldownl", "zh": "向左倒", "en": "FallDownL"},
	3: {"id": "falldownr", "zh": "向右倒", "en": "FallDownR"},
	4: {"id": "stiff", "zh": "小颤抖", "en": "Stiff"},
	5: {"id": "shake", "zh": "大颤抖", "en": "Shake"},
	6: {"id": "jump", "zh": "跳", "en": "Jump"},
	7: {"id": "hophop", "zh": "蹦跳", "en": "Hop"},
}

# 动作 ID <-> 字符串（剧本语法里的 {jump} 等）
const ACTION_BY_ID := {
	1: "greeting", 2: "falldownl", 3: "falldownr", 4: "stiff",
	5: "shake", 6: "jump", 7: "hophop",
}

# ---------------------------------------------------------------------------
# 进出场（appear）
# ---------------------------------------------------------------------------
const APPEAR := {
	0: {"id": "", "zh": "无"},
	1: {"id": "al", "zh": "从右入场"},
	2: {"id": "ar", "zh": "从左入场"},
	3: {"id": "a", "zh": "登场"},
	4: {"id": "dl", "zh": "向左退场"},
	5: {"id": "dr", "zh": "向右退场"},
	6: {"id": "d", "zh": "退场"},
}

const APPEAR_BY_ID := {
	1: "al", 2: "ar", 3: "a", 4: "dl", 5: "dr", 6: "d",
}

# ---------------------------------------------------------------------------
# 立绘效果（shapeOverride，位标记）
# ---------------------------------------------------------------------------
const SHAPES := {
	0: {"id": "", "zh": "无", "en": ""},
	1: {"id": "sig", "zh": "剪影（通讯）", "en": "sig"},
	2: {"id": "black", "zh": "变暗 / 黑屏剪影", "en": "black"},
	4: {"id": "closeup", "zh": "特写", "en": "closeup"},
}

# ---------------------------------------------------------------------------
# 过渡（transition）
# 来源：HaloCue 逆向的 tables.TRANSITION（61 条）。ID 是 GameAssembly.dll 里
# `Studio.Scripts.EnvProp.TransitionProp::Init()` 硬编码的 Dictionary 键（不是哈希）。
# 字段：name = AA 英文名（写回/查表）、zh = 中文显示名、group = 分组、
#       duration = 总时长(ms，0=瞬时)、fade_in/fade_out = 是否含淡入/淡出。
# ---------------------------------------------------------------------------
const TRANSITIONS := {
	0: {"name": "None", "zh": "无过渡", "group": "none", "duration": 0, "fade_in": false, "fade_out": false},
	1408872282: {"name": "Fade 250 >> 250", "zh": "淡入淡出 250+250ms", "group": "fade", "duration": 500, "fade_in": true, "fade_out": true},
	2130373248: {"name": "Fade 500 >> 500", "zh": "淡入淡出 500+500ms", "group": "fade", "duration": 1000, "fade_in": true, "fade_out": true},
	1122508889: {"name": "Fade 1000 >> 1000", "zh": "淡入淡出 1000+1000ms", "group": "fade", "duration": 2000, "fade_in": true, "fade_out": true},
	509674679: {"name": "Fade 1500 >> 1500", "zh": "淡入淡出 1500+1500ms", "group": "fade", "duration": 3000, "fade_in": true, "fade_out": true},
	2482233134: {"name": "Fade 2000 >> 2000", "zh": "淡入淡出 2000+2000ms", "group": "fade", "duration": 4000, "fade_in": true, "fade_out": true},
	1606908815: {"name": "Fade 2500 >> 2500", "zh": "淡入淡出 2500+2500ms", "group": "fade", "duration": 5000, "fade_in": true, "fade_out": true},
	2752031158: {"name": "Fade 3000 >> 3000", "zh": "淡入淡出 3000+3000ms", "group": "fade", "duration": 6000, "fade_in": true, "fade_out": true},
	1238175709: {"name": "Fade 4000 >> 4000", "zh": "淡入淡出 4000+4000ms", "group": "fade", "duration": 8000, "fade_in": true, "fade_out": true},
	3411222921: {"name": "Fade 5000 >> 5000", "zh": "淡入淡出 5000+5000ms", "group": "fade", "duration": 10000, "fade_in": true, "fade_out": true},
	259497043: {"name": "Fade >> 4000", "zh": "淡入 4000ms", "group": "fade", "duration": 4000, "fade_in": true, "fade_out": false},
	1272583944: {"name": "Fade 4000 >>", "zh": "淡出 4000ms", "group": "fade", "duration": 4000, "fade_in": false, "fade_out": true},
	3222392982: {"name": "Fade >> 3000", "zh": "淡入 3000ms", "group": "fade", "duration": 3000, "fade_in": true, "fade_out": false},
	3174465279: {"name": "Fade 3000 >>", "zh": "淡出 3000ms", "group": "fade", "duration": 3000, "fade_in": false, "fade_out": true},
	2457385855: {"name": "Fade >> 2000", "zh": "淡入 2000ms", "group": "fade", "duration": 2000, "fade_in": true, "fade_out": false},
	2243764445: {"name": "Fade 2000 >>", "zh": "淡出 2000ms", "group": "fade", "duration": 2000, "fade_in": false, "fade_out": true},
	2127590351: {"name": "Fade >> 1500", "zh": "淡入 1500ms", "group": "fade", "duration": 1500, "fade_in": true, "fade_out": false},
	4203358158: {"name": "Fade 1500 >>", "zh": "淡出 1500ms", "group": "fade", "duration": 1500, "fade_in": false, "fade_out": true},
	2136104277: {"name": "Fade >> 1000", "zh": "淡入 1000ms", "group": "fade", "duration": 1000, "fade_in": true, "fade_out": false},
	348351892: {"name": "Fade 1000 >>", "zh": "淡出 1000ms", "group": "fade", "duration": 1000, "fade_in": false, "fade_out": true},
	1974926776: {"name": "Fade >> 500", "zh": "淡入 500ms", "group": "fade", "duration": 500, "fade_in": true, "fade_out": false},
	2046503352: {"name": "Fade 500 >>", "zh": "淡出 500ms", "group": "fade", "duration": 500, "fade_in": false, "fade_out": true},
	326824049: {"name": "Fade >> 250", "zh": "淡入 250ms", "group": "fade", "duration": 250, "fade_in": true, "fade_out": false},
	2089682509: {"name": "Fade 250 >>", "zh": "淡出 250ms", "group": "fade", "duration": 250, "fade_in": false, "fade_out": true},
	3868567233: {"name": "Fade White 250 >> 250", "zh": "白色淡入淡出 250+250ms", "group": "fade_white", "duration": 500, "fade_in": true, "fade_out": true},
	2246884625: {"name": "Fade White 500 >> 500", "zh": "白色淡入淡出 500+500ms", "group": "fade_white", "duration": 1000, "fade_in": true, "fade_out": true},
	3182852162: {"name": "Fade White 1000 >> 1000", "zh": "白色淡入淡出 1000+1000ms", "group": "fade_white", "duration": 2000, "fade_in": true, "fade_out": true},
	1289388507: {"name": "Fade White 1500 >> 1500", "zh": "白色淡入淡出 1500+1500ms", "group": "fade_white", "duration": 3000, "fade_in": true, "fade_out": true},
	3785883235: {"name": "Fade White 2000 >> 2000", "zh": "白色淡入淡出 2000+2000ms", "group": "fade_white", "duration": 4000, "fade_in": true, "fade_out": true},
	3181383424: {"name": "Fade White 2500 >> 2500", "zh": "白色淡入淡出 2500+2500ms", "group": "fade_white", "duration": 5000, "fade_in": true, "fade_out": true},
	1346493585: {"name": "Fade White 3000 >> 3000", "zh": "白色淡入淡出 3000+3000ms", "group": "fade_white", "duration": 6000, "fade_in": true, "fade_out": true},
	4075662009: {"name": "Fade White 4000 >> 4000", "zh": "白色淡入淡出 4000+4000ms", "group": "fade_white", "duration": 8000, "fade_in": true, "fade_out": true},
	3539052749: {"name": "Fade White 5000 >> 5000", "zh": "白色淡入淡出 5000+5000ms", "group": "fade_white", "duration": 10000, "fade_in": true, "fade_out": true},
	3765959531: {"name": "Fade White >> 4000", "zh": "白淡入 4000ms", "group": "fade_white", "duration": 4000, "fade_in": true, "fade_out": false},
	429693191: {"name": "Fade White 4000 >>", "zh": "白淡出 4000ms", "group": "fade_white", "duration": 4000, "fade_in": false, "fade_out": true},
	2259711251: {"name": "Fade White >> 3000", "zh": "白淡入 3000ms", "group": "fade_white", "duration": 3000, "fade_in": true, "fade_out": false},
	3657480713: {"name": "Fade White 3000 >>", "zh": "白淡出 3000ms", "group": "fade_white", "duration": 3000, "fade_in": false, "fade_out": true},
	2527144513: {"name": "Fade White >> 2000", "zh": "白淡入 2000ms", "group": "fade_white", "duration": 2000, "fade_in": true, "fade_out": false},
	704731093: {"name": "Fade White 2000 >>", "zh": "白淡出 2000ms", "group": "fade_white", "duration": 2000, "fade_in": false, "fade_out": true},
	457377075: {"name": "Fade White >> 1500", "zh": "白淡入 1500ms", "group": "fade_white", "duration": 1500, "fade_in": true, "fade_out": false},
	2160391595: {"name": "Fade White 1500 >>", "zh": "白淡出 1500ms", "group": "fade_white", "duration": 1500, "fade_in": false, "fade_out": true},
	1626584722: {"name": "Fade White >> 1000", "zh": "白淡入 1000ms", "group": "fade_white", "duration": 1000, "fade_in": true, "fade_out": false},
	2878370298: {"name": "Fade White 1000 >>", "zh": "白淡出 1000ms", "group": "fade_white", "duration": 1000, "fade_in": false, "fade_out": true},
	3977094957: {"name": "Fade White >> 500", "zh": "白淡入 500ms", "group": "fade_white", "duration": 500, "fade_in": true, "fade_out": false},
	42187309: {"name": "Fade White 500 >>", "zh": "白淡出 500ms", "group": "fade_white", "duration": 500, "fade_in": false, "fade_out": true},
	375948222: {"name": "Crossfade 200 >>", "zh": "交叉渐变 200ms", "group": "crossfade", "duration": 200, "fade_in": true, "fade_out": true},
	4187997050: {"name": "Crossfade 300 >>", "zh": "交叉渐变 300ms", "group": "crossfade", "duration": 300, "fade_in": true, "fade_out": true},
	3854440696: {"name": "Crossfade 500 >>", "zh": "交叉渐变 500ms", "group": "crossfade", "duration": 500, "fade_in": true, "fade_out": true},
	4004024664: {"name": "Crossfade 1000 >>", "zh": "交叉渐变 1000ms", "group": "crossfade", "duration": 1000, "fade_in": true, "fade_out": true},
	1173843909: {"name": "Crossfade 1500 >>", "zh": "交叉渐变 1500ms", "group": "crossfade", "duration": 1500, "fade_in": true, "fade_out": true},
	1369285246: {"name": "Crossfade 2000 >>", "zh": "交叉渐变 2000ms", "group": "crossfade", "duration": 2000, "fade_in": true, "fade_out": true},
	3054018111: {"name": "Crossfade 2500 >>", "zh": "交叉渐变 2500ms", "group": "crossfade", "duration": 2500, "fade_in": true, "fade_out": true},
	1027503790: {"name": "Crossfade 3000 >>", "zh": "交叉渐变 3000ms", "group": "crossfade", "duration": 3000, "fade_in": true, "fade_out": true},
	3196842123: {"name": "Crossfade 3500 >>", "zh": "交叉渐变 3500ms", "group": "crossfade", "duration": 3500, "fade_in": true, "fade_out": true},
	2091508330: {"name": "Crossfade 4000 >>", "zh": "交叉渐变 4000ms", "group": "crossfade", "duration": 4000, "fade_in": true, "fade_out": true},
	1127535352: {"name": "Swipe R", "zh": "Swipe R", "group": "special", "duration": 0, "fade_in": false, "fade_out": false},
	3957412172: {"name": "Swipe L", "zh": "Swipe L", "group": "special", "duration": 0, "fade_in": false, "fade_out": false},
	3029168926: {"name": "Swipe D", "zh": "Swipe D", "group": "special", "duration": 0, "fade_in": false, "fade_out": false},
	4152299906: {"name": "Swipe U", "zh": "Swipe U", "group": "special", "duration": 0, "fade_in": false, "fade_out": false},
	3344317924: {"name": "Noise", "zh": "Noise", "group": "special", "duration": 0, "fade_in": false, "fade_out": false},
	1914875660: {"name": "Circle", "zh": "Circle", "group": "special", "duration": 0, "fade_in": false, "fade_out": false},
}

## 过渡分组（AA 面板上的 4 个按钮）。
const TRANSITION_GROUPS := {
	"none": "无",
	"fade": "淡入淡出",
	"fade_white": "淡入淡出（白）",
	"crossfade": "交叉渐变",
	"special": "特殊效果",
}

## 中文简写 -> 英文名模板（`{d}` 为时长毫秒）。编辑器写 `transition_resolve()` 可还原 ID。
const TRANSITION_CN := {
	"无": "None",
	"淡入淡出": "Fade {d} >> {d}",
	"淡出": "Fade {d} >>",
	"淡入": "Fade >> {d}",
	"白淡入淡出": "Fade White {d} >> {d}",
	"淡入淡出白": "Fade White {d} >> {d}",
	"白淡出": "Fade White {d} >>",
	"白淡入": "Fade White >> {d}",
	"交叉渐变": "Crossfade {d} >>",
	"叠化": "Crossfade {d} >>",
	"右扫": "Swipe R",
	"左扫": "Swipe L",
	"下扫": "Swipe D",
	"上扫": "Swipe U",
	"噪点": "Noise",
	"圆形": "Circle",
}

## 中文简写对应的默认时长（毫秒）。
const TRANSITION_CN_DEFAULT_MS := {
	"淡入淡出": 1000,
	"淡出": 1000,
	"淡入": 1000,
	"白淡入淡出": 1000,
	"淡入淡出白": 1000,
	"白淡出": 1000,
	"白淡入": 1000,
	"交叉渐变": 1000,
	"叠化": 1000,
}

# ---------------------------------------------------------------------------
# 背景效果（bgEffect）
# 来源：HaloCue 逆向的 tables.BGEFFECT（26 条 + None）。
# 字段：name = AA 资源名（UI_FX_<name>.prefab）、zh = 中文别名。
# ---------------------------------------------------------------------------
const BG_EFFECTS := {
	0: {"name": "None", "zh": "无"},
	1377724294: {"name": "BG_Dust_L", "zh": "烟尘"},
	3550865647: {"name": "BG_FocusLine", "zh": "集中线"},
	2728481130: {"name": "BG_Mist_L", "zh": "烟雾"},
	3134544579: {"name": "BG_UnderFire", "zh": "枪战"},
	2313116516: {"name": "BG_UnderFire_R", "zh": "枪战（右）"},
	4006301275: {"name": "BG_Filter_Red", "zh": "红滤镜"},
	2174743540: {"name": "BG_Filter_Red_BG", "zh": "红滤镜（无背景）"},
	3934311147: {"name": "BG_Ash_Black", "zh": "黑灰"},
	736631543: {"name": "BG_Ash_Red", "zh": "红灰"},
	1061522909: {"name": "BG_Shining_L", "zh": "闪光"},
	1870781268: {"name": "BG_Shining_L_BGOff", "zh": "闪光无背景"},
	1679852157: {"name": "BG_Love_L", "zh": "爱心"},
	3023046476: {"name": "BG_Love_L_BGOff", "zh": "爱心无背景"},
	786952175: {"name": "BG_Flash", "zh": "闪白"},
	1566732214: {"name": "BG_Flash_Sound", "zh": "闪电（含音效）"},
	880081110: {"name": "BG_Teleport", "zh": "传送"},
	3676184657: {"name": "BG_Rain_L", "zh": "雨"},
	2675527592: {"name": "BG_Snow_L", "zh": "雪"},
	575794762: {"name": "BG_SandStorm_L", "zh": "沙尘暴"},
	866423043: {"name": "BG_Wave_F", "zh": "水波"},
	3610115052: {"name": "BG_WaveShort_F", "zh": "短水波"},
	176581582: {"name": "BG_ScrollL_1.0", "zh": "向左滚动 1.0"},
	442565896: {"name": "BG_ScrollR_1.0", "zh": "向右滚动 1.0"},
	1488006201: {"name": "BG_ScrollB_0.5", "zh": "向下滚动 0.5"},
	2551519896: {"name": "BG_Fireworks_L_BGOff_01", "zh": "烟花 01（无背景）"},
	2499688462: {"name": "BG_Fireworks_L_BGOff_02", "zh": "烟花 02（无背景）"},
}

const BG_EFFECT_CN := {
	"无": "None",
	"烟尘": "BG_Dust_L",
	"扬尘": "BG_Dust_L",
	"集中线": "BG_FocusLine",
	"速度线": "BG_FocusLine",
	"烟雾": "BG_Mist_L",
	"雾": "BG_Mist_L",
	"朦胧": "BG_Mist_L",
	"烟感": "BG_Mist_L",
	"枪战": "BG_UnderFire",
	"被射击": "BG_UnderFire",
	"红滤镜": "BG_Filter_Red",
	"危机": "BG_Filter_Red",
	"黑灰": "BG_Ash_Black",
	"灰烬": "BG_Ash_Black",
	"红灰": "BG_Ash_Red",
	"闪光": "BG_Shining_L",
	"闪光无背景": "BG_Shining_L_BGOff",
	"爱心": "BG_Love_L",
	"爱心无背景": "BG_Love_L_BGOff",
	"闪白": "BG_Flash",
	"闪电": "BG_Flash_Sound",
	"传送": "BG_Teleport",
	"雨": "BG_Rain_L",
	"雪": "BG_Snow_L",
	"沙尘暴": "BG_SandStorm_L",
	"水波": "BG_Wave_F",
	"短水波": "BG_WaveShort_F",
	"烟花": "BG_Fireworks_L_BGOff_01",
}
# ---------------------------------------------------------------------------
# 查询辅助
# ---------------------------------------------------------------------------

static func emoticon_info(value: int) -> Dictionary:
	return EMOTICONS.get(value, {"symbol": "", "zh": "未知表情(%d)" % value, "en": "unknown", "keynote": ""})


static func emoticon_symbol(value: int) -> String:
	return emoticon_info(value).get("symbol", "")


static func emoticon_zh(value: int) -> String:
	return emoticon_info(value).get("zh", "")


## 按中文名找表情 ID（编辑器用），找不到返回 -1。
static func emoticon_id_by_zh(zh: String) -> int:
	for id in EMOTICONS:
		if EMOTICONS[id]["zh"] == zh:
			return id
	return -1


static func action_info(value: int) -> Dictionary:
	return ACTIONS.get(value, {"id": "unknown", "zh": "未知动作(%d)" % value, "en": ""})


static func action_name(value: int) -> String:
	return action_info(value).get("zh", "")


static func action_id_by_name(token: String) -> int:
	var lower := token.to_lower()
	for id in ACTION_BY_ID:
		if ACTION_BY_ID[id] == lower:
			return id
	return 0


static func appear_info(value: int) -> Dictionary:
	return APPEAR.get(value, {"id": "", "zh": "未知进出场(%d)" % value})


static func appear_token(value: int) -> String:
	return appear_info(value).get("id", "")


static func appear_id_by_token(token: String) -> int:
	var lower := token.to_lower()
	for id in APPEAR_BY_ID:
		if APPEAR_BY_ID[id] == lower:
			return id
	return 0


## shapeOverride 是位标记，返回组合后的中文，如 "剪影（通讯）+特写"。
static func shape_zh(value: int) -> String:
	if value == 0:
		return "无"
	var parts: Array = []
	for bit in [1, 2, 4]:
		if value & bit:
			parts.append(SHAPES[bit]["zh"])
	if parts.is_empty():
		return "未知效果(%d)" % value
	return "+".join(parts)


static func shape_tokens(value: int) -> PackedStringArray:
	var out := PackedStringArray()
	for bit in [1, 2, 4]:
		if value & bit:
			out.append(SHAPES[bit]["id"])
	return out


## 剧本语法 `<特写>` / `<sig+black>` -> shapeOverride 值。
static func shape_id_by_token(token: String) -> int:
	var lower := token.strip_edges().to_lower()
	if lower.is_empty() or lower == "无":
		return 0
	var total := 0
	for part in lower.split("+", false):
		for bit in [1, 2, 4]:
			if SHAPES[bit]["id"] == part:
				total |= bit
	return total


static func transition_info(value: int) -> Dictionary:
	if TRANSITIONS.has(value):
		return TRANSITIONS[value]
	return {
		"name": "Unknown_%d" % value,
		"zh": "未知过渡(%d)" % value,
		"group": "unknown",
		"duration": 0,
		"fade_in": false,
		"fade_out": false,
	}


static func transition_zh(value: int) -> String:
	return transition_info(value).get("zh", "")


## 过渡时长（毫秒，0 = 无过渡 / 瞬时）。
static func transition_duration(value: int) -> int:
	return int(transition_info(value).get("duration", 0))


static func bg_effect_info(value: int) -> Dictionary:
	if BG_EFFECTS.has(value):
		return BG_EFFECTS[value]
	return {"name": "Unknown_%d" % value, "zh": "未知背景效果(%d)" % value}


static func bg_effect_zh(value: int) -> String:
	return bg_effect_info(value).get("zh", "")


## 编辑器下拉用：表情列表 [{id, symbol, zh}]（不含 -1 的“无”？含，方便清空）。
static func emoticon_choices(include_none := true) -> Array:
	var out: Array = []
	var ids := EMOTICONS.keys()
	ids.sort()
	for id in ids:
		if id == -1 and not include_none:
			continue
		out.append({"id": id, "symbol": EMOTICONS[id]["symbol"], "zh": EMOTICONS[id]["zh"]})
	return out


static func action_choices() -> Array:
	var out: Array = []
	var ids := ACTIONS.keys()
	ids.sort()
	for id in ids:
		out.append({"id": id, "id_name": ACTIONS[id]["id"], "zh": ACTIONS[id]["zh"]})
	return out


static func appear_choices() -> Array:
	var out: Array = []
	var ids := APPEAR.keys()
	ids.sort()
	for id in ids:
		out.append({"id": id, "id_name": APPEAR[id]["id"], "zh": APPEAR[id]["zh"]})
	return out


## 解析过渡：接受数字 ID / 英文全名 / 中文简写[+时长]（如 "淡入淡出 2000"、"交叉渐变 500"）。
## 找不到返回 0，并 push_warning 提示可用值。
static func transition_resolve(token: String) -> int:
	var t := token.strip_edges().replace("　", " ")
	if t.is_empty():
		return 0
	if t.is_valid_int():
		return t.to_int()
	for id in TRANSITIONS:
		if TRANSITIONS[id]["name"] == t:
			return id
	# 中文简写：按 key 长度降序做前缀匹配（支持 "淡入淡出2000" / "淡入淡出 2000"）
	var keys := TRANSITION_CN.keys()
	keys.sort_custom(func(a, b): return a.length() > b.length())
	for head in keys:
		if not t.begins_with(head):
			continue
		var tpl: String = TRANSITION_CN[head]
		var rest := t.substr(head.length()).strip_edges()
		if not tpl.contains("{d}"):
			for id in TRANSITIONS:
				if TRANSITIONS[id]["name"] == tpl:
					return id
			return 0
		var d: int = int(TRANSITION_CN_DEFAULT_MS.get(head, 1000))
		if rest.is_valid_int():
			d = rest.to_int()
		var wanted := tpl.format({"d": d})
		for id in TRANSITIONS:
			if TRANSITIONS[id]["name"] == wanted:
				return id
	push_warning("AaEnums: 未知过渡「%s」" % token)
	return 0


## 过渡下拉数据（按分组、时长排序）：[{id, name, zh, group, duration}]
static func transition_choices() -> Array:
	var out: Array = []
	for group in ["none", "fade", "fade_white", "crossfade", "special"]:
		var group_items: Array = []
		for id in TRANSITIONS:
			var info: Dictionary = TRANSITIONS[id]
			if str(info.get("group", "")) != group:
				continue
			group_items.append({
				"id": id,
				"name": info.get("name", ""),
				"zh": info.get("zh", ""),
				"group": group,
				"duration": int(info.get("duration", 0)),
			})
		group_items.sort_custom(func(a, b): return int(a["duration"]) < int(b["duration"]))
		out.append_array(group_items)
	return out


## 解析背景效果：接受数字 ID / 英文资源名 / 中文别名（如 "集中线"、"BG_UnderFire"）。
static func bg_effect_resolve(token: String) -> int:
	var t := token.strip_edges()
	if t.is_empty():
		return 0
	if t.is_valid_int():
		return t.to_int()
	for id in BG_EFFECTS:
		if BG_EFFECTS[id]["name"] == t:
			return id
	if BG_EFFECT_CN.has(t):
		var en: String = BG_EFFECT_CN[t]
		for id in BG_EFFECTS:
			if BG_EFFECTS[id]["name"] == en:
				return id
	push_warning("AaEnums: 未知背景效果「%s」" % token)
	return 0


## 背景效果下拉数据：[{id, name, zh}]（按 id 排序）。
static func bg_effect_choices() -> Array:
	var ids := BG_EFFECTS.keys()
	ids.sort()
	var out: Array = []
	for id in ids:
		out.append({"id": id, "name": BG_EFFECTS[id].get("name", ""), "zh": BG_EFFECTS[id].get("zh", "")})
	return out


# ---------------------------------------------------------------------------
# 角色表情 faceId（docs/spec/enums.md §6；字符串，不是封闭枚举）
# ---------------------------------------------------------------------------

## 常用 faceId 下拉（编辑器用；真实工程还有 07–46、S2_xx 等，字符串原样保留）
const FACE_IDS := ["00", "01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "11", "12", "99"]

## 标准 BA 模型的表情语义（来自 .atlas region 名；各角色/各套模型不保证一致）
const FACE_SEMANTICS := {
	"00": {"name": "default", "zh": "默认/无表情"},
	"01": {"name": "normal", "zh": "平常"},
	"02": {"name": "respond", "zh": "回应"},
	"03": {"name": "smile", "zh": "微笑"},
	"04": {"name": "embarrassed", "zh": "害羞"},
	"05": {"name": "serious", "zh": "认真"},
	"06": {"name": "depressed", "zh": "低落"},
	"99": {"name": "unknown", "zh": "特殊/占位"},
}

## 官方美术拼写错误归一化（做 atlas 语义归一时用）
const FACE_ALIAS := {
	"embarassed": "embarrassed", "embrassed": "embarrassed", "embarrased": "embarrassed",
	"emvarassed": "embarrassed", "embarrass": "embarrassed",
	"nomal": "normal", "defualt": "default", "deuflat": "default",
	"depressde": "depressed", "deparaeesd": "depressed",
	"repond": "respond", "sarcatic": "sarcastic", "yarn": "yawn",
	"serioous": "serious", "inocent": "innocent",
	"eyeclosed": "eyeclose", "eye_close": "eyeclose", "thingking": "thinking",
}

## 表情中文名；未知/自定义编号只显示编号（不猜语义）。
static func face_zh(face_id: String) -> String:
	var info: Dictionary = FACE_SEMANTICS.get(face_id, {})
	if not info.is_empty():
		return info["zh"]
	return "表情 " + face_id


## 表情语义名（未知返回 ""）。
static func face_semantic_name(face_id: String) -> String:
	return str(FACE_SEMANTICS.get(face_id, {}).get("name", ""))


## 归一化 atlas 里的表情名（修正官方拼写错误）。
static func face_normalize(token: String) -> String:
	var lower := token.strip_edges().to_lower()
	return str(FACE_ALIAS.get(lower, lower))


# ---------------------------------------------------------------------------
# 槽位 / BGM
# ---------------------------------------------------------------------------

## 槽位显示名：0 = 无立绘说话槽，1–5 = 立绘位（屏幕左→右）。
const SLOT_LABELS := ["#0 发言", "#1 左", "#2 中偏左", "#3 中", "#4 中偏右", "#5 右"]

## bgmId = 999 表示静音。
const BGM_MUTE := 999


static func slot_label(slot: int) -> String:
	if slot >= 0 and slot < SLOT_LABELS.size():
		return SLOT_LABELS[slot]
	return "槽位 %d" % slot


static func emoticon_choices_with_none() -> Array:
	return emoticon_choices(true)
