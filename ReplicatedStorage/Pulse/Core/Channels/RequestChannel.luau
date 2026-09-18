--[[
	RequestChannel - Two-way network communication (request/response).
	Supports timeouts, retries, and automatic response routing.

	Usage:
		-- Server handler
		Pulse.Requests.MyRequest:Handle(function(player, arg1, arg2)
			return true, "success data"
		end)

		-- Client asking server
		local success, result = Pulse.Requests.MyRequest:AskServer(arg1, arg2)

		-- Server asking client
		local success, result = Pulse.Requests.MyRequest:AskClient(player, arg1, arg2)
]]

-- Type definitions (using comments since Luau doesn't support union types with |)
-- type Signal = any -- From Signal module
-- type Definition = {
-- 	Id: number,
-- 	Timeout: number,
-- 	RateLimit: { Count: number, Window: number },
-- }
-- type Context = {
-- 	IsServer: boolean,
-- 	SendRequest: (definition: Definition, target: string, player: Player?, requestId: number, ...any) -> (),
-- 	SendResponse: (definition: Definition, target: string, player: Player?, requestId: number, success: boolean, result: any) -> (),
-- }
-- type RequestChannel = {
-- 	Name: string,
-- 	_definition: Definition,
-- 	_context: Context,
-- 	_handler: ((...any) -> (boolean, any))?,
-- 	_nextId: number,
-- 	_pending: { [number]: Signal },
-- 	new: (name: string, definition: Definition, context: Context) -> RequestChannel,
-- 	Handle: (self: RequestChannel, callback: (...any) -> (boolean, any)) -> (),
-- 	Unhandle: (self: RequestChannel) -> (),
-- 	AskServer: (self: RequestChannel, ...any) -> (boolean, any?),
-- 	AskClient: (self: RequestChannel, player: Player, ...any) -> (boolean, any?),
-- 	_ask: (self: RequestChannel, target: string, player: Player?, ...any) -> (boolean, any?),
-- 	_ReceiveResponse: (self: RequestChannel, requestId: number, success: boolean, result: any) -> (),
-- 	_HandleIncoming: (self: RequestChannel, player: Player, requestId: number, args: {any}) -> (),
-- }

local Signal = require(script.Parent.Parent.Utilities.Signal)
local Constants = require(script.Parent.Parent.Config.Constants)

local RequestChannel: RequestChannel = {}
RequestChannel.__index = RequestChannel

--- Creates a new request channel
--- @param name string -- Channel name
--- @param definition Definition -- Channel definition from registry
--- @param context Context -- Pulse context
--- @return RequestChannel
function RequestChannel.new(name: string, definition: Definition, context: Context): RequestChannel
	return setmetatable({
		Name = name,
		_definition = definition,
		_context = context,
		_handler = nil,
		_nextId = 0,
		_pending = {},
	}, RequestChannel)
end

--- Sets the request handler (server only)
--- @param callback function -- Called with (player, ...) on server, (...) on client. Returns (success, result)
function RequestChannel:Handle(callback: (...any) -> (boolean, any))
	assert(type(callback) == "function", "Handler must be a function")
	self._handler = callback
end

--- Removes the request handler
function RequestChannel:Unhandle()
	self._handler = nil
end

--- Sends request to server and waits for response (client only)
--- @param ...any -- Request arguments
--- @return boolean, any? -- Success flag and result data (or error message)
function RequestChannel:AskServer(...: any): (boolean, any?)
	assert(not self._context.IsServer, "AskServer() can only be called by a client")
	return self:_ask("Server", nil, ...)
end

--- Sends request to specific client and waits for response (server only)
--- @param player Player -- Target player
--- @param ...any -- Request arguments
--- @return boolean, any? -- Success flag and result data (or error message)
function RequestChannel:AskClient(player: Player, ...: any): (boolean, any?)
	assert(self._context.IsServer, "AskClient() can only be called by the server")
	return self:_ask("Client", player, ...)
end

--- Internal: Sends request and waits for response
--- @param target string -- "Server" or "Client"
--- @param player Player? -- Target player (for Client target)
--- @param ...any -- Request arguments
--- @return boolean, any? -- Success flag and result data
function RequestChannel:_ask(target: string, player: Player?, ...: any): (boolean, any?)
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

--- Internal: Receives response from network
--- @param requestId number
--- @param success boolean
--- @param result any
function RequestChannel:_ReceiveResponse(requestId: number, success: boolean, result: any)
	local waiter = self._pending[requestId]
	if not waiter then return end

	self._pending[requestId] = nil
	waiter:Fire(success, result)
end

--- Internal: Handles incoming request from network
--- @param player Player -- Source player
--- @param requestId number -- Request ID
--- @param args {any} -- Request arguments
function RequestChannel:_HandleIncoming(player: Player, requestId: number, args: {any})
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