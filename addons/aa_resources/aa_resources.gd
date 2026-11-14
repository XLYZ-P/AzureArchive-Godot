extends Node
## AAResources —— 资源层入口（autoload，见 project.godot）。
## 契约见 docs/DESIGN.md §5.2。
##
## 数据根目录（默认 user://aa_data，可用 set_data_root 指向 AA 真实 data 目录）：
##   projects/  saves/  overrides/  assets/  packs/  settings/
##
## 职责：
##   - 目录布局/工程存档列表/资源包安装卸载
##   - make_context(project_path, save_path) -> AaResContext（资源解析入口）
##
## 注意（DESIGN §10）：所有素材都运行时用 AaRawLoader 加载，不依赖 --import；
## 本脚本只做文件系统操作，_ready() 不阻塞、不打印刷屏。

signal packs_changed
signal data_root_changed

const DEFAULT_ROOT := "user://aa_data"
const RawLoader = preload("res://addons/aa_resources/raw_loader.gd")
const AaManifestScript = preload("res://addons/aa_resources/aa_manifest.gd")
const AaPackScript = preload("res://addons/aa_resources/aa_pack.gd")
const ResContextScript = preload("res://addons/aa_resources/res_context.gd")

## 数据根目录。默认 user://aa_data；set_data_root 可指向 AA 真实 data/。
var data_root: String = DEFAULT_ROOT
## 最近一次失败原因（空串 = 最近操作成功）。
var last_error: String = ""
## 只启用这些 pack id（空数组 = 全部已安装 pack 都启用）。低 → 高优先级顺序按 id 升序。
var enabled_pack_ids: PackedStringArray = PackedStringArray()

var _installed_packs_cache: Array = []
var _packs_cache_valid := false

const LAYOUT_DIRS := ["projects", "saves", "overrides", "assets", "packs", "settings"]


func _ready() -> void:
	ensure_layout()


# ---------------------------------------------------------------------------
# 根目录 / 布局
# ---------------------------------------------------------------------------

func set_data_root(path: String) -> void:
	var normalized := path.strip_edges()
	if normalized.is_empty():
		normalized = DEFAULT_ROOT
	if normalized == data_root:
		ensure_layout()
		return
	data_root = normalized
	_invalidate_packs_cache()
	ensure_layout()
	data_root_changed.emit()


func ensure_layout() -> void:
	for d in LAYOUT_DIRS:
		DirAccess.make_dir_recursive_absolute(join_root(d))


func join_root(rel: String) -> String:
	if data_root.is_empty():
		return rel
	if rel.is_empty():
		return data_root
	return data_root.path_join(rel)


func get_projects_dir() -> String:
	return join_root("projects")


func get_saves_dir() -> String:
	return join_root("saves")


func get_overrides_dir() -> String:
	return join_root("overrides")


func get_packs_dir() -> String:
	return join_root("packs")


func get_settings_dir() -> String:
	return join_root("settings")


func get_assets_dir() -> String:
	return join_root("assets")


## 工程/存档对应的"同名自定义资源文件夹"（AA 约定：`projects/<名字>/`）。
func get_local_dir_for(file_path: String) -> String:
	if file_path.is_empty():
		return ""
	if DirAccess.dir_exists_absolute(file_path):
		return file_path
	return file_path.get_base_dir().path_join(file_path.get_file().get_basename())


func get_project_local_dir(project_path: String) -> String:
	return get_local_dir_for(project_path)


func get_save_local_dir(save_path: String) -> String:
	return get_local_dir_for(save_path)


# ---------------------------------------------------------------------------
# 工程 / 存档列表
# ---------------------------------------------------------------------------

## AA 的「分类名-文件名」命名规则：`第一章-初遇.aap` → category=第一章, file_name=初遇。
static func parse_category_name(stem: String) -> Dictionary:
	var trimmed := stem.strip_edges()
	for sep in ["-", "－", "—", "–"]:
		var idx := trimmed.find(sep)
		if idx > 0 and idx < trimmed.length() - 1:
			var category := trimmed.substr(0, idx).strip_edges()
			var name := trimmed.substr(idx + sep.length()).strip_edges()
			if not category.is_empty() and not name.is_empty():
				return {"category": category, "name": name}
	return {"category": "", "name": trimmed}


## 列出 projects/*.aap。返回 [{name, path, category, modified, preview_title,
## preview_header, preview_bg_name, project_name, file_name, error}]。
func get_projects() -> Array[Dictionary]:
	return _list_media_files(get_projects_dir(), "aap")


## 列出 saves/*.aas。字段同 get_projects（.aas 是 FlatBuffers，读不到封面字段则为空）。
func get_saves() -> Array[Dictionary]:
	return _list_media_files(get_saves_dir(), "aas")


func _list_media_files(dir_path: String, ext: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(dir_path):
		return out
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if fname != "." and fname != ".." and not dir.current_is_dir():
			if fname.get_extension().to_lower() == ext:
				var path := dir_path.path_join(fname)
				out.append(_describe_media_file(path))
		fname = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(_media_file_compare)
	return out


func _describe_media_file(path: String) -> Dictionary:
	var stem := path.get_file().get_basename()
	var parsed := parse_category_name(stem)
	var info := {
		"name": str(parsed["name"]),
		"path": path,
		"category": str(parsed["category"]),
		"modified": FileAccess.get_modified_time(path),
		"preview_title": "",
		"preview_header": "",
		"preview_bg_name": 0,
		"project_name": "",
		"file_name": stem,
		"error": "",
	}
	# 读 .aap 顶部字段（.aas 是二进制 FlatBuffers，只有文本 JSON 才尝试）
	if path.get_extension().to_lower() == "aap" or _looks_like_json(path):
		var data: Variant = RawLoader.read_json(path)
		if data is Dictionary:
			var d := data as Dictionary
			var project_name := str(d.get("ProjectName", ""))
			if not project_name.is_empty():
				info["project_name"] = project_name
				# 文件名带分类时保留分类，显示名用 ProjectName 更准
				if str(parsed["category"]).is_empty():
					info["name"] = project_name
			var header: Variant = d.get("PreviewHeader", null)
			info["preview_header"] = "" if header == null else str(header)
			var title: Variant = d.get("PreviewTitle", null)
			info["preview_title"] = "" if title == null else str(title)
			var bg: Variant = d.get("PreviewBgName", 0)
			info["preview_bg_name"] = int(bg) if bg != null else 0
		else:
			info["error"] = "无法解析 .aap（不是 JSON 对象）"
	return info


func _looks_like_json(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var head := f.get_buffer(8)
	f.close()
	if head.is_empty():
		return false
	while not head.is_empty() and (head[0] == 0x20 or head[0] == 0x09):
		head = head.slice(1)
	return not head.is_empty() and head[0] == 0x7B  # '{'


func _media_file_compare(a: Dictionary, b: Dictionary) -> bool:
	var ca := str(a.get("category", ""))
	var cb := str(b.get("category", ""))
	if ca != cb:
		if ca.is_empty():
			return false
		if cb.is_empty():
			return true
		return ca < cb
	return str(a.get("name", "")).to_lower() < str(b.get("name", "")).to_lower()


# ---------------------------------------------------------------------------
# aa_pack 资源包
# ---------------------------------------------------------------------------

func _invalidate_packs_cache() -> void:
	_packs_cache_valid = false
	_installed_packs_cache.clear()


## 列出已安装 aa_pack。
## 返回 [{id, name, version, author, description, path, manifest, manifest_dict,
##        valid, errors, counts}]，按 id 升序（= 低 → 高优先级）。
func get_packs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pack in get_installed_pack_objects():
		out.append(pack.to_dict())
	return out


## 已安装 aa_pack 的 AaPack 实例（低 → 高优先级）。
func get_installed_pack_objects() -> Array:
	if _packs_cache_valid:
		return _installed_packs_cache.duplicate()
	var packs: Array = []
	var packs_dir := get_packs_dir()
	if DirAccess.dir_exists_absolute(packs_dir):
		var dir := DirAccess.open(packs_dir)
		if dir != null:
			dir.list_dir_begin()
			var fname := dir.get_next()
			while not fname.is_empty():
				if fname != "." and fname != ".." and dir.current_is_dir() and not fname.begins_with("."):
					var pack := AaPackScript.from_path(packs_dir.path_join(fname))
					if pack.valid and _pack_enabled(pack.id):
						packs.append(pack)
					else:
						pack.close()
				fname = dir.get_next()
			dir.list_dir_end()
	packs.sort_custom(func(a, b): return a.id < b.id)
	_installed_packs_cache = packs
	_packs_cache_valid = true
	return packs.duplicate()


func _pack_enabled(pack_id: String) -> bool:
	if enabled_pack_ids.is_empty():
		return true
	return pack_id in enabled_pack_ids


func set_enabled_packs(ids: PackedStringArray) -> void:
	enabled_pack_ids = ids.duplicate()
	_invalidate_packs_cache()
	packs_changed.emit()


## pack 元数据摘要（给目录界面用）：[{id,name,version,path,valid}]。
func get_pack_summaries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in get_packs():
		out.append({
			"id": item.get("id", ""),
			"name": item.get("name", ""),
			"version": item.get("version", ""),
			"path": item.get("path", ""),
			"valid": item.get("valid", false),
		})
	return out


func get_pack(pack_id: String) -> AaPack:
	for pack in get_installed_pack_objects():
		if pack.id == pack_id:
			return pack
	return null


static func _is_safe_pack_id(id: String) -> bool:
	if id.is_empty() or id == "." or id == "..":
		return false
	if id.contains("/") or id.contains("\\") or id.contains(":"):
		return false
	for i in id.length():
		if id.unicode_at(i) < 0x20:
			return false
	return true


## 安装 aa_pack（目录或 .zip）到 `<data_root>/packs/<id>/`。
## id 取 catalog.json 的 id；读不到则用目录名/zip 文件名。
## 同 id 已安装会先删后装。返回 Error（OK / ERR_*），原因写 last_error。
func install_pack(source_path: String) -> Error:
	last_error = ""
	var src := source_path.strip_edges()
	if src.is_empty():
		last_error = "install_pack: 路径为空"
		return ERR_INVALID_PARAMETER
	var is_zip := FileAccess.file_exists(src) and src.get_extension().to_lower() in ["zip", "aapack"]
	var is_dir := DirAccess.dir_exists_absolute(src)
	if not is_zip and not is_dir:
		last_error = "install_pack: 文件/目录不存在: " + src
		return ERR_FILE_NOT_FOUND
	var packs_dir := get_packs_dir()
	DirAccess.make_dir_recursive_absolute(packs_dir)
	var staging := packs_dir.path_join(".installing_%d_%d" % [Time.get_ticks_usec(), randi()])
	var zip_reader: ZIPReader = null
	var pack_id := ""
	var err := OK
	if is_zip:
		zip_reader = ZIPReader.new()
		err = zip_reader.open(src)
		if err != OK:
			last_error = "install_pack: 无法打开 zip (%d): %s" % [err, src]
			return err
		var catalog := _read_catalog_from_zip(zip_reader)
		pack_id = str(catalog.get("id", "")).strip_edges()
		if pack_id.is_empty():
			pack_id = str(_read_pack_meta_from_zip(zip_reader).get("id", "")).strip_edges()
		if pack_id.is_empty():
			pack_id = src.get_file().get_basename()
		if not _is_safe_pack_id(pack_id):
			zip_reader.close()
			last_error = "install_pack: 非法 pack id: " + pack_id
			return ERR_INVALID_PARAMETER
		err = _extract_zip_to(zip_reader, staging)
		zip_reader.close()
		zip_reader = null
	else:
		var catalog := _read_catalog_from_dir(src)
		pack_id = str(catalog.get("id", "")).strip_edges()
		if pack_id.is_empty():
			pack_id = str(_read_pack_meta_from_dir(src).get("id", "")).strip_edges()
		if pack_id.is_empty():
			pack_id = src.get_file()
		if not _is_safe_pack_id(pack_id):
			last_error = "install_pack: 非法 pack id: " + pack_id
			return ERR_INVALID_PARAMETER
		err = RawLoader.copy_dir_recursive(src, staging)
	if err != OK:
		RawLoader.remove_dir_recursive(staging)
		last_error = "install_pack: 复制/解压失败 (%d)" % err
		return err
	var target := packs_dir.path_join(pack_id)
	if DirAccess.dir_exists_absolute(target):
		RawLoader.remove_dir_recursive(target)
	var rename_err := DirAccess.rename_absolute(staging, target)
	if rename_err != OK:
		RawLoader.remove_dir_recursive(staging)
		last_error = "install_pack: 移动到 %s 失败 (%d)" % [target, rename_err]
		return rename_err
	if not FileAccess.file_exists(target.path_join("catalog.json")):
		last_error = "aa_pack 缺少 catalog.json（已安装，可能不是合法 aa_pack）"
	_invalidate_packs_cache()
	packs_changed.emit()
	return OK


## 卸载 aa_pack：删除 `<data_root>/packs/<id>/`。
func uninstall_pack(pack_id: String) -> Error:
	last_error = ""
	var id := pack_id.strip_edges()
	if not _is_safe_pack_id(id):
		last_error = "uninstall_pack: 非法 pack id: " + pack_id
		return ERR_INVALID_PARAMETER
	var target := get_packs_dir().path_join(id)
	if not DirAccess.dir_exists_absolute(target):
		last_error = "uninstall_pack: 未安装: " + id
		return ERR_FILE_NOT_FOUND
	var err := RawLoader.remove_dir_recursive(target)
	if err != OK:
		last_error = "uninstall_pack: 删除失败 (%d): %s" % [err, target]
		return err
	_invalidate_packs_cache()
	packs_changed.emit()
	return OK


func _read_catalog_from_zip(zip_reader: ZIPReader) -> Dictionary:
	var bytes := zip_reader.read_file("catalog.json")
	if bytes.is_empty():
		# 兼容：zip 内多一层目录（例如解压工具生成的 <name>/catalog.json）
		for rel in zip_reader.get_files():
			if rel.get_file() == "catalog.json" and rel.count("/") == 1:
				bytes = zip_reader.read_file(rel)
				break
	if bytes.is_empty():
		return {}
	var data: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	return data if data is Dictionary else {}


func _read_pack_meta_from_zip(zip_reader: ZIPReader) -> Dictionary:
	var bytes := zip_reader.read_file("pack.json")
	if bytes.is_empty():
		return {}
	var data: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	return data if data is Dictionary else {}


func _read_pack_meta_from_dir(dir_path: String) -> Dictionary:
	var path := dir_path.path_join("pack.json")
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = RawLoader.read_json(path)
	return data if data is Dictionary else {}


func _read_catalog_from_dir(dir_path: String) -> Dictionary:
	var path := dir_path.path_join("catalog.json")
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = RawLoader.read_json(path)
	return data if data is Dictionary else {}


func _extract_zip_to(zip_reader: ZIPReader, target_dir: String) -> Error:
	DirAccess.make_dir_recursive_absolute(target_dir)
	for rel in zip_reader.get_files():
		var safe := AaManifestScript.normalize_relative(rel)
		if safe.is_empty() or rel.ends_with("/"):
			continue
		var dest := target_dir.path_join(safe)
		var bytes := zip_reader.read_file(rel)
		if bytes.is_empty() and not zip_reader.file_exists(rel):
			continue
		var err := RawLoader.write_bytes(dest, bytes)
		if err != OK:
			return err
	return OK


# ---------------------------------------------------------------------------
# 资源上下文
# ---------------------------------------------------------------------------

## 创建资源上下文：解析工程（+存档）以及全局 overrides / 已安装 aa_pack。
## project_path/save_path 可以是 .aap/.aas 文件路径，也可以是同名资源文件夹。
func make_context(project_path := "", save_path := "") -> AaResContext:
	var ctx: AaResContext = ResContextScript.new()
	ctx.setup(data_root, get_installed_pack_objects(), project_path, save_path)
	return ctx


## 便捷：确保工程/存档对应的本地资源文件夹存在，返回路径。
func ensure_local_dir(file_path: String) -> String:
	var dir := get_local_dir_for(file_path)
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
	return dir


# ---------------------------------------------------------------------------
# AA 数据目录探测（可选便利接口；只读，不写任何文件）
# ---------------------------------------------------------------------------

## 常见 AA data/ 目录候选（环境变量 AA_DATA / Android 官方路径 / user://aa_data）。
func detect_aa_data_root() -> String:
	var candidates: Array[String] = []
	var env := OS.get_environment("AA_DATA")
	if not env.is_empty():
		candidates.append(env)
	candidates.append("/storage/emulated/0/Android/data/com.foxxlight.AzureArchive/files/data")
	candidates.append("user://aa_data")
	for candidate in candidates:
		if DirAccess.dir_exists_absolute(candidate.path_join("projects")):
			return candidate
	return ""


func clear_caches() -> void:
	RawLoader.clear_cache()
	_invalidate_packs_cache()
