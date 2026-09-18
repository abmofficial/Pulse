local Signal = {}
Signal.__index = Signal

function Signal.new()
return setmetatable({ _handlers = {}, _count = 0, _firing = false, _deferred = nil, _destroyed = false }, Signal)
end

function Signal:Connect(callback)
assert(not self._destroyed, "Cannot connect to a destroyed Signal")
assert(type(callback) == "function", "Callback must be a function")

local signal = self
local connection = { Connected = true }

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

function Signal:Once(callback)
local connection
connection = self:Connect(function(...)
connection:Disconnect()
callback(...)
end)
return connection
end

function Signal:Wait()
assert(not self._destroyed, "Cannot wait on a destroyed Signal")

local thread = coroutine.running()
local connection
connection = self:Connect(function(...)
connection:Disconnect()
task.spawn(thread, ...)
end)

return coroutine.yield()
end

function Signal:Fire(...)
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

function Signal:Destroy()
if self._destroyed then return end

self._destroyed = true
table.clear(self._handlers)
self._count = 0
self._deferred = nil
end

function Signal:_remove(connection)
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