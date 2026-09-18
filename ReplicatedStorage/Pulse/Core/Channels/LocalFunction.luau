local LocalFunction = {}
LocalFunction.__index = LocalFunction

function LocalFunction.new(name)
return setmetatable({ Name = name, _handler = nil }, LocalFunction)
end

function LocalFunction:Handle(callback)
assert(type(callback) == "function", "Handler must be a function")
self._handler = callback
end

function LocalFunction:Unhandle()
self._handler = nil
end

function LocalFunction:Call(...)
assert(self._handler, "No handler registered for LocalFunction " .. self.Name)
return self._handler(...)
end

return LocalFunction