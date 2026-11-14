class_name AaManifest
extends RefCounted
## AA `manifest.json` 读写 + 覆盖合并。
##
## AA 的 manifest 是每个工程一份的资源覆盖登记表：
##   6 字段旧版：CharacterOverrides / VoiceOverrides / PopupOverrides /
##               SoundOverrides / BgOverrides / BgmOverrides
##   8+ 字段新版（AA 1.0+）：额外 BgEffectOverrides / BgSpineOverrides
## 本类同时接受 PascalCase（AA 原生）与 snake_case（aa_pack 手写更友好）键名，
## 未知字段/未知角色字段会被保留（round-trip 不丢数据）。
##
## 覆盖优先级（低 → 高）：aa_pack < 全局 overrides/ < projects|saves/<同名文件夹>/
## 对应 `base.overlay(higher)`：把 high 合并进 base（high 胜出）。
##
## 用法：
##   var m := AaManifest.load_from_file(".../manifest.json")
##   m.overlay(AaManifest.load_from_file(".../overrides/manifest.json"))
##   m.save_to_file(".../manifest.json")

const RawLoader = preload("res://addons/aa_resources/raw_loader.gd")

## AA 写出顺序（新版 8 字段）。保存时按这个顺序输出。
const FIELD_ORDER := [
	"CharacterOverrides", "VoiceOverrides", "PopupOverrides", "SoundOverrides",
	"BgOverrides", "BgEffectOverrides", "BgSpineOverrides", "BgmOverrides",
]
const LEGACY_FIELDS := [
	"CharacterOverrides", "VoiceOverrides", "PopupOverrides", "SoundOverrides",
	"BgOverrides", "BgmOverrides",
]
const CHARACTER_FIELDS := [
	"Identifier", "Name", "Nickname", "CharacterReference",
	"OriginalIdentifier", "SpinePortraitPath", "SmallPortraitPath",
]

var character_overrides: Array = []
var voice_overrides: Array = []
var popup_overrides: Array = []
var sound_overrides: Array = []
var bg_overrides: Array = []
var bg_effect_overrides: Array = []
var bg_spine_overrides: Array = []
var bgm_overrides: Array = []

## manifest 文件所在目录（相对路径相对它解析）；空串表示"不知道根目录"。
var source_path: String = ""
## 未识别的顶层字段，原样保留（round-trip）。
var extra: Dictionary = {}
## 6 = 旧版字段集；8 = 新版（含 BgEffect/BgSpine）。仅影响写文件。
var format_version: int = 8
## 加载时的 JSON 解析错误（空串 = 正常/文件不存在）。
var load_error: String = ""


static func make_empty(version := 8) -> AaManifest:
	var m := AaManifest.new()
	m.format_version = version
	return m


static func load_from_file(path: String) -> AaManifest:
	var m := AaManifest.new()
	m.source_path = path
	if path.is_empty() or not FileAccess.file_exists(path):
		return m
	var data: Variant = RawLoader.read_json(path)
	if data == null:
		m.load_error = "JSON 解析失败: " + path
		return m
	if not (data is Dictionary):
		m.load_error = "manifest 顶层不是对象: " + path
		return m
	m._apply_dict(data)
	return m


static func from_dict(data: Dictionary, path := "") -> AaManifest:
	var m := AaManifest.new()
	m.source_path = path
	m._apply_dict(data)
	return m


func _apply_dict(data: Dictionary) -> void:
	# 先按"字段名变体"收集；大小写不敏感 + snake_case 兼容。
	var consumed: Array = []
	var found_new := false
	for field in FIELD_ORDER:
		var v: Variant = null
		var found := false
		for variant in _key_variants(field):
			if data.has(variant):
				v = data[variant]
				found = true
				consumed.append(variant)
				break
		if not found:
			continue
		match field:
			"CharacterOverrides":
				character_overrides = _normalize_characters(_as_array(v))
			"VoiceOverrides":
				voice_overrides = _normalize_path_list(_as_array(v))
			"PopupOverrides":
				popup_overrides = _normalize_path_list(_as_array(v))
			"SoundOverrides":
				sound_overrides = _normalize_path_list(_as_array(v))
			"BgOverrides":
				bg_overrides = _normalize_path_list(_as_array(v))
			"BgmOverrides":
				bgm_overrides = _normalize_path_list(_as_array(v))
			"BgEffectOverrides":
				bg_effect_overrides = _normalize_path_list(_as_array(v))
				found_new = true
			"BgSpineOverrides":
				bg_spine_overrides = _normalize_path_list(_as_array(v))
				found_new = true
	# 版本判定：只有 6 个旧字段 → 旧版；出现新字段 → 新版。
	if found_new:
		format_version = 8
	elif not data.is_empty():
		format_version = 6
	for key in data.keys():
		if not (key in consumed):
			extra[key] = data[key]


# ---------------------------------------------------------------------------
# 序列化
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var out := {}
	var full := format_version >= 8 or not bg_effect_overrides.is_empty() or not bg_spine_overrides.is_empty()
	for field in FIELD_ORDER:
		if not full and field in ["BgEffectOverrides", "BgSpineOverrides"]:
			continue
		match field:
			"CharacterOverrides":
				out[field] = _dump_characters(character_overrides)
			"VoiceOverrides":
				out[field] = _dump_paths(voice_overrides)
			"PopupOverrides":
				out[field] = _dump_paths(popup_overrides)
			"SoundOverrides":
				out[field] = _dump_paths(sound_overrides)
			"BgOverrides":
				out[field] = _dump_paths(bg_overrides)
			"BgmOverrides":
				out[field] = _dump_paths(bgm_overrides)
			"BgEffectOverrides":
				out[field] = _dump_paths(bg_effect_overrides)
			"BgSpineOverrides":
				out[field] = _dump_paths(bg_spine_overrides)
	for key in extra.keys():
		if not out.has(key):
			out[key] = extra[key]
	return out


func to_json_text(pretty := true) -> String:
	if pretty:
		return JSON.stringify(to_dict(), "  ") + "\n"
	return JSON.stringify(to_dict())


func save_to_file(path: String) -> Error:
	var text := to_json_text(true)
	var err := RawLoader.write_text(path, text)
	if err != OK:
		return err
	source_path = path
	return OK


# ---------------------------------------------------------------------------
# 合并（self 为低优先级，local 为高优先级）
# ---------------------------------------------------------------------------

func overlay(local: AaManifest) -> void:
	if local == null:
		return
	_merge_characters(local.character_overrides)
	_merge_paths(voice_overrides, local.voice_overrides, "voice")
	_merge_paths(popup_overrides, local.popup_overrides, "stem")
	_merge_paths(sound_overrides, local.sound_overrides, "stem")
	_merge_paths(bg_overrides, local.bg_overrides, "stem")
	_merge_paths(bgm_overrides, local.bgm_overrides, "stem")
	_merge_paths(bg_effect_overrides, local.bg_effect_overrides, "named")
	_merge_paths(bg_spine_overrides, local.bg_spine_overrides, "named")
	if local.format_version >= 8:
		format_version = 8
	for key in local.extra.keys():
		extra[key] = local.extra[key]


func _merge_characters(high: Array) -> void:
	for entry in high:
		if not (entry is Dictionary):
			continue
		var ident := str(entry.get("Identifier", ""))
		if ident.is_empty():
			continue
		var replaced := false
		for i in character_overrides.size():
			var existing = character_overrides[i]
			if existing is Dictionary and str(existing.get("Identifier", "")) == ident:
				character_overrides[i] = entry.duplicate(true)
				replaced = true
				break
		if not replaced:
			character_overrides.append(entry.duplicate(true))


func _merge_paths(base: Array, high: Array, key_mode: String) -> void:
	var existing := {}
	for v in base:
		existing[_path_key(v, key_mode)] = true
	for v in high:
		var key := _path_key(v, key_mode)
		# 同一 key 的不同写法（例如 Windows 反斜杠 vs 正斜杠）只保留先出现的低优先级条目，
		# 高优先级条目追加在末尾，由资源层索引时"后写覆盖先写"生效。
		if not existing.has(key):
			base.append(v.duplicate(true) if v is Dictionary else v)
			existing[key] = true


static func _path_key(v: Variant, mode: String) -> String:
	if v is Dictionary:
		var d := v as Dictionary
		for field in ["Name", "name", "Identifier", "identifier", "Path", "path"]:
			if d.has(field):
				return str(d[field]).to_lower()
		return JSON.stringify(d).to_lower()
	var s := str(v).replace("\\", "/")
	match mode:
		"voice", "stem":
			return s.get_file().get_basename().to_lower()
		_:
			return s.get_file().get_basename().to_lower() if not s.get_file().is_empty() else s.to_lower()


# ---------------------------------------------------------------------------
# 查询
# ---------------------------------------------------------------------------

func find_character(identifier: String) -> Dictionary:
	if identifier.is_empty():
		return {}
	for entry in character_overrides:
		if entry is Dictionary and str(entry.get("Identifier", "")) == identifier:
			return entry
	# 大小写/i18n 兜底
	var lower := identifier.to_lower()
	for entry in character_overrides:
		if entry is Dictionary and str(entry.get("Identifier", "")).to_lower() == lower:
			return entry
	return {}


func get_character_identifiers() -> PackedStringArray:
	var out := PackedStringArray()
	for entry in character_overrides:
		if entry is Dictionary:
			var ident := str(entry.get("Identifier", ""))
			if not ident.is_empty() and not out.has(ident):
				out.append(ident)
	return out


func is_empty() -> bool:
	return character_overrides.is_empty() and voice_overrides.is_empty() \
		and popup_overrides.is_empty() and sound_overrides.is_empty() \
		and bg_overrides.is_empty() and bgm_overrides.is_empty() \
		and bg_effect_overrides.is_empty() and bg_spine_overrides.is_empty()


func clone() -> AaManifest:
	var m := AaManifest.from_dict(to_dict(), source_path)
	m.format_version = format_version
	return m


func summary() -> Dictionary:
	return {
		"characters": character_overrides.size(),
		"voices": voice_overrides.size(),
		"popups": popup_overrides.size(),
		"sounds": sound_overrides.size(),
		"bgs": bg_overrides.size(),
		"bgeffects": bg_effect_overrides.size(),
		"bgspines": bg_spine_overrides.size(),
		"bgm": bgm_overrides.size(),
		"format_version": format_version,
	}


# ---------------------------------------------------------------------------
# 路径工具（manifest 里 AA 写的是 Windows 反斜杠相对路径）
# ---------------------------------------------------------------------------

## 规范化为 posix 风格相对路径；不安全（绝对路径 / 盘符 / ..）时返回空串。
static func normalize_relative(rel: String) -> String:
	var r := rel.replace("\\", "/").strip_edges()
	while r.begins_with("./"):
		r = r.substr(2)
	if r.is_empty() or r.begins_with("/") or r.contains(":"):
		return ""
	for part in r.split("/"):
		if part.is_empty() or part == "." or part == "..":
			return ""
	return r


## 相对路径 → 基于 manifest 所在目录的绝对/资源路径。
func resolve_relative(rel: String) -> String:
	var r := normalize_relative(rel)
	if r.is_empty():
		return ""
	var base := source_path.get_base_dir()
	if base.is_empty():
		return r
	return base.path_join(r)


func source_dir() -> String:
	return source_path.get_base_dir()


# ---------------------------------------------------------------------------
# 内部规范/序列化
# ---------------------------------------------------------------------------

static func _as_array(v: Variant) -> Array:
	if v is Array:
		return v
	if v == null:
		return []
	return [v]


static func _key_variants(field: String) -> PackedStringArray:
	var snake := ""
	for i in field.length():
		var c: String = field[i]
		if i > 0 and c == c.to_upper() and c != c.to_lower():
			snake += "_"
		snake += c.to_lower()
	return PackedStringArray([field, field.to_lower(), snake])


static func _normalize_characters(arr: Array) -> Array:
	var out: Array = []
	for v in arr:
		if not (v is Dictionary):
			continue
		var d := v as Dictionary
		var entry := {}
		for field in CHARACTER_FIELDS:
			var snake := ""
			for i in field.length():
				var c: String = field[i]
				if i > 0 and c == c.to_upper() and c != c.to_lower():
					snake += "_"
				snake += c.to_lower()
			if d.has(field):
				entry[field] = d[field]
			elif d.has(snake):
				entry[field] = d[snake]
			else:
				entry[field] = null
		for key in d.keys():
			if not entry.has(key):
				entry[key] = d[key]
		out.append(entry)
	return out


static func _normalize_path_list(arr: Array) -> Array:
	var out: Array = []
	for v in arr:
		if v is Dictionary:
			out.append(v.duplicate(true))
		else:
			var s := str(v)
			if not s.is_empty():
				out.append(s)
	return out


static func _dump_characters(arr: Array) -> Array:
	var out: Array = []
	for entry in arr:
		if entry is Dictionary:
			out.append((entry as Dictionary).duplicate(true))
	return out


static func _dump_paths(arr: Array) -> Array:
	var out: Array = []
	for v in arr:
		out.append(v.duplicate(true) if v is Dictionary else str(v))
	return out
