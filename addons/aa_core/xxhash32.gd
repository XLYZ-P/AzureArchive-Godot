class_name AaHash
extends RefCounted
## xxHash32（seed = 0）实现，用于 AA 的 `bgName` / `PreviewBgName`。
##
## 背景：AA 里背景 ID 不是查表得到的，而是
## `bgName = xxHash32(utf8(bgFriendlyName), seed=0)`（无符号 32 位）。
## 因此新增自定义背景时不需要任何对照表，直接算即可。
##
## GDScript 的 int 是 64 位有符号，这里所有中间结果都手动截断到 32 位无符号，
## 乘法用 `_mul32` 拆分，避免两个 32 位操作数相乘溢出 64 位。
##
## 用法：
## [codeblock]
## var id := AaHash.bg_id("BG_RuinUndergroundPassage")  # -> 3558049603
## var raw := AaHash.xxh32("abc".to_utf8_buffer())      # -> 852579327
## [/codeblock]

const P1 := 2654435761  # 0x9E3779B1
const P2 := 2246822519  # 0x85EBCA77
const P3 := 3266489917  # 0xC2B2AE3D
const P4 := 668265263   # 0x27D4EB2F
const P5 := 374761393   # 0x165667B1
const MASK32 := 0xFFFFFFFF
## 空背景（bgFriendlyName == ""）对应的 ID，AA 规定为 0。
const EMPTY_BG_ID := 0


## 32 位无符号乘法：(a * b) mod 2^32，拆成 16 位避免 64 位溢出。
static func _mul32(a: int, b: int) -> int:
	var lo := a & 0xFFFF
	var hi := (a >> 16) & 0xFFFF
	return ((lo * b) + ((hi * b & 0xFFFF) << 16)) & MASK32


## 32 位循环左移。
static func _rotl32(x: int, r: int) -> int:
	return ((x << r) | (x >> (32 - r))) & MASK32


## 小端读取 32 位无符号整数。
static func _read_u32(data: PackedByteArray, offset: int) -> int:
	return data[offset] | (data[offset + 1] << 8) | (data[offset + 2] << 16) | (data[offset + 3] << 24)


## xxHash32 主实现。返回 0 .. 2^32-1 的无符号整数值。
static func xxh32(data: PackedByteArray, seed := 0) -> int:
	var length := data.size()
	var offset := 0
	var h: int
	if length >= 16:
		var v1 := (seed + P1 + P2) & MASK32
		var v2 := (seed + P2) & MASK32
		var v3 := seed & MASK32
		var v4 := (seed - P1) & MASK32
		while offset <= length - 16:
			v1 = _mul32(_rotl32((v1 + _mul32(_read_u32(data, offset), P2)) & MASK32, 13), P1)
			offset += 4
			v2 = _mul32(_rotl32((v2 + _mul32(_read_u32(data, offset), P2)) & MASK32, 13), P1)
			offset += 4
			v3 = _mul32(_rotl32((v3 + _mul32(_read_u32(data, offset), P2)) & MASK32, 13), P1)
			offset += 4
			v4 = _mul32(_rotl32((v4 + _mul32(_read_u32(data, offset), P2)) & MASK32, 13), P1)
			offset += 4
		h = (_rotl32(v1, 1) + _rotl32(v2, 7) + _rotl32(v3, 12) + _rotl32(v4, 18)) & MASK32
	else:
		h = (seed + P5) & MASK32
	h = (h + length) & MASK32
	while offset <= length - 4:
		h = _mul32(_rotl32((h + _mul32(_read_u32(data, offset), P3)) & MASK32, 17), P4)
		offset += 4
	while offset < length:
		h = _mul32(_rotl32((h + data[offset] * P5) & MASK32, 11), P1)
		offset += 1
	h ^= h >> 15
	h = _mul32(h, P2)
	h ^= h >> 13
	h = _mul32(h, P3)
	h ^= h >> 16
	return h & MASK32


## `bgFriendlyName` -> `bgName`。空串固定返回 0（AA 的“无背景”）。
static func bg_id(friendly_name: String) -> int:
	if friendly_name.is_empty():
		return EMPTY_BG_ID
	return xxh32(friendly_name.to_utf8_buffer(), 0)
