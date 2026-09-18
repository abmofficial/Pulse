-- Type-tagged value encoding. The decoder'"'"'s output types are closed, so
-- functions and sparse tables physically cannot cross the wire.
local Constants = require(script.Parent.Parent.Config.Constants)
local Writer = require(script.Parent.BufferWriter)
local Reader = require(script.Parent.BufferReader)

local NIL, TRUE, FALSE = 0, 1, 2
local U8, U16, U32, I32, F64 = 3, 4, 5, 6, 7
local STR, VEC3, VEC2, CFRAME, COLOR3 = 8, 9, 10, 11, 12
local ARRAY, MAP = 13, 14

local MaxArguments = Constants.MaxArguments
local MaxString = Constants.MaxString
local MaxTableDepth = Constants.MaxTableDepth
local MaxTableSize = Constants.MaxTableSize

local function finite(x, y, z)
return x == x and y == y and z == z
and x ~= math.huge and y ~= math.huge and z ~= math.huge
and x ~= -math.huge and y ~= -math.huge and z ~= -math.huge
end

local function isDenseArray(value)
local count = #value

if count == 0 then
return next(value) == nil
end

return next(value, count) == nil
end

local ValueCodec = {}

function ValueCodec.CanPack(value, depth)
local valueType = type(value)

if valueType == "nil" or valueType == "boolean" or valueType == "number" or valueType == "string" then
return true
elseif valueType == "vector" then
return finite(value.X, value.Y, value.Z)
elseif valueType == "userdata" then
local typeName = typeof(value)

if typeName == "Vector2" then
return finite(value.X, value.Y, 0)
elseif typeName == "CFrame" then
local position = value.Position
return finite(position.X, position.Y, position.Z)
elseif typeName == "Color3" then
return value.R >= 0 and value.R <= 1 and value.G >= 0 and value.G <= 1 and value.B >= 0 and value.B <= 1
end

return false
elseif valueType == "table" then
if depth >= MaxTableDepth then return false end

if not isDenseArray(value) then
for key in pairs(value) do
if type(key) ~= "string" then return false end
end
end

local size = 0
for _, child in pairs(value) do
size += 1
if size > MaxTableSize then return false end
if not ValueCodec.CanPack(child, depth + 1) then return false end
end

return true
end

return false
end

function ValueCodec.Encode(writer, value, depth)
local valueType = type(value)

if valueType == "nil" then
writer:U8(NIL)
elseif valueType == "boolean" then
writer:U8(if value then TRUE else FALSE)
elseif valueType == "number" then
if value >= 0 and value == math.floor(value) then
if value <= 255 then
writer:U8(U8)
writer:U8(value)
elseif value <= 65535 then
writer:U8(U16)
writer:U16(value)
elseif value <= 4294967295 then
writer:U8(U32)
writer:U32(value)
else
writer:U8(F64)
writer:F64(value)
end
elseif value == math.floor(value) and value >= -2147483648 then
writer:U8(I32)
writer:I32(value)
else
writer:U8(F64)
writer:F64(value)
end
elseif valueType == "string" then
writer:U8(STR)
writer:String(value)
elseif valueType == "vector" then
writer:U8(VEC3)
writer:F32(value.X)
writer:F32(value.Y)
writer:F32(value.Z)
elseif valueType == "userdata" then
local typeName = typeof(value)

if typeName == "Vector2" then
writer:U8(VEC2)
writer:F32(value.X)
writer:F32(value.Y)
elseif typeName == "CFrame" then
-- ToAxisAngle returns (axis, angle), not the other way around
local axis, angle = value:ToAxisAngle()
local position = value.Position

writer:U8(CFRAME)
writer:F32(position.X)
writer:F32(position.Y)
writer:F32(position.Z)
writer:F32(angle)
writer:F32(axis.X)
writer:F32(axis.Y)
writer:F32(axis.Z)
elseif typeName == "Color3" then
writer:U8(COLOR3)
writer:U8(math.floor(value.R * 255 + 0.5))
writer:U8(math.floor(value.G * 255 + 0.5))
writer:U8(math.floor(value.B * 255 + 0.5))
else
error("unpackable userdata: " .. typeName)
end
elseif valueType == "table" then
if depth >= MaxTableDepth then error("table too deep") end

if isDenseArray(value) then
local count = #value
writer:U8(ARRAY)
writer:U8(count)

for index = 1, count do
ValueCodec.Encode(writer, value[index], depth + 1)
end
else
writer:U8(MAP)
local countOffset = writer:Skip(1)
local count = 0

for key, child in pairs(value) do
count += 1
writer:String(key)
ValueCodec.Encode(writer, child, depth + 1)
end

writer:PatchU8(countOffset, count)
end
else
error("unpackable value: " .. valueType)
end
end

function ValueCodec.Decode(reader, depth)
local tag = reader:U8()

if tag == NIL then
return nil
elseif tag == TRUE then
return true
elseif tag == FALSE then
return false
elseif tag == U8 then
return reader:U8()
elseif tag == U16 then
return reader:U16()
elseif tag == U32 then
return reader:U32()
elseif tag == I32 then
return reader:I32()
elseif tag == F64 then
local value = reader:F64()
if value ~= value or value == math.huge or value == -math.huge then error("non-finite number") end
return value
elseif tag == STR then
return reader:String(MaxString)
elseif tag == VEC3 then
local x, y, z = reader:F32(), reader:F32(), reader:F32()
if not finite(x, y, z) then error("non-finite vector") end
return Vector3.new(x, y, z)
elseif tag == VEC2 then
local x, y = reader:F32(), reader:F32()
if not finite(x, y, 0) then error("non-finite vector") end
return Vector2.new(x, y)
elseif tag == CFRAME then
local px, py, pz = reader:F32(), reader:F32(), reader:F32()
local angle = reader:F32()
local ax, ay, az = reader:F32(), reader:F32(), reader:F32()
if not finite(px, py, pz) or not finite(angle, ax, ay) or not finite(az, 0, 0) then error("non-finite cframe") end
return CFrame.new(px, py, pz) * CFrame.fromAxisAngle(Vector3.new(ax, ay, az), angle)
elseif tag == COLOR3 then
return Color3.new(reader:U8() / 255, reader:U8() / 255, reader:U8() / 255)
elseif tag == ARRAY then
if depth >= MaxTableDepth then error("table too deep") end

local count = reader:U8()
if count > MaxTableSize then error("table too large") end

local result = table.create(count)
for index = 1, count do
local value = ValueCodec.Decode(reader, depth + 1)
if value == nil then error("nil inside array") end
result[index] = value
end

return result
elseif tag == MAP then
if depth >= MaxTableDepth then error("table too deep") end

local count = reader:U8()
if count > MaxTableSize then error("table too large") end

local result = {}
for index = 1, count do
local key = reader:String(255)
local value = ValueCodec.Decode(reader, depth + 1)
if value == nil then error("nil inside map") end
result[key] = value
end

return result
end

error("unknown type tag: " .. tag)
end

return ValueCodec