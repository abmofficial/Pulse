local Signal = require(script.Parent.Parent.Utilities.Signal)
local Constants = require(script.Parent.Parent.Config.Constants)

local RequestChannel = {}
RequestChannel.__index = RequestChannel

function RequestChannel.new(name, definition, context)
return setmetatable({
Name = name,
_definition = definition,
_context = context,
_handler = nil,
_nextId = 0,
_pending = {},
}, RequestChannel)
end

function RequestChannel:Handle(callback)
assert(type(callback) == "function", "Handler must be a function")
self._handler = callback
end

function RequestChannel:Unhandle()
self._handler = nil
end

function RequestChannel:AskServer(...)
assert(not self._context.IsServer, "AskServer() can only be called by a client")
return self:_ask("Server", nil, ...)
end

function RequestChannel:AskClient(player, ...)
assert(self._context.IsServer, "AskClient() can only be called by the server")
return self:_ask("Client", player, ...)
end

function RequestChannel:_ask(target, player, ...)
self._nextId = self._nextId % Constants.MaxRequestId + 1

local requestId = self._nextId
local waiter = Signal.new()
self._pending[requestId] = waiter

self._context.SendRequest(self._definition, target, player, requestId, ...)

local timeout = self._definition.Timeout or Constants.DefaultRequestTimeout

task.delay(timeout, function()
if self._pending[requestId] ~= waiter then return end

self._pending[requestId] = nil
waiter:Fire(false, "Request timed out after " .. timeout .. " seconds")
end)

local success, result = waiter:Wait()
waiter:Destroy()

if success then
return result
end

return nil, result
end

function RequestChannel:_ReceiveResponse(requestId, success, result)
local waiter = self._pending[requestId]
if not waiter then return end

self._pending[requestId] = nil
waiter:Fire(success, result)
end

function RequestChannel:_HandleIncoming(player, requestId, args)
local respond = self._context.SendResponse
local target = if self._context.IsServer then "Client" else "Server"

if not self._handler then
respond(self._definition, target, player, requestId, false, "No request handler registered for " .. self.Name)
return
end

task.spawn(function()
local success, result

if self._context.IsServer then
success, result = pcall(self._handler, player, table.unpack(args))
else
success, result = pcall(self._handler, table.unpack(args))
end

respond(self._definition, target, player, requestId, success, result)
end)
end

return RequestChannel