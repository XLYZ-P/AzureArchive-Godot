extends RefCounted
## Fallback 版 ScriptData+CharacterRecordData（字段顺序与 AA 一致）
## 只做编辑器需要的读写；core-dev 的 AaCharacterRecord 就绪后编辑器优先用 core。
## 字段见 docs/DESIGN.md §4。

const TYPE_STR := "ScriptData+CharacterRecordData, Assembly-CSharp"

var name := ""
var face_id := "00"
var starting_pos := 0
var ending_pos := 0
var emoticon := -1
var action := 0
var effect := 0
var appear := 0
var shape_override := 0

var extra: Dictionary = {}
var nulls: Dictionary = {}


func is_empty() -> bool:
	return name.is_empty()


func duplicate_record():
	var c = get_script().new()
	c.name = name
	c.face_id = face_id
	c.starting_pos = starting_pos
	c.ending_pos = ending_pos
	c.emoticon = emoticon
	c.action = action
	c.effect = effect
	c.appear = appear
	c.shape_override = shape_override
	c.extra = extra.duplicate(true)
	return c


func to_dict() -> Dictionary:
	var d := {
		"$type": TYPE_STR,
		"name": null if nulls.has("name") else name,
		"faceId": null if nulls.has("faceId") else face_id,
		"startingPos": starting_pos,
		"endingPos": ending_pos,
		"emoticon": emoticon,
		"action": action,
		"effect": effect,
		"appear": appear,
		"shapeOverride": shape_override,
	}
	for k in extra.keys():
		d[k] = extra[k]
	return d


static func from_dict(d: Dictionary):
	var c = load("res://addons/aa_editor/model/fallback_character.gd").new()
	if d.has("name") and d["name"] == null:
		c.nulls["name"] = true
	if d.has("faceId") and d["faceId"] == null:
		c.nulls["faceId"] = true
	c.name = str(d.get("name", ""))
	c.face_id = str(d.get("faceId", "00"))
	c.starting_pos = int(d.get("startingPos", 0))
	c.ending_pos = int(d.get("endingPos", 0))
	c.emoticon = int(d.get("emoticon", -1))
	c.action = int(d.get("action", 0))
	c.effect = int(d.get("effect", 0))
	c.appear = int(d.get("appear", 0))
	c.shape_override = int(d.get("shapeOverride", 0))
	var known := ["$type", "name", "faceId", "startingPos", "endingPos", "emoticon", "action", "effect", "appear", "shapeOverride"]
	for k in d.keys():
		if not known.has(k):
			c.extra[k] = d[k]
	return c
