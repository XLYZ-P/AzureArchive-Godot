extends RefCounted
## test_main_integration.gd —— 目录界面（scenes/main）的「用户真实路径」集成测试。
##
## 用户日常路径：打开 App → 看到工程列表 → 选中 → 播放 / 编辑。本用例在 headless 下
## 走完整条链路（Lead 手动验证过可行，脚本来自 /tmp/integ_main.gd，测试化后断言）：
##   1. 临时数据根 + 拷入真实样本 `sample_kei_01.aap` → `refresh()` 列出 1 个工程；
##   2. 未选中时 `_on_play()` 给出提示不崩；
##   3. 选中 → `_on_play()` → overlay 里出现 Player → instant + debug_run_to_finish 跑完
##      （170 行真实剧情 / 5 个选择）→ `_close_overlay()` 清空 overlay 并刷新列表；
##   4. 选中 → `_on_edit()` → overlay 里出现 Editor → 打开真实样本 17 节点 → 关闭。
##
## 依赖 Lead 的 scenes/main/Main.tscn + aa_player + aa_editor；缺失时 PENDING。
## 测试结束恢复 AAResources.data_root 并清理临时目录。

const Fw = preload("res://tests/framework.gd")

const MAIN_SCENE := "res://scenes/main/Main.tscn"
const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const EDITOR_SCENE := "res://scenes/editor/Editor.tscn"
const SAMPLE := "res://fixtures/aap/sample_kei_01.aap"
const TMP_ROOT := "user://qa_main_data"


func run(ctx: Fw.Ctx) -> void:
	if not ResourceLoader.exists(MAIN_SCENE):
		ctx.pending("等待 Lead：%s 不存在" % MAIN_SCENE)
		return
	var main_script := ctx.load_script("res://scenes/main/main.gd")
	if main_script == null:
		ctx.pending("等待 Lead：scenes/main/main.gd 加载失败")
		return
	if not ctx.need_methods(main_script, ["refresh", "_on_play", "_on_edit", "_close_overlay"],
			"Lead"):
		return

	var ar := ctx.tree.get_root().get_node_or_null("AAResources")
	ctx.not_null(ar, "autoload AAResources 存在")
	if ar == null:
		return
	var original_root := String(ar.get("data_root"))

	# ---------------------------------------------------------------- 0. 临时数据根 + 真实样本
	_rmtree(TMP_ROOT)
	ar.set_data_root(TMP_ROOT)
	ar.ensure_layout()
	DirAccess.make_dir_recursive_absolute(TMP_ROOT.path_join("projects"))
	var project_path := TMP_ROOT.path_join("projects/sample_kei_01.aap")
	_copy_file(SAMPLE, project_path)
	ctx.is_true(FileAccess.file_exists(project_path), "真实样本已拷入临时 projects/")
	# 同名自定义资源文件夹（manifest），模拟 AA 工程本地资源（可选，不影响断言）
	var local_dir := TMP_ROOT.path_join("projects/sample_kei_01")
	DirAccess.make_dir_recursive_absolute(local_dir)
	_copy_file("res://fixtures/aap/sample_kei_01.manifest.json", local_dir.path_join("manifest.json"))

	# ---------------------------------------------------------------- 1. 实例化目录界面
	var scene: PackedScene = load(MAIN_SCENE)
	ctx.not_null(scene, "Main.tscn 可加载")
	if scene == null:
		_restore(ar, original_root)
		return
	var main: Variant = scene.instantiate()
	ctx.not_null(main, "Main.tscn 可实例化")
	ctx.root_node().add_child(main)
	await ctx.advance_frames(4)
	ctx.is_true(main.is_inside_tree(), "目录界面已挂到场景树")
	ctx.not_null(main.get("project_list"), "project_list 已构建")
	if main.get("project_list") == null:
		main.queue_free()
		_restore(ar, original_root)
		_rmtree(TMP_ROOT)
		return

	# ---------------------------------------------------------------- 2. 刷新列表
	main.refresh()
	await ctx.advance_frames(1)
	var list: ItemList = main.get("project_list")
	ctx.eq(list.item_count, 1, "refresh() 后工程列表 1 项（临时数据根只有拷入的样本）")
	ctx.contains(list.get_item_text(0), "Kei-初遇", "列表项显示 ProjectName（Kei-初遇）")
	var status: Label = main.get("status")
	ctx.contains(status.text, "工程 1 个", "状态栏显示工程数量")
	ctx.contains(String(main.get("path_label").text), TMP_ROOT, "路径栏显示数据目录")

	# 未选中时点播放：提示而不崩
	list.deselect_all()
	main._on_play()
	ctx.contains(String(main.get("status").text), "请先选择", "未选中时 _on_play 给出提示")
	await ctx.advance_frames(1)

	# ---------------------------------------------------------------- 3. 播放真实样本
	ctx.is_true(ResourceLoader.exists(PLAYER_SCENE), "Player.tscn 就绪（播放路径可测）")
	list.select(0)
	await ctx.advance_frames(1)
	main._on_selection_changed(0)
	await ctx.advance_frames(1)
	ctx.contains(String(main.get("detail_label").text), "Kei-初遇", "选中后详情显示工程名")
	main._on_play()
	await ctx.advance_frames(4)
	var overlay: Control = main.get("overlay_root")
	ctx.not_null(overlay, "overlay_root 存在")
	var player: Variant = _find_child_with_method(overlay, "setup_from_path")
	ctx.not_null(player, "_on_play() 后 overlay 里出现播放器")
	if player != null:
		ctx.is_true(player.is_inside_tree(), "播放器已挂树")
		# 等播放器把工程数据准备好
		var wait_frames := 0
		while player.get("play_data") != null and (player.get("play_data") as Dictionary).is_empty() \
				and wait_frames < 30:
			await ctx.advance_frames(1)
			wait_frames += 1
		ctx.is_false(player.is_finished(), "播放器刚打开时未结束")
		player.set_instant_mode(true)
		var result: Dictionary = player.debug_run_to_finish(8000, 0)
		ctx.is_true(bool(result.get("finished", false)), "真实样本在播放器中跑到结局（finished）")
		ctx.gte(int(result.get("lines", 0)), 100, "真实样本播放行数 >= 100（实际 %d）" % int(result.get("lines", 0)))
		ctx.gte(int(result.get("choices", 0)), 5, "真实样本经过 >= 5 次选择（实际 %d）" % int(result.get("choices", 0)))
		var reason := String(result.get("reason", ""))
		ctx.is_true(not reason.is_empty(), "播放结束原因非空：%s" % reason)

	# 关闭 overlay：清空并刷新列表
	main._close_overlay()
	await ctx.advance_frames(3)
	ctx.eq(overlay.get_child_count(), 0, "_close_overlay() 后 overlay 清空")
	ctx.eq(main.get("project_list").item_count, 1, "_close_overlay() 后列表刷新且仍有 1 个工程")

	# ---------------------------------------------------------------- 4. 编辑真实样本
	ctx.is_true(ResourceLoader.exists(EDITOR_SCENE), "Editor.tscn 就绪（编辑路径可测）")
	main.get("project_list").select(0)
	await ctx.advance_frames(1)
	main._on_edit()
	await ctx.advance_frames(5)
	var editor: Variant = _find_child_with_method(overlay, "open_project_file")
	if editor == null:
		editor = _find_child_with_method(overlay, "save_as")
	ctx.not_null(editor, "_on_edit() 后 overlay 里出现编辑器")
	if editor != null:
		ctx.is_true(editor.is_inside_tree(), "编辑器已挂树")
		var wait_edit := 0
		while editor.get("project") == null and wait_edit < 30:
			await ctx.advance_frames(1)
			wait_edit += 1
		ctx.not_null(editor.get("project"), "编辑器已打开工程")
		if editor.get("project") != null:
			ctx.eq(editor.get("project").nodes.size(), 17, "编辑器打开真实样本 = 17 节点")
			ctx.eq(String(editor.get("project").project_name), "Kei-初遇", "编辑器里工程名正确")
	main._close_overlay()
	await ctx.advance_frames(3)
	ctx.eq(overlay.get_child_count(), 0, "关闭编辑器后 overlay 清空")

	# ---------------------------------------------------------------- 5. 清理
	main.queue_free()
	await ctx.advance_frames(2)
	_restore(ar, original_root)
	_rmtree(TMP_ROOT)


func _find_child_with_method(parent: Node, method: String) -> Variant:
	if parent == null:
		return null
	for c in parent.get_children():
		if c.has_method(method):
			return c
	return null


func _restore(ar: Node, original_root: String) -> void:
	if ar != null and not original_root.is_empty():
		ar.set_data_root(original_root)


func _copy_file(src: String, dst: String) -> void:
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	if not FileAccess.file_exists(src):
		return
	var bytes := FileAccess.get_file_as_bytes(src)
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()


func _rmtree(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		return
	if not DirAccess.dir_exists_absolute(path):
		return
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name != "." and name != "..":
			var full := path.path_join(name)
			if d.current_is_dir():
				_rmtree(full)
			else:
				DirAccess.remove_absolute(full)
		name = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path)
