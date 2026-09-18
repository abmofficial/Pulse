--[[
DEFINITIONS / Where you add all your networking channels.

Open this file, copy a template below, paste at the bottom of the right
list, and rename it. The list order decides the channel ID, and the client
and server must agree on it. Only add to the bottom; never remove or
reorder channels already shipping. Never put URLs or keys in here (HTTP
config, which can hold secrets, lives server-only in ServerScriptService).

EVENTS (one-way):
    "MyEvent"                                     reliable, default 20/sec
    { "MyEvent", Rate = 5 }                      reliable, 5/sec
    { "MyEvent", Unreliable = true, Rate = 60 }  fast, may drop
    { "MyEvent", Unreliable = true, Batch = true, Rate = 60 }  batched
    Pulse.Events.MyEvent:SendServer("hi")           -- client to server
    Pulse.Events.MyEvent:SendClient(player, "hi")   -- server to one client
    Pulse.Events.MyEvent:Broadcast("hi")            -- server to everyone
    Pulse.Events.MyEvent:Listen(function(player, msg) end)  -- server
    Pulse.Events.MyEvent:Listen(function(msg) end)          -- client

REQUESTS (ask + answer):
    { "MyRequest", Rate = 5, Timeout = 5 }
    Pulse.Requests.MyRequest:Handle(function(player, data) return 5 end)
    local result = Pulse.Requests.MyRequest:AskServer(data)
    (result is nil if it timed out or the handler failed)

LOCAL EVENTS / FUNCTIONS (same context, no network):
    LocalEvents = { "MyBus" }     LocalFunctions = { "MyMath" }
    Pulse.LocalEvents.MyBus:Emit(...) / :Listen(fn)
    Pulse.LocalFunctions.MyMath:Call(...) / :Handle(fn)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Definitions = {
Events = {
-- REQUIRED: Pulse data layer. Do not remove.
{ "DataSync", Rate = 60 },
},

Requests = {
-- REQUIRED: Pulse data layer. Do not remove.
{ "DataSet", Rate = 10 },
{ "DataIncrement", Rate = 10 },
},

LocalEvents = {
},

LocalFunctions = {
},

Groups = {
},
}

return Definitions