class_name AaScriptLine
extends RefCounted
## AA `ScriptData`：剧本里的一行（一条对白 / 一条环境指令）。
##
## 字段顺序（AA 序列化严格顺序，改顺序会导致 AA 读不了）：
## `text, popup, bgEffect, bgName, bgFriendlyName, sound, voice, transition,
##  bgmId, selectionGroup, additionalPrompt, characters, speakerSlotNum,
##  highlightedSlotNums, isDialogScript, placeText`
##
## 关键规则（见 research/halocue/docs__format.md）：
## - `bg_name = AaHash.bg_id(bg_friendly_name)`；空背景时两者都是空/0；
##   老工程里可能存在“名字改过大小写、bgName 没更新”的历史脏数据，
##   用 `bg_id_matches()` 检查、`computed_bg_id()` 重新计算。
## - `bgm_id = 999` 表示静音；0 = 未设置。
## - `characters` 恒 6 项，见 AaCharacterRecord。
## - `speaker_slot_num` / `highlighted_slot_nums` 都是**槽位下标**。
## - `additional_prompt` 是 `#` 额外指令，多条用 `\n` 分隔。
##
## 解析缓存：`get_commands()` / `get_inline_runs()` / `get_bbcode()` 会缓存结果，
## 改字段后会自动失效（也提供 `invalidate_cache()`）。
##
## AA 编译器在编译 `.aas` 时会自动插等待：有气泡 2500ms / 有位移或进出场或动作 1500ms；
## 作者写的 `#wait` 是**覆盖**不是叠加（HaloCue 134 组实测）。对应 `auto_wait_ms()` /
## `effective_wait_ms()`，Player 可以直接用。

const TYPE_STRING := AaJson.T_SCRIPT
## AA 自动等待时长（毫秒）：有表情符号
const AUTO_WAIT_EMOTICON := 2500
## AA 自动等待时长（毫秒）：有位移 / 进出场 / 动作
const AUTO_WAIT_MOTION := 1500
## 槽位总数（含 0 号无立绘说话槽）
const SLOT_COUNT := AaCharacterRecord.SLOT_COUNT

var text: String = ""
var popup: String = ""
var bg_effect: int = 0
var bg_name: int = 0
var bg_friendly_name: String = ""
var sound: String = ""
var voice: String = ""
var transition: int = 0
var bgm_id: int = 0
var selection_group: int = 0
var additional_prompt: String = ""
var characters: Array = []
var speaker_slot_num: int = 0
var highlighted_slot_nums: PackedInt32Array = PackedInt32Array()
var is_dialog_script: bool = true
var place_text: String = ""

## 未知字段（向前兼容：原样保留）
var extra: Dictionary = {}
## 源 JSON 中值为 null 的字符串字段（AA 会把未设置的可选字段写成 null，须原样保留）
var _nulls: Dictionary = {}

var _commands_cache: Array = []
var _commands_source: String = ""
var _commands_dirty := true
var _inline_cache: Array = []
var _inline_source: String = ""
var _inline_dirty := true


func _init() -> void:
	characters = []
	for i in SLOT_COUNT:
		characters.append(AaCharacterRecord.new())


const _KNOWN := {
	"$type": true, "text": true, "popup": true, "bgEffect": true, "bgName": true,
	"bgFriendlyName": true, "sound": true, "voice": true, "transition": true,
	"bgmId": true, "selectionGroup": true, "additionalPrompt": true,
	"characters": true, "speakerSlotNum": true, "highlightedSlotNums": true,
	"isDialogScript": true, "placeText": true,
}


# ---------------------------------------------------------------------------
# 构造 / 解析 / 序列化
# ---------------------------------------------------------------------------

## 新建空白行。AA 的每行 `voice` 都是 36 字符 Guid（没有语音文件也一样），
## 所以新建时生成一个；`bgmId` 默认 999（静音），避免新工程沿用上一次的 BGM。
static func make_empty(is_dialog := true) -> AaScriptLine:
	var line := AaScriptLine.new()
	line.is_dialog_script = is_dialog
	line.voice = AaGuid.new_uuid()
	line.bgm_id = 999
	return line


static func from_dict(d: Variant) -> AaScriptLine:
	var line := AaScriptLine.new()
	if not (d is Dictionary):
		return line
	var dd: Dictionary = d
	line.text = AaJson.get_str(dd, "text", "")
	line.popup = AaJson.get_str(dd, "popup", "")
	line.bg_effect = AaJson.get_int(dd, "bgEffect", 0)
	line.bg_name = AaJson.get_int(dd, "bgName", 0)
	line.bg_friendly_name = AaJson.get_str(dd, "bgFriendlyName", "")
	line.sound = AaJson.get_str(dd, "sound", "")
	line.voice = AaJson.get_str(dd, "voice", "")
	line.transition = AaJson.get_int(dd, "transition", 0)
	line.bgm_id = AaJson.get_int(dd, "bgmId", 0)
	line.selection_group = AaJson.get_int(dd, "selectionGroup", 0)
	line.additional_prompt = AaJson.get_str(dd, "additionalPrompt", "")
	line.speaker_slot_num = AaJson.get_int(dd, "speakerSlotNum", 0)
	line.is_dialog_script = AaJson.get_bool(dd, "isDialogScript", true)
	line.place_text = AaJson.get_str(dd, "placeText", "")
	# characters：恒 6 项（多余截断、缺失补空）
	var recs: Array = AaJson.values_of(dd.get("characters"))
	line.characters = []
	for i in SLOT_COUNT:
		if i < recs.size():
			line.characters.append(AaCharacterRecord.from_dict(recs[i]))
		else:
			line.characters.append(AaCharacterRecord.new())
	# highlightedSlotNums：int 列表
	var highs := PackedInt32Array()
	for v in AaJson.values_of(dd.get("highlightedSlotNums")):
		highs.append(int(v))
	line.highlighted_slot_nums = highs
	# null 保留
	for key in ["text", "popup", "bgFriendlyName", "sound", "voice", "additionalPrompt", "placeText"]:
		if AaJson.is_null_field(dd, key):
			line._nulls[key] = true
	# 未知字段原样保留
	for key in dd.keys():
		if not _KNOWN.has(key):
			line.extra[key] = dd[key]
	return line


func to_dict() -> Dictionary:
	var d := {}
	d["$type"] = TYPE_STRING
	d["text"] = _out_str("text", text)
	d["popup"] = _out_str("popup", popup)
	d["bgEffect"] = bg_effect
	d["bgName"] = bg_name
	d["bgFriendlyName"] = _out_str("bgFriendlyName", bg_friendly_name)
	d["sound"] = _out_str("sound", sound)
	d["voice"] = _out_str("voice", voice)
	d["transition"] = transition
	d["bgmId"] = bgm_id
	d["selectionGroup"] = selection_group
	d["additionalPrompt"] = _out_str("additionalPrompt", additional_prompt)
	var recs: Array = []
	for i in SLOT_COUNT:
		if i < characters.size() and characters[i] is AaCharacterRecord:
			recs.append(characters[i].to_dict())
		else:
			recs.append(AaCharacterRecord.new().to_dict())
	d["characters"] = AaJson.wrap_list(AaJson.T_CHARACTER_LIST, recs)
	d["speakerSlotNum"] = speaker_slot_num
	d["highlightedSlotNums"] = AaJson.wrap_int_list(highlighted_slot_nums)
	d["isDialogScript"] = is_dialog_script
	d["placeText"] = _out_str("placeText", place_text)
	for key in extra.keys():
		d[key] = extra[key]
	return d


func _out_str(key: String, value: String) -> Variant:
	if _nulls.has(key) and value.is_empty():
		return null
	return value


# ---------------------------------------------------------------------------
# 便利方法（Player / Editor 用）
# ---------------------------------------------------------------------------

## 取指定槽位的角色记录（越界返回空记录，不崩溃）。
func get_character(slot: int) -> AaCharacterRecord:
	if slot >= 0 and slot < characters.size() and characters[slot] is AaCharacterRecord:
		return characters[slot]
	return AaCharacterRecord.new()


## 当前说话者记录（speaker_slot_num 越界时返回 0 号槽）。
func speaker() -> AaCharacterRecord:
	return get_character(speaker_slot_num)


## 说话者名字；旁白（0 号槽也空）返回 ""。
func speaker_name() -> String:
	return speaker().name


## 本行可见立绘（1–5 槽且有人），返回 [{slot, record}]。
func visible_characters() -> Array:
	var out: Array = []
	for i in range(1, SLOT_COUNT):
		var rec := get_character(i)
		if not rec.is_empty():
			out.append({"slot": i, "record": rec})
	return out


## 本行是否显示对话框（AA：isDialogScript 为 true 且有台词）。
func is_dialog() -> bool:
	return is_dialog_script and not text.is_empty()


## 计算得到的 bgName（不会被写回，用于校验历史脏数据）。
func computed_bg_id() -> int:
	return AaHash.bg_id(bg_friendly_name)


## bgName 与 bgFriendlyName 是否一致。老工程可能有大小写漂移的脏数据。
func bg_id_matches() -> bool:
	if bg_friendly_name.is_empty():
		return bg_name == 0
	return bg_name == computed_bg_id()


## 重新计算并写回 bgName，返回是否有改动。
func repair_bg_id() -> bool:
	var want := computed_bg_id()
	if bg_name == want:
		return false
	bg_name = want
	return true


## 本行是否静音 BGM（bgm_id == 999）。
func is_bgm_muted() -> bool:
	return bgm_id == 999


## 编译器会自动插入的等待（0 = 不插）：有气泡 2500ms；否则有位移/进出场/动作 1500ms。
## 只统计有人（name 非空）的槽位。
func auto_wait_ms() -> int:
	var has_emoticon := false
	var has_motion := false
	for rec in characters:
		if not (rec is AaCharacterRecord) or rec.name.is_empty():
			continue
		if rec.emoticon >= 0:
			has_emoticon = true
		if rec.appear != 0 or rec.action != 0 or rec.starting_pos != rec.ending_pos:
			has_motion = true
	if has_emoticon:
		return AUTO_WAIT_EMOTICON
	if has_motion:
		return AUTO_WAIT_MOTION
	return 0


## 作者显式写的 `#wait;毫秒`（没有返回 -1）。
func explicit_wait_ms() -> int:
	for cmd in get_commands():
		if cmd.name == AaCommands.CMD_WAIT:
			return AaCommands.wait_ms(cmd)
	return -1


## 最终生效等待：显式 `#wait` 覆盖自动等待；都没有返回 0。
func effective_wait_ms() -> int:
	var explicit := explicit_wait_ms()
	if explicit >= 0:
		return explicit
	return auto_wait_ms()


## 本行是否是旁白/无立绘说话（有台词但说话槽无角色名）。
func is_narration() -> bool:
	return is_dialog_script and not text.is_empty() and speaker_name().is_empty()


## 本行的屏幕文字指令（`#st` / `#stm`），没有返回 null。
## 屏幕文字内容就是本行的 `text`；位置/模式/字号用 AaCommands.parse_screen_text()。
func screen_text_command() -> Variant:
	for cmd in get_commands():
		if cmd.name == AaCommands.CMD_ST or cmd.name == AaCommands.CMD_STM:
			return cmd
	return null


# ---------------------------------------------------------------------------
# 编译器自动指令推导（docs/spec/commands.md §3 / §3.1）
# `.aap` 里**不存**这些自动指令，AA 编译 `.aas` 时才推导；直接播放 `.aap` 时
# 必须在运行时自己算（走位/隐藏/进出场/气泡/动作/特写/高亮）。这里提供现成推导：
# Player 按行推进时把上一行传进来即可。
# ---------------------------------------------------------------------------

## 推导本行的“舞台状态变化”（对照上一行 `prev`；null = 首次播放/本节点第一行）。
## 返回 Array[Dictionary]，每项：`{kind, slot, value?, token?, raw}`，顺序 =
## AA 编译器求值顺序：进出场 → 隐藏 → 走位 → 气泡/动作/特写/高亮 → 旁白。
## - kind="appear"    出现（token = al/ar/a/dl/dr/d）
## - kind="hide"      1–5 槽角色消失（切镜头；仅比较上一行有人的槽）
## - kind="move"      走位（value = ending_pos）
## - kind="emoticon"  气泡（value = emoticon ID，token = 原生符号）
## - kind="action"    动作（value = action ID，token = greeting/falldownl/.../jump/...）
## - kind="closeup"   特写（shapeOverride 位 4；其它位由渲染层按整行状态处理）
## - kind="highlight" 高亮（slot 来自 highlightedSlotNums，按原顺序，不保证升序）
## - kind="narration" 旁白（0 号说话槽无角色但有台词）
func derive_stage_events(prev: AaScriptLine) -> Array:
	var events: Array = []
	# 1) 进出场（新角色就位；必须先于走位，否则新角色没有起始位置）
	for i in range(1, SLOT_COUNT):
		var rec := get_character(i)
		if rec.name.is_empty() or rec.appear == 0:
			continue
		var token := AaEnums.appear_token(rec.appear)
		events.append({"kind": "appear", "slot": i, "value": rec.appear, "token": token,
			"raw": "#%d;%s" % [i, token]})
	# 2) 隐藏：上一行占着、本行为空的立绘槽
	if prev != null:
		for i in range(1, SLOT_COUNT):
			if not prev.get_character(i).name.is_empty() and get_character(i).name.is_empty():
				events.append({"kind": "hide", "slot": i, "raw": "#%d;hide" % i})
	# 3) 走位（startingPos != endingPos）
	for i in range(1, SLOT_COUNT):
		var rec := get_character(i)
		if rec.name.is_empty() or rec.starting_pos == rec.ending_pos:
			continue
		events.append({"kind": "move", "slot": i, "value": rec.ending_pos,
			"raw": "#%d;m%d" % [i, rec.ending_pos]})
	# 4) 气泡（-1 是无；0 是真实值“怒筋”）
	for i in range(1, SLOT_COUNT):
		var rec := get_character(i)
		if rec.name.is_empty() or rec.emoticon < 0:
			continue
		var symbol := AaEnums.emoticon_symbol(rec.emoticon)
		events.append({"kind": "emoticon", "slot": i, "value": rec.emoticon, "token": symbol,
			"raw": "#%d;em;%s" % [i, symbol]})
	# 5) 动作（action 6 = jump，不是气泡）
	for i in range(1, SLOT_COUNT):
		var rec := get_character(i)
		if rec.name.is_empty() or rec.action == 0:
			continue
		var token := AaEnums.action_info(rec.action).get("id", "")
		events.append({"kind": "action", "slot": i, "value": rec.action, "token": token,
			"raw": "#%d;%s" % [i, token]})
	# 6) 特写（shapeOverride 的 bit2）
	for i in range(1, SLOT_COUNT):
		var rec := get_character(i)
		if not rec.name.is_empty() and (rec.shape_override & 4) != 0:
			events.append({"kind": "closeup", "slot": i, "value": rec.shape_override,
				"raw": "#%d;closeup" % i})
	# 7) 高亮（顺序不保证升序，按原样）
	for slot in highlighted_slot_nums:
		events.append({"kind": "highlight", "slot": int(slot), "raw": "#%d;h" % slot})
	# 8) 旁白标记
	if is_narration():
		events.append({"kind": "narration", "slot": speaker_slot_num,
			"raw": "#na;%s" % text})
	return events


## 推导本行环境变化（与上一行 `prev` 对比；null = 首次）。返回 Dictionary：
## - `bg_changed` / `bg_name` / `bg_friendly_name`
## - `transition`（本行进入时的过渡 ID）/ `transition_changed`
## - `bg_effect` / `bg_effect_changed`
## - `bgm_changed` / `bgm_id`（999 = 静音）
## - `sound`（非空 = 本行播放音效）
## - `popup` / `popup_cleared`
## - `place_text`（非空 = 地点名称卡）
func derive_environment(prev: AaScriptLine) -> Dictionary:
	var changed_bg := prev == null \
		or prev.bg_name != bg_name or prev.bg_friendly_name != bg_friendly_name
	var transition_changed := prev == null or prev.transition != transition
	var bgm_changed := prev == null or prev.bgm_id != bgm_id
	var prev_popup := prev.popup if prev != null else ""
	return {
		"bg_changed": changed_bg,
		"bg_name": bg_name,
		"bg_friendly_name": bg_friendly_name,
		"transition": transition,
		"transition_changed": transition_changed,
		"bg_effect": bg_effect,
		"bg_effect_changed": prev == null or prev.bg_effect != bg_effect,
		"bgm_changed": bgm_changed,
		"bgm_id": bgm_id,
		"bgm_muted": bgm_id == 999,
		"sound": sound,
		"popup": popup,
		"popup_cleared": not prev_popup.is_empty() and popup.is_empty(),
		"place_text": place_text,
	}


## 本行实际等待：作者 `#wait` 覆盖自动等待；两者都没有返回 -1（= 等玩家点击/自动推进）。
func derive_wait_ms() -> int:
	var explicit := explicit_wait_ms()
	if explicit >= 0:
		return explicit
	var auto := auto_wait_ms()
	return auto if auto > 0 else -1


## 把一行的完整演出压成有序事件列表（给 Player 的简单实现直接消费）：
## 舞台事件（含旁白）→ 环境 → 作者额外指令 → 台词 → 等待。
## 事件 kind：
## - "appear"/"hide"/"move"/"emoticon"/"action"/"closeup"/"highlight"/"narration"
## - "environment"（env = derive_environment 的结果）
## - "command"（command = AaCommands.ExtraCommand）
## - "text"（text / bbcode / speaker_slot / speaker_name）
## - "wait"（ms，-1 = 等玩家点击）
func build_events(prev: AaScriptLine) -> Array:
	var events: Array = []
	events.append_array(derive_stage_events(prev))
	events.append({"kind": "environment", "env": derive_environment(prev)})
	for cmd in get_commands():
		events.append({"kind": "command", "command": cmd})
	events.append({
		"kind": "text",
		"text": text,
		"bbcode": get_bbcode(),
		"speaker_slot": speaker_slot_num,
		"speaker_name": speaker_name(),
	})
	events.append({"kind": "wait", "ms": derive_wait_ms()})
	return events


## 解析 `additional_prompt`（带缓存），返回 Array[AaCommands.ExtraCommand]。
func get_commands() -> Array:
	# 直接改 additional_prompt 字段也能自动失效（不强制走 set_additional_prompt）
	if _commands_dirty or additional_prompt != _commands_source:
		_commands_cache = AaCommands.parse_extra(additional_prompt)
		_commands_source = additional_prompt
		_commands_dirty = false
	return _commands_cache


## 是否有指定名字的额外指令。
func has_command(command_name: String) -> bool:
	for cmd in get_commands():
		if cmd.name == command_name:
			return true
	return false


## 解析 text 里的内联标记（带缓存），返回 Array。
func get_inline_runs() -> Array:
	if _inline_dirty or text != _inline_source:
		_inline_cache = AaCommands.parse_inline(text)
		_inline_source = text
		_inline_dirty = false
	return _inline_cache


## 给 RichTextLabel 用的 BBCode。
func get_bbcode(base_font_size := 48) -> String:
	return AaCommands.to_bbcode(text, base_font_size)


## 去掉内联标记的纯文本（backlog / 日志用）。
func plain_text() -> String:
	return AaCommands.strip_inline(text)


## 使解析缓存失效（改了 text / additional_prompt 后调用）。
func invalidate_cache() -> void:
	_commands_dirty = true
	_inline_dirty = true


func set_text(value: String) -> void:
	text = value
	_inline_dirty = true


func set_additional_prompt(value: String) -> void:
	additional_prompt = value
	_commands_dirty = true


## 深拷贝别名（编辑器 backend 通过 `has_method("duplicate")` 探测）。
func duplicate(_deep := true) -> AaScriptLine:
	return duplicate_line()


## 深拷贝（选项跳转表 / 编辑器复制用）。
func duplicate_line() -> AaScriptLine:
	var line := AaScriptLine.new()
	line.text = text
	line.popup = popup
	line.bg_effect = bg_effect
	line.bg_name = bg_name
	line.bg_friendly_name = bg_friendly_name
	line.sound = sound
	line.voice = voice
	line.transition = transition
	line.bgm_id = bgm_id
	line.selection_group = selection_group
	line.additional_prompt = additional_prompt
	line.characters = []
	for rec in characters:
		line.characters.append(rec.duplicate_record())
	line.speaker_slot_num = speaker_slot_num
	line.highlighted_slot_nums = highlighted_slot_nums.duplicate()
	line.is_dialog_script = is_dialog_script
	line.place_text = place_text
	line.extra = extra.duplicate(true)
	line._nulls = _nulls.duplicate(true)
	return line
