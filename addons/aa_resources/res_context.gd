class_name AaResContext
extends RefCounted
## 资源上下文：播放/编辑一个工程（可选一个存档）时的资源解析入口。
##
## 覆盖优先级（低 → 高），索引时后注册覆盖先注册：
##   aa_pack（按 id 升序） < `data_root/overrides/`（全局）
##   < `data_root/projects/<同名文件夹>/` < `data_root/saves/<同名文件夹>/`
##
## 契约（DESIGN §5.2）：
##   get_character / get_characters / get_bg / get_bg_by_id / get_bg_entries /
##   get_bgm / get_bgm_entries / get_sound / get_sound_entries / get_popup /
##   get_popup_entries / get_voice / get_bg_effect / get_manifest
##
## 缺失资源策略：**返回可用占位（纹理/静音流/剪影），不返回 null 崩溃**。
## 例外：请求本身是空字符串时返回 null（表示"没有"）。
## 占位资源都带 `meta: aa_placeholder = true`，调用方可用 `is_placeholder()` 判断。
##
## 所有文件读取都走 AaRawLoader（运行时加载，不依赖 --import）。

const RawLoader = preload("res://addons/aa_resources/raw_loader.gd")
const AaManifestScript = preload("res://addons/aa_resources/aa_manifest.gd")
const CharacterAsset = preload("res://addons/aa_resources/character_asset.gd")
const Placeholders = preload("res://addons/aa_resources/placeholders.gd")
const ResHash = preload("res://addons/aa_resources/res_hash.gd")

const IMAGE_EXTS := ["png", "webp", "jpg", "jpeg"]
const AUDIO_EXTS := ["ogg", "wav", "mp3", "flac"]
const FONT_EXTS := ["ttf", "otf", "woff", "woff2"]
const MUTE_BGM_KEY := 999
const NO_PORTRAIT_REFERENCE := "???"
const THUMB_MAX := Vector2i(320, 180)

## 数据根目录（"user://aa_data" 或 AA 真实 data 目录）。
var data_root: String = ""
## 工程 .aap 路径（可空）。
var project_path: String = ""
## 存档 .aas 路径（可空）。
var save_path: String = ""
## 工程名（.aap 文件名 stem；make_context 时推断）。
var project_name: String = ""

## AaPack 实例数组（低 → 高优先级顺序）。
var packs: Array = []
## 覆盖层列表，低 → 高：[{kind,label,root,manifest,pack}]。
var layers: Array = []
## 合并后的 manifest（低 → 高 overlay）。
var merged_manifest: AaManifest = null
## 缺失资源记录（最近 N 条，便于诊断/测试）。
var last_missing: PackedStringArray = PackedStringArray()

var _index_built := false
var _bg_by_name: Dictionary = {}
var _bg_by_id: Dictionary = {}
var _bgm_by_key: Dictionary = {}
var _bgm_by_id: Dictionary = {}
var _sounds: Dictionary = {}
var _popups: Dictionary = {}
var _voices: Dictionary = {}
var _bg_effects: Dictionary = {}
var _bg_spine: Dictionary = {}
var _characters: Dictionary = {}
var _native_characters: Dictionary = {}
var _fonts: Dictionary = {}
var _ui: Dictionary = {}
var _character_cache: Dictionary = {}
var _thumb_cache: Dictionary = {}
var _missing_seen: Dictionary = {}


func _init(p_data_root := "", p_packs: Array = [], p_project_path := "", p_save_path := "") -> void:
	if not p_data_root.is_empty() or not p_project_path.is_empty() or not p_save_path.is_empty():
		setup(p_data_root, p_packs, p_project_path, p_save_path)


## 初始化/重建上下文。packs 按低 → 高优先级传入。
func setup(p_data_root: String, p_packs: Array, p_project_path := "", p_save_path := "") -> void:
	data_root = p_data_root
	project_path = p_project_path
	save_path = p_save_path
	packs = p_packs.duplicate()
	project_name = _name_from_path(project_path)
	_build_layers()
	merged_manifest = AaManifestScript.make_empty()
	for layer in layers:
		var m: AaManifest = layer.get("manifest", null)
		if m != null:
			merged_manifest.overlay(m)
	_index_built = false
	_clear_index()
	last_missing = PackedStringArray()
	_missing_seen.clear()


func refresh() -> void:
	# 重新扫描覆盖层（资源安装/卸载后调用）
	var root := data_root
	var pp := project_path
	var sp := save_path
	var pk := packs
	setup(root, pk, pp, sp)


func _clear_index() -> void:
	_bg_by_name.clear()
	_bg_by_id.clear()
	_bgm_by_key.clear()
	_bgm_by_id.clear()
	_sounds.clear()
	_popups.clear()
	_voices.clear()
	_bg_effects.clear()
	_bg_spine.clear()
	_characters.clear()
	_native_characters.clear()
	_fonts.clear()
	_ui.clear()
	_character_cache.clear()
	_thumb_cache.clear()


func _name_from_path(path: String) -> String:
	if path.is_empty():
		return ""
	if DirAccess.dir_exists_absolute(path):
		return path.get_file()
	return path.get_file().get_basename()


## AA 的同名自定义资源文件夹：`projects/<name>/` 或 `saves/<name>/`。
func _local_dir_for(path: String) -> String:
	if path.is_empty():
		return ""
	if DirAccess.dir_exists_absolute(path):
		return path
	var base := path.get_base_dir()
	var stem := path.get_file().get_basename()
	if base.is_empty() or stem.is_empty():
		return ""
	var candidate := base.path_join(stem)
	if DirAccess.dir_exists_absolute(candidate):
		return candidate
	return ""


func _build_layers() -> void:
	layers.clear()
	for pack in packs:
		if pack == null or not pack.valid:
			continue
		layers.append({
			"kind": "pack",
			"label": pack.pack_label(),
			"root": pack.dir_path(),
			"manifest": pack.manifest if pack.manifest != null else AaManifestScript.make_empty(),
			"pack": pack,
		})
	var global_dir := data_root.path_join("overrides")
	if not data_root.is_empty() and DirAccess.dir_exists_absolute(global_dir):
		layers.append({
			"kind": "global",
			"label": "overrides",
			"root": global_dir,
			"manifest": AaManifestScript.load_from_file(global_dir.path_join("manifest.json")),
			"pack": null,
		})
	var project_dir := _local_dir_for(project_path)
	if not project_dir.is_empty():
		layers.append({
			"kind": "project",
			"label": "project:" + project_dir.get_file(),
			"root": project_dir,
			"manifest": AaManifestScript.load_from_file(project_dir.path_join("manifest.json")),
			"pack": null,
		})
	var save_dir := _local_dir_for(save_path)
	if not save_dir.is_empty() and save_dir != project_dir:
		layers.append({
			"kind": "save",
			"label": "save:" + save_dir.get_file(),
			"root": save_dir,
			"manifest": AaManifestScript.load_from_file(save_dir.path_join("manifest.json")),
			"pack": null,
		})


# ===========================================================================
# 公共 API
# ===========================================================================

func get_manifest() -> AaManifest:
	if merged_manifest == null:
		merged_manifest = AaManifestScript.make_empty()
	return merged_manifest


func get_layers() -> Array:
	return layers


func get_packs() -> Array:
	return packs


func get_data_root() -> String:
	return data_root


func get_project_name() -> String:
	return project_name


func get_bg(friendly_name: String) -> Texture2D:
	if friendly_name.strip_edges().is_empty():
		return null
	_ensure_index()
	var name := friendly_name.strip_edges()
	var entry: Variant = _bg_by_name.get(name.to_lower())
	if entry == null:
		# 允许传文件名（带扩展名）
		entry = _bg_by_name.get(name.get_file().get_basename().to_lower())
	if entry != null:
		var tex := _load_texture_entry(entry)
		if tex != null:
			return tex
	_record_missing("bg", name)
	return Placeholders.mark_placeholder(Placeholders.bg_placeholder("bg:" + name), "bg:" + name)


func get_bg_by_id(bg_id: int) -> Texture2D:
	_ensure_index()
	var normalized := bg_id & 0xFFFFFFFF
	var entry: Variant = _bg_by_id.get(normalized)
	if entry == null:
		entry = _bg_by_id.get(bg_id)
	if entry != null:
		var tex := _load_texture_entry(entry)
		if tex != null:
			return tex
	_record_missing("bg_id", str(bg_id))
	var place := Placeholders.bg_placeholder("bg:%d" % normalized)
	return Placeholders.mark_placeholder(place, "bg:%d" % normalized)


func get_bg_entries(with_textures := true) -> Array[Dictionary]:
	_ensure_index()
	var out: Array[Dictionary] = []
	for entry in _bg_by_name.values():
		var item := {
			"id": int(entry.get("id", 0)),
			"name": str(entry.get("name", "")),
			"category": str(entry.get("category", "背景")),
			"path": str(entry.get("path", "")),
			"source": str(entry.get("source", "")),
		}
		if with_textures:
			item["texture"] = _thumbnail_entry(entry)
		out.append(item)
	out.sort_custom(func(a, b): return str(a["name"]).to_lower() < str(b["name"]).to_lower())
	return out


func get_bgm(key: Variant) -> AudioStream:
	var key_str := str(key).strip_edges()
	# 999 = 静音（AA 约定），返回静音流而不是 null
	if key is int or key is float:
		if int(key) == MUTE_BGM_KEY:
			return _make_mute_stream()
	if key_str == "999":
		return _make_mute_stream()
	_ensure_index()
	var entry: Variant = _bgm_by_key.get(key_str.to_lower())
	if entry == null and (key is int or key is float):
		entry = _bgm_by_id.get(int(key))
	if entry == null:
		# 数字 id 的模糊兜底：把 id 当名字再找一次
		entry = _bgm_by_key.get(key_str.to_lower())
	if entry != null:
		var stream := _load_audio_entry(entry)
		if stream != null:
			return stream
	_record_missing("bgm", key_str)
	var silent := Placeholders.silent_audio()
	Placeholders.mark_placeholder(silent, "bgm:" + key_str)
	return silent


func get_bgm_entries() -> Array[Dictionary]:
	_ensure_index()
	var out: Array[Dictionary] = []
	for entry in _bgm_by_key.values():
		out.append({
			"key": str(entry.get("name", "")),
			"name": str(entry.get("name", "")),
			"title": str(entry.get("title", entry.get("name", ""))),
			"id": entry.get("id", null),
			"path": str(entry.get("path", "")),
			"source": str(entry.get("source", "")),
		})
	out.sort_custom(func(a, b): return str(a["name"]).to_lower() < str(b["name"]).to_lower())
	return out


func get_sound(name: String) -> AudioStream:
	if name.strip_edges().is_empty():
		return null
	_ensure_index()
	var key := _stem_lower(name)
	var entry: Variant = _sounds.get(key)
	if entry != null:
		var stream := _load_audio_entry(entry)
		if stream != null:
			return stream
	_record_missing("sound", name)
	var silent := Placeholders.silent_audio()
	Placeholders.mark_placeholder(silent, "sound:" + name)
	return silent


func get_sound_entries() -> Array[Dictionary]:
	_ensure_index()
	var out: Array[Dictionary] = []
	for entry in _sounds.values():
		out.append({
			"name": str(entry.get("name", "")),
			"title": str(entry.get("title", entry.get("name", ""))),
			"path": str(entry.get("path", "")),
			"source": str(entry.get("source", "")),
		})
	out.sort_custom(func(a, b): return str(a["name"]).to_lower() < str(b["name"]).to_lower())
	return out


func get_popup(name: String) -> Texture2D:
	if name.strip_edges().is_empty():
		return null
	_ensure_index()
	var key := _stem_lower(name)
	var entry: Variant = _popups.get(key)
	if entry != null:
		var tex := _load_texture_entry(entry)
		if tex != null:
			return tex
	_record_missing("popup", name)
	return Placeholders.mark_placeholder(Placeholders.bg_placeholder("popup:" + name, Vector2i(320, 180)), "popup:" + name)


func get_popup_entries(with_textures := true) -> Array[Dictionary]:
	_ensure_index()
	var out: Array[Dictionary] = []
	for entry in _popups.values():
		var item := {
			"name": str(entry.get("name", "")),
			"path": str(entry.get("path", "")),
			"source": str(entry.get("source", "")),
		}
		if with_textures:
			item["texture"] = _thumbnail_entry(entry)
		out.append(item)
	out.sort_custom(func(a, b): return str(a["name"]).to_lower() < str(b["name"]).to_lower())
	return out


func get_voice(guid: String) -> AudioStream:
	if guid.strip_edges().is_empty():
		return null
	_ensure_index()
	var key := _stem_lower(guid)
	var entry: Variant = _voices.get(key)
	if entry != null:
		var stream := _load_audio_entry(entry)
		if stream != null:
			return stream
	_record_missing("voice", guid)
	var silent := Placeholders.silent_audio()
	Placeholders.mark_placeholder(silent, "voice:" + guid)
	return silent


func has_voice(guid: String) -> bool:
	_ensure_index()
	return _voices.has(_stem_lower(guid))


func get_voice_entries() -> Array[Dictionary]:
	_ensure_index()
	var out: Array[Dictionary] = []
	for entry in _voices.values():
		out.append({
			"guid": str(entry.get("name", "")),
			"path": str(entry.get("path", "")),
			"text": str(entry.get("text", "")),
			"source": str(entry.get("source", "")),
		})
	out.sort_custom(func(a, b): return str(a["guid"]).to_lower() < str(b["guid"]).to_lower())
	return out


## 背景效果：返回可播占位/描述字典（运行时按 type 处理；没有真实 prefab 时 type="placeholder"）。
func get_bg_effect(name: Variant) -> Variant:
	var key_str := str(name).strip_edges()
	if key_str.is_empty():
		return null
	_ensure_index()
	var entry: Variant = _bg_effects.get(key_str.to_lower())
	if entry != null:
		var effect := {
			"name": str(entry.get("name", key_str)),
			"id": int(entry.get("id", ResHash.bg_id(key_str))),
			"type": str(entry.get("type", "placeholder")),
			"path": str(entry.get("path", "")),
			"params": entry.get("params", {}),
			"source": str(entry.get("source", "")),
			"placeholder": str(entry.get("path", "")).is_empty() and str(entry.get("type", "")) == "",
		}
		# 有 json 描述文件则读出来合并
		var file_path := str(entry.get("path", ""))
		if not file_path.is_empty() and file_path.get_extension().to_lower() == "json":
			var data: Variant = RawLoader.read_json(file_path)
			if data is Dictionary:
				effect["params"] = data
				effect["placeholder"] = false
		return effect
	if name is int:
		# 未知 id：给一个可播占位，不崩
		_record_missing("bg_effect", key_str)
		return {"name": key_str, "id": int(name) & 0xFFFFFFFF, "type": "placeholder",
			"params": {"duration": 1.0}, "placeholder": true}
	_record_missing("bg_effect", key_str)
	var color := Placeholders.color_for("bgeffect:" + key_str)
	return {"name": key_str, "id": ResHash.bg_id(key_str), "type": "placeholder",
		"params": {"color": color, "duration": 1.0}, "placeholder": true}


func get_bg_effect_entries() -> Array[Dictionary]:
	_ensure_index()
	var out: Array[Dictionary] = []
	for entry in _bg_effects.values():
		out.append({
			"name": str(entry.get("name", "")),
			"id": int(entry.get("id", 0)),
			"type": str(entry.get("type", "placeholder")),
			"path": str(entry.get("path", "")),
			"source": str(entry.get("source", "")),
		})
	out.sort_custom(func(a, b): return str(a["name"]).to_lower() < str(b["name"]).to_lower())
	return out


## 背景分层图（BgSpineOverrides，AA 1.0 的背景图层资源）；返回描述数组。
func get_bg_spine_layers(name: String) -> Array[Dictionary]:
	_ensure_index()
	var out: Array[Dictionary] = []
	var entry: Variant = _bg_spine.get(_stem_lower(name))
	if entry == null:
		return out
	var rels: Variant = entry.get("files", [])
	if rels is Array:
		for rel in rels:
			out.append({"file": str(rel), "name": str(rel).get_file().get_basename(),
				"source": str(entry.get("source", ""))})
	return out


func get_character(id: String) -> AaCharacterAsset:
	_ensure_index()
	var raw_id := id.strip_edges()
	if raw_id.is_empty():
		return _make_placeholder_character("", "")
	var key := raw_id.to_lower()
	if _character_cache.has(key):
		return _character_cache[key]
	var asset: AaCharacterAsset = null
	var entry: Variant = _characters.get(key)
	if entry != null:
		asset = _asset_from_entry(entry)
		if asset == null:
			asset = _make_native_character(raw_id)
	else:
		var native: Variant = _native_characters.get(key)
		if native != null:
			asset = _make_native_character(raw_id)
		else:
			_record_missing("character", raw_id)
			asset = _make_placeholder_character(raw_id, raw_id)
	asset.prepare_textures(true)
	_character_cache[key] = asset
	return asset


func get_characters() -> Array[AaCharacterAsset]:
	_ensure_index()
	var out: Array[AaCharacterAsset] = []
	var seen := {}
	for key in _characters.keys():
		var asset := get_character(str(_characters[key].get("identifier", key)))
		if asset != null and not seen.has(asset.identifier.to_lower()):
			seen[asset.identifier.to_lower()] = true
			out.append(asset)
	for entry in _characters.values():
		var reference := _ref_string(entry.get("reference", null))
		if reference.is_empty() or reference == NO_PORTRAIT_REFERENCE:
			continue
		if seen.has(reference.to_lower()):
			continue
		seen[reference.to_lower()] = true
		out.append(get_character(reference))
	for key in _native_characters.keys():
		if seen.has(str(key)):
			continue
		seen[str(key)] = true
		out.append(get_character(str(_native_characters[key].get("key", key))))
	out.sort_custom(_character_compare)
	return out


func get_font(name: String) -> Font:
	if name.strip_edges().is_empty():
		return null
	_ensure_index()
	var entry: Variant = _fonts.get(_stem_lower(name))
	if entry != null:
		var path := str(entry.get("path", ""))
		if not path.is_empty():
			var font := RawLoader.load_font(path)
			if font != null:
				return font
	_record_missing("font", name)
	var fallback := "res://assets/fonts/wqy-zenhei-extracted.ttf"
	if FileAccess.file_exists(fallback):
		return RawLoader.load_font(fallback)
	return null


func get_ui_texture(name: String) -> Texture2D:
	if name.strip_edges().is_empty():
		return null
	_ensure_index()
	var entry: Variant = _ui.get(_stem_lower(name))
	if entry != null:
		var tex := _load_texture_entry(entry)
		if tex != null:
			return tex
	_record_missing("ui", name)
	return Placeholders.mark_placeholder(Placeholders.bg_placeholder("ui:" + name, Vector2i(128, 128)), "ui:" + name)


func get_missing() -> PackedStringArray:
	return last_missing


func clear_missing() -> void:
	last_missing = PackedStringArray()
	_missing_seen.clear()


static func is_placeholder(res: Variant) -> bool:
	if res is Object and res != null:
		return (res as Object).has_meta("aa_placeholder") and bool((res as Object).get_meta("aa_placeholder"))
	return false


func get_placeholder_texture(key := "missing") -> Texture2D:
	return Placeholders.mark_placeholder(Placeholders.bg_placeholder(key), key)


func report() -> Dictionary:
	_ensure_index()
	return {
		"data_root": data_root,
		"project": project_path,
		"save": save_path,
		"project_name": project_name,
		"layers": layers.map(func(l): return str(l.get("label", ""))),
		"counts": {
			"bgs": _bg_by_name.size(),
			"bgm": _bgm_by_key.size(),
			"sounds": _sounds.size(),
			"popups": _popups.size(),
			"voices": _voices.size(),
			"characters": _characters.size(),
			"native_characters": _native_characters.size(),
			"bg_effects": _bg_effects.size(),
			"fonts": _fonts.size(),
			"ui": _ui.size(),
		},
		"missing": Array(last_missing),
	}


# ===========================================================================
# 索引构建
# ===========================================================================

func _ensure_index() -> void:
	if _index_built:
		return
	_index_built = true
	for layer in layers:
		var kind := str(layer.get("kind", ""))
		var root := str(layer.get("root", ""))
		var manifest: AaManifest = layer.get("manifest", null)
		var pack: Variant = layer.get("pack", null)
		if kind == "pack" and pack != null:
			_register_pack_layer(layer)
			if manifest != null:
				_register_manifest_layer(layer, manifest)
			continue
		# 本地/全局文件夹：先按目录扫描兜底，再按 manifest 登记（manifest 优先）
		_scan_local_dirs(layer)
		if manifest != null:
			_register_manifest_layer(layer, manifest)


func _scan_local_dirs(layer: Dictionary) -> void:
	var root := str(layer.get("root", ""))
	if root.is_empty():
		return
	for path in RawLoader.list_files_recursive(root.path_join("bgs"), IMAGE_EXTS):
		_register_bg_path(layer, path.get_file().get_basename(), path, "")
	for path in RawLoader.list_files_recursive(root.path_join("bgm"), AUDIO_EXTS):
		_register_audio_path(layer, path.get_file().get_basename(), path, "bgm")
	for path in RawLoader.list_files_recursive(root.path_join("sounds"), AUDIO_EXTS):
		_register_audio_path(layer, path.get_file().get_basename(), path, "sound")
	for path in RawLoader.list_files_recursive(root.path_join("popups"), IMAGE_EXTS):
		_register_popup_path(layer, path.get_file().get_basename(), path)
	for path in RawLoader.list_files_recursive(root.path_join("voices"), AUDIO_EXTS):
		_register_voice_path(layer, path.get_file().get_basename(), path, "")
	for path in RawLoader.list_files_recursive(root.path_join("fonts"), FONT_EXTS):
		_register_font_path(layer, path.get_file().get_basename(), path)
	for path in RawLoader.list_files_recursive(root.path_join("bg_effects"), PackedStringArray(["json"])):
		_register_bg_effect_path(layer, path.get_file().get_basename(), path, "json")
	# characters/<identifier>/ 目录：PNG 立绘 / Spine
	var chars_root := root.path_join("characters")
	if DirAccess.dir_exists_absolute(chars_root):
		var dir := DirAccess.open(chars_root)
		if dir != null:
			dir.list_dir_begin()
			var fname := dir.get_next()
			while not fname.is_empty():
				if fname != "." and fname != ".." and dir.current_is_dir():
					var char_dir := chars_root.path_join(fname)
					var scan := CharacterAsset.scan_character_dir(char_dir)
					var entry := _new_character_entry(fname, fname, "", "", layer, null)
					entry["faces"] = scan.get("faces", {})
					entry["spine_base"] = str(scan.get("spine_base", ""))
					entry["avatar"] = str(scan.get("avatar", ""))
					entry["kind"] = "custom"
					_put(_characters, fname, entry)
				fname = dir.get_next()
			dir.list_dir_end()


func _register_manifest_layer(layer: Dictionary, manifest: AaManifest) -> void:
	var root := str(layer.get("root", ""))
	var pack: Variant = layer.get("pack", null)
	for raw in manifest.bg_overrides:
		var rel := _entry_rel(raw)
		if rel.is_empty():
			continue
		var path := _layer_file(layer, rel)
		_register_bg_path(layer, rel.get_file().get_basename(), path, rel)
	for raw in manifest.bgm_overrides:
		var rel := _entry_rel(raw)
		if rel.is_empty():
			continue
		_register_audio_path(layer, rel.get_file().get_basename(), _layer_file(layer, rel), "bgm", rel)
	for raw in manifest.sound_overrides:
		var rel := _entry_rel(raw)
		if rel.is_empty():
			continue
		_register_audio_path(layer, rel.get_file().get_basename(), _layer_file(layer, rel), "sound", rel)
	for raw in manifest.popup_overrides:
		var rel := _entry_rel(raw)
		if rel.is_empty():
			continue
		_register_popup_path(layer, rel.get_file().get_basename(), _layer_file(layer, rel), rel)
	for raw in manifest.voice_overrides:
		var rel := _entry_rel(raw)
		if rel.is_empty():
			continue
		_register_voice_path(layer, rel.get_file().get_basename(), _layer_file(layer, rel), rel)
	for raw in manifest.bg_effect_overrides:
		var rel := _entry_rel(raw)
		if rel.is_empty():
			continue
		_register_bg_effect_path(layer, rel.get_file().get_basename(), _layer_file(layer, rel), "json", rel)
	for raw in manifest.bg_spine_overrides:
		var rel := _entry_rel(raw)
		if rel.is_empty():
			continue
		var name := rel.get_file().get_basename()
		_put(_bg_spine, name.to_lower(), {
			"name": name, "files": [rel], "source": str(layer.get("label", "")),
		})
	# 角色：manifest 登记优先于目录扫描
	for raw in manifest.character_overrides:
		if not (raw is Dictionary):
			continue
		_register_manifest_character(layer, raw)


func _register_manifest_character(layer: Dictionary, d: Dictionary) -> void:
	var identifier := str(d.get("Identifier", "")).strip_edges()
	if identifier.is_empty():
		return
	var entry := _new_character_entry(
		identifier,
		str(d.get("Name", identifier)),
		str(d.get("Nickname", "")),
		_ref_string(d.get("CharacterReference", null)),
		layer,
		null
	)
	entry["original_identifier"] = _ref_string(d.get("OriginalIdentifier", null))
	entry["raw"] = d.duplicate(true)
	var spine_rel := _rel_from_value(d.get("SpinePortraitPath", null))
	if not spine_rel.is_empty():
		entry["spine_base"] = _layer_file_stem(layer, spine_rel)
	var avatar_rel := _rel_from_value(d.get("SmallPortraitPath", null))
	if not avatar_rel.is_empty():
		entry["avatar"] = _layer_file(layer, avatar_rel)
	# 同名本地角色目录补充表情/骨骼信息
	var root := str(layer.get("root", ""))
	if not root.is_empty():
		var char_dir := root.path_join("characters").path_join(identifier)
		if DirAccess.dir_exists_absolute(char_dir):
			var scan := CharacterAsset.scan_character_dir(char_dir)
			var faces: Dictionary = scan.get("faces", {})
			for face in faces.keys():
				if not (entry["faces"] as Dictionary).has(face):
					(entry["faces"] as Dictionary)[face] = faces[face]
			if str(entry["spine_base"]).is_empty():
				entry["spine_base"] = str(scan.get("spine_base", ""))
			if str(entry["avatar"]).is_empty():
				entry["avatar"] = str(scan.get("avatar", ""))
	_merge_character_entry(entry)
	_put(_characters, identifier, entry)


## 合并角色条目：新条目缺少的立绘/头像/骨骼信息从已有条目补齐（跨层同名 Identifier 容错）。
func _merge_character_entry(entry: Dictionary) -> void:
	var existing: Variant = _characters.get(str(entry.get("identifier", "")))
	if not (existing is Dictionary):
		return
	var old := existing as Dictionary
	# 立绘数据：新层没有就用旧层的（高优先级层只改名字/昵称时仍能显示立绘）
	if (entry["faces"] as Dictionary).is_empty() and not (old.get("faces", {}) as Dictionary).is_empty():
		entry["faces"] = (old.get("faces", {}) as Dictionary).duplicate(true)
	if str(entry.get("spine_base", "")).is_empty() and not str(old.get("spine_base", "")).is_empty():
		entry["spine_base"] = old["spine_base"]
	if str(entry.get("avatar", "")).is_empty() and not str(old.get("avatar", "")).is_empty():
		entry["avatar"] = old["avatar"]
	# 名字/昵称：空则沿用旧值
	if str(entry.get("name", "")).is_empty():
		entry["name"] = old.get("name", "")
	if str(entry.get("nickname", "")).is_empty():
		entry["nickname"] = old.get("nickname", "")
	if str(entry.get("reference", "")).is_empty() and not str(old.get("reference", "")).is_empty():
		entry["reference"] = old["reference"]
	if str(entry.get("source", "")).is_empty():
		entry["source"] = old.get("source", "")


func _register_pack_layer(layer: Dictionary) -> void:
	var pack: AaPack = layer.get("pack", null)
	if pack == null:
		return
	var label := pack.pack_label()
	for e in pack.get_bg_entries():
		_put(_bg_by_name, str(e["name"]).to_lower(), {
			"name": e["name"], "id": e["id"], "category": e.get("category", "背景"),
			"path": pack.resolve_path(str(e["file"])),
			"pack": pack, "rel": str(e["file"]), "source": label,
		})
		_bg_by_id[int(e["id"])] = _bg_by_name[str(e["name"]).to_lower()]
	for e in pack.get_audio_entries("bgm"):
		_put(_bgm_by_key, str(e["key"]).to_lower(), {
			"name": e["key"], "title": e.get("title", e["key"]), "id": e.get("id", null),
			"path": pack.resolve_path(str(e["file"])), "pack": pack, "rel": str(e["file"]), "source": label,
		})
		if e.get("id", null) != null:
			_bgm_by_id[int(e["id"])] = _bgm_by_key[str(e["key"]).to_lower()]
	for e in pack.get_audio_entries("sounds"):
		_put(_sounds, str(e["key"]).to_lower(), {
			"name": e["key"], "title": e.get("title", e["key"]),
			"path": pack.resolve_path(str(e["file"])), "pack": pack, "rel": str(e["file"]), "source": label,
		})
	for e in pack.get_popup_entries():
		_put(_popups, str(e["name"]).to_lower(), {
			"name": e["name"], "path": pack.resolve_path(str(e["file"])),
			"pack": pack, "rel": str(e["file"]), "source": label,
		})
	for e in pack.get_voice_entries():
		_put(_voices, str(e["guid"]).to_lower(), {
			"name": e["guid"], "path": pack.resolve_path(str(e["file"])),
			"pack": pack, "rel": str(e["file"]), "text": e.get("text", ""), "source": label,
		})
	for e in pack.get_bg_effect_entries():
		_put(_bg_effects, str(e["name"]).to_lower(), {
			"name": e["name"], "id": e["id"], "type": e.get("type", "json"),
			"path": pack.resolve_path(str(e["file"])), "pack": pack, "rel": str(e["file"]),
			"params": e.get("params", {}), "source": label,
		})
	for e in pack.get_font_entries():
		_put(_fonts, str(e["name"]).to_lower(), {
			"name": e["name"], "path": pack.resolve_path(str(e["file"])),
			"pack": pack, "rel": str(e["file"]), "source": label,
		})
	for e in pack.get_ui_entries():
		_put(_ui, str(e["name"]).to_lower(), {
			"name": e["name"], "path": pack.resolve_path(str(e["file"])),
			"pack": pack, "rel": str(e["file"]), "source": label,
		})
	for e in pack.get_character_entries():
		var entry := _new_character_entry(
			str(e["identifier"]),
			str(e.get("display_name", e["identifier"])),
			str(e.get("nickname", "")),
			_ref_string(e.get("native_reference", null)),
			layer,
			pack
		)
		entry["kind"] = "custom"
		var dir_rel := str(e.get("dir", ""))
		var face_files: Variant = e.get("face_files", {})
		if face_files is Dictionary:
			for face in face_files.keys():
				(entry["faces"] as Dictionary)[str(face)] = _pack_character_file(pack, dir_rel, str(face_files[face]))
		var spine_rel := str(e.get("spine_base", ""))
		entry["spine_base"] = _pack_character_stem(pack, dir_rel, spine_rel) if not spine_rel.is_empty() else ""
		entry["avatar"] = _pack_character_file(pack, dir_rel, str(e.get("small_portrait", "")))
		entry["raw"] = e
		if str(entry["spine_base"]).is_empty() and not spine_rel.is_empty():
			# zip 包无法给出绝对路径：记下 rel 供后续解包（已安装的包都是目录，正常不会走到）
			entry["spine_rel"] = spine_rel
		_merge_character_entry(entry)
		_put(_characters, str(e["identifier"]), entry)
	for e in pack.get_native_characters():
		_put(_native_characters, str(e["key"]), e)
	# aa_pack 里可选的 AA 兼容 manifest：角色别名/覆盖也注册（catalog 优先）
	var manifest := pack.manifest
	if manifest != null:
		for raw in manifest.character_overrides:
			if raw is Dictionary:
				_register_manifest_character(layer, raw)


# ---------------------------------------------------------------------------
# 注册辅助
# ---------------------------------------------------------------------------

func _new_character_entry(identifier: String, display_name: String, nickname: String, reference: String, layer: Dictionary, pack: Variant) -> Dictionary:
	return {
		"identifier": identifier,
		"name": display_name,
		"nickname": nickname,
		"reference": reference,
		"original_identifier": "",
		"faces": {},
		"spine_base": "",
		"avatar": "",
		"raw": {},
		"source": str(layer.get("label", "")),
		"layer_kind": str(layer.get("kind", "")),
		"pack": pack,
		"kind": "custom",
	}


func _register_bg_path(layer: Dictionary, name: String, path: String, rel: String) -> void:
	if name.is_empty():
		return
	if path.is_empty() and layer.get("pack") == null:
		return  # 登记了但文件丢失：跳过，回退到低优先级层（qa Q-005 修复）
	var entry := {
		"name": name,
		"id": ResHash.bg_id(name),
		"category": "背景",
		"path": path,
		"pack": layer.get("pack", null),
		"rel": rel,
		"source": str(layer.get("label", "")),
	}
	_put(_bg_by_name, name.to_lower(), entry)
	_bg_by_id[int(entry["id"])] = entry


func _register_audio_path(layer: Dictionary, name: String, path: String, kind: String, rel := "") -> void:
	if name.is_empty():
		return
	if path.is_empty() and layer.get("pack") == null:
		return
	var entry := {
		"name": name,
		"title": name,
		"id": null,
		"path": path,
		"pack": layer.get("pack", null),
		"rel": rel,
		"source": str(layer.get("label", "")),
	}
	if kind == "bgm":
		_put(_bgm_by_key, name.to_lower(), entry)
	else:
		_put(_sounds, name.to_lower(), entry)


func _register_popup_path(layer: Dictionary, name: String, path: String, rel := "") -> void:
	if name.is_empty():
		return
	if path.is_empty() and layer.get("pack") == null:
		return
	_put(_popups, name.to_lower(), {
		"name": name, "path": path, "pack": layer.get("pack", null), "rel": rel,
		"source": str(layer.get("label", "")),
	})


func _register_voice_path(layer: Dictionary, name: String, path: String, rel := "") -> void:
	if name.is_empty():
		return
	if path.is_empty() and layer.get("pack") == null:
		return
	_put(_voices, name.to_lower(), {
		"name": name, "path": path, "pack": layer.get("pack", null), "rel": rel,
		"text": "", "source": str(layer.get("label", "")),
	})


func _register_bg_effect_path(layer: Dictionary, name: String, path: String, type: String, rel := "") -> void:
	if name.is_empty():
		return
	if path.is_empty() and layer.get("pack") == null:
		return
	_put(_bg_effects, name.to_lower(), {
		"name": name, "id": ResHash.bg_id(name), "type": type, "path": path,
		"pack": layer.get("pack", null), "rel": rel, "params": {},
		"source": str(layer.get("label", "")),
	})


func _register_font_path(layer: Dictionary, name: String, path: String) -> void:
	if name.is_empty():
		return
	if path.is_empty() and layer.get("pack") == null:
		return
	_put(_fonts, name.to_lower(), {
		"name": name, "path": path, "pack": layer.get("pack", null),
		"source": str(layer.get("label", "")),
	})


static func _put(dict: Dictionary, key: String, value: Variant) -> void:
	dict[key.to_lower()] = value


# ===========================================================================
# 资源加载辅助
# ===========================================================================

func _load_texture_entry(entry: Dictionary) -> Texture2D:
	var path := str(entry.get("path", ""))
	if not path.is_empty():
		return RawLoader.load_texture(path)
	var pack: Variant = entry.get("pack", null)
	if pack != null and pack is AaPack:
		return (pack as AaPack).get_texture(str(entry.get("rel", "")))
	return null


func _thumbnail_entry(entry: Dictionary) -> Texture2D:
	var key := "%s|%s" % [str(entry.get("source", "")), str(entry.get("name", ""))]
	if _thumb_cache.has(key):
		return _thumb_cache[key]
	var tex := _load_texture_entry(entry)
	if tex == null:
		return null
	var thumb := _make_thumbnail(tex)
	_thumb_cache[key] = thumb
	return thumb


func _make_thumbnail(tex: Texture2D) -> Texture2D:
	var img := tex.get_image()
	if img == null or img.is_empty():
		return tex
	if img.get_width() <= THUMB_MAX.x and img.get_height() <= THUMB_MAX.y:
		return tex
	var scale := minf(float(THUMB_MAX.x) / float(img.get_width()), float(THUMB_MAX.y) / float(img.get_height()))
	var w: int = maxi(1, int(float(img.get_width()) * scale))
	var h: int = maxi(1, int(float(img.get_height()) * scale))
	var copy := img.duplicate()
	copy.resize(w, h, Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(copy)


func _load_audio_entry(entry: Dictionary) -> AudioStream:
	var path := str(entry.get("path", ""))
	if not path.is_empty():
		return RawLoader.load_audio(path)
	var pack: Variant = entry.get("pack", null)
	if pack != null and pack is AaPack:
		return (pack as AaPack).get_audio(str(entry.get("rel", "")))
	return null


func _make_mute_stream() -> AudioStream:
	_ensure_index()
	var silent := Placeholders.silent_audio()
	silent.set_meta("aa_mute", true)
	silent.set_meta("aa_placeholder", false)
	return silent


func _record_missing(kind: String, key: String) -> void:
	var id := "%s:%s" % [kind, key]
	if _missing_seen.has(id):
		return
	_missing_seen[id] = true
	if last_missing.size() >= 256:
		return
	last_missing.append(id)


# ===========================================================================
# 角色解析
# ===========================================================================

func _asset_from_entry(entry: Dictionary) -> AaCharacterAsset:
	var asset := CharacterAsset.new()
	asset.identifier = str(entry.get("identifier", ""))
	asset.display_name = str(entry.get("name", ""))
	asset.nickname = str(entry.get("nickname", ""))
	asset.character_reference = _ref_string(entry.get("reference", null))
	asset.original_identifier = str(entry.get("original_identifier", ""))
	asset.source = str(entry.get("source", ""))
	asset.meta = {"layer_kind": str(entry.get("layer_kind", "")), "kind": str(entry.get("kind", "custom"))}
	var faces: Dictionary = entry.get("faces", {})
	var spine_base := str(entry.get("spine_base", ""))
	var avatar := str(entry.get("avatar", ""))
	var has_media := not faces.is_empty() or not spine_base.is_empty() or not avatar.is_empty()
	if has_media:
		asset.mode = CharacterAsset.MODE_SPINE if not spine_base.is_empty() else CharacterAsset.MODE_PNG
		asset.spine_base_path = spine_base
		asset.small_portrait_path = avatar
		asset.face_paths = faces.duplicate(true)
		asset.face_ids = _sorted_face_ids(faces)
		if asset.display_name.is_empty():
			asset.display_name = asset.identifier
		return asset
	var reference := asset.character_reference
	if reference.is_empty():
		# 未登记立绘、也没有引用：无立绘角色（合法，例如旁白专用角色）
		asset.mode = CharacterAsset.MODE_NONE
		if asset.display_name.is_empty():
			asset.display_name = asset.identifier
		return asset
	if reference == NO_PORTRAIT_REFERENCE:
		asset.mode = CharacterAsset.MODE_NONE
		return asset
	# 别名：目标可能是另一个自定义角色，也可能是原生角色
	var target_key := reference.to_lower()
	if target_key != asset.identifier.to_lower() and _characters.has(target_key):
		var target := get_character(reference)
		if target != null and target.identifier.to_lower() != asset.identifier.to_lower():
			asset.mode = target.mode
			asset.face_paths = target.face_paths.duplicate(true)
			asset.face_ids = target.face_ids.duplicate()
			asset.spine_base_path = target.spine_base_path
			asset.small_portrait_path = target.small_portrait_path
			asset.meta["alias_of"] = target.identifier
			if target.mode == CharacterAsset.MODE_NATIVE:
				asset.character_reference = target.character_reference if not target.character_reference.is_empty() else reference
			return asset
	# 原生角色
	var native: Variant = _native_characters.get(target_key)
	asset.mode = CharacterAsset.MODE_NATIVE
	asset.character_reference = reference
	asset.meta["official_portrait_available"] = false
	if native != null:
		if asset.display_name.is_empty():
			asset.display_name = str(native.get("display_name", reference))
		if asset.nickname.is_empty():
			asset.nickname = str(native.get("nickname", ""))
	else:
		asset.display_name = reference if asset.display_name.is_empty() else asset.display_name
	return asset


func _make_native_character(key: String) -> AaCharacterAsset:
	var asset := CharacterAsset.new()
	asset.identifier = key
	asset.display_name = key
	asset.mode = CharacterAsset.MODE_NATIVE
	asset.character_reference = key
	var native: Variant = _native_characters.get(key.to_lower())
	if native != null:
		asset.display_name = str(native.get("display_name", key))
		asset.nickname = str(native.get("nickname", ""))
	asset.source = "native"
	asset.meta = {"official_portrait_available": false}
	return asset


func _make_placeholder_character(identifier: String, display_name: String) -> AaCharacterAsset:
	var asset := CharacterAsset.new()
	asset.identifier = identifier
	asset.display_name = display_name if not display_name.is_empty() else identifier
	asset.mode = CharacterAsset.MODE_PLACEHOLDER
	asset.is_placeholder = true
	asset.source = "missing"
	return asset


func _sorted_face_ids(faces: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for face in CharacterAsset.FACE_IDS:
		if faces.has(face):
			out.append(face)
	var extras: Array = []
	for key in faces.keys():
		if not out.has(str(key)):
			extras.append(str(key))
	extras.sort()
	for key in extras:
		out.append(key)
	return out


func _character_compare(a: AaCharacterAsset, b: AaCharacterAsset) -> bool:
	if a.is_placeholder != b.is_placeholder:
		return not a.is_placeholder
	if a.mode != b.mode:
		return a.mode < b.mode
	return a.display_name.to_lower() < b.display_name.to_lower()


# ===========================================================================
# 路径/字段工具
# ===========================================================================

## pack 角色文件：先按包根解析；失败则按角色目录解析（catalog 里两种写法都常见）。
func _pack_character_file(pack: AaPack, dir_rel: String, rel: String) -> String:
	var safe := AaManifestScript.normalize_relative(rel)
	if safe.is_empty():
		return ""
	var direct := pack.resolve_path(safe)
	if not direct.is_empty():
		return direct
	if not dir_rel.is_empty():
		return pack.resolve_path(dir_rel.path_join(safe))
	return ""


func _pack_character_stem(pack: AaPack, dir_rel: String, rel: String) -> String:
	var safe := AaManifestScript.normalize_relative(rel)
	if safe.is_empty():
		return ""
	var direct := pack.resolve_stem_path(safe)
	if not direct.is_empty():
		return direct
	if not dir_rel.is_empty():
		return pack.resolve_stem_path(dir_rel.path_join(safe))
	return ""


func _layer_file(layer: Dictionary, rel: String) -> String:
	var safe := AaManifestScript.normalize_relative(rel)
	if safe.is_empty():
		return ""
	var pack: Variant = layer.get("pack", null)
	if pack != null and pack is AaPack:
		return (pack as AaPack).resolve_path(safe)
	var root := str(layer.get("root", ""))
	if root.is_empty():
		return ""
	var full := root.path_join(safe)
	return full if FileAccess.file_exists(full) else ""


## 不带后缀的路径（Spine：.skel/.atlas/同名 png 共用基础名）。
func _layer_file_stem(layer: Dictionary, rel: String) -> String:
	var safe := AaManifestScript.normalize_relative(rel)
	if safe.is_empty():
		return ""
	var pack: Variant = layer.get("pack", null)
	if pack != null and pack is AaPack:
		var p := (pack as AaPack).resolve_stem_path(safe)
		if not p.is_empty():
			return p
	var root := str(layer.get("root", ""))
	if root.is_empty():
		return ""
	var base := root.path_join(safe)
	for ext in ["", ".skel", ".atlas", ".png", ".webp"]:
		if FileAccess.file_exists(base + ext):
			return base + ("" if ext.is_empty() else ext.trim_suffix(""))
	return base


func _entry_rel(raw: Variant) -> String:
	if raw is String:
		return AaManifestScript.normalize_relative(raw)
	if raw is Dictionary:
		var d := raw as Dictionary
		for key in ["file", "File", "path", "Path"]:
			if d.has(key):
				return AaManifestScript.normalize_relative(str(d[key]))
	return ""


func _rel_from_value(v: Variant) -> String:
	if v == null:
		return ""
	return AaManifestScript.normalize_relative(str(v))


func _ref_string(v: Variant) -> String:
	if v == null:
		return ""
	var s := str(v).strip_edges()
	if s.is_empty() or s.to_lower() == "null" or s.to_lower() == "none":
		return ""
	return s


static func _stem_lower(name: String) -> String:
	return name.get_file().get_basename().to_lower()
