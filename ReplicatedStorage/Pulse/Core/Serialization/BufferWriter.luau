--[[
	Growable byte writer over the native Luau buffer type.
	Provides efficient binary serialization with automatic buffer growth.

	Usage:
		local writer = Writer.new(128)
		writer:U8(1)
		writer:U16(256)
		writer:String("hello")
		local buffer = writer:ToBuffer()
]]

--!native

-- Type definitions (using comments since Luau doesn't support union types with | or ?)
-- type Writer = {
-- 	_data: buffer,
-- 	_len: number,
-- 	new: (capacity?: number) -> Writer,
-- 	Reset: (self: Writer) -> (),
-- 	Reserve: (self: Writer, extra: number) -> (),
-- 	Skip: (self: Writer, count: number) -> number,
-- 	PatchU8: (self: Writer, offset: number, value: number) -> (),
-- 	ToBuffer: (self: Writer) -> buffer,
-- 	U8: (self: Writer, value: number) -> (),
-- 	U16: (self: Writer, value: number) -> (),
-- 	U32: (self: Writer, value: number) -> (),
-- 	I32: (self: Writer, value: number) -> (),
-- 	F32: (self: Writer, value: number) -> (),
-- 	F64: (self: Writer, value: number) -> (),
-- 	Varint: (self: Writer, value: number) -> (),
-- 	Boolean: (self: Writer, value: boolean) -> (),
-- 	String: (self: Writer, value: string) -> (),
-- }

local Writer: Writer = {}
Writer.__index = Writer

--- Creates a new writer with optional initial capacity
--- @param capacity number? -- Initial buffer capacity (default: 64)
--- @return Writer
function Writer.new(capacity: number?): Writer
	return setmetatable({ _data = buffer.create(capacity or 64), _len = 0 }, Writer)
end

--- Resets the writer to empty state (keeps allocated buffer)
function Writer:Reset()
	self._len = 0
end

--- Ensures buffer has space for extra bytes
--- @param extra number -- Additional bytes needed
function Writer:Reserve(extra: number)
	local needed = self._len + extra
	local size = buffer.len(self._data)

	if needed > size then
		local grown = buffer.create(math.max(size * 2, needed))
		buffer.copy(grown, 0, self._data, 0, self._len)
		self._data = grown
	end
end

--- Skips count bytes and returns the offset (for later patching)
--- @param count number -- Bytes to skip
--- @return number -- Offset of skipped region
function Writer:Skip(count: number): number
	self:Reserve(count)
	local offset = self._len
	self._len += count
	return offset
end

--- Patches a single byte at the given offset
--- @param offset number -- Offset to patch
--- @param value number -- Byte value (0-255)
function Writer:PatchU8(offset: number, value: number)
	buffer.writeu8(self._data, offset, value)
end

--- Returns a new buffer containing only the written data
--- @return buffer
function Writer:ToBuffer(): buffer
	local out = buffer.create(self._len)
	buffer.copy(out, 0, self._data, 0, self._len)
	return out
end

--- Writes an unsigned 8-bit integer
--- @param value number -- Value 0-255
function Writer:U8(value: number)
	self:Reserve(1)
	buffer.writeu8(self._data, self._len, value)
	self._len += 1
end

--- Writes an unsigned 16-bit integer (little-endian)
--- @param value number -- Value 0-65535
function Writer:U16(value: number)
	self:Reserve(2)
	buffer.writeu16(self._data, self._len, value)
	self._len += 2
end

--- Writes an unsigned 32-bit integer (little-endian)
--- @param value number -- Value 0-4294967295
function Writer:U32(value: number)
	self:Reserve(4)
	buffer.writeu32(self._data, self._len, value)
	self._len += 4
end

--- Writes a signed 32-bit integer (little-endian)
--- @param value number -- Value -2147483648 to 2147483647
function Writer:I32(value: number)
	self:Reserve(4)
	buffer.writei32(self._data, self._len, value)
	self._len += 4
end

--- Writes a 32-bit float (little-endian)
--- @param value number -- Float value
function Writer:F32(value: number)
	self:Reserve(4)
	buffer.writef32(self._data, self._len, value)
	self._len += 4
end

--- Writes a 64-bit float (little-endian)
--- @param value number -- Double value
function Writer:F64(value: number)
	self:Reserve(8)
	buffer.writef64(self._data, self._len, value)
	self._len += 8
end

--- Writes a LEB128 variable-length integer (1-5 bytes for u32)
--- @param value number -- Non-negative integer
function Writer:Varint(value: number)
	while true do
		if value < 0x80 then
			self:U8(value)
			return
		end
		self:U8(0x80 + value % 0x80)
		value = math.floor(value / 0x80)
	end
end

--- Writes a boolean as a single byte
--- @param value boolean
function Writer:Boolean(value: boolean)
	self:U8(if value then 1 else 0)
end

--- Writes a string with length prefix (varint)
--- @param value string
function Writer:String(value: string)
	local length = #value
	self:Varint(length)
	self:Reserve(length)
	buffer.writestring(self._data, self._len, value)
	self._len += length
end

return Writer