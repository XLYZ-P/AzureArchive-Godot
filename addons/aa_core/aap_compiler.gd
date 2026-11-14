class_name AapCompiler
extends RefCounted
## 节点图 -> PlayScript 编译器（`AapProject.compile()` 内部实现）。
##
## 负责：
## 1. 把 ScriptNodeData 的 `scripts` 顺序合并成一条可执行行序列；
## 2. 建选项跳转表（SelectionNodeData 的 `ConnectionsTo[i]` ↔ `selectionTexts[i]`）；
## 3. 判定出口类型：Ending / To be continued / `#nextepisode;Header;Title`；
## 4. 收集坏连线、不可达节点等编译警告（不中断播放）。
##
## 编译**不做**任何会改变 `.aap` 数据的修复；坏数据只记录到 `warnings`。

## 编译期警告
var warnings: Array = []


func compile(project: AapProject) -> PlayScript:
	warnings = []
	var script := PlayScript.new()
	script.project = project
	if project == null:
		warnings.append("工程为空，无法编译")
		script.warnings = warnings.duplicate()
		return script
	script.project_name = project.project_name
	var entry := project.get_entry()
	if entry == null:
		warnings.append("缺少入口节点，退化为从第一个节点开始播放")
		if not project.nodes.is_empty() and project.nodes[0] is AapNode:
			entry = project.nodes[0]
	script.start_guid = entry.guid if entry != null else ""
	if entry != null:
		script.entry_title = entry.title
		script.entry_header = entry.header
	# 逐个节点铺平
	for node in project.nodes:
		if not (node is AapNode):
			continue
		if script.nodes.has(node.guid):
			warnings.append("Guid 重复，节点被忽略：" + node.guid)
			continue
		script.nodes[node.guid] = _build_play_node(project, node)
	# 不可达节点警告
	var reachable := _reachable_guids(project, script.start_guid)
	for node in project.nodes:
		if node is AapNode and not reachable.has(node.guid) and node.node_type != AapProject.NODE_UNKNOWN:
			warnings.append("节点不可达（没有从入口连过来）：%s" % _node_label(node))
	script.warnings = warnings.duplicate()
	return script


func _build_play_node(project: AapProject, node: AapNode) -> PlayNode:
	var play := PlayNode.make(_kind_of(node), node.guid)
	play.pos = node.pos
	match node.node_type:
		AapProject.NODE_ENTRY:
			play.next_guid = _first_target(project, node, "")
		AapProject.NODE_SCRIPT:
			play.lines = node.scripts.duplicate()
			play.next_guid = _first_target(project, node, "脚本节点「%s」" % node.node_name)
		AapProject.NODE_CHOICE:
			_build_choices(project, node, play)
		AapProject.NODE_EXIT:
			_build_exit(node, play)
		_:
			warnings.append("未知节点类型（$type=%s），按空节点处理" % node._unknown_type)
			play.kind = PlayNode.KIND_SCRIPT
			play.next_guid = _first_target(project, node, "")
	play.sync_compat()
	return play


func _kind_of(node: AapNode) -> int:
	match node.node_type:
		AapProject.NODE_ENTRY:
			return PlayNode.KIND_ENTRY
		AapProject.NODE_CHOICE:
			return PlayNode.KIND_CHOICE
		AapProject.NODE_EXIT:
			return PlayNode.KIND_EXIT
	return PlayNode.KIND_SCRIPT


## 取第一条有效出边；多条时告警（AA 的 Script 节点本来只有一条）。
func _first_target(project: AapProject, node: AapNode, label: String) -> String:
	if node.connections.is_empty():
		return ""
	if node.connections.size() > 1 and not label.is_empty():
		warnings.append("%s 有多条出边（只跟第一条）" % label)
	var target := node.connections[0]
	if project.find_node(target) == null:
		warnings.append("%s 的出边指向不存在的节点 %s" % [label if not label.is_empty() else "节点", target])
		return ""
	return target


func _build_choices(project: AapProject, node: AapNode, play: PlayNode) -> void:
	if node.connections.size() > AapNode.SELECTION_SLOT_COUNT:
		warnings.append("选择节点选项数 %d 超过 16" % node.connections.size())
	for i in node.connections.size():
		var option := PlayNode.Choice.new()
		option.index = i
		option.text = node.get_selection_text(i)
		option.target_guid = node.connections[i]
		option.valid = project.find_node(option.target_guid) != null
		if not option.valid:
			warnings.append("选择节点第 %d 个选项指向不存在的节点 %s" % [i + 1, option.target_guid])
		if option.text.is_empty():
			warnings.append("选择节点第 %d 个选项文本为空" % [i + 1])
		play.options.append(option)


func _build_exit(node: AapNode, play: PlayNode) -> void:
	play.ne_line = node.ne_script
	play.ne_text = node.ne_script.text if node.ne_script != null else ""
	play.end_text = node.end_text
	play.ne_header = node.ne_header
	play.ne_title = node.ne_title
	# ExitNodeData 的 NeScriptDirty.additionalPrompt 会被 AA 编译器写成
	# `#nextepisode;Header;Title`；这里也接受作者手写的情况，并覆盖 NeHeader/NeTitle。
	if node.ne_script != null:
		for cmd in node.ne_script.get_commands():
			if cmd.name == AaCommands.CMD_NEXT_EPISODE:
				var info := AaCommands.parse_next_episode(cmd)
				if not info["header"].is_empty():
					play.ne_header = info["header"]
				if not info["title"].is_empty():
					play.ne_title = info["title"]
	if node.is_ending:
		play.exit_type = PlayNode.EXIT_ENDING
	elif not play.ne_title.is_empty() or not play.ne_header.is_empty():
		play.exit_type = PlayNode.EXIT_NEXT_EPISODE
	else:
		play.exit_type = PlayNode.EXIT_TO_BE_CONTINUED


## 从入口做 BFS，返回可达 guid 集合。
func _reachable_guids(project: AapProject, start_guid: String) -> Dictionary:
	var seen := {}
	if start_guid.is_empty():
		return seen
	var queue: Array = [start_guid]
	while not queue.is_empty():
		var guid: String = queue.pop_front()
		if seen.has(guid):
			continue
		seen[guid] = true
		var node := project.find_node(guid)
		if node == null:
			continue
		for target in node.connections:
			if not seen.has(target):
				queue.append(target)
	return seen


func _node_label(node: AapNode) -> String:
	if node == null:
		return "null"
	if node.is_entry():
		return "入口节点"
	if node.is_script():
		return "脚本节点「%s」" % node.node_name
	if node.is_choice():
		return "选择节点"
	if node.is_exit():
		return "出口节点"
	return "节点"
