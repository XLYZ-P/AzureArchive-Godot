extends RefCounted
## test_editor_smoke.gd —— 编辑器 headless 冒烟（新建→加节点→连线→保存→重载）。
##
## 验证 docs/DESIGN.md §6 对外 API（与 editor-dev 约定）：
##   1. `scenes/editor/Editor.tscn` 可 headless 实例化不崩；
##   2. `new_project()` 得到只有入口节点的新工程；
##   3. `add_node(NODE_SCRIPT/NODE_EXIT)` 返回 guid 且模型里查得到；`connect_nodes()` 连边成功；
##   4. `save_as("/tmp/...")` 后再用 `AapProject.load_from_file()` 载入：节点数/连线/字段顺序一致；
##   5. `open_project_file(真实样本)` 能打开 17 节点工程；
##   6. `undo()/redo()` 对节点增删生效；
##   7. `compile()` 能编译出 PlayScript。
##
## 依赖 editor-dev 的 addons/aa_editor + scenes/editor/Editor.tscn（未就绪则 PENDING）。

const Fw = preload("res://tests/framework.gd")

const EDITOR_SCENE := "res://scenes/editor/Editor.tscn"
const SAMPLE := "res://fixtures/aap/sample_kei_01.aap"
const SMOKE := "res://fixtures/synth/smoke.aap"
const TMP_SAVE := "/tmp/qa_editor_smoke.aap"
const ZERO_GUID := "00000000-0000-0000-0000-000000000000"


func run(ctx: Fw.Ctx) -> void:
	if not ResourceLoader.exists(EDITOR_SCENE):
		ctx.pending("等待 editor-dev：%s 不存在" % EDITOR_SCENE)
		return
	var editor_script := ctx.load_script("res://addons/aa_editor/editor.gd")
	if editor_script == null:
		ctx.pending("等待 editor-dev：addons/aa_editor/editor.gd 加载失败")
		return
	if not ctx.need_methods(editor_script, ["new_project", "get_project", "add_node",
			"connect_nodes", "save_as", "open_project_file", "undo", "redo", "compile"],
			"editor-dev"):
		return

	# ---------------------------------------------------------------- 1. 实例化
	var scene: PackedScene = load(EDITOR_SCENE)
	ctx.not_null(scene, "Editor.tscn 可加载")
	if scene == null:
		return
	var editor: Variant = scene.instantiate()
	ctx.not_null(editor, "Editor.tscn 可实例化")
	ctx.root_node().add_child(editor)
	await ctx.advance_frames(3)
	ctx.is_true(editor.is_inside_tree(), "编辑器已挂到场景树")
	ctx.eq(editor.get_class(), "Control", "编辑器根节点是 Control")

	# ---------------------------------------------------------------- 2. 新建工程
	ctx.is_true(editor.new_project(), "new_project() 成功")
	var proj: Variant = editor.get_project()
	ctx.not_null(proj, "get_project() 非空")
	if proj == null:
		editor.queue_free()
		return
	ctx.eq(proj.nodes.size(), 1, "新工程只有 1 个节点（入口）")
	ctx.not_null(proj.get_entry(), "新工程有入口节点")
	ctx.eq(proj.get_entry().guid, ZERO_GUID, "入口 Guid 全 0")
	ctx.eq(String(editor.get_current_path()), "", "新工程 current_path 为空")

	# ---------------------------------------------------------------- 3. 加节点 + 连线（入口 → 脚本 → 出口）
	var script_guid: String = editor.add_node(AapProject.NODE_SCRIPT, Vector2(0, -200))
	ctx.is_true(not script_guid.is_empty(), "add_node(NODE_SCRIPT) 返回 guid")
	ctx.not_null(proj.find_node(script_guid), "新脚本节点在模型里可查到")
	var script_node: Variant = proj.find_node(script_guid)
	ctx.eq(int(script_node.get("node_type")), AapProject.NODE_SCRIPT, "节点类型 NODE_SCRIPT")
	ctx.almost_eq(script_node.get("pos").y, -200.0, 1e-3, "节点坐标 Y=-200")
	ctx.eq(script_node.get("scripts").size(), 1, "新建 Script 节点默认带 1 行空脚本")

	ctx.is_true(editor.connect_nodes(ZERO_GUID, script_guid), "connect_nodes(入口→脚本) 成功")
	var entry: Variant = proj.get_entry()
	ctx.contains(Array(entry.get("connections")), script_guid, "入口出边包含新脚本 guid")

	var exit_guid: String = editor.add_node(AapProject.NODE_EXIT, Vector2(0, -400))
	ctx.is_true(not exit_guid.is_empty(), "add_node(NODE_EXIT) 返回 guid")
	ctx.is_true(editor.connect_nodes(script_guid, exit_guid), "connect_nodes(脚本→出口) 成功")
	ctx.contains(Array(proj.find_node(script_guid).get("connections")), exit_guid,
			"脚本节点出边包含出口 guid")

	# 填一句台词 + 出口结局标记，保证保存内容有意义
	var line: Variant = proj.find_node(script_guid).get("scripts")[0]
	line.set("text", "编辑器保存测试台词。")
	line.set("bg_friendly_name", "synth_bg")
	line.set("bg_name", AaHash.bg_id("synth_bg"))
	var exit_node: Variant = proj.find_node(exit_guid)
	exit_node.set("is_ending", true)
	exit_node.set("end_text", "—— 完 ——")

	# 已知问题（Q-006）：editor.save_as() 会 _commit_inspector()，若 inspector 当前展示的
	# 脚本节点行仍挂着「空文本」控件，会把外部直接改模型的行文本覆盖回去。真实编辑流程
	# 用户是在 inspector 里改，不受影响；这里先把 inspector 切到出口节点再保存（测试隔离）。
	editor.get_inspector().show_node(proj, proj.find_node(exit_guid))
	# ---------------------------------------------------------------- 4. 保存到 /tmp 并重载
	_remove_file(TMP_SAVE)
	ctx.is_true(editor.save_as(TMP_SAVE), "save_as(/tmp/...) 成功")
	ctx.is_true(FileAccess.file_exists(TMP_SAVE), "保存文件存在：%s" % TMP_SAVE)
	var saved_json: Variant = JSON.parse_string(FileAccess.get_file_as_string(TMP_SAVE))
	ctx.is_true(saved_json is Dictionary, "保存的 .aap 是合法 JSON")
	if saved_json is Dictionary:
		var saved_nodes: Array = (saved_json as Dictionary)["nodes"]["$values"]
		ctx.eq(saved_nodes.size(), 3, "保存 3 个节点（入口/脚本/出口）")
		ctx.eq(String((saved_nodes[0] as Dictionary).get("Guid", "")), ZERO_GUID, "保存的入口 Guid 全 0")
		ctx.eq_keys(saved_nodes[0], ["$type", "Title", "Header", "Guid", "ConnectionsTo", "X", "Y"],
				"保存的 Entry 字段顺序符合 AA")
		ctx.eq_keys(saved_nodes[1], ["$type", "Scripts", "NodeName", "Guid", "ConnectionsTo", "X", "Y"],
				"保存的 ScriptNode 字段顺序符合 AA")
		ctx.eq_keys(saved_nodes[2], ["$type", "IsEnding", "EndText", "NeHeader", "NeTitle",
				"NeScriptDirty", "Guid", "ConnectionsTo", "X", "Y"],
				"保存的 ExitNode 字段顺序符合 AA")

	var loaded: AapProject = AapProject.load_from_file(TMP_SAVE)
	ctx.not_null(loaded, "保存的 .aap 可被 AapProject 重新载入")
	if loaded != null:
		ctx.eq(loaded.nodes.size(), 3, "重载后 3 个节点")
		ctx.eq_deep_ordered(loaded.to_dict(), proj.to_dict(), "重载后与编辑器内模型深度+字段顺序一致")
		ctx.contains(Array(loaded.get_entry().connections), script_guid, "重载后入口连线保持")
		var loaded_script: Variant = loaded.find_node(script_guid)
		ctx.not_null(loaded_script, "重载后能按 guid 找到脚本节点")
		if loaded_script != null:
			ctx.eq(String(loaded_script.get("scripts")[0].get("text")), "编辑器保存测试台词。",
					"重载后台词内容保持")
			ctx.eq(int(loaded_script.get("scripts")[0].get("bg_name")), AaHash.bg_id("synth_bg"),
					"重载后 bgName 保持")
		ctx.is_true(bool(loaded.find_node(exit_guid).get("is_ending")), "重载后出口 Ending 标记保持")

	# ---------------------------------------------------------------- 5. 打开真实样本
	ctx.is_true(editor.open_project_file(SAMPLE), "open_project_file(真实样本) 成功")
	var sample_proj: Variant = editor.get_project()
	ctx.not_null(sample_proj, "打开样本后 get_project() 非空")
	if sample_proj != null:
		ctx.eq(sample_proj.nodes.size(), 17, "真实样本打开后 17 节点")
		ctx.eq(String(sample_proj.project_name), "Kei-初遇", "样本 ProjectName")
		ctx.eq(String(editor.get_current_path()), SAMPLE, "编辑器 current_path 指向样本")
		var ps: Variant = editor.compile()
		ctx.not_null(ps, "compile() 真实样本成功")
		if ps != null:
			ctx.gt(int(ps.get_node_count()), 0, "编译产物节点数 > 0")

	# 打开合成工程（6 节点）
	ctx.is_true(editor.open_project_file(SMOKE), "open_project_file(合成 smoke.aap) 成功")
	ctx.eq(editor.get_project().nodes.size(), 6, "合成工程打开后 6 节点")

	# ---------------------------------------------------------------- 6. undo / redo
	var n_before: int = editor.get_project().nodes.size()
	var extra_guid: String = editor.add_node(AapProject.NODE_SCRIPT, Vector2(0, -600))
	ctx.is_true(not extra_guid.is_empty(), "再加一个脚本节点")
	ctx.eq(editor.get_project().nodes.size(), n_before + 1, "加节点后数量 +1")
	ctx.is_true(editor.undo(), "undo() 成功")
	ctx.eq(editor.get_project().nodes.size(), n_before, "undo 后节点数恢复")
	ctx.is_true(editor.redo(), "redo() 成功")
	ctx.eq(editor.get_project().nodes.size(), n_before + 1, "redo 后节点数恢复为 +1")

	# ---------------------------------------------------------------- 清理
	_remove_file(TMP_SAVE)
	editor.queue_free()
	await ctx.advance_frames(2)


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
