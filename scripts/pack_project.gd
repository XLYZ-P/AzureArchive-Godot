extends SceneTree
## 用 Godot 内置 PCKPacker 打包游戏 PCK（不依赖 editor/--export，本机 --export 会崩）。
## 用法： godot --headless --path . --script scripts/pack_project.gd -- --out=/path/game.pck
## 包含：project.godot、.godot/global_script_class_cache.cfg、addons/、scenes/、assets/、fixtures/aap/、README.md
## 不含：.git/.godot 其他内容/shots/build/research/tests/tools/scripts/docs/fixtures 其他

const INCLUDE_DIRS := ["addons", "scenes", "assets", "fixtures/aap"]
const INCLUDE_FILES := ["project.godot", ".godot/global_script_class_cache.cfg", "README.md"]

func _initialize() -> void:
	var out := "/tmp/game.pck"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var root := ProjectSettings.globalize_path("res://")
	var paths: Array[String] = []
	for f in INCLUDE_FILES:
		if FileAccess.file_exists(root.path_join(f)):
			paths.append(f)
		else:
			printerr("[pack] missing ", f)
	for d in INCLUDE_DIRS:
		_collect(root, d, paths)
	paths.sort()
	print("[pack] files: ", paths.size())
	var packer := PCKPacker.new()
	var err := packer.pck_start(out, 32)
	if err != OK:
		printerr("[pack] pck_start failed: ", err); quit(1); return
	for rel in paths:
		var src := root.path_join(rel)
		err = packer.add_file(rel, src)
		if err != OK:
			printerr("[pack] add failed: ", rel, " err=", err)
	err = packer.flush(true)
	if err != OK:
		printerr("[pack] flush failed: ", err); quit(1); return
	var sz := FileAccess.get_file_as_bytes(out).size()
	print("[pack] OK -> ", out, " (", "%.1f" % (sz / 1048576.0), " MB)")
	quit(0)

func _collect(root: String, rel: String, out: Array[String]) -> void:
	var d := DirAccess.open(root.path_join(rel))
	if d == null:
		printerr("[pack] dir not found: ", rel); return
	d.include_hidden = true
	for f in d.get_files():
		out.append(rel.path_join(f))
	for sub in d.get_directories():
		_collect(root, rel.path_join(sub), out)
