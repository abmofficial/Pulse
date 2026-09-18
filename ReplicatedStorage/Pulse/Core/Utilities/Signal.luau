--[[
	Signal - Lightweight event system with connection management.
	Supports Connect, Once, Wait, and Fire with proper cleanup.

	Usage:
		local signal = Signal.new()
		local conn = signal:Connect(function(...) print(...) end)
		signal:Fire("hello")
		conn:Disconnect()
]]

-- Type definitions (using comments since Luau doesn't support union types with |)
-- type Connection = {
-- 	Connected: boolean,
-- 	Disconnect: (self: Connection) -> (),
-- }
-- type Signal = {
-- 	_handlers: { [number]: { Connection, (...any) -> () } },
-- 	_count: number,
-- 	_firing: boolean,
-- 	_deferred: { [Connection]: true }?,
-- 	_destroyed: boolean,
-- 	new: () -> Signal,
-- 	Connect: (self: Signal, callback: (...any) -> ()) -> Connection,
-- 	Once: (self: Signal, callback: (...any) -> ()) -> Connection,
-- 	Wait: (self: Signal) -> ...any,
-- 	Fire: (self: Signal, ...any) -> (),
-- 	Destroy: (self: Signal) -> (),
-- 	_remove: (self: Signal, connection: Connection) -> (),
-- }

local Signal: Signal = {}
Signal.__index = Signal

--- Creates a new signal
--- @return Signal
function Signal.new(): Signal
	return setmetatable({ _handlers = {}, _count = 0, _firing = false, _deferred = nil, _destroyed = false }, Signal)
end

--- Connects a callback to the signal
--- @param callback function -- Called when signal fires
--- @return Connection -- Connection object with Disconnect() method
function Signal:Connect(callback: (...any) -> ()): Connection
	assert(not self._destroyed, "Cannot connect to a destroyed Signal")
	assert(type(callback) == "function", "Callback must be a function")

	local signal = self
	local connection: Connection = { Connected = true }

	function connection:Disconnect()
		if not self.Connected then return end

		self.Connected = false

		if signal._firing then
			local deferred = signal._deferred or {}
			deferred[self] = true
			signal._deferred = deferred
			return
		end

		signal:_remove(self)
	end

	signal._count += 1
	signal._handlers[signal._count] = { connection, callback }

	return connection
end

--- Connects a one-time callback
--- @param callback function -- Called once when signal fires
--- @return Connection
function Signal:Once(callback: (...any) -> ()): Connection
	local connection: Connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

--- Yields until the signal fires
--- @return ...any -- Arguments passed to Fire()
function Signal:Wait(): ...any
	assert(not self._destroyed, "Cannot wait on a destroyed Signal")

	local thread = coroutine.running()
	local connection: Connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		task.spawn(thread, ...)
	end)

	return coroutine.yield()
end

--- Fires the signal to all connected callbacks
--- @param ...any -- Arguments to pass to callbacks
function Signal:Fire(...: any)
	if self._destroyed or self._count == 0 then return end

	self._firing = true

	local handlers = self._handlers
	for index = 1, self._count do
		local entry = handlers[index]
		if entry[1].Connected then
			task.spawn(entry[2], ...)
		end
	end

	self._firing = false

	local deferred = self._deferred
	if deferred then
		self._deferred = nil
		for connection in deferred do
			self:_remove(connection)
		end
	end
end

--- Destroys the signal and cleans up all connections
function Signal:Destroy()
	if self._destroyed then return end

	self._destroyed = true
	table.clear(self._handlers)
	self._count = 0
	self._deferred = nil
end

--- Internal: Removes a connection from the handler list
--- @param connection Connection
function Signal:_remove(connection: Connection)
	local handlers = self._handlers
	local count = self._count

	for index = 1, count do
		if handlers[index][1] == connection then
			handlers[index] = handlers[count]
			handlers[count] = nil
			self._count = count - 1
			return
		end
	end
end

return Signal