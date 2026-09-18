--[[
	LocalFunction - Same-context function calls (like BindableFunction).
	No network involved, calls handler immediately within the same Lua state.

	Usage:
		-- Register handler
		Pulse.LocalFunctions.MyFunc:Handle(function(a, b) return a + b end)

		-- Call function
		local result = Pulse.LocalFunctions.MyFunc:Call(1, 2)
]]

-- Type definitions (using comments since Luau doesn't support union types with |)
-- type LocalFunction = {
-- 	Name: string,
-- 	_handler: ((...any) -> ...any)?,
-- 	new: (name: string) -> LocalFunction,
-- 	Handle: (self: LocalFunction, callback: (...any) -> ...any) -> (),
-- 	Unhandle: (self: LocalFunction) -> (),
-- 	Call: (self: LocalFunction, ...any) -> ...any,
-- }

local LocalFunction: LocalFunction = {}
LocalFunction.__index = LocalFunction

--- Creates a new local function
--- @param name string -- Function name
--- @return LocalFunction
function LocalFunction.new(name: string): LocalFunction
	return setmetatable({ Name = name, _handler = nil }, LocalFunction)
end

--- Sets the function handler
--- @param callback function -- Called when function is invoked
function LocalFunction:Handle(callback: (...any) -> ...any)
	assert(type(callback) == "function", "Handler must be a function")
	self._handler = callback
end

--- Removes the function handler
function LocalFunction:Unhandle()
	self._handler = nil
end

--- Calls the function and returns results
--- @param ...any -- Arguments to pass to handler
--- @return ...any -- Results from handler
function LocalFunction:Call(...: any): ...any
	assert(self._handler, "No handler registered for LocalFunction " .. self.Name)
	return self._handler(...)
end

return LocalFunction