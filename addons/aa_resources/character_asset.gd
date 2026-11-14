class_name AaCharacterAsset
extends RefCounted
## 单个角色的解析结果（AaResContext.get_character() 返回）。
##
## 支持 AA 的四种角色来源：
##   1. 原生角色：角色名（韩文/中文/英文均可），官方 Addressables 资源包里有立绘；
##      本机没有官方资源包时 `get_face_texture()` 返回占位剪影，不崩。
##   2. 自定义 Spine 角色：manifest.CharacterOverrides 里 SpinePortraitPath 指向
##      `<name>.skel/.atlas/.png`（路径不带后缀）。Spine 运行时不在资源层实现
##      （DESIGN §9：接口预留 AaSpineProvider），这里返回占位，并暴露
##      `get_spine_base_path()` 给后续 Spine 层。
##   3. 自定义 PNG 立绘角色：`characters/<Identifier>/` 下按 AA 规则命名的 PNG
##      （包含 00~12、99、halo_01、halo_02 的图片；`-avatar.png` 为小头像）。
##   4. 别名：CharacterReference 指向另一个角色/原生角色，只改 Name/Nickname。
##
## 纹理一律经 AaRawLoader 运行时加载（不依赖 .import）。

const RawLoader = preload("res://addons/aa_resources/raw_loader.gd")
const Placeholders = preload("res://addons/aa_resources/placeholders.gd")
const ResHash = preload("res://addons/aa_resources/res_hash.gd")

const MODE_NONE := "none"          # 无立绘（'???' 角色 / 只有名字）
const MODE_NATIVE := "native"      # 原生角色（官方资源包里才有立绘）
const MODE_ALIAS := "alias"        # 指向另一个角色的别名
const MODE_SPINE := "spine"        # 自定义 Spine（.skel/.atlas/.png）
const MODE_PNG := "png"            # 自定义 PNG 立绘（多表情图）
const MODE_PLACEHOLDER := "placeholder"  # 查无此角色

## AA PNG 立绘扫描规则（p24/p35：图片名包含 00~12 / 99 / halo_01 / halo_02）。
const FACE_IDS := [
	"00", "01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "11", "12",
	"99", "halo_01", "halo_02",
]
const IMAGE_EXTS := ["png", "webp", "jpg", "jpeg"]

var identifier: String = ""
var display_name: String = ""
var nickname: String = ""
## manifest 的 CharacterReference（别名目标 / 原生角色名）；无则空串。
var character_reference: String = ""
var original_identifier: String = ""
## Spine 立绘基础路径（不带后缀）；PNG 立绘为空。
var spine_base_path: String = ""
## PNG 小头像路径；无则空串。
var small_portrait_path: String = ""
## 当前模式：MODE_*。
var mode: String = MODE_NONE
## PNG 表情表：face_id -> 文件路径。
var face_paths: Dictionary = {}
## 表情 id 列表（已排序，含 PNG 实际存在的表情）。
var face_ids: PackedStringArray = PackedStringArray()
## 来源描述：如 "pack:synth_pack" / "project" / "overrides"。
var source: String = ""
## 该文件/角色是否只是占位（找不到定义时 true）。
var is_placeholder: bool = false
## 额外信息（atlas 页、pack 条目等），供 UI/运行时参考。
var meta: Dictionary = {}

## 以下三个属性供播放器/编辑器直接 `Object.get("portrait")` 等读取（懒填充）。
## 由 `prepare_textures()` 或 AaResContext.get_character() 填充，避免每次都走方法。
var portrait: Texture2D = null        # 对话/头像用的小图（= small_portrait）
var small_portrait: Texture2D = null  # 小头像
var faces: Dictionary = {}            # face_id -> Texture2D

var _texture_cache: Dictionary = {}
var _placeholder_texture: Texture2D = null
var _avatar_texture: Texture2D = null
var _avatar_loaded := false
var _textures_prepared := false


## 从 AA 命名规则的文件名提取表情 id；不是表情图返回空串。
static func face_id_from_filename(fname: String) -> String:
	var stem := fname.get_file().get_basename()
	var lower := stem.to_lower()
	if lower.ends_with("-avatar") or lower.ends_with("_avatar"):
		return ""
	if lower.contains("halo_01"):
		return "halo_01"
	if lower.contains("halo_02"):
		return "halo_02"
	# AA 的规则是"名字包含 00~12/99"，注意匹配顺序避免 "10" 被 "01" 抢走：
	# 先长后短，避免 "100" 里的 "00" 之类误判（AA 本身较宽松，这里保持一致）
	for face in ["10", "11", "12", "00", "01", "02", "03", "04", "05", "06", "07", "08", "09", "99"]:
		if lower.contains(face):
			return face
	return ""


static func is_avatar_filename(fname: String) -> bool:
	var lower := fname.get_file().get_basename().to_lower()
	return lower.ends_with("-avatar") or lower.ends_with("_avatar")


## 扫描一个目录，得到 face_id -> path 表（同时识别小头像）。
## 返回 {faces: Dictionary, avatar: String, spine_base: String}
static func scan_character_dir(dir: String) -> Dictionary:
	var result := {"faces": {}, "avatar": "", "spine_base": "", "files": PackedStringArray()}
	if dir.is_empty() or not DirAccess.dir_exists_absolute(dir):
		return result
	var files := RawLoader.list_files_recursive(dir)
	result["files"] = files
	for path in files:
		var fname: String = path
		var ext: String = fname.get_extension().to_lower()
		if is_avatar_filename(fname) and ext in IMAGE_EXTS and str(result["avatar"]).is_empty():
			result["avatar"] = path
			continue
		if ext in ["skel", "atlas"]:
			var base: String = str(path).get_basename()
			if str(result["spine_base"]).is_empty():
				result["spine_base"] = base
			continue
		if ext in IMAGE_EXTS:
			var face := face_id_from_filename(fname)
			if not face.is_empty() and not (result["faces"] as Dictionary).has(face):
				(result["faces"] as Dictionary)[face] = path
	return result


func get_face_texture(face_id := "") -> Texture2D:
	if mode == MODE_PNG:
		var path := _pick_face_path(face_id)
		if not path.is_empty():
			var tex := RawLoader.load_texture(path)
			if tex != null:
				return tex
	elif mode == MODE_SPINE:
		# Spine 静态帧/完整运行时不在资源层实现：若同目录有 base.png 之类静态图则尝试，
		# 否则返回占位剪影（DESIGN §9 MVP 允许）。
		var static_tex := _try_spine_static_frame()
		if static_tex != null:
			return static_tex
	return get_placeholder()


## PNG 模式：按 face_id → 00 → 01 → 第一个存在的表情回退。
func _pick_face_path(face_id: String) -> String:
	if face_paths.is_empty():
		return ""
	var want := face_id
	if want.is_empty():
		want = "00"
	if face_paths.has(want):
		return str(face_paths[want])
	if face_paths.has("00"):
		return str(face_paths["00"])
	if face_paths.has("01"):
		return str(face_paths["01"])
	for key in face_paths.keys():
		return str(face_paths[key])
	return ""


func _try_spine_static_frame() -> Texture2D:
	if spine_base_path.is_empty():
		return null
	for ext in IMAGE_EXTS:
		var candidate: String = spine_base_path + "." + str(ext)
		if FileAccess.file_exists(candidate):
			var tex := RawLoader.load_texture(candidate)
			if tex != null:
				return tex
	return null


## 小头像：优先 -avatar.png，其次 PNG 表情 00，最后占位。
func get_small_portrait() -> Texture2D:
	if _avatar_loaded:
		return _avatar_texture
	_avatar_loaded = true
	var path := small_portrait_path
	if path.is_empty() and mode == MODE_PNG:
		path = _pick_face_path("00")
	if not path.is_empty():
		_avatar_texture = RawLoader.load_texture(path)
	if _avatar_texture == null:
		_avatar_texture = get_placeholder()
	return _avatar_texture


## 占位剪影（同一角色名颜色稳定）。
## 预加载头像/表情纹理，填好 `portrait/small_portrait/faces` 属性（幂等、可重复调用）。
func prepare_textures(load_faces := true) -> void:
	if _textures_prepared:
		return
	_textures_prepared = true
	small_portrait = get_small_portrait()
	portrait = small_portrait
	if not load_faces:
		return
	if mode == MODE_PNG and not face_paths.is_empty():
		for face in face_ids:
			var tex := get_face_texture(face)
			if tex != null:
				faces[str(face)] = tex
		if faces.is_empty():
			var fallback := get_face_texture("00")
			if fallback != null:
				faces["00"] = fallback
	elif mode == MODE_SPINE or mode == MODE_NATIVE:
		# 资源层没有 Spine 运行时/官方资源包：留空，播放器用占位剪影
		pass


func get_placeholder() -> Texture2D:
	if _placeholder_texture == null:
		var key := display_name if not display_name.is_empty() else identifier
		if key.is_empty():
			key = "unknown"
		_placeholder_texture = Placeholders.silhouette(key)
		Placeholders.mark_placeholder(_placeholder_texture, key)
	return _placeholder_texture


## 是否有可视化立绘数据（PNG 有图 / Spine 有骨骼文件）。占位/NATIVE 返回 false。
func has_portrait_data() -> bool:
	match mode:
		MODE_PNG:
			return not face_paths.is_empty() or FileAccess.file_exists(small_portrait_path)
		MODE_SPINE:
			return not spine_base_path.is_empty() \
				or FileAccess.file_exists(spine_base_path + ".skel") \
				or FileAccess.file_exists(spine_base_path + ".atlas")
		_:
			return false


func is_native() -> bool:
	return mode == MODE_NATIVE


func get_display_label() -> String:
	var label := display_name if not display_name.is_empty() else identifier
	if not nickname.is_empty():
		return "%s（%s）" % [label, nickname]
	return label


func to_dict() -> Dictionary:
	return {
		"identifier": identifier,
		"display_name": display_name,
		"nickname": nickname,
		"character_reference": character_reference,
		"original_identifier": original_identifier,
		"mode": mode,
		"spine_base_path": spine_base_path,
		"small_portrait_path": small_portrait_path,
		"face_ids": Array(face_ids),
		"face_paths": face_paths.duplicate(true),
		"source": source,
		"is_placeholder": is_placeholder,
		"has_portrait_data": has_portrait_data(),
		"meta": meta.duplicate(true),
	}
