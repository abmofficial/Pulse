-- Posts security logs to a Discord webhook through the server-only Http
-- wrapper. Set the URL in Pulse/Http/Config (Endpoints.PulseWebhook).
-- Violations batch every BATCH_INTERVAL seconds, kicks flush immediately.
local Http = require(script.Parent.Parent.Http.Http)

local BATCH_INTERVAL = 10

local queue = {}
local flushScheduled = false
local setupWarned = false

local function post(payload)
local ok, err = Http.Request("PulseWebhook", payload)

if not ok and not setupWarned then
setupWarned = true

if err == "NOT_CONFIGURED" then
warn("[PULSE] Webhook is not configured — set it in Pulse/Http/Config (Endpoints.PulseWebhook)")
else
warn("[PULSE] Webhook unavailable: " .. tostring(err))
end
end
end

local function flush()
if next(queue) == nil then return end

local pending = queue
queue = {}

for index = 1, #pending, 10 do
local embeds = {}
for embedIndex = index, math.min(index + 9, #pending) do
embeds[#embeds + 1] = pending[embedIndex]
end
post({ embeds = embeds })
end
end

local function scheduleFlush()
if flushScheduled then return end

flushScheduled = true
task.defer(function()
flushScheduled = false
flush()
end)
end

local Webhook = {}

function Webhook.Log(embed, flushNow)
queue[#queue + 1] = embed
if flushNow then scheduleFlush() end
end

function Webhook.Start()
task.spawn(function()
while true do
task.wait(BATCH_INTERVAL)
pcall(flush)
end
end)
end

return Webhook