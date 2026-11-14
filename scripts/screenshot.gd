extends SceneTree
## 离屏截图（Lead 用）：Xvfb 下运行主场景并保存 PNG。
## 用法：xvfb-run -s "-screen 0 1280x720x24" scripts/godot.sh --script scripts/screenshot.gd -- --scene=res://scenes/main/Main.tscn --out=/tmp/shot.png
## 注意：需要真实渲染器，不能用 --headless。

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	var scene_path: String = args.get("scene", "res://scenes/main/Main.tscn")
	var out: String = args.get("out", "/tmp/shot.png")
	var wait_frames: int = int(args.get("frames", "20"))
	print("[screenshot] scene=", scene_path, " out=", out)
	var packed: PackedScene = load(scene_path)
	if packed == null:
		printerr("无法加载场景: ", scene_path)
		quit(1)
		return
	var root := packed.instantiate()
	root.name = "ShotRoot"
	get_root().add_child(root)
	for i in wait_frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_root().get_texture().get_image()
	if img == null or img.is_empty():
		printerr("截图失败：空图像")
		quit(1)
		return
	var err := img.save_png(out)
	print("[screenshot] save err=", err, " size=", img.get_size())
	quit(0 if err == OK else 1)
