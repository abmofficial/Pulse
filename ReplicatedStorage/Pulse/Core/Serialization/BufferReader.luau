-- Bounds-checked reader over a received buffer. Any out-of-bounds,
-- oversized or malformed read raises, which the dispatcher turns into a
-- violation.
local Reader = {}
Reader.__index = Reader

function Reader.new(data)
return setmetatable({ _data = data, _len = buffer.len(data), _offset = 0 }, Reader)
end

function Reader:U8()
local offset = self._offset
if offset + 1 > self._len then error("read out of bounds") end
self._offset = offset + 1
return buffer.readu8(self._data, offset)
end

function Reader:U16()
local offset = self._offset
if offset + 2 > self._len then error("read out of bounds") end
self._offset = offset + 2
return buffer.readu16(self._data, offset)
end

function Reader:U32()
local offset = self._offset
if offset + 4 > self._len then error("read out of bounds") end
self._offset = offset + 4
return buffer.readu32(self._data, offset)
end

function Reader:I32()
local offset = self._offset
if offset + 4 > self._len then error("read out of bounds") end
self._offset = offset + 4
return buffer.readi32(self._data, offset)
end

function Reader:F32()
local offset = self._offset
if offset + 4 > self._len then error("read out of bounds") end
self._offset = offset + 4
return buffer.readf32(self._data, offset)
end

function Reader:F64()
local offset = self._offset
if offset + 8 > self._len then error("read out of bounds") end
self._offset = offset + 8
return buffer.readf64(self._data, offset)
end

function Reader:Varint()
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

function Reader:Boolean()
return self:U8() ~= 0
end

function Reader:String(maxLength)
local length = self:Varint()
if length > maxLength then error("string too long") end

local offset = self._offset
if offset + length > self._len then error("read out of bounds") end

self._offset = offset + length
return buffer.readstring(self._data, offset, length)
end

return Reader