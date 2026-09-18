-- Growable byte writer over the native Luau buffer type
local Writer = {}
Writer.__index = Writer

function Writer.new(capacity)
return setmetatable({ _data = buffer.create(capacity or 64), _len = 0 }, Writer)
end

function Writer:Reset()
self._len = 0
end

function Writer:Reserve(extra)
local needed = self._len + extra
local size = buffer.len(self._data)

if needed > size then
local grown = buffer.create(math.max(size * 2, needed))
buffer.copy(grown, 0, self._data, 0, self._len)
self._data = grown
end
end

function Writer:Skip(count)
self:Reserve(count)
local offset = self._len
self._len += count
return offset
end

function Writer:PatchU8(offset, value)
buffer.writeu8(self._data, offset, value)
end

function Writer:ToBuffer()
local out = buffer.create(self._len)
buffer.copy(out, 0, self._data, 0, self._len)
return out
end

function Writer:U8(value)
self:Reserve(1)
buffer.writeu8(self._data, self._len, value)
self._len += 1
end

function Writer:U16(value)
self:Reserve(2)
buffer.writeu16(self._data, self._len, value)
self._len += 2
end

function Writer:U32(value)
self:Reserve(4)
buffer.writeu32(self._data, self._len, value)
self._len += 4
end

function Writer:I32(value)
self:Reserve(4)
buffer.writei32(self._data, self._len, value)
self._len += 4
end

function Writer:F32(value)
self:Reserve(4)
buffer.writef32(self._data, self._len, value)
self._len += 4
end

function Writer:F64(value)
self:Reserve(8)
buffer.writef64(self._data, self._len, value)
self._len += 8
end

-- LEB128: 1 byte for values < 128, up to 5 bytes for a u32
function Writer:Varint(value)
while true do
if value < 0x80 then
self:U8(value)
return
end
self:U8(0x80 + value % 0x80)
value = math.floor(value / 0x80)
end
end

function Writer:Boolean(value)
self:U8(if value then 1 else 0)
end

function Writer:String(value)
local length = #value
self:Varint(length)
self:Reserve(length)
buffer.writestring(self._data, self._len, value)
self._len += length
end

return Writer