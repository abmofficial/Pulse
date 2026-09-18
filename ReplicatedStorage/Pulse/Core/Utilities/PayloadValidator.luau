--!native
local Constants = require(script.Parent.Parent.Config.Constants)

local MaxArguments = Constants.MaxArguments
local MaxString = Constants.MaxString
local MaxTableDepth = Constants.MaxTableDepth
local MaxTableSize = Constants.MaxTableSize

local ALLOWED_USERDATA = {
Vector2 = true, Vector3 = true, CFrame = true, Color3 = true,
UDim = true, UDim2 = true, BrickColor = true, Ray = true,
Rect = true, Region3 = true, NumberRange = true,
TweenInfo = true, DateTime = true, Instance = true,
}

local function validateValue(value, depth)
local valueType = type(value)

if valueType == "boolean" then
return true
elseif valueType == "number" then
return value == value and value ~= math.huge and value ~= -math.huge
elseif valueType == "string" then
return #value <= MaxString
elseif valueType == "table" then
if depth >= MaxTableDepth then return false end

local size = 0
for key, child in pairs(value) do
size += 1
if size > MaxTableSize then return false end
if type(key) == "number" and (key ~= key or key == math.huge or key == -math.huge) then return false end
if not validateValue(child, depth + 1) then return false end
end

return true
elseif valueType == "vector" then
-- Luau native vector (Vector3): type() returns "vector", not "userdata"
local x, y, z = value.X, value.Y, value.Z
return x == x and y == y and z == z
and x ~= math.huge and y ~= math.huge and z ~= math.huge
and x ~= -math.huge and y ~= -math.huge and z ~= -math.huge
elseif valueType == "userdata" then
return ALLOWED_USERDATA[typeof(value)] == true
end

return false
end

local function validateArguments(args)
local count = 0

for index = 1, MaxArguments do
local value = rawget(args, index)
if value == nil then break end
if not validateValue(value, 1) then return false end
count = index
end

if count == 0 then
return next(args) == nil
end

-- the next(args, count) check catches holes, dict keys and oversized arrays
return next(args, count) == nil
end

local PayloadValidator = {}

function PayloadValidator.ValidateArguments(args)
return validateArguments(args)
end

function PayloadValidator.ValidateValue(value)
return validateValue(value, 1)
end

return PayloadValidator