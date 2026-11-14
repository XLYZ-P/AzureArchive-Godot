class_name AaInterpreter
extends RefCounted
## 剧情解释器：逐行执行 PlayData（AaAapMock 或 aa_core PlayScript 归一化后的数据）。
## 不直接操作 UI/音频，只发信号；AaPlayer 负责把行落实到舞台/对话框/音频。
##
## 状态机：
##   行(有台词)  -> WAIT_CLICK   （点击/advance 推进）
##   行(无台词)  -> WAIT_TIMER   （#wait 毫秒 / 气泡动作默认等待）
##   选择节点    -> CHOICE       （choose(index) 后跳转）
##   出口节点    -> EXIT         （发 exit_reached + finished）
## 若单元没有台词也没有等待（纯环境行），会连续自动推进到下一行/下一单元。

signal line_started(line: Dictionary, index: int)
signal choice_requested(texts: Array)
signal exit_reached(unit: Dictionary)
signal finished(reason: String)

enum State { IDLE, WAIT_CLICK, WAIT_TIMER, CHOICE, DONE }

const DEFAULT_EMOTICON_WAIT := 2.5
const DEFAULT_ACTION_WAIT := 1.5
const EMPTY_LINE_WAIT := 0.25
const MAX_EMPTY_ADVANCE := 5000

var data: Dictionary = {}
var instant_mode := false

var cur_guid := ""
var cur_index := -1
var cur_line: Dictionary = {}
var state: int = State.IDLE
var wait_left := 0.0
var wait_total := 0.0
var visited_lines := 0
var choice_count := 0
var finish_reason := ""

var _unit: Dictionary = {}
var _finished := false
var _advance_guard := 0


func configure(play_data: Dictionary) -> void:
	data = play_data
	cur_guid = ""
	cur_index = -1
	cur_line = {}
	state = State.IDLE
	wait_left = 0.0
	wait_total = 0.0
	visited_lines = 0
	choice_count = 0
	finish_reason = ""
	_unit = {}
	_finished = false
	_advance_guard = 0


func start() -> void:
	_finished = false
	var start_guid := str(data.get("start_guid", ""))
	if start_guid.is_empty():
		_finish("empty_script")
		return
	_begin_unit(start_guid)


func jump_to(guid: String) -> void:
	if guid.is_empty():
		return
	_finished = false
	_begin_unit(guid)


func current_line() -> Dictionary:
	return cur_line


func current_guid() -> String:
	return cur_guid


func current_index() -> int:
	return cur_index


func is_done() -> bool:
	return state == State.DONE


func is_waiting_click() -> bool:
	return state == State.WAIT_CLICK


func is_waiting_timer() -> bool:
	return state == State.WAIT_TIMER


func is_waiting_choice() -> bool:
	return state == State.CHOICE


func state_name() -> String:
	match state:
		State.IDLE:
			return "idle"
		State.WAIT_CLICK:
			return "wait_click"
		State.WAIT_TIMER:
			return "wait_timer"
		State.CHOICE:
			return "choice"
		State.DONE:
			return "done"
	return "?"


## 用户点击/空格的统一入口。返回是否消费了这次推进。
func request_advance() -> bool:
	match state:
		State.WAIT_CLICK:
			_next_line()
			return true
		State.WAIT_TIMER:
			wait_left = 0.0
			_next_line()
			return true
	return false


func choose(index: int) -> bool:
	if state != State.CHOICE:
		return false
	var conns: Array = _unit.get("connections", [])
	if index < 0 or index >= conns.size():
		return false
	choice_count += 1
	state = State.IDLE
	var target := str(conns[index])
	if target.is_empty():
		_finish("empty_connection")
	else:
		_begin_unit(target)
	return true


## 每帧驱动（只处理计时等待类行）
func tick(delta: float) -> void:
	if state != State.WAIT_TIMER:
		return
	wait_left -= delta
	if wait_left <= 0.0:
		_next_line()


# ---------------------------------------------------------------- 内部

func _begin_unit(guid: String) -> void:
	_advance_guard = 0
	cur_guid = guid
	_unit = {}
	while true:
		var units: Dictionary = data.get("units", {})
		if not units.has(guid):
			_finish("missing_node")
			return
		_unit = units[guid]
		cur_guid = guid
		var kind := int(_unit.get("kind", AaAapMock.KIND_SCRIPT))
		if kind == AaAapMock.KIND_EXIT:
			state = State.DONE
			exit_reached.emit(_unit)
			_finish(_exit_reason())
			return
		if kind == AaAapMock.KIND_CHOICE:
			var conns: Array = _unit.get("connections", [])
			var texts: Array = _unit.get("selection_texts", [])
			var shown: Array = []
			for i in conns.size():
				if i < texts.size() and not str(texts[i]).strip_edges().is_empty():
					shown.append(str(texts[i]))
				else:
					shown.append("选项 %d" % (i + 1))
			if shown.is_empty():
				# 没有连线的选择节点：直接结束
				_finish("empty_choice")
				return
			state = State.CHOICE
			choice_requested.emit(shown)
			return
		# 脚本节点
		var lines: Array = _unit.get("lines", [])
		cur_index = -1
		if lines.is_empty():
			# 空节点：沿第一条出边继续
			_advance_guard += 1
			if _advance_guard > MAX_EMPTY_ADVANCE:
				_finish("loop_detected")
				return
			var out: Array = _unit.get("connections", [])
			if out.is_empty():
				_finish("empty_node")
				return
			guid = str(out[0])
			continue
		cur_index = 0
		_begin_line(0)
		return


func _begin_line(index: int) -> void:
	var lines: Array = _unit.get("lines", [])
	if index < 0 or index >= lines.size():
		_finish_unit()
		return
	cur_index = index
	cur_line = lines[index]
	visited_lines += 1
	var text := str(cur_line.get("text", ""))
	var commands: Array = cur_line.get("commands", [])
	var has_screen_text := AaText.has_command(commands, "st") or AaText.has_command(commands, "stm")
	var wait_sec := _line_wait(cur_line)
	var has_text := text.strip_edges() != ""
	if has_text:
		# 有台词（对话或屏幕文字）：等点击推进（instant_mode 只影响打字机速度）
		state = State.WAIT_CLICK
	elif wait_sec > 0.0 and not instant_mode:
		state = State.WAIT_TIMER
		wait_total = wait_sec
		wait_left = wait_sec
	else:
		state = State.IDLE
	line_started.emit(cur_line, index)
	if state == State.IDLE:
		# 没有可等待内容：立即推进（用计数保护，避免无限递归）
		_advance_guard += 1
		if _advance_guard > MAX_EMPTY_ADVANCE:
			_finish("loop_detected")
			return
		_next_line()


func _next_line() -> void:
	wait_left = 0.0
	var lines: Array = _unit.get("lines", [])
	if cur_index + 1 < lines.size():
		_begin_line(cur_index + 1)
	else:
		_finish_unit()


func _finish_unit() -> void:
	var out: Array = _unit.get("connections", [])
	state = State.IDLE
	if out.is_empty():
		_finish("no_connection")
		return
	if out.size() > 1:
		# 非选择节点有多条出边：AA 的编辑器语义里会取第一条（选择节点才有分支）
		pass
	_begin_unit(str(out[0]))


func _line_wait(line: Dictionary) -> float:
	# core 的 AaScriptLine.effective_wait_ms()：气泡 2500 / 位移·进出场·动作 1500 / #wait 覆盖
	if line.has("wait_ms"):
		return maxf(float(int(line["wait_ms"])) / 1000.0, 0.0)
	var commands: Array = line.get("commands", [])
	var wait_cmd := AaText.find_command(commands, "wait")
	if not wait_cmd.is_empty():
		var args: Array = wait_cmd.get("args", [])
		if args.size() > 0 and str(args[0]).is_valid_int():
			return maxf(float(int(args[0])) / 1000.0, 0.0)
	# AA 自动等待规则（docs/spec/aap.md）：
	#   气泡 -> 2500ms；位移/进出场/动作 -> 1500ms；作者 #wait 覆盖（不叠加），已在上面处理。
	var has_emoticon := false
	var has_move_or_action := false
	var records: Array = line.get("characters", [])
	for r in records:
		if not (r is Dictionary):
			continue
		if int(r.get("emoticon", -1)) >= 0:
			has_emoticon = true
		if int(r.get("action", 0)) > 0:
			has_move_or_action = true
		if int(r.get("starting_pos", 0)) != int(r.get("ending_pos", 0)) and not str(r.get("name", "")).is_empty():
			has_move_or_action = true
		if int(r.get("appear", 0)) != 0 and not str(r.get("name", "")).is_empty():
			has_move_or_action = true
	if has_emoticon:
		return DEFAULT_EMOTICON_WAIT
	if has_move_or_action:
		return DEFAULT_ACTION_WAIT
	return 0.0


func _exit_reason() -> String:
	if bool(_unit.get("is_ending", false)):
		return "ending"
	var ne_title := str(_unit.get("ne_title", ""))
	var ne_header := str(_unit.get("ne_header", ""))
	if not ne_title.is_empty() or not ne_header.is_empty():
		return "to_be_continued"
	return "exit"


func _finish(reason: String) -> void:
	if _finished:
		return
	_finished = true
	state = State.DONE
	finish_reason = reason
	finished.emit(reason)
