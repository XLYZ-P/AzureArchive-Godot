class_name AaCharacterRecord
extends RefCounted
## AA `ScriptData+CharacterRecordData`：一行里某个槽位上的角色状态。
##
## `characters` 恒 6 项：
## - 下标 0 = **无立绘说话槽**（旁白 / 只有声音不出立绘的角色；startingPos 恒 0）；
## - 下标 1–5 = 五个可见立绘位，下标就是 `startingPos`（编译器写 `#N;...` 时的 N 也是下标）。
##
## 字段顺序（AA 序列化严格顺序，改顺序会导致 AA 读不了）：
## `name, faceId, startingPos, endingPos, emoticon, action, effect, appear, shapeOverride`
##
## `-1` 表示“无表情”，注意 `emoticon = 0` 是真实值（怒筋）。

const TYPE_STRING := AaJson.T_CHARACTER
## 6 个槽位
const SLOT_COUNT := 6
## 立绘槽数量（1–5）
const PORTRAIT_SLOTS := 5

var name: String = ""
var face_id: String = "00"
var starting_pos: int = 0
var ending_pos: int = 0
var emoticon: int = -1
var action: int = 0
## 恒为 0（112770 条实测确认未使用；立绘效果写在 shape_override）
var effect: int = 0
var appear: int = 0
var shape_override: int = 0

## 未知字段（向前兼容：原样保留，序列化时追加在已知字段之后）
var extra: Dictionary = {}
## 源 JSON 中值为 null 的字符串字段（AA 对未设置的可选字符串写 null；原样保留）
var _nulls: Dictionary = {}


static func make_empty() -> AaCharacterRecord:
	return AaCharacterRecord.new()


static func from_dict(d: Variant) -> AaCharacterRecord:
	var rec := AaCharacterRecord.new()
	if not (d is Dictionary):
		return rec
	var dd: Dictionary = d
	rec.name = AaJson.get_str(dd, "name", "")
	rec.face_id = AaJson.get_str(dd, "faceId", "00")
	rec.starting_pos = AaJson.get_int(dd, "startingPos", 0)
	rec.ending_pos = AaJson.get_int(dd, "endingPos", 0)
	rec.emoticon = AaJson.get_int(dd, "emoticon", -1)
	rec.action = AaJson.get_int(dd, "action", 0)
	rec.effect = AaJson.get_int(dd, "effect", 0)
	rec.appear = AaJson.get_int(dd, "appear", 0)
	rec.shape_override = AaJson.get_int(dd, "shapeOverride", 0)
	for key in ["name", "faceId"]:
		if AaJson.is_null_field(dd, key):
			rec._nulls[key] = true
	# 未知字段原样保留
	for key in dd.keys():
		if not _KNOWN.has(key):
			rec.extra[key] = dd[key]
	return rec


const _KNOWN := {
	"$type": true, "name": true, "faceId": true, "startingPos": true,
	"endingPos": true, "emoticon": true, "action": true, "effect": true,
	"appear": true, "shapeOverride": true,
}


func to_dict() -> Dictionary:
	var d := {}
	d["$type"] = TYPE_STRING
	d["name"] = _out_str("name", name)
	d["faceId"] = _out_str("faceId", face_id)
	d["startingPos"] = starting_pos
	d["endingPos"] = ending_pos
	d["emoticon"] = emoticon
	d["action"] = action
	d["effect"] = effect
	d["appear"] = appear
	d["shapeOverride"] = shape_override
	for key in extra.keys():
		d[key] = extra[key]
	return d


func _out_str(key: String, value: String) -> Variant:
	if _nulls.has(key) and value.is_empty():
		return null
	return value


## 该槽位是否无人（AA 用空字符串表示）。
func is_empty() -> bool:
	return name.is_empty()


## 该槽位是否需要显示立绘（1–5 槽且有人）。
func is_visible() -> bool:
	return starting_pos >= 1 and not name.is_empty()


## 本行是否有位移。
func is_moving() -> bool:
	return starting_pos != ending_pos


func duplicate_record() -> AaCharacterRecord:
	var rec := AaCharacterRecord.new()
	rec.name = name
	rec.face_id = face_id
	rec.starting_pos = starting_pos
	rec.ending_pos = ending_pos
	rec.emoticon = emoticon
	rec.action = action
	rec.effect = effect
	rec.appear = appear
	rec.shape_override = shape_override
	rec.extra = extra.duplicate(true)
	rec._nulls = _nulls.duplicate(true)
	return rec


func clear() -> void:
	name = ""
	face_id = "00"
	starting_pos = 0
	ending_pos = 0
	emoticon = -1
	action = 0
	effect = 0
	appear = 0
	shape_override = 0
	_nulls.clear()
