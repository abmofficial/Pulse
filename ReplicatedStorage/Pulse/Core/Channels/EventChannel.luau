local Signal = require(script.Parent.Parent.Utilities.Signal)

local EventChannel = {}
EventChannel.__index = EventChannel

function EventChannel.new(name, definition, context)
return setmetatable({
Name = name,
_definition = definition,
_context = context,
_signal = Signal.new(),
}, EventChannel)
end

function EventChannel:Listen(callback)
return self._signal:Connect(callback)
end

function EventChannel:Once(callback)
return self._signal:Once(callback)
end

function EventChannel:Wait()
return self._signal:Wait()
end

function EventChannel:SendServer(...)
assert(not self._context.IsServer, "SendServer() can only be used by the client")
self._context.SendEvent(self._definition, "Server", nil, ...)
end

function EventChannel:SendClient(player, ...)
assert(self._context.IsServer, "SendClient() can only be used by the server")
assert(typeof(player) == "Instance" and player:IsA("Player"), "SendClient() requires a Player")
self._context.SendEvent(self._definition, "Client", player, ...)
end

function EventChannel:Broadcast(...)
assert(self._context.IsServer, "Broadcast() can only be used by the server")
self._context.SendEvent(self._definition, "All", nil, ...)
end

function EventChannel:_Dispatch(player, ...)
if self._context.IsServer then
self._signal:Fire(player, ...)
else
self._signal:Fire(...)
end
end

return EventChannel