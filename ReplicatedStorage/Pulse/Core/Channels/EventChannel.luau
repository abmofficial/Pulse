--[[
	EventChannel - One-way network communication channel.
	Supports reliable and unreliable delivery, with optional batching.

	Usage:
		-- Server to client
		Pulse.Events.MyEvent:SendClient(player, data)
		Pulse.Events.MyEvent:Broadcast(data)

		-- Client to server
		Pulse.Events.MyEvent:SendServer(data)

		-- Listening
		Pulse.Events.MyEvent:Listen(function(player, data) ... end)
]]

-- Type definitions (using comments since Luau doesn't support union types with |)
-- type Signal = any -- From Signal module
-- type Definition = {
-- 	Id: number,
-- 	Reliability: "Reliable" | "Unreliable",
-- 	Batch: boolean,
-- 	RateLimit: { Count: number, Window: number },
-- }
-- type Context = {
-- 	IsServer: boolean,
-- 	SendEvent: (definition: Definition, target: string, player: Player?, ...any) -> (),
-- }
-- type EventChannel = {
-- 	Name: string,
-- 	_definition: Definition,
-- 	_context: Context,
-- 	_signal: Signal,
-- 	new: (name: string, definition: Definition, context: Context) -> EventChannel,
-- 	Listen: (self: EventChannel, callback: (...any) -> ()) -> { Connected: boolean, Disconnect: (self: any) -> () },
-- 	Once: (self: EventChannel, callback: (...any) -> ()) -> { Connected: boolean, Disconnect: (self: any) -> () },
-- 	Wait: (self: EventChannel) -> ...any,
-- 	SendServer: (self: EventChannel, ...any) -> (),
-- 	SendClient: (self: EventChannel, player: Player, ...any) -> (),
-- 	Broadcast: (self: EventChannel, ...any) -> (),
-- 	_Dispatch: (self: EventChannel, player: Player?, ...any) -> (),
-- }

local Signal = require(script.Parent.Parent.Utilities.Signal)

local EventChannel: EventChannel = {}
EventChannel.__index = EventChannel

--- Creates a new event channel
--- @param name string -- Channel name
--- @param definition Definition -- Channel definition from registry
--- @param context Context -- Pulse context (provides IsServer and SendEvent)
--- @return EventChannel
function EventChannel.new(name: string, definition: Definition, context: Context): EventChannel
	return setmetatable({
		Name = name,
		_definition = definition,
		_context = context,
		_signal = Signal.new(),
	}, EventChannel)
end

--- Registers a listener for this event
--- @param callback function -- Called when event fires (player, ... on server; ... on client)
--- @return Connection -- Connection object with Disconnect() method
function EventChannel:Listen(callback: (...any) -> ())
	return self._signal:Connect(callback)
end

--- Registers a one-time listener
--- @param callback function -- Called once when event fires
--- @return Connection
function EventChannel:Once(callback: (...any) -> ())
	return self._signal:Once(callback)
end

--- Yields until the event fires
--- @return ...any -- Event arguments
function EventChannel:Wait(): ...any
	return self._signal:Wait()
end

--- Sends event to server (client only)
--- @param ...any -- Event arguments
function EventChannel:SendServer(...: any)
	assert(not self._context.IsServer, "SendServer() can only be used by the client")
	self._context.SendEvent(self._definition, "Server", nil, ...)
end

--- Sends event to specific client (server only)
--- @param player Player -- Target player
--- @param ...any -- Event arguments
function EventChannel:SendClient(player: Player, ...: any)
	assert(self._context.IsServer, "SendClient() can only be used by the server")
	assert(typeof(player) == "Instance" and player:IsA("Player"), "SendClient() requires a Player")
	self._context.SendEvent(self._definition, "Client", player, ...)
end

--- Broadcasts event to all clients (server only)
--- @param ...any -- Event arguments
function EventChannel:Broadcast(...: any)
	assert(self._context.IsServer, "Broadcast() can only be used by the server")
	self._context.SendEvent(self._definition, "All", nil, ...)
end

--- Internal: Dispatches event to listeners
--- @param player Player? -- Source player (server only)
--- @param ...any -- Event arguments
function EventChannel:_Dispatch(player: Player?, ...: any)
	if self._context.IsServer then
		self._signal:Fire(player, ...)
	else
		self._signal:Fire(...)
	end
end

return EventChannel