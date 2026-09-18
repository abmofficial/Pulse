-- Validates client-submitted data mutations against the field rules.
-- Everything that reaches game state has passed through here first.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PayloadValidator = require(ReplicatedStorage.Pulse.Core.Utilities.PayloadValidator)

local Validate = {}

local function checkRules(value, rules)
local ruleType = rules.Type

if ruleType == "number" then
if type(value) ~= "number" then return false end
if value ~= value or value == math.huge or value == -math.huge then return false end
if rules.Min and value < rules.Min then return false end
if rules.Max and value > rules.Max then return false end
return true
elseif ruleType == "string" then
if type(value) ~= "string" then return false end
return #value <= (rules.MaxString or 100)
elseif ruleType == "boolean" then
return type(value) == "boolean"
elseif ruleType == "table" then
if type(value) ~= "table" then return false end

-- whitelist: every key must be declared, and every value must pass
for key, child in pairs(value) do
local childRules = rules.Keys and rules.Keys[key]
if not childRules then return false end
if not checkRules(child, childRules) then return false end
end

return true
end

return false
end

function Validate.Value(rules, value)
if type(value) ~= "table" then
-- cheap generic sanity pass for leaves
if type(value) ~= "number" and type(value) ~= "string" and type(value) ~= "boolean" then
return false
end
else
-- deep size/depth/type caps on table payloads
if not PayloadValidator.ValidateValue(value) then
return false
end
end

return checkRules(value, rules)
end

return Validate