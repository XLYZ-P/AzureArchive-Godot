class_name AaAapMock
extends RefCounted
## 不依赖 aa_core 的 .aap 解析 / 线性化编译器（Mock 数据源 + core 未就绪时的兜底）。
##
## 产出统一的 PlayData 字典，供 AaInterpreter / AaPlayer 直接执行：
## {
##   "project_name": String, "header": String, "title": String, "preview_bg_name": int,
##   "start_guid": String,
##   "units": { guid: {
##       "guid": String, "kind": int,          # KIND_SCRIPT / KIND_CHOICE / KIND_EXIT
##       "lines": Array[Dictionary],           # 行结构见 normalize_line()
##       "connections": Array[String],
##       "selection_texts": Array[String],
##       "is_ending": bool, "end_text": String, "ne_header": String, "ne_title": String,
##       "ne_script": Dictionary|null,
##   } }
## }
## 行（线）结构字段名与 DESIGN §4 的 ScriptData 一一对应（snake_case）：
##   text, popup, bg_effect, bg_name, bg_friendly_name, sound, voice, transition,
##   bgm_id, selection_group, additional_prompt, characters, speaker_slot,
##   highlighted_slots, is_dialog, place_text；另加解析缓存 commands。

const KIND_SCRIPT := 0
const KIND_CHOICE := 1
const KIND_EXIT := 2
const KIND_ENTRY := 3

const T_ENTRY := "EntryNodeData"
const T_SCRIPT := "ScriptNodeData"
const T_CHOICE := "SelectionNodeData"
const T_EXIT := "ExitNodeData"


static func from_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := AaRawLoader.read_text(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		push_warning("AaAapMock: 无法解析 .aap: " + path)
		return {}
	return from_dict(parsed)


static func from_dict(d: Dictionary) -> Dictionary:
	var data := {
		"project_name": str(d.get("ProjectName", "")),
		"header": str(d.get("PreviewHeader", "") if d.get("PreviewHeader") != null else ""),
		"title": str(d.get("PreviewTitle", "") if d.get("PreviewTitle") != null else ""),
		"preview_bg_name": int(d.get("PreviewBgName", 0)),
		"start_guid": "",
		"units": {},
	}
	var nodes: Array = _values(d.get("nodes", []))
	var entry_guid := ""
	var first_script_guid := ""
	for raw in nodes:
		if not (raw is Dictionary):
			continue
		var node: Dictionary = raw
		var kind := node_kind(str(node.get("$type", "")))
		var guid := str(node.get("Guid", ""))
		var conns := _guid_array(node.get("ConnectionsTo", []))
		match kind:
			KIND_ENTRY:
				entry_guid = guid
				if data["start_guid"] == "" and conns.size() > 0:
					data["start_guid"] = conns[0]
				elif data["start_guid"] == "":
					data["start_guid"] = "ENTRY"
			KIND_SCRIPT:
				if first_script_guid == "":
					first_script_guid = guid
				var lines: Array = []
				for s in _values(node.get("Scripts", [])):
					if s is Dictionary:
						lines.append(normalize_line(s))
				data["units"][guid] = {
					"guid": guid, "kind": KIND_SCRIPT, "lines": lines, "connections": conns,
					"selection_texts": [], "is_ending": false, "end_text": "",
					"ne_header": "", "ne_title": "", "ne_script": null,
				}
			KIND_CHOICE:
				var texts: Array = []
				for t in _values(node.get("selectionTexts", [])):
					texts.append(str(t))
				data["units"][guid] = {
					"guid": guid, "kind": KIND_CHOICE, "lines": [], "connections": conns,
					"selection_texts": texts, "is_ending": false, "end_text": "",
					"ne_header": "", "ne_title": "", "ne_script": null,
				}
			KIND_EXIT:
				var ne_script: Variant = null
				var ne_raw: Variant = node.get("NeScriptDirty", null)
				if ne_raw is Dictionary:
					ne_script = normalize_line(ne_raw)
				data["units"][guid] = {
					"guid": guid, "kind": KIND_EXIT, "lines": [], "connections": conns,
					"selection_texts": [], "is_ending": bool(node.get("IsEnding", false)),
					"end_text": str(node.get("EndText", "")),
					"ne_header": str(node.get("NeHeader", "")),
					"ne_title": str(node.get("NeTitle", "")),
					"ne_script": ne_script,
				}
	if data["start_guid"] == "" or data["start_guid"] == "ENTRY":
		data["start_guid"] = first_script_guid
	if data["start_guid"] == "" and data["units"].size() > 0:
		data["start_guid"] = data["units"].keys()[0]
	return data


static func node_kind(type_str: String) -> int:
	if type_str.begins_with(T_ENTRY):
		return KIND_ENTRY
	if type_str.begins_with(T_SCRIPT):
		return KIND_SCRIPT
	if type_str.begins_with(T_CHOICE):
		return KIND_CHOICE
	if type_str.begins_with(T_EXIT):
		return KIND_EXIT
	return -1


static func normalize_line(d: Dictionary) -> Dictionary:
	var chars: Array = []
	var recs := _values(d.get("characters", []))
	for i in 6:
		if i < recs.size() and recs[i] is Dictionary:
			chars.append(normalize_record(recs[i]))
		else:
			chars.append(empty_record())
	var hls: Array = []
	for n in _values(d.get("highlightedSlotNums", [])):
		hls.append(int(n))
	var prompt := str(d.get("additionalPrompt", "") if d.get("additionalPrompt") != null else "")
	var popup_raw: Variant = d.get("popup", null)
	return {
		"text": str(d.get("text", "") if d.get("text") != null else ""),
		"popup": "" if popup_raw == null else str(popup_raw),
		"bg_effect": int(d.get("bgEffect", 0)),
		"bg_name": int(d.get("bgName", 0)),
		"bg_friendly_name": str(d.get("bgFriendlyName", "") if d.get("bgFriendlyName") != null else ""),
		"sound": str(d.get("sound", "") if d.get("sound") != null else ""),
		"voice": str(d.get("voice", "") if d.get("voice") != null else ""),
		"transition": int(d.get("transition", 0)),
		"bgm_id": int(d.get("bgmId", 0)),
		"selection_group": int(d.get("selectionGroup", 0)),
		"additional_prompt": prompt,
		"characters": chars,
		"speaker_slot": clampi(int(d.get("speakerSlotNum", 0)), 0, 5),
		"highlighted_slots": hls,
		"is_dialog": bool(d.get("isDialogScript", true)),
		"place_text": str(d.get("placeText", "") if d.get("placeText") != null else ""),
		"commands": AaText.parse_extra(prompt),
	}


static func normalize_record(d: Dictionary) -> Dictionary:
	return {
		"name": str(d.get("name", "") if d.get("name") != null else ""),
		"face_id": str(d.get("faceId", "00") if d.get("faceId") != null else "00"),
		"starting_pos": int(d.get("startingPos", 0)),
		"ending_pos": int(d.get("endingPos", 0)),
		"emoticon": int(d.get("emoticon", -1)),
		"action": int(d.get("action", 0)),
		"effect": int(d.get("effect", 0)),
		"appear": int(d.get("appear", 0)),
		"shape_override": int(d.get("shapeOverride", 0)),
	}


static func empty_record() -> Dictionary:
	return {
		"name": "", "face_id": "00", "starting_pos": 0, "ending_pos": 0,
		"emoticon": -1, "action": 0, "effect": 0, "appear": 0, "shape_override": 0,
	}


static func _values(v: Variant) -> Array:
	if v is Array:
		return v
	if v is PackedStringArray or v is PackedInt32Array or v is PackedInt64Array or v is PackedFloat32Array:
		var out: Array = []
		for item in v:
			out.append(item)
		return out
	if v is Dictionary:
		var d: Dictionary = v
		if d.has("$values") and d["$values"] is Array:
			return d["$values"]
	return []


static func _guid_array(v: Variant) -> Array:
	var out: Array = []
	for g in _values(v):
		out.append(str(g))
	return out


## 兜底：把 aa_core 的 PlayScript / AapProject（或任何同构对象）转为 PlayData。
## 用反射读属性名，兼容 core-dev 的字段命名微调；识别失败返回 {}（播放器会退化到占位演示）。
static func from_core_project(project: Variant) -> Dictionary:
	if project == null:
		return {}
	if project is Dictionary:
		var pd: Dictionary = project
		if pd.has("units") and pd.has("start_guid"):
			return pd
		if pd.has("nodes"):
			return from_dict(pd)
		return {}
	# 有 compile() 就用编译结果，否则尝试直接把 nodes 当 AapProject 读
	if project.has_method("compile"):
		var compiled: Variant = project.call("compile")
		var data := from_play_script(compiled)
		if not data.is_empty():
			return data
	# 直接 duck-type 读 AapProject
	if project.has_method("get_entry") or _props(project).has("nodes"):
		return _from_project_object(project)
	return {}


static func from_play_script(ps: Variant) -> Dictionary:
	if ps == null:
		return {}
	var props := _props(ps)
	if not props.has("nodes"):
		return {}
	var start := ""
	for key in ["start_guid", "startGuid", "entry_guid", "entry"]:
		if props.has(key):
			start = str(props[key])
			break
	var raw_nodes: Variant = props.get("nodes", {})
	var units := {}
	if raw_nodes is Dictionary:
		for guid in raw_nodes.keys():
			var node: Variant = raw_nodes[guid]
			var unit := _from_play_node(str(guid), node)
			if not unit.is_empty():
				units[str(guid)] = unit
	elif raw_nodes is Array:
		for node in raw_nodes:
			var np := _props(node)
			var g := ""
			for key in ["guid", "id", "node_guid"]:
				if np.has(key):
					g = str(np[key])
					break
			var unit := _from_play_node(g, node)
			if not unit.is_empty():
				units[g] = unit
	if start.is_empty() and units.size() > 0:
		start = str(units.keys()[0])
	return {
		"project_name": str(props.get("project_name", props.get("ProjectName", ""))),
		"header": "", "title": "", "preview_bg_name": 0,
		"start_guid": start, "units": units,
	}


static func _from_play_node(guid: String, node: Variant) -> Dictionary:
	var np := _props(node)
	if np.is_empty():
		return {}
	# aa_core PlayNode：KIND_ENTRY=0(entry)/1(script)/2(choice)/3(exit)，兼容字段 kind_name 更稳
	var kind := KIND_SCRIPT
	var kind_name := str(np.get("kind_name", ""))
	match kind_name:
		"entry", "script":
			kind = KIND_SCRIPT
		"choice":
			kind = KIND_CHOICE
		"exit":
			kind = KIND_EXIT
		_:
			kind = clampi(int(np.get("kind", 1)) - 1, 0, 2)
	var conns: Array = []
	var texts: Array = []
	# 选择节点优先读 options（带 valid / target_guid）
	if kind == KIND_CHOICE and np.get("options") is Array:
		for opt in np.get("options"):
			var op := _props(opt)
			var text := str(op.get("text", ""))
			var target := str(op.get("target_guid", ""))
			texts.append(text)
			conns.append(target)
	else:
		for c in _values(np.get("connections", [])):
			conns.append(str(c))
		for t in _values(np.get("selection_texts", [])):
			texts.append(str(t))
	if kind == KIND_SCRIPT:
		var next_guid := str(np.get("next_guid", ""))
		if not next_guid.is_empty():
			if conns.is_empty():
				conns.append(next_guid)
			elif conns.size() == 1 and str(conns[0]).is_empty():
				conns[0] = next_guid
	var lines: Array = []
	if kind == KIND_SCRIPT:
		for s in _values(np.get("lines", [])):
			lines.append(_normalize_any_line(s))
	var ne_script: Variant = null
	var ne_raw: Variant = np.get("ne_script", np.get("ne_line", null))
	if ne_raw != null:
		ne_script = _normalize_any_line(ne_raw)
	return {
		"guid": guid, "kind": kind, "lines": lines, "connections": conns,
		"selection_texts": texts,
		"is_ending": bool(np.get("is_ending", false)),
		"end_text": str(np.get("end_text", "")),
		"ne_header": str(np.get("ne_header", "")),
		"ne_title": str(np.get("ne_title", "")),
		"ne_script": ne_script,
	}


## 把 aa_core 的 AaScriptLine / Dictionary 行统一成 snake_case 行字典。
static func _normalize_any_line(line: Variant) -> Dictionary:
	if line is Dictionary:
		var d: Dictionary = line
		if d.has("commands") and d.has("characters") and d.has("is_dialog"):
			return d
		if d.has("$type") or d.has("bgFriendlyName") or d.has("additionalPrompt"):
			return normalize_line(d)
		return normalize_line(d)
	var p := _props(line)
	if p.is_empty():
		return normalize_line({})
	var raw := {
		"text": _first(p, ["text"], ""),
		"popup": _first(p, ["popup"], ""),
		"bgEffect": _first(p, ["bg_effect", "bgEffect"], 0),
		"bgName": _first(p, ["bg_name", "bgName"], 0),
		"bgFriendlyName": _first(p, ["bg_friendly_name", "bgFriendlyName"], ""),
		"sound": _first(p, ["sound", "se"], ""),
		"voice": _first(p, ["voice"], ""),
		"transition": _first(p, ["transition"], 0),
		"bgmId": _first(p, ["bgm_id", "bgmId"], 0),
		"selectionGroup": _first(p, ["selection_group", "selectionGroup"], 0),
		"additionalPrompt": _first(p, ["additional_prompt", "additionalPrompt"], ""),
		"speakerSlotNum": _first(p, ["speaker_slot", "speaker_slot_num", "speakerSlotNum"], 0),
		"highlightedSlotNums": _first(p, ["highlighted_slots", "highlighted_slot_nums", "highlightedSlotNums"], []),
		"isDialogScript": _first(p, ["is_dialog", "is_dialog_script", "isDialogScript"], true),
		"placeText": _first(p, ["place_text", "placeText"], ""),
	}
	var chars: Array = []
	var c_raw: Variant = _first(p, ["characters"], [])
	for c in (c_raw if c_raw is Array else []):
		var cp: Dictionary = c if c is Dictionary else _props(c)
		if cp.is_empty():
			chars.append(empty_record())
			continue
		chars.append({
			"name": str(_first(cp, ["name"], "")),
			"faceId": str(_first(cp, ["face_id", "faceId"], "00")),
			"startingPos": int(_first(cp, ["starting_pos", "startingPos"], 0)),
			"endingPos": int(_first(cp, ["ending_pos", "endingPos"], 0)),
			"emoticon": int(_first(cp, ["emoticon"], -1)),
			"action": int(_first(cp, ["action"], 0)),
			"effect": int(_first(cp, ["effect"], 0)),
			"appear": int(_first(cp, ["appear"], 0)),
			"shapeOverride": int(_first(cp, ["shape_override", "shapeOverride"], 0)),
		})
	while chars.size() < 6:
		chars.append(empty_record())
	raw["characters"] = chars
	var line_dict := normalize_line(raw)
	# core 的 AaScriptLine 有现成 get_commands()/effective_wait_ms()，优先使用避免两套规则
	if line is Object:
		if line.has_method("get_commands"):
			var cmd_dicts: Array = []
			for c in line.call("get_commands"):
				cmd_dicts.append(_core_command_to_dict(c))
			if not cmd_dicts.is_empty():
				line_dict["commands"] = cmd_dicts
		if line.has_method("effective_wait_ms"):
			line_dict["wait_ms"] = int(line.call("effective_wait_ms"))
	return line_dict


static func _core_command_to_dict(c: Variant) -> Dictionary:
	var cp := _props(c)
	if cp.is_empty() and c is Dictionary:
		cp = c
	return {
		"name": str(cp.get("name", "")),
		"args": cp.get("args", []) if cp.get("args", []) is Array else [],
		"raw": str(cp.get("raw", "")),
		"slot": int(cp.get("slot", -1)),
		"fx": str(cp.get("fx", "")).replace("{", "").replace("}", ""),
	}


## 反射读对象的所有属性到字典（Object 属性 + Dictionary 直读）。
static func _props(obj: Variant) -> Dictionary:
	if obj == null:
		return {}
	if obj is Dictionary:
		return obj
	var out := {}
	if obj is Object:
		for pd in obj.get_property_list():
			var name := str(pd.get("name", ""))
			if name.is_empty() or name.begins_with("_") or name == "script":
				continue
			if int(pd.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				var v: Variant = obj.get(name)
				if v != null:
					out[name] = v
	return out


static func _first(d: Dictionary, keys: Array, default: Variant) -> Variant:
	for k in keys:
		if d.has(k):
			return d[k]
	return default


static func _from_project_object(project: Variant) -> Dictionary:
	# 直接按 AapProject 契约（project_name / nodes / get_entry）读
	var props := _props(project)
	var pseudo := {"ProjectName": props.get("project_name", ""), "PreviewBgName": props.get("preview_bg_name", 0),
		"PreviewHeader": props.get("preview_header", null), "PreviewTitle": props.get("preview_title", null),
		"nodes": {"$values": []}}
	var raw_nodes: Variant = props.get("nodes", [])
	if raw_nodes is Array:
		for n in raw_nodes:
			var np := _props(n)
			if np.is_empty():
				continue
			pseudo["nodes"]["$values"].append(_node_object_to_dict(np))
	return from_dict(pseudo)


static func _node_object_to_dict(np: Dictionary) -> Dictionary:
	var kind := int(np.get("node_type", 0))
	var out := {"Guid": str(np.get("guid", "")), "X": 0.0, "Y": 0.0,
		"ConnectionsTo": {"$values": []}}
	for c in (np.get("connections", []) if np.get("connections", []) is Array else []):
		out["ConnectionsTo"]["$values"].append(str(c))
	match kind:
		0:
			out["$type"] = T_ENTRY
			out["Title"] = str(np.get("title", ""))
			out["Header"] = str(np.get("header", ""))
		1:
			out["$type"] = T_SCRIPT
			out["NodeName"] = str(np.get("node_name", ""))
			var scripts: Array = []
			for s in (np.get("scripts", []) if np.get("scripts", []) is Array else []):
				scripts.append(_line_to_dict(s))
			out["Scripts"] = {"$values": scripts}
		2:
			out["$type"] = T_CHOICE
			var texts: Array = []
			for t in (np.get("selection_texts", []) if np.get("selection_texts", []) is PackedStringArray or np.get("selection_texts", []) is Array else []):
				texts.append(str(t))
			while texts.size() < 16:
				texts.append("")
			out["selectionTexts"] = {"$values": texts}
		3:
			out["$type"] = T_EXIT
			out["IsEnding"] = bool(np.get("is_ending", false))
			out["EndText"] = str(np.get("end_text", ""))
			out["NeHeader"] = str(np.get("ne_header", ""))
			out["NeTitle"] = str(np.get("ne_title", ""))
			if np.get("ne_script") != null:
				out["NeScriptDirty"] = _line_to_dict(np.get("ne_script"))
	return out


static func _line_to_dict(line: Variant) -> Dictionary:
	var p := _props(line)
	var chars: Array = []
	var c_raw: Variant = p.get("characters", [])
	for c in (c_raw if c_raw is Array else []):
		var cp := _props(c)
		chars.append({
			"$type": "ScriptData+CharacterRecordData, Assembly-CSharp",
			"name": str(cp.get("name", "")),
			"faceId": str(cp.get("face_id", cp.get("faceId", "00"))),
			"startingPos": int(cp.get("starting_pos", cp.get("startingPos", 0))),
			"endingPos": int(cp.get("ending_pos", cp.get("endingPos", 0))),
			"emoticon": int(cp.get("emoticon", -1)),
			"action": int(cp.get("action", 0)),
			"effect": int(cp.get("effect", 0)),
			"appear": int(cp.get("appear", 0)),
			"shapeOverride": int(cp.get("shape_override", cp.get("shapeOverride", 0))),
		})
	var hls: Array = []
	var hl_raw: Variant = p.get("highlighted_slots", p.get("highlighted_slot_nums", []))
	for n in (hl_raw if hl_raw is Array or hl_raw is PackedInt32Array else []):
		hls.append(int(n))
	return {
		"$type": "ScriptData, Assembly-CSharp",
		"text": str(p.get("text", "")),
		"popup": p.get("popup", ""),
		"bgEffect": int(p.get("bg_effect", 0)),
		"bgName": int(p.get("bg_name", 0)),
		"bgFriendlyName": str(p.get("bg_friendly_name", "")),
		"sound": str(p.get("sound", "")),
		"voice": str(p.get("voice", "")),
		"transition": int(p.get("transition", 0)),
		"bgmId": int(p.get("bgm_id", 0)),
		"selectionGroup": int(p.get("selection_group", 0)),
		"additionalPrompt": str(p.get("additional_prompt", "")),
		"characters": {"$type": "System.Collections.Generic.List`1[[ScriptData+CharacterRecordData, Assembly-CSharp]], mscorlib", "$values": chars},
		"speakerSlotNum": int(p.get("speaker_slot", 0)),
		"highlightedSlotNums": {"$type": "System.Collections.Generic.List`1[[System.Int32, mscorlib]], mscorlib", "$values": hls},
		"isDialogScript": bool(p.get("is_dialog", true)),
		"placeText": str(p.get("place_text", "")),
	}


## ---------- 合成演示数据（无 .aap 时预览播放器用） ----------

static func demo_data() -> Dictionary:
	var line_common := func(text: String, bg: String, bg_id: int) -> Dictionary:
		return {
			"text": text, "popup": "", "bg_effect": 0, "bg_name": bg_id,
			"bg_friendly_name": bg, "sound": "", "voice": "", "transition": 0,
			"bgm_id": 999, "selection_group": 0, "additional_prompt": "",
			"characters": _demo_chars(), "speaker_slot": 0,
			"highlighted_slots": [], "is_dialog": true, "place_text": "",
			"commands": [],
		}
	var l1: Dictionary = line_common.call("这是播放器的合成演示剧本。", "BG_Black", 1047754314)
	l1["place_text"] = "演示场景"
	l1["additional_prompt"] = "#wait;300"
	l1["commands"] = AaText.parse_extra("#wait;300")
	l1["characters"][1] = _demo_rec("01", "02", 1, 1, -1, 0, 3)
	l1["characters"][5] = _demo_rec("02", "03", 5, 5, -1, 0, 3)
	l1["speaker_slot"] = 1
	var l2: Dictionary = line_common.call("[size=90]内联标记[/size]：颜色 [ff6666]红色[-]、[ruby=zhuyin]注音[/ruby]", "BG_CS_Millenium_01", 1391744589)
	l2["transition"] = 4004024664
	l2["characters"] = l1["characters"].duplicate(true)
	l2["speaker_slot"] = 5
	l2["characters"][5] = _demo_rec("02", "04", 5, 5, 3, 6, 0)
	l2["bgm_id"] = 64
	var l3: Dictionary = line_common.call("", "BG_CS_Millenium_01", 1391744589)
	l3["additional_prompt"] = "#bgshake\n#wait;600"
	l3["commands"] = AaText.parse_extra("#bgshake\n#wait;600")
	l3["characters"] = l2["characters"].duplicate(true)
	var l4: Dictionary = line_common.call("背景震动、屏幕文字、走位演示。", "BG_CS_Millenium_01", 1391744589)
	l4["additional_prompt"] = "#stm;[0,-620];serial;64;"
	l4["commands"] = AaText.parse_extra("#stm;[0,-620];serial;64;")
	l4["characters"] = l3["characters"].duplicate(true)
	l4["characters"][1] = _demo_rec("01", "02", 1, 3, -1, 6, 0)
	var l5: Dictionary = line_common.call("选一个选项继续剧情吧。", "BG_CS_Millenium_01", 1391744589)
	l5["characters"] = l4["characters"].duplicate(true)
	l5["speaker_slot"] = 3
	l5["highlighted_slots"] = [1, 3]
	var choice_guid := "demo-choice"
	var end_guid := "demo-end"
	l5["characters"] = l4["characters"].duplicate(true)
	var scripts := {
		"demo-s0": _unit(KIND_SCRIPT, "demo-s0", [l1, l2, l3], ["demo-choice"]),
		"demo-s1": _unit(KIND_SCRIPT, "demo-s1", [l4], [choice_guid]),
		choice_guid: _unit(KIND_CHOICE, choice_guid, [], [end_guid, "demo-s1"],
			["继续（走到出口）", "再看一次走位"]),
		end_guid: {
			"guid": end_guid, "kind": KIND_EXIT, "lines": [], "connections": [],
			"selection_texts": [], "is_ending": true, "end_text": "演示剧本结束，感谢观看。",
			"ne_header": "", "ne_title": "", "ne_script": null,
		},
	}
	return {
		"project_name": "播放器合成演示", "header": "Demo", "title": "占位演出",
		"preview_bg_name": 0, "start_guid": "demo-s0", "units": scripts,
	}


static func _unit(kind: int, guid: String, lines: Array, conns: Array, texts: Array = []) -> Dictionary:
	return {
		"guid": guid, "kind": kind, "lines": lines, "connections": conns,
		"selection_texts": texts, "is_ending": false, "end_text": "",
		"ne_header": "", "ne_title": "", "ne_script": null,
	}


static func _demo_chars() -> Array:
	var arr: Array = []
	for i in 6:
		arr.append(empty_record())
	return arr


static func _demo_rec(id: String, face: String, start_p: int, end_p: int, emo: int, act: int, appear: int) -> Dictionary:
	return {
		"name": id, "face_id": face, "starting_pos": start_p, "ending_pos": end_p,
		"emoticon": emo, "action": act, "effect": 0, "appear": appear, "shape_override": 0,
	}
