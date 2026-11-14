class_name AaRawLoader
extends RefCounted
## 绕过 Godot 导入器的"原始资源"加载工具（Lead 提供骨架，pack-dev 扩展）
## 背景：本机 headless 环境 `--import` 会崩溃（glibc double free），
## 因此 tests/headless 运行必须只加载 .tscn/.gd/.json 等文本资源，
## 贴图/字体/音频一律用这里的运行时加载接口，不依赖 .import。
##
## 已实测（Godot 4.7.2 headless）：Image.load / load_*_from_buffer /
## FontFile.load_dynamic_font / AudioStream*Vorbis/MP3/WAV.load_from_file 都可用。
##
## 路径可以是 res://、user:// 或绝对路径。所有接口失败时返回 null / ""，不抛错。

const _IMAGE_EXTS := ["png", "jpg", "jpeg", "webp", "svg", "bmp", "tga"]

static var _texture_cache: Dictionary = {}
static var _audio_cache: Dictionary = {}
static var _font_cache: Dictionary = {}


static func clear_cache() -> void:
	_texture_cache.clear()
	_audio_cache.clear()
	_font_cache.clear()


static func file_exists(path: String) -> bool:
	if path.is_empty():
		return false
	return FileAccess.file_exists(path)


static func read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


static func read_bytes(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	return f.get_buffer(f.get_length())


static func read_json(path: String) -> Variant:
	var t := read_text(path)
	if t.is_empty():
		return null
	return JSON.parse_string(t)


static func write_text(path: String, text: String) -> Error:
	_ensure_parent_dir(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()
	return OK


static func write_bytes(path: String, bytes: PackedByteArray) -> Error:
	_ensure_parent_dir(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(bytes)
	f.close()
	return OK


static func _ensure_parent_dir(path: String) -> void:
	var parent := path.get_base_dir()
	if parent.is_empty():
		return
	if not DirAccess.dir_exists_absolute(parent):
		DirAccess.make_dir_recursive_absolute(parent)


# ---------------------------------------------------------------------------
# 贴图
# ---------------------------------------------------------------------------

## 加载贴图。扩展名不区分大小写；SVG 由 Image.load 处理（Godot 内建）。
static func load_texture(path: String, use_cache := true) -> Texture2D:
	if path.is_empty():
		return null
	if use_cache and _texture_cache.has(path):
		return _texture_cache[path]
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	var err := img.load(path)
	var tex: Texture2D = null
	if err == OK and not img.is_empty():
		tex = ImageTexture.create_from_image(img)
	if use_cache:
		_texture_cache[path] = tex
	return tex


## 从内存字节加载贴图（zip 包、内嵌资源用）。返回 null 表示无法识别。
static func load_texture_from_bytes(bytes: PackedByteArray) -> Texture2D:
	if bytes.is_empty():
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes.size() >= 8 and bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
		err = img.load_png_from_buffer(bytes)
	elif bytes.size() >= 4 and bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = img.load_jpg_from_buffer(bytes)
	elif bytes.size() >= 12 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(bytes)
	else:
		# 其它格式（含 SVG）：落临时文件后让 Image.load 处理
		var tmp := "user://aa_tmp_%d%s" % [Time.get_ticks_usec(), ""]
		if write_bytes(tmp, bytes) == OK:
			err = img.load(tmp)
			DirAccess.remove_absolute(tmp)
	if err != OK or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


## 用原始像素构造贴图（占位素材/程序化生成用）。
static func texture_from_image(img: Image) -> ImageTexture:
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------------
# 音频
# ---------------------------------------------------------------------------

static func load_audio(path: String, use_cache := true) -> AudioStream:
	if path.is_empty():
		return null
	if use_cache and _audio_cache.has(path):
		return _audio_cache[path]
	if not FileAccess.file_exists(path):
		return null
	var stream := load_audio_from_bytes(read_bytes(path), path.get_extension())
	if use_cache:
		_audio_cache[path] = stream
	return stream


## 从内存字节加载音频。支持 ogg/wav/mp3（也按魔数猜）。
static func load_audio_from_bytes(bytes: PackedByteArray, ext: String) -> AudioStream:
	if bytes.is_empty():
		return null
	var e := ext.to_lower()
	if e.begins_with("."):
		e = e.substr(1)
	match e:
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
		"wav":
			return AudioStreamWAV.load_from_buffer(bytes)
		"mp3":
			return AudioStreamMP3.load_from_buffer(bytes)
		_:
			if bytes.size() >= 4 and bytes.slice(0, 4).get_string_from_ascii() == "OggS":
				return AudioStreamOggVorbis.load_from_buffer(bytes)
			if bytes.size() >= 4 and bytes[0] == 0x52 and bytes[1] == 0x49 and bytes[2] == 0x46 and bytes[3] == 0x46:
				return AudioStreamWAV.load_from_buffer(bytes)
			if bytes.size() >= 3 and bytes[0] == 0x49 and bytes[1] == 0x44 and bytes[2] == 0x33:
				return AudioStreamMP3.load_from_buffer(bytes)
			return null


# ---------------------------------------------------------------------------
# 字体
# ---------------------------------------------------------------------------

static func load_font(path: String) -> Font:
	if path.is_empty():
		return null
	if _font_cache.has(path):
		return _font_cache[path]
	if not FileAccess.file_exists(path):
		return null
	var f := FontFile.new()
	var result: Font = null
	if f.load_dynamic_font(path) == OK:
		result = f
	_font_cache[path] = result
	return result


# ---------------------------------------------------------------------------
# 杂项（install_pack / 目录扫描 / fixture 工具使用）
# ---------------------------------------------------------------------------

static func is_image_path(path: String) -> bool:
	return path.get_extension().to_lower() in _IMAGE_EXTS


static func is_audio_path(path: String) -> bool:
	return path.get_extension().to_lower() in ["ogg", "wav", "mp3", "flac"]


## 递归列出目录下的文件。目录不存在返回空数组。
static func list_files_recursive(root: String, extensions: Array = []) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(root):
		return out
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if fname != "." and fname != "..":
			var full := root.path_join(fname)
			if dir.current_is_dir():
				out.append_array(list_files_recursive(full, extensions))
			else:
				if extensions.is_empty() or fname.get_extension().to_lower() in extensions:
					out.append(full)
		fname = dir.get_next()
	dir.list_dir_end()
	return out


## 递归复制目录（覆盖已存在文件）。
static func copy_dir_recursive(src: String, dst: String) -> Error:
	if not DirAccess.dir_exists_absolute(src):
		return ERR_FILE_NOT_FOUND
	DirAccess.make_dir_recursive_absolute(dst)
	for file_path in list_files_recursive(src):
		var rel := file_path.trim_prefix(src + "/").trim_prefix(src)
		var target := dst.path_join(rel)
		_ensure_parent_dir(target)
		var err := DirAccess.copy_absolute(file_path, target)
		if err != OK:
			return err
	return OK


## 递归删除目录。不存在时返回 OK。
static func remove_dir_recursive(path: String) -> Error:
	if not DirAccess.dir_exists_absolute(path):
		return OK
	var dir := DirAccess.open(path)
	if dir == null:
		return ERR_CANT_OPEN
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if fname != "." and fname != "..":
			var full := path.path_join(fname)
			if dir.current_is_dir():
				var err := remove_dir_recursive(full)
				if err != OK:
					dir.list_dir_end()
					return err
			else:
				DirAccess.remove_absolute(full)
		fname = dir.get_next()
	dir.list_dir_end()
	return DirAccess.remove_absolute(path)
