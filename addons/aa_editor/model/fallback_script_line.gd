extends RefCounted
## Fallback 版 ScriptData（一行脚本，字段顺序与 AA 严格一致）
## 字段见 docs/DESIGN.md §4 / docs/spec/aap.md。core-dev 的 AaScriptLine 就绪后优先用 core。

const TYPE_STR := "ScriptData, Assembly-CSharp"
const CHAR_SCRIPT = preload("res://addons/aa_editor/model/fallback_character.gd")

var text := ""
var popup := ""
var bg_effect := 0
var bg_name := 0
var bg_friendly_name := ""
var sound := ""
var voice := ""
var transition := 0
var bgm_id := 999
var selection_group := 0
var additional_prompt := ""
var characters: Array = []          # 6 个 CharacterRecord
var speaker_slot_num := 0
var highlighted_slot_nums: Array = []
var is_dialog_script := true
var place_text := ""

var extra: Dictionary = {}
## 源 JSON 中为 null 的字段（round-trip 保留 null）
var nulls: Dictionary = {}

const _NULLABLE := ["text", "popup", "bgFriendlyName", "sound", "voice", "additionalPrompt", "placeText"]


func _init() -> void:
	for i in 6:
		characters.append(CHAR_SCRIPT.new())


func is_empty() -> bool:
	if not text.strip_edges().is_empty():
		return false
	if not additional_prompt.strip_edges().is_empty():
		return false
	if not popup.is_empty() or not sound.is_empty() or not voice.is_empty() or not place_text.is_empty():
		return false
	if bg_friendly_name != "" or bg_effect != 0 or transition != 0 or bgm_id != 999:
		return false
	if not highlighted_slot_nums.is_empty():
		return false
	for c in characters:
		if not c.is_empty():
			return false
	return true


## 该行是否有立绘（1-5 槽有角色）
func has_portrait() -> bool:
	for i in range(1, characters.size()):
		if not characters[i].is_empty():
			return true
	return false


func to_dict() -> Dictionary:
	var chars := []
	for c in characters:
		chars.append(c.to_dict())
	var d := {
		"$type": TYPE_STR,
		"text": null if nulls.has("text") else text,
		"popup": null if nulls.has("popup") else popup,
		"bgEffect": bg_effect,
		"bgName": bg_name,
		"bgFriendlyName": null if nulls.has("bgFriendlyName") else bg_friendly_name,
		"sound": null if nulls.has("sound") else sound,
		"voice": null if nulls.has("voice") else voice,
		"transition": transition,
		"bgmId": bgm_id,
		"selectionGroup": selection_group,
		"additionalPrompt": null if nulls.has("additionalPrompt") else additional_prompt,
		"characters": {"$type": "System.Collections.Generic.List`1[[ScriptData+CharacterRecordData, Assembly-CSharp]], mscorlib", "$values": chars},
		"speakerSlotNum": speaker_slot_num,
		"highlightedSlotNums": {"$type": "System.Collections.Generic.List`1[[System.Int32, mscorlib]], mscorlib", "$values": highlighted_slot_nums.duplicate()},
		"isDialogScript": is_dialog_script,
		"placeText": null if nulls.has("placeText") else place_text,
	}
	for k in extra.keys():
		d[k] = extra[k]
	return d


static func from_dict(d: Dictionary):
	var line = load("res://addons/aa_editor/model/fallback_script_line.gd").new()
	for k in _NULLABLE:
		if d.has(k) and d[k] == null:
			line.nulls[k] = true
	line.text = str(d.get("text", ""))
	line.popup = str(d.get("popup", ""))
	line.bg_effect = int(d.get("bgEffect", 0))
	line.bg_name = int(d.get("bgName", 0))
	line.bg_friendly_name = str(d.get("bgFriendlyName", ""))
	line.sound = str(d.get("sound", ""))
	line.voice = str(d.get("voice", ""))
	line.transition = int(d.get("transition", 0))
	line.bgm_id = int(d.get("bgmId", 999))
	line.selection_group = int(d.get("selectionGroup", 0))
	line.additional_prompt = str(d.get("additionalPrompt", ""))
	line.speaker_slot_num = int(d.get("speakerSlotNum", 0))
	line.is_dialog_script = bool(d.get("isDialogScript", true))
	line.place_text = str(d.get("placeText", ""))
	var hl = d.get("highlightedSlotNums", {})
	if hl is Dictionary:
		var vals = hl.get("$values", [])
		if vals is Array:
			for v in vals:
				line.highlighted_slot_nums.append(int(v))
	var chars = d.get("characters", {})
	var vals = []
	if chars is Dictionary:
		vals = chars.get("$values", [])
	elif chars is Array:
		vals = chars
	line.characters.clear()
	for i in 6:
		if i < vals.size() and vals[i] is Dictionary:
			line.characters.append(CHAR_SCRIPT.from_dict(vals[i]))
		else:
			line.characters.append(CHAR_SCRIPT.new())
	var known := [
		"$type", "text", "popup", "bgEffect", "bgName", "bgFriendlyName", "sound", "voice",
		"transition", "bgmId", "selectionGroup", "additionalPrompt", "characters",
		"speakerSlotNum", "highlightedSlotNums", "isDialogScript", "placeText",
	]
	for k in d.keys():
		if not known.has(k):
			line.extra[k] = d[k]
	return line
