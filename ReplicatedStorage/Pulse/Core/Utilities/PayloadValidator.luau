--[[
	PayloadValidator - Validates network payloads against size, depth, and type constraints.
	Prevents malicious or malformed data from entering the game state.

	Usage:
		local valid = PayloadValidator.ValidateArguments(args)
		local valid = PayloadValidator.ValidateValue(value)
]]

--!native

-- Type definitions (using comments since Luau doesn't support union types with | or ?)
-- type PayloadValidator = {
-- 	ValidateArguments: (args: {any}) -> boolean,
-- 	ValidateValue: (value: any) -> boolean,
-- }

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

--- Validates a single value recursively
--- @param value any -- Value to validate
--- @param depth number -- Current nesting depth
--- @return boolean -- True if valid
local function validateValue(value: any, depth: number): boolean
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

--- Validates an arguments table
--- @param args {any} -- Arguments to validate
--- @return boolean -- True if valid
local function validateArguments(args: {any}): boolean
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

local PayloadValidator: PayloadValidator = {}

--- Validates a table of arguments for network transmission
--- @param args {any} -- Arguments to validate
--- @return boolean -- True if all arguments are valid
function PayloadValidator.ValidateArguments(args: {any}): boolean
	return validateArguments(args)
end

--- Validates a single value for network transmission
--- @param value any -- Value to validate
--- @return boolean -- True if value is valid
function PayloadValidator.ValidateValue(value: any): boolean
	return validateValue(value, 1)
end

return PayloadValidator