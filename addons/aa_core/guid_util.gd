class_name AaGuid
extends RefCounted
## UUID / Guid 辅助（AA 的 Guid 是小写 36 字符 `D` 格式）。
##
## 单独成文件是为了避免 `aap_node.gd` 与 `script_line.gd` 互相 class_name 引用。

const ZERO := "00000000-0000-0000-0000-000000000000"


## 生成小写 UUID v4，如 `b292a9b5-dd77-435e-b675-29b1b8ad0e92`。
static func new_uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0F) | 0x40  # version 4
	bytes[8] = (bytes[8] & 0x3F) | 0x80  # variant
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)
	]


## 是否全 0 Guid（AA 的入口节点专用）。
static func is_zero(guid: String) -> bool:
	if guid.is_empty():
		return true
	for ch in guid:
		if ch != "0" and ch != "-":
			return false
	return true


## 是否形如 `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`（只做格式校验，不保证 v4）。
static func is_valid(guid: String) -> bool:
	if guid.length() != 36:
		return false
	for i in 36:
		var c := guid.unicode_at(i)
		if i == 8 or i == 13 or i == 18 or i == 23:
			if c != 0x2D:  # '-'
				return false
			continue
		var is_hex := (c >= 0x30 and c <= 0x39) or (c >= 0x41 and c <= 0x46) or (c >= 0x61 and c <= 0x66)
		if not is_hex:
			return false
	return true
