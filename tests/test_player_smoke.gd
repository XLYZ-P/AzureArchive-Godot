extends RefCounted
## test_player_smoke.gd —— 播放器 headless 冒烟：加载合成工程，推进到出口。
##
## 用 `fixtures/synth/smoke.aap`（入口 + 3 行台词含 #wait/内联标记 + 2 选项 + 2 分支 + Ending）。
## 验证 docs/DESIGN.md §5.3：
##   1. `scenes/player/Player.tscn` 可 headless 实例化、挂树、不崩；
##   2. `setup_from_path()` / `setup(AapProject)` 两种入口都能加载合成工程；
##   3. `set_instant_mode(true)` + `advance()` / `choose()` 交互路径能走到结局；
##   4. `debug_run_to_finish()` 能跑完并返回统计（finished/choices/lines/texts）；
##   5. 剧情行文本按预期出现（含选择分支文本），`finished` 信号触发；
##   6. 打不开的工程路径不崩（显示提示而非报错崩溃）。
##
## 依赖 runtime-dev 的 addons/aa_player + scenes/player/Player.tscn（未就绪则 PENDING）。

const Fw = preload("res://tests/framework.gd")

const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const SMOKE := "res://fixtures/synth/smoke.aap"
const TMP_ROOT := "user://qa_player_data"


func run(ctx: Fw.Ctx) -> void:
	if not ResourceLoader.exists(PLAYER_SCENE):
		ctx.pending("等待 runtime-dev：%s 不存在" % PLAYER_SCENE)
		return
	var player_script := ctx.load_script("res://addons/aa_player/player.gd")
	if player_script == null:
		ctx.pending("等待 runtime-dev：addons/aa_player/player.gd 加载失败")
		return
	if not ctx.need_methods(player_script, ["setup_from_path", "setup", "play",
			"advance", "choose", "set_instant_mode", "is_finished",
			"is_waiting_choice", "debug_run_to_finish"], "runtime-dev"):
		return
	if not FileAccess.file_exists(SMOKE):
		ctx.fail("合成工程 fixtures/synth/smoke.aap 不存在（先跑 python3 tests/make_fixtures.py）")
		return

	# 给播放器准备一个数据根（装合成包），让背景/角色有真资源可加载
	var ar := ctx.tree.get_root().get_node_or_null("AAResources")
	var original_root := ""
	if ar != null:
		original_root = String(ar.get("data_root"))
		_rmtree(TMP_ROOT)
		ar.set_data_root(TMP_ROOT)
		ar.ensure_layout()
		if DirAccess.dir_exists_absolute("res://fixtures/synth/pack"):
			ar.install_pack("res://fixtures/synth/pack")

	# ---------------------------------------------------------------- 1. 实例化
	var scene: PackedScene = load(PLAYER_SCENE)
	ctx.not_null(scene, "Player.tscn 可加载")
	if scene == null:
		return
	var player: Variant = scene.instantiate()
	ctx.not_null(player, "Player.tscn 可实例化")
	ctx.root_node().add_child(player)
	await ctx.advance_frames(2)
	ctx.is_true(player.is_inside_tree(), "播放器已挂到场景树")
	ctx.is_true(player is AaPlayer, "Player.tscn 根节点是 AaPlayer（class_name 生效）")
	if not (player is AaPlayer):
		player.queue_free()
		_restore(ar, original_root)
		return

	var finished_count := [0]
	player.finished.connect(func() -> void: finished_count[0] += 1)

	# ---------------------------------------------------------------- 2. setup_from_path + 交互推进
	player.set_instant_mode(true)
	ctx.is_true(player.is_instant_mode(), "set_instant_mode(true) 生效")
	player.setup_from_path(SMOKE)
	player.play()
	await ctx.advance_frames(2)
	ctx.is_false(player.is_finished(), "刚 play() 时未结束")
	ctx.eq(finished_count[0], 0, "刚 play() 时 finished 信号未触发")
	var guid0: String = player.get_current_guid()
	ctx.is_true(not guid0.is_empty(), "play() 后 get_current_guid() 非空")
	ctx.gte(player.get_current_line_index(), 0, "get_current_line_index() >= 0")
	# 第 1 行含 [size]/[FF0000] 内联标记：对话框应渲染成文字而不是原样标记
	var first_line_label: Variant = player.get("dialogue").get("text_label")
	var first_line_rendered: String = first_line_label.get_parsed_text()
	ctx.contains(first_line_rendered, "合成工程开始", "第 1 行台词显示在对话框")
	ctx.contains(first_line_rendered, "放大", "[size=200] 的内联文字显示出来")
	ctx.not_contains(first_line_rendered, "[size=", "对话框把 [size] 转成 BBCode（不显示原标记）")

	# 交互式推进：遇到选择就选第 0 项，直到 finished（最多 120 步）
	var steps := 0
	var saw_choice := false
	while steps < 120 and not player.is_finished():
		if player.is_waiting_choice():
			saw_choice = true
			player.choose(0)
		else:
			player.advance()
		steps += 1
		await ctx.advance_frames(1)
	ctx.is_true(saw_choice, "推进过程中出现选择节点（is_waiting_choice）")
	ctx.is_true(player.is_finished(), "交互推进 %d 步后到达结局（is_finished）" % steps)
	ctx.eq(finished_count[0], 1, "finished 信号触发 1 次")
	ctx.gt(steps, 0, "推进步数 > 0")

	# 剧情文本（选择第 0 项走「向右走」分支）
	var texts: Array = player.get("_collected_texts") if player.get("_collected_texts") != null else []
	ctx.gt(texts.size(), 0, "收集到的台词非空")
	var joined := "\n".join(texts)
	ctx.contains(joined, "合成工程开始", "播放到第 1 行台词（含内联标记）")
	ctx.contains(joined, "第一句台词", "播放到第 2 行台词")
	ctx.contains(joined, "第二句台词", "播放到第 3 行台词")
	ctx.contains(joined, "你向右走了", "选择 0 后进入对应分支")
	# `_collected_texts` 是原始剧本文本（含标记，给调试/统计用）；对话框显示层应转成 BBCode。
	# 这里检查 dialogue_box 的 RichTextLabel 实际渲染文本。
	var dialogue_box: Variant = player.get("dialogue")
	ctx.not_null(dialogue_box, "player.dialogue 存在")
	if dialogue_box != null:
		var label: Variant = dialogue_box.get("text_label")
		ctx.not_null(label, "dialogue.text_label 存在")
		if label != null:
			var rendered: String = label.get_parsed_text()
			ctx.not_contains(rendered, "[size=200]", "对话框渲染文本不残留 AA [size] 标记")
			ctx.not_contains(rendered, "[FF0000]", "对话框渲染文本不残留 AA 颜色标记")

	# 结束后不应崩：再点几下也无异常
	player.advance()
	player.choose(0)
	await ctx.advance_frames(2)
	ctx.is_true(player.is_finished(), "结束后重复输入仍安全（保持 finished）")

	# ---------------------------------------------------------------- 3. debug_run_to_finish（快速通道）
	var player2: Variant = scene.instantiate()
	ctx.root_node().add_child(player2)
	await ctx.advance_frames(1)
	var finished2 := [0]
	player2.finished.connect(func() -> void: finished2[0] += 1)
	player2.setup_from_path(SMOKE)
	player2.play()
	var result: Dictionary = player2.debug_run_to_finish(6000, 0)
	ctx.is_true(bool(result.get("finished", false)), "debug_run_to_finish finished == true")
	ctx.gte(int(result.get("choices", 0)), 1, "debug_run_to_finish 经过 %d 次选择" % int(result.get("choices", 0)))
	ctx.gte(int(result.get("lines", 0)), 4, "debug_run_to_finish 播放行数 >= 4（实际 %d）" % int(result.get("lines", 0)))
	var texts2: Array = result.get("texts", [])
	ctx.gt(texts2.size(), 0, "debug_run_to_finish 返回 texts")
	if texts2.size() > 0:
		ctx.contains("\n".join(texts2), "你向右走了", "debug_run_to_finish 文本含分支台词")
	var reason := String(result.get("reason", ""))
	ctx.is_true(not reason.is_empty(), "debug_run_to_finish 有结束原因：%s" % reason)
	ctx.eq(finished2[0], 1, "debug_run_to_finish 也触发 finished 信号")

	# ---------------------------------------------------------------- 4. setup(AapProject) 入口
	var project := AapProject.load_from_file(SMOKE)
	ctx.not_null(project, "AapProject 载入合成工程（给 setup 用）")
	var player3: Variant = scene.instantiate()
	ctx.root_node().add_child(player3)
	await ctx.advance_frames(1)
	player3.set_instant_mode(true)
	player3.setup(project)
	player3.play()
	var result3: Dictionary = player3.debug_run_to_finish(6000, 0)
	ctx.is_true(bool(result3.get("finished", false)), "setup(AapProject) 后也能跑到结局")
	ctx.gte(int(result3.get("lines", 0)), 4, "setup(AapProject) 播放行数 >= 4")

	# ---------------------------------------------------------------- 5. 坏路径不崩
	var player4: Variant = scene.instantiate()
	ctx.root_node().add_child(player4)
	await ctx.advance_frames(1)
	player4.setup_from_path("res://fixtures/不存在的工程.aap")
	player4.play()
	await ctx.advance_frames(2)
	ctx.is_false(player4.is_finished(), "坏路径不会假装播放完成")
	ctx.is_false(player4.is_waiting_choice(), "坏路径不会卡在选择")

	# ---------------------------------------------------------------- 清理
	player.queue_free()
	player2.queue_free()
	player3.queue_free()
	player4.queue_free()
	await ctx.advance_frames(2)
	_restore(ar, original_root)
	_rmtree(TMP_ROOT)


func _restore(ar: Node, original_root: String) -> void:
	if ar != null and not original_root.is_empty():
		ar.set_data_root(original_root)


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
