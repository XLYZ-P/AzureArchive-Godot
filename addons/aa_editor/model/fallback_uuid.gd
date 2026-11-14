extends RefCounted
## GUID 小工具（fallback 模型用；core 就绪后走 core 的生成逻辑）
## AA 使用 System.Guid 的 "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" 小写形式。


static func random_guid() -> String:
	var bytes := PackedByteArray()
	bytes.resize(16)
	for i in 16:
		bytes[i] = randi() % 256
	return format_guid(bytes)


static func format_guid(bytes: PackedByteArray) -> String:
	var h := ""
	for b in bytes:
		h += "%02x" % b
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]


static func is_zero_guid(guid: String) -> bool:
	return guid.replace("-", "").strip_edges() == "00000000000000000000000000000000"
