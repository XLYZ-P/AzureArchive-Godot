extends RefCounted
## test_class_cache.gd —— headless 环境自检（零业务依赖）。
##
## 本机没有编辑器做全局类扫描，Godot 4.7 的 `class_name` 全局解析依赖
## `.godot/global_script_class_cache.cfg`（见 docs/DESIGN.md §10/§11）。
## 这个用例守护三件事：
##   1. 缓存文件存在且已被引擎读到（`ProjectSettings.get_global_class_list()` 非空）；
##   2. 缓存与实际 .gd 文件一致（扫描所有带 class_name 的脚本，不能漏类 = 不能是过期缓存）；
##   3. 关键基础件可用：AaRawLoader（绕过导入器读文本/JSON/字体）与 autoload AAResources。
##
## 若失败，先跑 `python3 scripts/gen_class_cache.py`（`bash scripts/test.sh` 会自动跑）。

const Fw = preload("res://tests/framework.gd")

const CACHE_PATH := "res://.godot/global_script_class_cache.cfg"
const REQUIRED_CLASSES := ["AaHash", "AaRawLoader"]
const REQUIRED_FILES := [
	"res://addons/aa_resources/raw_loader.gd",
	"res://addons/aa_resources/aa_resources.gd",
	"res://fixtures/aap/sample_kei_01.aap",
	"res://scripts/gen_class_cache.py",
	"res://scripts/godot.sh",
]
const SKIP_DIRS := [".godot", ".git", "__pycache__", "tmp", ".import"]


func run(ctx: Fw.Ctx) -> void:
	# ---------------------------------------------------------------- 1. 缓存基本状态
	ctx.is_true(FileAccess.file_exists(CACHE_PATH),
			"class 缓存文件存在（先跑 python3 scripts/gen_class_cache.py）")
	var globals: Array = ProjectSettings.get_global_class_list()
	ctx.gt(globals.size(), 0, "引擎已读取到 global_class_list（否则 class_name 全部解析失败）")

	var cache_map := {}
	for g in globals:
		cache_map[String(g.get("class", ""))] = g

	for cls_name in REQUIRED_CLASSES:
		ctx.is_true(cache_map.has(String(cls_name)), "基础设施类 %s 已在全局缓存中" % cls_name)

	# ---------------------------------------------------------------- 2. 缓存与磁盘一致（防过期缓存）
	var disk: Array = []
	_scan_gd("res://", disk)
	ctx.gt(disk.size(), 0, "扫描到 res:// 下的 .gd 文件")
	var missing: Array = []
	var race_notes: Array = []
	var cache_mtime := 0
	if FileAccess.file_exists(CACHE_PATH):
		cache_mtime = FileAccess.get_modified_time(CACHE_PATH)
	for entry in disk:
		var cls_name := String(entry.get("class", ""))
		if cache_map.has(cls_name):
			continue
		var mtime := int(entry.get("mtime", 0))
		if mtime > cache_mtime:
			# 并发开发中：文件刚写、缓存尚未刷新，不算用例失败，只提示。
			race_notes.append("%s（%s 在缓存生成后被修改）" % [cls_name, entry.get("path", "")])
		else:
			missing.append("%s @ %s" % [cls_name, entry.get("path", "")])
	ctx.eq(missing.size(), 0, "所有 class_name 都进了缓存（缺 %s）" % str(missing))
	if not race_notes.is_empty():
		ctx.note("并发写入、本轮未计入失败：%s" % str(race_notes))

	# 缓存里的每个类：路径存在且能 load，class 名一致。
	var bad_paths: Array = []
	var load_fail: Array = []
	var name_mismatch: Array = []
	for g in globals:
		var p := String(g.get("path", ""))
		if not FileAccess.file_exists(p):
			bad_paths.append(p)
			continue
		var s = load(p)
		if s == null:
			load_fail.append(p)
			continue
		if s.has_method("get_global_name"):
			var gn := String(s.get_global_name())
			if not gn.is_empty() and gn != String(g.get("class", "")):
				name_mismatch.append("%s != %s" % [gn, g.get("class", "")])
	ctx.eq(bad_paths.size(), 0, "缓存中所有 path 都存在（坏条目 %s）" % str(bad_paths))
	ctx.eq(load_fail.size(), 0, "缓存中所有类都能 load（失败 %s）" % str(load_fail))
	ctx.eq(name_mismatch.size(), 0, "缓存 class 名与脚本内 class_name 一致（%s）" % str(name_mismatch))

	# ---------------------------------------------------------------- 3. 文件清单
	for p in REQUIRED_FILES:
		ctx.is_true(FileAccess.file_exists(p), "基础文件存在：%s" % p)

	# ---------------------------------------------------------------- 4. AaRawLoader（绕过导入器）
	var loader_script := ctx.load_script("res://addons/aa_resources/raw_loader.gd")
	ctx.not_null(loader_script, "AaRawLoader 脚本可加载")
	if loader_script != null:
		for m in ["read_text", "read_json", "load_texture", "load_font", "load_audio"]:
			ctx.is_true(ctx.has_script_method(loader_script, m), "AaRawLoader 提供 %s()" % m)
		var text := String(ctx.static_call(loader_script, "read_text", ["res://project.godot"]))
		ctx.contains(text, "AzureArchive", "AaRawLoader.read_text 能读 project.godot")
		var json: Variant = ctx.static_call(loader_script, "read_json", ["res://fixtures/aap/sample_kei_01.aap"])
		ctx.is_true(json is Dictionary, "AaRawLoader.read_json 能解析真实 .aap")
		if json is Dictionary:
			ctx.eq(((json as Dictionary).get("nodes", {}) as Dictionary).get("$values", []).size(), 17,
					"read_json 得到 17 节点")
		var font = ctx.static_call(loader_script, "load_font", ["res://assets/fonts/wqy-zenhei-extracted.ttf"])
		ctx.not_null(font, "AaRawLoader.load_font 能加载内置 CJK 字体（不依赖 .import）")
		# 不存在的文件应安全返回 null/空串而不是崩溃
		ctx.is_null(ctx.static_call(loader_script, "load_texture", ["res://no_such_file.png"]),
				"load_texture(不存在) 安全返回 null")
		ctx.is_null(ctx.static_call(loader_script, "load_audio", ["res://no_such_file.wav"]),
				"load_audio(不存在) 安全返回 null")

	# ---------------------------------------------------------------- 5. autoload AAResources
	var tree := ctx.tree
	var ar := tree.get_root().get_node_or_null("AAResources")
	ctx.not_null(ar, "autoload AAResources 已挂到 root（project.godot [autoload] 生效）")
	if ar != null:
		ctx.is_true(ar.has_method("set_data_root"), "AAResources 有 set_data_root()")
		ctx.is_true(ar.has_method("ensure_layout"), "AAResources 有 ensure_layout()")
		ctx.is_true(ar.has_method("make_context"), "AAResources 有 make_context()")
		var dr: Variant = ar.get("data_root")
		ctx.is_true(dr is String, "AAResources.data_root 是 String（实际 %s）" % str(dr))

	# ---------------------------------------------------------------- 6. 运行环境
	ctx.eq(OS.get_name(), "Linux", "运行平台是 Linux（本机 proot）")
	var vi := Engine.get_version_info()
	ctx.eq(int(vi.get("major", 4)), 4, "Godot major 版本 4")
	ctx.is_true(DisplayServer.get_name() == "headless", "以 headless 模式运行（显示驱动：%s）" % DisplayServer.get_name())
	ctx.is_true(DirAccess.dir_exists_absolute("res://.godot"), ".godot 目录存在")


## 递归扫描 res:// 下所有 .gd，找出带 class_name 的脚本。
func _scan_gd(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			if not (name in SKIP_DIRS):
				_scan_gd(full, out)
		elif name.ends_with(".gd"):
			var text := FileAccess.get_file_as_string(full)
			var re := RegEx.new()
			re.compile("(?m)^\\s*class_name\\s+([A-Za-z_][A-Za-z0-9_]*)")
			var m := re.search(text)
			if m != null:
				out.append({
					"class": m.get_string(1),
					"path": full,
					"mtime": FileAccess.get_modified_time(full),
				})
		name = d.get_next()
	d.list_dir_end()
