extends SceneTree
## 播放器截图（Lead 验收用，需要 xvfb + opengl3，不能 --headless）
## 用法：xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path . --rendering-driver opengl3 \
##   --script scripts/shot_player.gd -- --project=res://fixtures/aap/sample_kei_01.aap --out=/tmp/p.png --advance=6

func _initialize() -> void:
	var args := _parse_args()
	var project: String = args.get("project", "res://fixtures/aap/sample_kei_01.aap")
	var out: String = args.get("out", "/tmp/player.png")
	var advance := int(args.get("advance", "6"))
	var p = load("res://scenes/player/Player.tscn").instantiate()
	get_root().add_child(p)
	await process_frame
	p.setup_from_path(project)
	p.play()
	for i in max(1, advance):
		p.advance()
		for f in 3:
			await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	_save(out)
	quit(0)

func _parse_args() -> Dictionary:
	var d := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			d[kv[0]] = kv[1]
	return d

func _save(out: String) -> void:
	var img: Image = get_root().get_texture().get_image()
	if img == null or img.is_empty():
		printerr("截图失败：空图像")
		return
	img.save_png(out)
	print("[shot_player] saved ", out, " size=", img.get_size())
