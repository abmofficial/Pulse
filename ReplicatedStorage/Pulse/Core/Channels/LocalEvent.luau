--[[
	LocalEvent - Same-context event communication (like BindableEvent).
	No network involved, fires immediately within the same Lua state.

	Usage:
		-- Fire event
		Pulse.LocalEvents.MyEvent:Emit(data)

		-- Listen
		Pulse.LocalEvents.MyEvent:Listen(function(data) ... end)
]]

-- Type definitions (using comments since Luau doesn't support union types with |)
-- type Signal = any -- From Signal module
-- type LocalEvent = {
-- 	Name: string,
-- 	_signal: Signal,
-- 	new: (name: string) -> LocalEvent,
-- 	Listen: (self: LocalEvent, callback: (...any) -> ()) -> { Connected: boolean, Disconnect: (self: any) -> () },
-- 	Once: (self: LocalEvent, callback: (...any) -> ()) -> { Connected: boolean, Disconnect: (self: any) -> () },
-- 	Wait: (self: LocalEvent) -> ...any,
-- 	Emit: (self: LocalEvent, ...any) -> (),
-- 	Destroy: (self: LocalEvent) -> (),
-- }

local Signal = require(script.Parent.Parent.Utilities.Signal)

local LocalEvent: LocalEvent = {}
LocalEvent.__index = LocalEvent

--- Creates a new local event
--- @param name string -- Event name
--- @return LocalEvent
function LocalEvent.new(name: string): LocalEvent
	return setmetatable({ Name = name, _signal = Signal.new() }, LocalEvent)
end

--- Registers a listener
--- @param callback function -- Called when event fires
--- @return Connection -- Connection object with Disconnect() method
function LocalEvent:Listen(callback: (...any) -> ())
	return self._signal:Connect(callback)
end

--- Registers a one-time listener
--- @param callback function -- Called once when event fires
--- @return Connection
function LocalEvent:Once(callback: (...any) -> ())
	return self._signal:Once(callback)
end

--- Yields until the event fires
--- @return ...any -- Event arguments
function LocalEvent:Wait(): ...any
	return self._signal:Wait()
end

--- Fires the event to all listeners
--- @param ...any -- Event arguments
function LocalEvent:Emit(...: any)
	self._signal:Fire(...)
end

--- Destroys the event and cleans up all connections
function LocalEvent:Destroy()
	self._signal:Destroy()
end

return LocalEvent