class_name AaResProvider
extends RefCounted
## 播放器资源提供者（薄包装）。
##
## 优先使用 aa_resources 的 `AaResContext`（pack-dev 的正式实现，API 见 DESIGN §5.2）；
## context 不可用（并行开发/没装资源包）时退化为「项目目录 + manifest.json」本地解析；
## 再找不到就返回 null，由 AaStage 用 AaArt 程序化占位素材正常演出。
##
## 角色 id 来自 .aap 的 characters[i].name（= manifest CharacterOverrides 的 Identifier），
## 显示名 / 昵称 / 头像 / 表情图从这里解析。

var context: Variant = null
var project_path: String = ""
var project_dir: String = ""
var manifest: Dictionary = {}

var _char_cache: Dictionary = {}
var _bg_cache: Dictionary = {}
var _audio_cache: Dictionary = {}
var _tex_cache: Dictionary = {}


static func create(project_path := "", context: Variant = null) -> AaResProvider:
	var p := AaResProvider.new()
	p.bind(project_path, context)
	return p


func bind(project_path_: String, context_: Variant = null) -> void:
	project_path = project_path_
	context = context_
	_char_cache.clear()
	_bg_cache.clear()
	_audio_cache.clear()
	_tex_cache.clear()
	manifest = {}
	if project_path.is_empty():
		return
	var base := project_path.get_base_dir()
	var stem := project_path.get_file().get_basename()
	var candidate := base.path_join(stem)
	project_dir = candidate if DirAccess.dir_exists_absolute(candidate) else base
	var mf := base.path_join(stem + ".manifest.json")
	if FileAccess.file_exists(mf):
		var parsed: Variant = AaRawLoader.read_json(mf)
		if parsed is Dictionary:
			manifest = parsed


# ---------------------------------------------------------------- 角色

## 返回 {id, display_name, nickname, portrait: Texture2D|null, faces: Dictionary}
func get_character(identifier: String) -> Dictionary:
	if identifier.is_empty():
		return {"id": "", "display_name": "", "nickname": "", "portrait": null, "faces": {}}
	if _char_cache.has(identifier):
		return _char_cache[identifier]
	var info := {
		"id": identifier, "display_name": identifier, "nickname": "",
		"portrait": null, "faces": {},
	}
	# 1) 正式资源上下文
	if context != null and context.has_method("get_character"):
		var asset: Variant = context.call("get_character", identifier)
		if asset != null:
			_apply_character_asset(info, asset)
	# 2) manifest overrides
	_fill_from_manifest(info, identifier)
	# 3) 本地头像 png
	if info["portrait"] == null:
		info["portrait"] = _local_character_portrait(identifier)
	_char_cache[identifier] = info
	return info


func _apply_character_asset(info: Dictionary, asset: Variant) -> void:
	var dn := _prop_first(asset, ["display_name", "name", "Name", "char_name"])
	if dn is String and not dn.is_empty():
		info["display_name"] = dn
	var nn := _prop_first(asset, ["nickname", "Nickname", "nick_name"])
	if nn is String:
		info["nickname"] = nn
	# 资源层对「原生角色/查无此角色」会返回半透明占位小图；播放器用自己的占位（更清晰、带名字）
	# 只有真 PNG/Spine 立绘数据才使用 asset 的贴图
	var usable := true
	if asset is Object:
		if asset.has_method("has_portrait_data"):
			usable = bool(asset.call("has_portrait_data"))
		var mode := str(_prop_first(asset, ["mode"]))
		if mode == "native" or mode == "none" or mode == "placeholder":
			usable = false
		if bool(_prop_first(asset, ["is_placeholder"])):
			usable = false
	if not usable:
		return
	var portrait: Variant = _prop_first(asset, ["portrait", "small_portrait", "texture", "avatar"])
	var tex := _as_texture(portrait)
	if tex != null:
		info["portrait"] = tex
	var faces: Variant = _prop_first(asset, ["faces", "face_textures", "expressions", "face_map"])
	var face_map := _as_face_map(faces)
	if not face_map.is_empty():
		info["faces"] = face_map


func _fill_from_manifest(info: Dictionary, identifier: String) -> void:
	var overrides: Variant = manifest.get("CharacterOverrides", [])
	if not (overrides is Array):
		return
	for item in overrides:
		if not (item is Dictionary):
			continue
		var od: Dictionary = item
		if str(od.get("Identifier", "")) != identifier:
			continue
		var nm := str(od.get("Name", ""))
		if not nm.is_empty():
			info["display_name"] = nm
		var nn := str(od.get("Nickname", "") if od.get("Nickname") != null else "")
		if not nn.is_empty():
			info["nickname"] = nn
		var sp := str(od.get("SmallPortraitPath", "") if od.get("SmallPortraitPath") != null else "")
		if not sp.is_empty():
			var tex := _load_local_texture(sp)
			if tex != null:
				info["portrait"] = tex
		return


func _local_character_portrait(identifier: String) -> Texture2D:
	if project_dir.is_empty():
		return null
	var dir := project_dir.path_join("characters").path_join(identifier)
	if not DirAccess.dir_exists_absolute(dir):
		return null
	for f in DirAccess.get_files_at(dir):
		var low := f.to_lower()
		if low.ends_with("-avatar.png") or low.ends_with("_avatar.png") or low.ends_with(".png"):
			var tex := AaRawLoader.load_texture(dir.path_join(f))
			if tex != null:
				return tex
	return null


# ---------------------------------------------------------------- 背景

func get_bg(friendly_name: String, bg_id: int = 0) -> Texture2D:
	var key := "%s|%d" % [friendly_name, bg_id]
	if _bg_cache.has(key):
		return _bg_cache[key]
	var tex: Texture2D = null
	if context != null:
		if bg_id != 0 and context.has_method("get_bg_by_id"):
			tex = _as_texture(context.call("get_bg_by_id", bg_id))
		if tex == null and not friendly_name.is_empty() and context.has_method("get_bg"):
			tex = _as_texture(context.call("get_bg", friendly_name))
	if tex == null and not friendly_name.is_empty():
		var local: Variant = _load_local_asset("bgs", friendly_name, true)
		if local is Texture2D:
			tex = local
	_bg_cache[key] = tex
	return tex


func get_popup(name: String) -> Texture2D:
	if name.is_empty():
		return null
	var key := "popup:" + name
	if _tex_cache.has(key):
		return _tex_cache[key]
	var tex: Texture2D = null
	if context != null and context.has_method("get_popup"):
		tex = _as_texture(context.call("get_popup", name))
	if tex == null:
		tex = _load_local_asset("popups", name, true) as Texture2D
	_tex_cache[key] = tex
	return tex


# ---------------------------------------------------------------- 音频

func get_bgm(key: Variant) -> AudioStream:
	var cache_key := "bgm:" + str(key)
	if _audio_cache.has(cache_key):
		return _audio_cache[cache_key]
	var stream: AudioStream = null
	if context != null and context.has_method("get_bgm"):
		stream = _as_audio(context.call("get_bgm", key))
	if stream == null and not (key is int and int(key) == 999):
		stream = _load_local_audio("bgm", str(key))
		if stream == null:
			stream = _load_local_audio("bgm", "Theme_" + str(key))
	_audio_cache[cache_key] = stream
	return stream


func get_sound(name: String) -> AudioStream:
	if name.is_empty():
		return null
	var cache_key := "se:" + name
	if _audio_cache.has(cache_key):
		return _audio_cache[cache_key]
	var stream: AudioStream = null
	if context != null and context.has_method("get_sound"):
		stream = _as_audio(context.call("get_sound", name))
	if stream == null:
		stream = _load_local_audio("sounds", name)
	_audio_cache[cache_key] = stream
	return stream


func get_voice(guid: String) -> AudioStream:
	if guid.is_empty():
		return null
	var cache_key := "voice:" + guid
	if _audio_cache.has(cache_key):
		return _audio_cache[cache_key]
	var stream: AudioStream = null
	if context != null and context.has_method("get_voice"):
		stream = _as_audio(context.call("get_voice", guid))
	if stream == null:
		var dir := project_dir.path_join("voices")
		for ext in ["ogg", "mp3", "wav"]:
			var p := dir.path_join(guid + "." + ext)
			if FileAccess.file_exists(p):
				stream = AaRawLoader.load_audio(p)
				break
	_audio_cache[cache_key] = stream
	return stream


# ---------------------------------------------------------------- 内部工具

func _load_local_asset(subdir: String, stem: String, texture: bool) -> Variant:
	if project_dir.is_empty() or stem.is_empty():
		return null
	var dir := project_dir.path_join(subdir)
	if not DirAccess.dir_exists_absolute(dir):
		return null
	var want := stem.to_lower()
	for f in DirAccess.get_files_at(dir):
		var base := f.get_basename()
		if base.to_lower() != want:
			continue
		var p := dir.path_join(f)
		if texture:
			var tex := AaRawLoader.load_texture(p)
			if tex != null:
				return tex
		else:
			var audio := AaRawLoader.load_audio(p)
			if audio != null:
				return audio
	return null


func _load_local_audio(subdir: String, stem: String) -> AudioStream:
	if project_dir.is_empty() or stem.is_empty():
		return null
	var dir := project_dir.path_join(subdir)
	var dirs: Array = [dir, project_dir.path_join("sounds"), project_dir.path_join("bgm"), project_dir]
	for d in dirs:
		if not DirAccess.dir_exists_absolute(d):
			continue
		for f in DirAccess.get_files_at(d):
			if f.get_basename().to_lower() != stem.to_lower():
				continue
			var stream := AaRawLoader.load_audio(d.path_join(f))
			if stream != null:
				return stream
	return null


func _load_local_texture(rel_path: String) -> Texture2D:
	var rel := rel_path.replace("\\", "/")
	var candidates := [
		project_dir.path_join(rel),
		project_path.get_base_dir().path_join(rel),
	]
	if project_dir.is_empty():
		candidates = [project_path.get_base_dir().path_join(rel)]
	for p in candidates:
		if FileAccess.file_exists(p):
			return AaRawLoader.load_texture(p)
	return null


func _as_texture(v: Variant) -> Texture2D:
	if v is Texture2D:
		return v
	if v is String and not (v as String).is_empty():
		var s: String = v
		if FileAccess.file_exists(s):
			var key := "tex:" + s
			if _tex_cache.has(key):
				return _tex_cache[key]
			var tex := AaRawLoader.load_texture(s)
			_tex_cache[key] = tex
			return tex
	return null


func _as_audio(v: Variant) -> AudioStream:
	if v is AudioStream:
		return v
	if v is String and not (v as String).is_empty():
		var s: String = v
		if FileAccess.file_exists(s):
			return AaRawLoader.load_audio(s)
	return null


func _as_face_map(v: Variant) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k in v.keys():
			var tex := _as_texture(v[k])
			if tex != null:
				out[str(k)] = tex
	elif v is Array:
		var i := 0
		for item in v:
			var tex := _as_texture(item)
			if tex != null:
				out["%02d" % i] = tex
			i += 1
	return out


func _prop_first(obj: Variant, names: Array) -> Variant:
	if obj == null:
		return null
	if obj is Dictionary:
		var d: Dictionary = obj
		for n in names:
			if d.has(n):
				return d[n]
		return null
	if obj is Object:
		for n in names:
			var v: Variant = obj.get(str(n))
			if v != null:
				return v
	return null
