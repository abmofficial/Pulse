local Signal = require(script.Parent.Parent.Utilities.Signal)

local LocalEvent = {}
LocalEvent.__index = LocalEvent

function LocalEvent.new(name)
return setmetatable({ Name = name, _signal = Signal.new() }, LocalEvent)
end

function LocalEvent:Listen(callback)
return self._signal:Connect(callback)
end

function LocalEvent:Once(callback)
return self._signal:Once(callback)
end

function LocalEvent:Wait()
return self._signal:Wait()
end

function LocalEvent:Emit(...)
self._signal:Fire(...)
end

function LocalEvent:Destroy()
self._signal:Destroy()
end

return LocalEvent