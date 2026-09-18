--[[
	Bounds-checked reader over a received buffer. Any out-of-bounds,
	oversized or malformed read raises, which the dispatcher turns into a
	violation.

	Usage:
		local reader = Reader.new(buffer)
		local value = reader:U8()
		local str = reader:String(100)
]]

--!native

-- Type definitions (using comments since Luau doesn't support union types with | or ?)
-- type Reader = {
-- 	_data: buffer,
-- 	_len: number,
-- 	_offset: number,
-- 	new: (data: buffer) -> Reader,
-- 	U8: (self: Reader) -> number,
-- 	U16: (self: Reader) -> number,
-- 	U32: (self: Reader) -> number,
-- 	I32: (self: Reader) -> number,
-- 	F32: (self: Reader) -> number,
-- 	F64: (self: Reader) -> number,
-- 	Varint: (self: Reader) -> number,
-- 	Boolean: (self: Reader) -> boolean,
-- 	String: (self: Reader, maxLength: number) -> string,
-- }

local Reader: Reader = {}
Reader.__index = Reader

--- Creates a new reader for the given buffer
--- @param data buffer -- Buffer to read from
--- @return Reader
function Reader.new(data: buffer): Reader
	return setmetatable({ _data = data, _len = buffer.len(data), _offset = 0 }, Reader)
end

--- Reads an unsigned 8-bit integer
--- @return number -- Value 0-255
function Reader:U8(): number
	local offset = self._offset
	if offset + 1 > self._len then error("read out of bounds") end
	self._offset = offset + 1
	return buffer.readu8(self._data, offset)
end

--- Reads an unsigned 16-bit integer (little-endian)
--- @return number -- Value 0-65535
function Reader:U16(): number
	local offset = self._offset
	if offset + 2 > self._len then error("read out of bounds") end
	self._offset = offset + 2
	return buffer.readu16(self._data, offset)
end

--- Reads an unsigned 32-bit integer (little-endian)
--- @return number -- Value 0-4294967295
function Reader:U32(): number
	local offset = self._offset
	if offset + 4 > self._len then error("read out of bounds") end
	self._offset = offset + 4
	return buffer.readu32(self._data, offset)
end

--- Reads a signed 32-bit integer (little-endian)
--- @return number -- Value -2147483648 to 2147483647
function Reader:I32(): number
	local offset = self._offset
	if offset + 4 > self._len then error("read out of bounds") end
	self._offset = offset + 4
	return buffer.readi32(self._data, offset)
end

--- Reads a 32-bit float (little-endian)
--- @return number -- Float value
function Reader:F32(): number
	local offset = self._offset
	if offset + 4 > self._len then error("read out of bounds") end
	self._offset = offset + 4
	return buffer.readf32(self._data, offset)
end

--- Reads a 64-bit float (little-endian)
--- @return number -- Double value
function Reader:F64(): number
	local offset = self._offset
	if offset + 8 > self._len then error("read out of bounds") end
	self._offset = offset + 8
	return buffer.readf64(self._data, offset)
end

--- Reads a LEB128 variable-length integer
--- @return number -- Decoded integer
function Reader:Varint(): number
	local value = 0
	local shift = 0

	while true do
		local byte = self:U8()
		value += (byte % 0x80) * 2 ^ shift

		if byte < 0x80 then
			return value
		end

		shift += 7
		if shift > 28 then error("varint overflow") end
	end
end

--- Reads a boolean (single byte, 0 = false, non-zero = true)
--- @return boolean
function Reader:Boolean(): boolean
	return self:U8() ~= 0
end

--- Reads a length-prefixed string
--- @param maxLength number -- Maximum allowed string length
--- @return string
function Reader:String(maxLength: number): string
	local length = self:Varint()
	if length > maxLength then error("string too long") end

	local offset = self._offset
	if offset + length > self._len then error("read out of bounds") end

	self._offset = offset + length
	return buffer.readstring(self._data, offset, length)
end

return Reader