--[[
Pulse Server / Data / Cloud
Read and write player data from OUTSIDE the game: a dashboard, a bot, or
your own server. This lets you control data offline, while the game is
not running.

It talks to the SAME DataStore the game uses, through Roblox Open Cloud
(standard datastore REST API). Data for a player lives under the key:
    Player_<userId>  ->  { Data = { ... }, Version, Lock, UpdatedAt }
A dashboard can read or edit player.Data without the game being online.

Setup (also in the README):
  1. Creator Dashboard > your experience > ACCESS > enable Open Cloud.
  2. Create an "Experience" API key, choose Standard DataStore, and
     scope it to this place/universe.
  3. Put the key in Pulse/Data/Config > OpenCloud.ApiKey and set
     OpenCloud.Enabled = true.

WARNING: only edit data while the player is OFFLINE (or no live server
holds their session). If they are online, that server'"'"'s autosave will
overwrite an external write.

All requests are pcall-wrapped. A bad key, wrong scopes, or Open Cloud
being off just returns false + a message; it never crashes anything.
]]

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

if not RunService:IsServer() then
error("[PULSE] Cloud can only be used on the server")
end

local Config = require(script.Parent.Config)

local BASE = "https://apis.roblox.com/datastores/v1/universes/" .. tostring(game.GameId) .. "/standard-datastores"
local DATASTORE = Config.DataStoreName

local Cloud = {}

local function keyFor(userId)
return "Player_" .. userId
end

local function configured()
local oc = Config.OpenCloud
return oc ~= nil and oc.Enabled == true and oc.ApiKey ~= ""
end

local function request(method, url, body)
local attempt = 0

while attempt <= 2 do
local ok, response = pcall(function()
return HttpService:RequestAsync({
Url = url,
Method = method,
Headers = {
["x-api-key"] = Config.OpenCloud.ApiKey,
},
Body = body,
})
end)

if ok and response.Success then
return true, response
end

attempt += 1

if attempt > 2 then
local status = if ok then response.StatusCode else "network"
return false, "cloud_" .. tostring(status)
end

task.wait(0.5 * attempt)
end

return false, "cloud_network"
end

local function getEntryUrl(key)
return BASE .. "/datastore/entries/key?datastoreName=" .. DATASTORE .. "&entryKey=" .. key
end

-- ok, envelope | ok=false, err
function Cloud.Read(userId)
if not configured() then
return false, "cloud_not_configured"
end

local ok, res = request("GET", getEntryUrl(keyFor(userId)))

if not ok then
return false, res
end

if res.Body == "null" or res.Body == "" then
return true, nil -- no record yet
end

-- the REST API returns the value as a JSON string inside a JSON envelope
local parsed = HttpService:JSONDecode(res.Body)
local inner = parsed and parsed.data

if type(inner) ~= "string" then
return false, "cloud_bad_payload"
end

local ok2, envelope = pcall(HttpService.JSONDecode, HttpService, inner)

if not ok2 then
return false, "cloud_bad_payload"
end

return true, envelope
end

-- writes the full envelope (data + version + lock) for a player
function Cloud.Write(userId, envelope)
if not configured() then
return false, "cloud_not_configured"
end

local key = keyFor(userId)

local ok, res = request("POST", getEntryUrl(key), HttpService:JSONEncode({
datastoreName = DATASTORE,
entryKey = key,
data = HttpService:JSONEncode(envelope),
exclusiveCreate = false,
}))

if not ok then
return false, res
end

return true
end

-- turn a plain Data table into a full envelope shape, keeping defaults
local function wrap(userId, data)
return {
Data = data,
Version = 1,
UpdatedAt = os.time(),
Lock = nil,
}
end

-- read, optionally edit, and write back, all in one call. fn(envelope) to edit.
function Cloud.Update(userId, fn)
local ok, envelope = Cloud.Read(userId)

if not ok then
return false, envelope
end

envelope = envelope or wrap(userId, {})

if fn then
envelope = fn(envelope) or envelope
end

return Cloud.Write(userId, envelope)
end

-- convenience: set a few fields and keep the rest
function Cloud.Merge(userId, fields)
return Cloud.Update(userId, function(envelope)
for field, value in fields do
envelope.Data[field] = value
end
end)
end

function Cloud.Enabled()
return configured()
end

return Cloud