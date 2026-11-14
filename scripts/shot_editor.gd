extends SceneTree
## 编辑器截图（Lead 验收用，需要 xvfb + opengl3）
## 用法：xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path . --rendering-driver opengl3 \
##   --script scripts/shot_editor.gd -- --project=res://fixtures/aap/sample_kei_01.aap --out=/tmp/e.png

func _initialize() -> void:
	var args := _parse_args()
	var project: String = args.get("project", "res://fixtures/aap/sample_kei_01.aap")
	var out: String = args.get("out", "/tmp/editor.png")
	var e = load("res://scenes/editor/Editor.tscn").instantiate()
	get_root().add_child(e)
	await process_frame
	if e.has_method("open_project_file"):
		e.open_project_file(project)
	else:
		e.call("open", null, project)
	for i in 10:
		await process_frame
	# 可选：聚焦到某个节点 + 提高缩放，便于演示截图
	var focus: String = args.get("focus", "")
	var zoom := float(args.get("zoom", "0"))
	if e.has_method("get_project") and e.has_method("get_graph"):
		var proj = e.get_project()
		if proj != null and proj.nodes.size() > 0:
			var target = null
			if focus != "":
				target = proj.find_node(focus)
			if target == null:
				for n in proj.nodes:
					if int(n.node_type) == 1:
						target = n
						break
			var g = e.get_graph()
			if g != null:
				if zoom > 0.0:
					g.zoom = zoom
				if target != null:
					g.focus_guid(target.guid)
					if e.has_method("get_inspector"):
						e.get_inspector().show_node(proj, target)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_root().get_texture().get_image()
	if img == null or img.is_empty():
		printerr("截图失败：空图像")
		quit(1)
		return
	img.save_png(out)
	print("[shot_editor] saved ", out, " size=", img.get_size())
	quit(0)

func _parse_args() -> Dictionary:
	var d := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			d[kv[0]] = kv[1]
	return d
