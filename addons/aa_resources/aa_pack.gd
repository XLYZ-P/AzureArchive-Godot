class_name AaPack
extends RefCounted
## 开放资源包 aa_pack 的读取器（目录 或 .zip）。
##
## 布局（详见 tools/README.md）：
##   <aa_pack>/
##     catalog.json            # 唯一必需元数据
##     manifest.json           # 可选：AA 兼容的覆盖登记表
##     bgs/ bgm/ sounds/ popups/ characters/<id>/ voices/ fonts/ ui/ bg_effects/
##
## catalog 里没列出的文件也会按目录命名规则扫描兜底（目录形态时）
## 或按相对路径扫描（zip 形态时）；catalog 条目优先。
##
## 本类不依赖导入器：贴图/音频都经 AaRawLoader 运行时加载。

const RawLoader = preload("res://addons/aa_resources/raw_loader.gd")
const AaManifestScript = preload("res://addons/aa_resources/aa_manifest.gd")
const CharacterAsset = preload("res://addons/aa_resources/character_asset.gd")
const ResHash = preload("res://addons/aa_resources/res_hash.gd")

const CATALOG_FILE := "catalog.json"
const PACK_FILE := "pack.json"
const MANIFEST_FILE := "manifest.json"
const KNOWN_DIRS := ["bgs", "bgm", "sounds", "popups", "characters", "voices", "fonts", "ui", "bg_effects"]
const IMAGE_EXTS := ["png", "webp", "jpg", "jpeg"]
const AUDIO_EXTS := ["ogg", "wav", "mp3", "flac"]
const SPINE_EXTS := ["skel", "atlas"]

var id: String = ""
var name: String = ""
var version: String = ""
var author: String = ""
var description: String = ""
var game: String = "AzureArchive"
var format: String = "aa_pack"
var format_version: int = 1

## 目录路径或 zip 文件路径。
var path: String = ""
var is_zip: bool = false
var catalog: Dictionary = {}
var pack_meta: Dictionary = {}
var _pack_meta: Dictionary = {}
var manifest: AaManifest = null
var valid: bool = false
var errors: PackedStringArray = PackedStringArray()

var _zip: ZIPReader = null
var _rel_files: PackedStringArray = PackedStringArray()
var _rel_files_loaded := false
## docs/spec/resources.md D 节的 `pack.json + catalog.entries` 现代格式（只读兼容）。
var _modern := false
var _modern_entries: Array = []


static func from_path(p: String) -> AaPack:
	var pack := AaPack.new()
	pack.path = p
	pack.is_zip = p.get_extension().to_lower() == "zip"
	pack._load()
	return pack


func _load() -> void:
	id = path.get_file().get_basename()
	if not is_zip:
		if not DirAccess.dir_exists_absolute(path):
			errors.append("目录不存在: " + path)
			return
		var catalog_path := path.path_join(CATALOG_FILE)
		if FileAccess.file_exists(catalog_path):
			var data: Variant = RawLoader.read_json(catalog_path)
			if data is Dictionary:
				catalog = data
			else:
				errors.append("catalog.json 解析失败")
		var pack_path := path.path_join(PACK_FILE)
		if FileAccess.file_exists(pack_path):
			var pdata: Variant = RawLoader.read_json(pack_path)
			if pdata is Dictionary:
				_pack_meta = pdata
		var manifest_path := path.path_join(MANIFEST_FILE)
		if FileAccess.file_exists(manifest_path):
			manifest = AaManifestScript.load_from_file(manifest_path)
	else:
		var err := _ensure_zip()
		if err != OK:
			errors.append("无法打开 zip: %s (%d)" % [path, err])
			return
		var catalog_bytes := _zip.read_file(CATALOG_FILE)
		if not catalog_bytes.is_empty():
			var data: Variant = JSON.parse_string(catalog_bytes.get_string_from_utf8())
			if data is Dictionary:
				catalog = data
			else:
				errors.append("catalog.json 解析失败")
		var pack_bytes := _zip.read_file(PACK_FILE)
		if not pack_bytes.is_empty():
			var pdata: Variant = JSON.parse_string(pack_bytes.get_string_from_utf8())
			if pdata is Dictionary:
				_pack_meta = pdata
		var manifest_bytes := _zip.read_file(MANIFEST_FILE)
		if not manifest_bytes.is_empty():
			var mdata: Variant = JSON.parse_string(manifest_bytes.get_string_from_utf8())
			if mdata is Dictionary:
				manifest = AaManifestScript.from_dict(mdata, "")
	if manifest == null:
		manifest = AaManifestScript.make_empty()
	_detect_modern_format()
	_apply_metadata()
	if catalog.is_empty() and _pack_meta.is_empty():
		name = id
		version = "0"
		errors.append("缺少 catalog.json/pack.json（按目录命名规则兜底扫描）")
	elif not catalog.is_empty() and _pack_meta.is_empty():
		pass
	if id.is_empty():
		id = "unnamed_pack"
	valid = true  # 有目录/zip 就允许尽力读取；catalog 缺失只记 warning


func close() -> void:
	if _zip != null:
		_zip.close()
		_zip = null


func _ensure_zip() -> Error:
	if not is_zip:
		return OK
	if _zip != null:
		return OK
	_zip = ZIPReader.new()
	return _zip.open(path)


func dir_path() -> String:
	return "" if is_zip else path


func pack_label() -> String:
	return "pack:%s" % id


# ---------------------------------------------------------------------------
# 文件访问
# ---------------------------------------------------------------------------

func read_bytes(rel: String) -> PackedByteArray:
	var safe := AaManifestScript.normalize_relative(rel)
	if safe.is_empty():
		return PackedByteArray()
	if is_zip:
		if _ensure_zip() != OK:
			return PackedByteArray()
		return _zip.read_file(safe)
	if not FileAccess.file_exists(path.path_join(safe)):
		return PackedByteArray()
	return RawLoader.read_bytes(path.path_join(safe))


func has_file(rel: String) -> bool:
	var safe := AaManifestScript.normalize_relative(rel)
	if safe.is_empty():
		return false
	if is_zip:
		if _ensure_zip() != OK:
			return false
		return _zip.file_exists(safe)
	return FileAccess.file_exists(path.path_join(safe))


func resolve_path(rel: String) -> String:
	var safe := AaManifestScript.normalize_relative(rel)
	if safe.is_empty() or is_zip:
		return ""
	var full := path.path_join(safe)
	return full if FileAccess.file_exists(full) else ""


## 解析"不带后缀"的 Spine 资源路径：检查 .skel/.atlas/同名 png 是否存在，
## 返回不带后缀的绝对路径（供 AaCharacterAsset 自行补后缀）。zip 包返回空。
func resolve_stem_path(rel: String) -> String:
	var safe := AaManifestScript.normalize_relative(rel)
	if safe.is_empty() or is_zip:
		return ""
	var full := path.path_join(safe)
	for ext in ["", ".skel", ".atlas", ".png", ".webp"]:
		if FileAccess.file_exists(full + ext):
			return full
	return ""


## 贴图：目录形态直接用 AaRawLoader（带缓存），zip 形态从内存解码。
func get_texture(rel: String) -> Texture2D:
	var full := resolve_path(rel)
	if not full.is_empty():
		return RawLoader.load_texture(full)
	if is_zip:
		return RawLoader.load_texture_from_bytes(read_bytes(rel))
	return null


## 音频：目录形态直接加载，zip 形态从内存解码。
func get_audio(rel: String) -> AudioStream:
	var full := resolve_path(rel)
	if not full.is_empty():
		return RawLoader.load_audio(full)
	if is_zip:
		return RawLoader.load_audio_from_bytes(read_bytes(rel), rel.get_extension())
	return null


## 所有文件相对路径（posix 风格）。
func rel_files() -> PackedStringArray:
	if _rel_files_loaded:
		return _rel_files
	_rel_files_loaded = true
	var out := PackedStringArray()
	if is_zip:
		if _ensure_zip() == OK:
			for f in _zip.get_files():
				out.append(f.replace("\\", "/"))
		return out
	if not DirAccess.dir_exists_absolute(path):
		return out
	for full in RawLoader.list_files_recursive(path):
		var rel := full.trim_prefix(path + "/").trim_prefix(path)
		out.append(rel.replace("\\", "/"))
	return out


# ---------------------------------------------------------------------------
# 两种 catalog 形态兼容：
#   A) 本工具实现的扁平格式：catalog.json 里直接有 bgs/bgm/sounds/popups/characters...
#   B) docs/spec/resources.md D 节提案：pack.json + catalog.json {format:"aa_pack/1", entries:[...]}
# 两种都转成同一套 get_*_entries() 输出，资源层其余代码无感。
# ---------------------------------------------------------------------------

func _detect_modern_format() -> void:
	var fmt := str(catalog.get("format", ""))
	if catalog.has("entries") and catalog.get("entries") is Array:
		_modern = true
		_modern_entries = catalog.get("entries")
	elif fmt.begins_with("aa_pack/"):
		_modern = true
		var entries: Variant = catalog.get("entries", [])
		_modern_entries = entries if entries is Array else []


func _apply_metadata() -> void:
	var meta := _pack_meta
	if meta.is_empty():
		meta = catalog
	pack_meta = _pack_meta.duplicate(true)
	id = str(meta.get("id", meta.get("pack_id", id))).strip_edges()
	name = str(meta.get("name", meta.get("title", id)))
	version = str(meta.get("version", meta.get("pack_version", "0")))
	author = str(meta.get("author", meta.get("source", "")))
	description = str(meta.get("description", meta.get("notes", "")))
	game = str(meta.get("game", "AzureArchive"))
	format = str(meta.get("format", "aa_pack"))
	if format.is_empty():
		format = "aa_pack"
	if not catalog.is_empty() and catalog.has("id") and not catalog.has("name") and _pack_meta.is_empty():
		id = str(catalog.get("id", id)).strip_edges()
	if id.is_empty():
		id = path.get_file().get_basename() if not is_zip else "unnamed_pack"


func is_modern_format() -> bool:
	return _modern


func _modern_of(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw in _modern_entries:
		if raw is Dictionary and str((raw as Dictionary).get("kind", "")) == kind:
			out.append(raw as Dictionary)
	return out


func _modern_meta(e: Dictionary) -> Dictionary:
	var meta: Variant = e.get("meta", {})
	return meta if meta is Dictionary else {}


func _modern_bg_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _modern_of("background"):
		var meta := _modern_meta(e)
		var name := str(e.get("key", "")).strip_edges()
		var raw_id: Variant = e.get("id", null)
		if name.is_empty() and raw_id != null:
			name = str(raw_id)
		if name.is_empty():
			name = str(e.get("path", "")).get_file().get_basename()
		if name.is_empty():
			continue
		var bg_id := ResHash.bg_id(name)
		if raw_id != null and is_number_like(raw_id):
			bg_id = int(raw_id)
		out.append({
			"name": name, "id": bg_id, "file": str(e.get("path", "")),
			"category": str(meta.get("category", "背景")),
			"source": pack_label(), "pack_id": id,
		})
	return out


func _modern_audio_entries(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var entry_kind := "bgm" if kind == "bgm" else "sound"
	for e in _modern_of(entry_kind):
		var meta := _modern_meta(e)
		var key := str(e.get("key", "")).strip_edges()
		var raw_id: Variant = e.get("id", null)
		if key.is_empty() and raw_id != null:
			key = str(raw_id)
		if key.is_empty():
			key = str(e.get("path", "")).get_file().get_basename()
		if key.is_empty():
			continue
		out.append({
			"key": key, "name": key,
			"title": str(meta.get("title", e.get("title", key))),
			"id": int(raw_id) if raw_id != null and is_number_like(raw_id) else null,
			"file": str(e.get("path", "")),
			"source": pack_label(), "pack_id": id,
		})
	return out


func _modern_simple_entries(kind: String, id_field: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _modern_of(kind):
		var name := str(e.get("key", e.get("id", ""))).strip_edges()
		if name.is_empty():
			name = str(e.get("path", "")).get_file().get_basename()
		if name.is_empty():
			continue
		var item := {"file": str(e.get("path", "")), "name": name,
			"source": pack_label(), "pack_id": id}
		if id_field == "guid":
			item["guid"] = str(e.get("id", name))
			item["text"] = str(_modern_meta(e).get("text", ""))
		else:
			item["category"] = str(_modern_meta(e).get("category", kind))
		out.append(item)
	return out


func _modern_bg_effect_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _modern_of("bg_effect"):
		var meta := _modern_meta(e)
		var name := str(e.get("key", e.get("id", ""))).strip_edges()
		var raw_id: Variant = e.get("id", null)
		if name.is_empty() and raw_id != null:
			name = str(raw_id)
		if name.is_empty():
			continue
		out.append({
			"name": name,
			"id": int(raw_id) if raw_id != null and is_number_like(raw_id) else ResHash.bg_id(name),
			"file": str(e.get("path", "")),
			"type": str(meta.get("type", "json")),
			"params": meta,
			"source": pack_label(), "pack_id": id,
		})
	return out


static func is_number_like(value: Variant) -> bool:
	if value is int or value is float:
		return true
	if value is String:
		return (value as String).is_valid_int()
	return false


func _modern_character_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw in _modern_entries:
		if not (raw is Dictionary):
			continue
		var e := raw as Dictionary
		var kind := str(e.get("kind", ""))
		if kind != "character" and kind != "portrait_png":
			continue
		var identifier := str(e.get("id", e.get("identifier", ""))).strip_edges()
		if identifier.is_empty():
			continue
		var meta := _modern_meta(e)
		var asset_path := str(e.get("path", "")).strip_edges()
		var dir_rel := str(e.get("dir", "")).strip_edges()
		if dir_rel.is_empty():
			dir_rel = asset_path.get_base_dir() if not asset_path.get_basename().is_empty() else asset_path
			if dir_rel == asset_path:
				dir_rel = ""
		var mode := str(meta.get("mode", "spine" if kind == "character" else "png"))
		var face_files := {}
		var faces: Variant = meta.get("faces", [])
		if faces is Array and not dir_rel.is_empty():
			for face in faces:
				var face_id := str(face)
				for ext in IMAGE_EXTS:
					var candidate := dir_rel.path_join(face_id + "." + ext)
					if has_file(candidate):
						face_files[face_id] = candidate
						break
		out.append({
			"identifier": identifier,
			"display_name": str(e.get("key", meta.get("display_name", identifier))),
			"nickname": str(e.get("nickname", meta.get("nickname", ""))),
			"native_reference": meta.get("reference", e.get("reference", null)),
			"dir": dir_rel,
			"face_files": face_files,
			"small_portrait": str(e.get("avatar", meta.get("avatar", ""))),
			"portrait_mode": mode,
			"spine_base": asset_path if mode == "spine" or kind == "character" else "",
			"stem": asset_path.get_file(),
			"source": pack_label(),
			"pack_id": id,
		})
	return out


func list_files(dir_rel: String, exts: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var out := PackedStringArray()
	var prefix := dir_rel.replace("\\", "/").strip_edges()
	if not prefix.is_empty() and not prefix.ends_with("/"):
		prefix += "/"
	for rel in rel_files():
		if not prefix.is_empty() and not rel.begins_with(prefix):
			continue
		if exts.is_empty() or rel.get_extension().to_lower() in exts:
			out.append(rel)
	return out


func list_dirs(dir_rel: String) -> PackedStringArray:
	var out := PackedStringArray()
	var prefix := dir_rel.replace("\\", "/").strip_edges()
	if not prefix.is_empty() and not prefix.ends_with("/"):
		prefix += "/"
	for rel in rel_files():
		if not rel.begins_with(prefix):
			continue
		var rest := rel.substr(prefix.length())
		var first := rest.split("/")[0]
		if rest.contains("/") and not out.has(first):
			out.append(first)
	return out


# ---------------------------------------------------------------------------
# 各类型条目
# ---------------------------------------------------------------------------

func _catalog_entries(key: String) -> Array:
	var v: Variant = catalog.get(key)
	if v is Array:
		return v
	return []


func _normalize_file_entry(raw: Variant, category: String, default_name := "") -> Dictionary:
	var entry := {"file": "", "name": default_name, "category": category, "extra": {}}
	if raw is String:
		entry["file"] = AaManifestScript.normalize_relative(raw)
	elif raw is Dictionary:
		var d := raw as Dictionary
		for key in ["file", "File", "path", "Path"]:
			if d.has(key):
				entry["file"] = AaManifestScript.normalize_relative(str(d[key]))
				break
		for key in ["name", "Name", "key", "Key", "id", "Identifier"]:
			if d.has(key):
				entry["name"] = str(d[key])
				break
		for key in ["category", "Category"]:
			if d.has(key):
				entry["category"] = str(d[key])
				break
		entry["extra"] = d.duplicate(true)
	if str(entry["file"]).is_empty():
		return {}
	if str(entry["name"]).is_empty():
		entry["name"] = str(entry["file"]).get_file().get_basename()
	return entry


func get_bg_entries() -> Array[Dictionary]:
	if _modern:
		return _modern_bg_entries()
	var out: Array[Dictionary] = []
	var seen := {}
	for raw in _catalog_entries("bgs"):
		var e := _normalize_file_entry(raw, "背景")
		if e.is_empty():
			continue
		var bg_name := str(e["name"])
		if seen.has(bg_name.to_lower()):
			continue
		seen[bg_name.to_lower()] = true
		var extra: Dictionary = e["extra"]
		var explicit_id: Variant = extra.get("id", extra.get("Id", null))
		var bg_id := int(explicit_id) if explicit_id != null else ResHash.bg_id(bg_name)
		out.append({
			"name": bg_name,
			"id": bg_id,
			"file": e["file"],
			"category": e["category"],
			"source": pack_label(),
			"pack_id": id,
		})
	for rel in list_files("bgs", PackedStringArray(IMAGE_EXTS)):
		var bg_name := rel.get_file().get_basename()
		if seen.has(bg_name.to_lower()):
			continue
		seen[bg_name.to_lower()] = true
		out.append({
			"name": bg_name,
			"id": ResHash.bg_id(bg_name),
			"file": rel,
			"category": "背景",
			"source": pack_label(),
			"pack_id": id,
		})
	return out


func get_audio_entries(kind: String) -> Array[Dictionary]:
	if _modern:
		return _modern_audio_entries(kind)
	var out: Array[Dictionary] = []
	var seen := {}
	for raw in _catalog_entries(kind):
		var e := _normalize_file_entry(raw, kind)
		if e.is_empty():
			continue
		var key := str(e["name"])
		if seen.has(key.to_lower()):
			continue
		seen[key.to_lower()] = true
		var extra: Dictionary = e["extra"]
		var title := key
		for field in ["title", "Title", "description"]:
			if extra.has(field):
				title = str(extra[field])
				break
		out.append({
			"key": key,
			"name": key,
			"title": title,
			"id": extra.get("id", null),
			"file": e["file"],
			"source": pack_label(),
			"pack_id": id,
		})
	for rel in list_files(kind, PackedStringArray(AUDIO_EXTS)):
		var key := rel.get_file().get_basename()
		if seen.has(key.to_lower()):
			continue
		seen[key.to_lower()] = true
		out.append({
			"key": key,
			"name": key,
			"title": key,
			"id": null,
			"file": rel,
			"source": pack_label(),
			"pack_id": id,
		})
	return out


func get_popup_entries() -> Array[Dictionary]:
	if _modern:
		return _modern_simple_entries("popup", "name")
	var out: Array[Dictionary] = []
	var seen := {}
	for raw in _catalog_entries("popups"):
		var e := _normalize_file_entry(raw, "弹出图")
		if e.is_empty():
			continue
		var key := str(e["name"])
		if seen.has(key.to_lower()):
			continue
		seen[key.to_lower()] = true
		out.append({"name": key, "file": e["file"], "category": e["category"],
			"source": pack_label(), "pack_id": id})
	for rel in list_files("popups", PackedStringArray(IMAGE_EXTS)):
		var key := rel.get_file().get_basename()
		if seen.has(key.to_lower()):
			continue
		seen[key.to_lower()] = true
		out.append({"name": key, "file": rel, "category": "弹出图",
			"source": pack_label(), "pack_id": id})
	return out


func get_voice_entries() -> Array[Dictionary]:
	if _modern:
		return _modern_simple_entries("voice", "guid")
	var out: Array[Dictionary] = []
	var seen := {}
	for raw in _catalog_entries("voices"):
		var e := _normalize_file_entry(raw, "语音", "")
		if e.is_empty():
			continue
		var guid := str(e["name"])
		if seen.has(guid.to_lower()):
			continue
		seen[guid.to_lower()] = true
		var extra: Dictionary = e["extra"]
		out.append({
			"guid": guid,
			"file": e["file"],
			"text": str(extra.get("text", extra.get("Text", ""))),
			"source": pack_label(),
			"pack_id": id,
		})
	for rel in list_files("voices", PackedStringArray(AUDIO_EXTS)):
		var guid := rel.get_file().get_basename()
		if seen.has(guid.to_lower()):
			continue
		seen[guid.to_lower()] = true
		out.append({"guid": guid, "file": rel, "text": "",
			"source": pack_label(), "pack_id": id})
	return out


func get_font_entries() -> Array[Dictionary]:
	if _modern:
		return _modern_simple_entries("font", "name")
	var out: Array[Dictionary] = []
	for raw in _catalog_entries("fonts"):
		var e := _normalize_file_entry(raw, "字体")
		if not e.is_empty():
			out.append({"name": e["name"], "file": e["file"], "category": e["category"],
				"source": pack_label(), "pack_id": id})
	for rel in list_files("fonts", PackedStringArray(["ttf", "otf", "woff", "woff2"])):
		out.append({"name": rel.get_file().get_basename(), "file": rel, "category": "字体",
			"source": pack_label(), "pack_id": id})
	return out


func get_ui_entries() -> Array[Dictionary]:
	if _modern:
		var out: Array[Dictionary] = _modern_simple_entries("ui", "name")
		out.append_array(_modern_simple_entries("avatar", "name"))
		return out
	var out: Array[Dictionary] = []
	var seen := {}
	for raw in _catalog_entries("ui"):
		var e := _normalize_file_entry(raw, "UI")
		if e.is_empty():
			continue
		if seen.has(str(e["name"]).to_lower()):
			continue
		seen[str(e["name"]).to_lower()] = true
		out.append({"name": e["name"], "file": e["file"], "category": e["category"],
			"source": pack_label(), "pack_id": id})
	for rel in list_files("ui", PackedStringArray(IMAGE_EXTS)):
		var key := rel.get_file().get_basename()
		if seen.has(key.to_lower()):
			continue
		seen[key.to_lower()] = true
		out.append({"name": key, "file": rel, "category": "UI",
			"source": pack_label(), "pack_id": id})
	return out


func get_bg_effect_entries() -> Array[Dictionary]:
	if _modern:
		return _modern_bg_effect_entries()
	var out: Array[Dictionary] = []
	var seen := {}
	for raw in _catalog_entries("bg_effects"):
		var e := _normalize_file_entry(raw, "背景效果")
		if e.is_empty():
			continue
		var effect_name := str(e["name"])
		if seen.has(effect_name.to_lower()):
			continue
		seen[effect_name.to_lower()] = true
		var extra: Dictionary = e["extra"]
		var explicit_id: Variant = extra.get("id", extra.get("Id", null))
		var effect_id := int(explicit_id) if explicit_id != null else ResHash.bg_id(effect_name)
		out.append({
			"name": effect_name,
			"id": effect_id,
			"file": e["file"],
			"type": str(extra.get("type", extra.get("Type", "json"))),
			"params": extra.get("params", {}),
			"source": pack_label(),
			"pack_id": id,
		})
	for rel in list_files("bg_effects", PackedStringArray(["json", "prefab", "txt"])):
		var effect_name := rel.get_file().get_basename()
		if seen.has(effect_name.to_lower()):
			continue
		seen[effect_name.to_lower()] = true
		out.append({"name": effect_name, "id": ResHash.bg_id(effect_name), "file": rel,
			"type": "json", "params": {}, "source": pack_label(), "pack_id": id})
	return out


## 角色条目：catalog 优先，`characters/<id>/` 目录兜底扫描。
func get_character_entries() -> Array[Dictionary]:
	if _modern:
		return _modern_character_entries()
	var out: Array[Dictionary] = []
	var seen := {}
	for raw in _catalog_entries("characters"):
		if not (raw is Dictionary):
			continue
		var d := raw as Dictionary
		var identifier := str(d.get("identifier", d.get("Identifier", ""))).strip_edges()
		var dir_rel := str(d.get("dir", d.get("Dir", ""))).strip_edges()
		if identifier.is_empty() and not dir_rel.is_empty():
			identifier = dir_rel.get_file()
		if identifier.is_empty():
			continue
		if dir_rel.is_empty():
			dir_rel = "characters/" + identifier
		seen[identifier.to_lower()] = true
		var stem := dir_rel.get_file()
		var spine_base_rel := str(d.get("spine_base", d.get("SpinePortraitPath", ""))).strip_edges()
		if spine_base_rel.is_empty():
			for rel in list_files(dir_rel, PackedStringArray(SPINE_EXTS)):
				spine_base_rel = rel.get_basename()
				break
		out.append({
			"identifier": identifier,
			"display_name": str(d.get("display_name", d.get("Name", identifier))),
			"nickname": str(d.get("nickname", d.get("Nickname", ""))),
			"native_reference": d.get("native_reference", d.get("CharacterReference", null)),
			"dir": dir_rel,
			"face_files": d.get("face_files", d.get("faceFiles", {})),
			"small_portrait": str(d.get("small_portrait", d.get("SmallPortraitPath", ""))),
			"portrait_mode": str(d.get("portrait_mode", d.get("portraitMode", ""))),
			"spine_base": spine_base_rel,
			"stem": stem,
			"source": pack_label(),
			"pack_id": id,
		})
	# 兜底：扫描 characters/<id>/ 子目录
	for sub in list_dirs("characters"):
		if seen.has(sub.to_lower()):
			continue
		var dir_rel := "characters/" + sub
		var files := list_files(dir_rel, PackedStringArray(IMAGE_EXTS + SPINE_EXTS))
		if files.is_empty():
			continue
		var faces := {}
		var avatar := ""
		var spine_base := ""
		for rel in files:
			var fname := rel.get_file()
			var ext := fname.get_extension().to_lower()
			if ext in SPINE_EXTS:
				if spine_base.is_empty():
					spine_base = rel.get_basename()
				continue
			if CharacterAsset.is_avatar_filename(fname):
				if avatar.is_empty():
					avatar = rel
				continue
			var face := CharacterAsset.face_id_from_filename(fname)
			if not face.is_empty() and not faces.has(face):
				faces[face] = rel
		seen[sub.to_lower()] = true
		out.append({
			"identifier": sub,
			"display_name": sub,
			"nickname": "",
			"native_reference": null,
			"dir": dir_rel,
			"face_files": faces,
			"small_portrait": avatar,
			"portrait_mode": "spine" if not spine_base.is_empty() else "png",
			"spine_base": spine_base,
			"stem": sub,
			"source": pack_label(),
			"pack_id": id,
		})
	return out


func get_native_characters() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw in _catalog_entries("native_characters"):
		if raw is String:
			out.append({"key": str(raw), "display_name": str(raw), "nickname": ""})
		elif raw is Dictionary:
			var d := raw as Dictionary
			var key := str(d.get("key", d.get("name", d.get("Identifier", ""))))
			if key.is_empty():
				continue
			out.append({
				"key": key,
				"display_name": str(d.get("display_name", d.get("Name", key))),
				"nickname": str(d.get("nickname", d.get("Nickname", ""))),
			})
	return out


# ---------------------------------------------------------------------------
# 输出
# ---------------------------------------------------------------------------

func counts() -> Dictionary:
	return {
		"bgs": get_bg_entries().size(),
		"bgm": get_audio_entries("bgm").size(),
		"sounds": get_audio_entries("sounds").size(),
		"popups": get_popup_entries().size(),
		"characters": get_character_entries().size(),
		"voices": get_voice_entries().size(),
	}


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"version": version,
		"author": author,
		"description": description,
		"game": game,
		"format": format,
		"format_version": format_version,
		"path": path,
		"is_zip": is_zip,
		"valid": valid,
		"errors": Array(errors),
		"manifest": manifest,
		"manifest_dict": manifest.to_dict() if manifest != null else {},
		"counts": counts(),
	}
