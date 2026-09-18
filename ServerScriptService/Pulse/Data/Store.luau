--[[
Pulse Server / Data / Store
Raw DataStore access. Every write goes through UpdateAsync (never
SetAsync) so the session lock is verified inside the same atomic
operation — two servers can never both "own" a player'"'"'s data, which is
what prevents duplication exploits after fast rejoins or crashes.

Session lock: on load we claim { JobId, Until } inside the payload; on
every save we re-verify the lock is still ours before writing; locks
from dead sessions expire after Config.SessionLockTimeout and may be
stolen. All calls retry with backoff (budget: 60 + 10 x players/min).
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local Config = require(script.Parent.Config)

local store = DataStoreService:GetDataStore(Config.DataStoreName)
local jobId = if game.JobId ~= "" then game.JobId else "Studio-" .. HttpService:GenerateGUID(false)

local MAX_RETRIES = 3
local RETRY_DELAY = 1

local Store = {}

function Store.JobId()
return jobId
end

local function withRetries(fn)
local attempt = 0

while true do
local ok, result = pcall(fn)

if ok then
return true, result
end

attempt += 1

if attempt >= MAX_RETRIES then
return false, result
end

task.wait(RETRY_DELAY * 2 ^ (attempt - 1))
end
end

-- true, data — lock claimed | false, "LOCKED" | false, "ERROR"
function Store.Load(userId)
local key = "Player_" .. userId

local ok, result = withRetries(function()
local claimed = nil
local locked = false

store:UpdateAsync(key, function(payload)
payload = payload or {}

local lock = payload.Lock
if lock and lock.JobId ~= jobId and os.time() < (lock.Until or 0) then
locked = true
return nil -- another live session owns it; write nothing
end

payload.Version = payload.Version or Config.Version
payload.Data = payload.Data or {}
payload.UpdatedAt = os.time()
payload.Lock = { JobId = jobId, Until = os.time() + Config.SessionLockTimeout }

claimed = payload
return payload
end)

return if locked then "LOCKED" else claimed
end)

if not ok then return false, "ERROR" end
if result == "LOCKED" or result == nil then return false, "LOCKED" end

return true, result.Data
end

-- true — saved | false, "LOCK_LOST" — another server took over | false, "ERROR"
function Store.Save(userId, data)
local key = "Player_" .. userId

local ok, result = withRetries(function()
local lockLost = false
local saved = false

store:UpdateAsync(key, function(payload)
payload = payload or {}

local lock = payload.Lock
if lock and lock.JobId ~= jobId and os.time() < (lock.Until or 0) then
lockLost = true
return nil -- we no longer own this session; write nothing
end

payload.Data = data
payload.Version = Config.Version
payload.UpdatedAt = os.time()
payload.Lock = { JobId = jobId, Until = os.time() + Config.SessionLockTimeout }

saved = true
return payload
end)

return if lockLost then "LOCK_LOST" else saved
end)

if not ok then return false, "ERROR" end
if result == "LOCK_LOST" then return false, "LOCK_LOST" end

return true
end

-- final save + lock release
function Store.Release(userId, data)
local key = "Player_" .. userId

local ok = withRetries(function()
store:UpdateAsync(key, function(payload)
payload = payload or {}

local lock = payload.Lock
if lock and lock.JobId ~= jobId then
return nil -- not ours anymore; leave it untouched
end

payload.Data = data
payload.Version = Config.Version
payload.UpdatedAt = os.time()
payload.Lock = nil

return payload
end)
end)

return ok
end

return Store