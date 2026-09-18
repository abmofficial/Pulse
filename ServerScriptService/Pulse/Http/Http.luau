--[[
Pulse Server / Http / Http
Server-only HTTP client.

Security model:
- This module and its Config are never replicated — clients cannot
  require, read or call them, and no remote exposes them.
- Allowlist only: endpoints declared in Config (or its Groups) are
  reachable; everything else is refused at the name check.
- If a player action should trigger a web request, expose a Pulse
  channel whose server handler validates input and calls this module
  itself. Never accept URLs, headers or secrets from the client.

Reliability model (built from DevForum pain reports):
- Global budget governor keeps the whole server under Roblox'"'"'s
  500 req/min cap with headroom, including a cold-start ramp for
  fresh servers (they start far lower than 500/min).
- Http.Queue fire-and-forget sends never block the caller'"'"'s thread
  and drain only when budget allows; full queues drop (callback
  still fires) instead of stalling the game.
- Identical in-flight GETs are shared between callers.
- Retries with backoff on transient failures (429/5xx/network).
- Http.GetStats() exposes the counters so trouble is visible before
  a lockout.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsServer() then
error("[PULSE] Http can only be used on the server")
end

local Signal = require(ReplicatedStorage.Pulse.Core.Utilities.Signal)
local RateLimiter = require(ReplicatedStorage.Pulse.Core.Utilities.RateLimiter)
local Config = require(script.Parent.Config)

local limiter = RateLimiter.new()
local serverStart = os.clock()

--------------------------------------------------
-- endpoint registry (Config + Groups, merged at boot)

local endpoints = {}

for name, spec in Config.Endpoints do
endpoints[name] = spec
end

for _, groupModule in Config.Groups or {} do
for name, spec in require(groupModule).Endpoints or {} do
assert(endpoints[name] == nil, "Duplicate HTTP endpoint: " .. name)
endpoints[name] = spec
end
end

--------------------------------------------------
-- global budget governor

local budget = { Tokens = 10, Capacity = 0, Rate = 0, Last = serverStart, PerMinute = 0 }
local coldStart = true
local lastBudgetWarn = 0

local function effectivePerMinute()
if coldStart and os.clock() - serverStart < Config.RampUpMinutes * 60 then
return Config.ColdStartPerMinute
end

coldStart = false
return Config.BudgetPerMinute
end

local function refillBudget()
local perMinute = effectivePerMinute()

if perMinute ~= budget.PerMinute then
budget.PerMinute = perMinute
budget.Capacity = perMinute
budget.Rate = perMinute / 60
end

local now = os.clock()
local elapsed = now - budget.Last

if elapsed > 0 then
budget.Tokens = math.min(budget.Capacity, budget.Tokens + elapsed * budget.Rate)
budget.Last = now
end

if budget.Tokens < budget.Capacity * 0.2 and os.clock() - lastBudgetWarn > 60 then
lastBudgetWarn = os.clock()
warn(("[PULSE] HTTP budget running low (%d/%d left this window)"):format(math.floor(budget.Tokens), budget.Capacity))
end
end

local function trySpendBudget()
refillBudget()

if budget.Tokens >= 1 then
budget.Tokens -= 1
return true
end

return false
end

local function spendWithWait(maxWait)
local waited = 0

while waited <= maxWait do
if trySpendBudget() then
return true
end

task.wait(0.25)
waited += 0.25
end

return false
end

--------------------------------------------------
-- request core

local stats = { Sent = 0, Failed = 0, Dropped = 0, Deduped = 0 }
local queue = {}
local workerActive = false

local function decodeBody(body)
if type(body) == "string" and body:sub(1, 1):match("[{%[]") then
local ok, decoded = pcall(HttpService.JSONDecode, HttpService, body)
if ok then
return decoded
end
end

return body
end

local function buildRequest(endpoint, body)
local request = {
Url = endpoint.Url,
Method = endpoint.Method or "GET",
Headers = endpoint.Headers or {},
}

if body ~= nil then
if type(body) == "table" then
request.Headers["Content-Type"] = request.Headers["Content-Type"] or "application/json"
request.Body = HttpService:JSONEncode(body)
else
request.Body = tostring(body)
end
end

return request
end

local function performRequest(request, options)
local attempt = 0

while true do
-- every physical attempt costs budget; sync callers bail out after a
-- short wait, queued jobs override BudgetWait so they simply wait
if not spendWithWait(options.BudgetWait or 2) then
return false, "BUDGET_EXHAUSTED"
end

local ok, response = pcall(function()
return HttpService:RequestAsync(request)
end)

if ok and response.Success then
stats.Sent += 1
return true, decodeBody(response.Body)
end

local status = if ok then response.StatusCode else 0
local reason = if ok then "HTTP_" .. status else "NETWORK_ERROR"
local permanent = ok and status >= 400 and status < 500 and status ~= 429

if permanent or attempt >= (options.Retries or Config.MaxRetries) then
stats.Failed += 1
return false, reason
end

task.wait((options.RetryBaseDelay or Config.RetryBaseDelay) * 2 ^ attempt)
attempt += 1
end
end

local inFlight = {}

-- identical in-flight GETs share one request; waiters yield on a signal
local function performDeduped(name, request, options)
local key = name .. "\1" .. request.Method .. "\1" .. tostring(request.Body)

local entry = inFlight[key]
if entry then
stats.Deduped += 1
return entry.signal:Wait()
end

entry = { signal = Signal.new() }
inFlight[key] = entry

local ok, data = performRequest(request, options)

inFlight[key] = nil
entry.signal:Fire(ok, data)

return ok, data
end

local Http = {}

function Http.IsEnabled()
return HttpService.HttpEnabled and Config.Enabled
end

function Http.GetStats()
refillBudget()

return {
Sent = stats.Sent,
Failed = stats.Failed,
Dropped = stats.Dropped,
Deduped = stats.Deduped,
Queued = #queue,
BudgetRemaining = math.floor(budget.Tokens),
BudgetPerMinute = budget.PerMinute,
ColdStart = coldStart,
}
end

-- yielding request: validates, rate-limits, retries. Returns ok, data/reason.
function Http.Request(name, body, options)
assert(type(name) == "string", "Endpoint name must be a string")

local endpoint = endpoints[name]
assert(endpoint ~= nil, "Unknown endpoint '" .. name .. "' — declare it in Pulse/Http/Config")

if not Config.Enabled or not HttpService.HttpEnabled then
return false, "HTTP_DISABLED"
end

if not endpoint.Url or endpoint.Url == "" then
return false, "NOT_CONFIGURED"
end

if not limiter:Allow("Server", name, { Count = endpoint.Rate or Config.DefaultRate, Window = 1 }) then
return false, "RATE_LIMITED"
end

local request = buildRequest(endpoint, body)

if Config.DedupeGets and (request.Method == "GET" or endpoint.Dedupe) then
return performDeduped(name, request, options)
end

return performRequest(request, options or {})
end

--------------------------------------------------
-- outbound queue (never blocks the caller)

local function runJob(job)
local options = job.Options or {}
options.BudgetWait = options.BudgetWait or 30

local request = buildRequest(job.Endpoint, job.Body)
local ok, data = performRequest(request, options)

if job.Callback then
task.spawn(job.Callback, ok, data)
end
end

local function ensureWorker()
if workerActive then return end

workerActive = true

task.spawn(function()
while #queue > 0 do
-- serial drain; runJob blocks on budget so the queue paces itself
runJob(table.remove(queue, 1))
end

workerActive = false
end)
end

-- fire-and-forget: returns immediately; callback(ok, data) fires on completion
function Http.Queue(name, body, callback, options)
assert(type(name) == "string", "Endpoint name must be a string")

local endpoint = endpoints[name]
assert(endpoint ~= nil, "Unknown endpoint '" .. name .. "' — declare it in Pulse/Http/Config")

if not Config.Enabled or not HttpService.HttpEnabled then
if callback then task.spawn(callback, false, "HTTP_DISABLED") end
return false, "HTTP_DISABLED"
end

if #queue >= Config.MaxQueueSize then
stats.Dropped += 1

if callback then
task.spawn(callback, false, "QUEUE_FULL")
end

return false, "QUEUE_FULL"
end

queue[#queue + 1] = { Name = name, Endpoint = endpoint, Body = body, Callback = callback, Options = options }
ensureWorker()

return true
end

return Http