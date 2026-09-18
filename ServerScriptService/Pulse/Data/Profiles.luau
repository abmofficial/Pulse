--[[
Pulse Server / Data / Profiles
Profile manager: session-locked loading, autosave, shutdown safety, and
the server-validated mutation handlers behind the DataSet /
DataIncrement requests.

The cheat path is closed like this: a client can only ASK the server to
change whitelisted fields, through Pulse channels (rate-limited,
anti-exploit-watched), and every request passes the schema validators
here. Fields without ClientWritable = true cannot be touched by a
client at all — server code edits them directly via Profiles.Get().

Server API:
Profiles.Ready:Connect(function(player) ... end)   -- data usable
local profile = Profiles.Get(player)               -- { Data = {...} }
profile.Data.Money += 100                          -- trusted, no validation
Profiles.Push(player, "Money")                     -- sync value to client

Client API (through Pulse, validated):
Pulse.Requests.DataIncrement:AskServer({ Field = "Coins", Delta = 10 })
Pulse.Requests.DataSet:AskServer({ Field = "Settings", Value = { Music = false, Quality = "High" } })
Pulse.Events.DataSync:Listen(function(payload) ... end) -- live updates
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Pulse.Core.Utilities.Signal)
local Pulse = require(ReplicatedStorage.Pulse)
local AntiExploit = require(script.Parent.Parent.Security.AntiExploit)
local Config = require(script.Parent.Config)
local Store = require(script.Parent.Store)
local Validate = require(script.Parent.Validate)

local Profiles = {}
Profiles.Ready = Signal.new()

local loaded = {}

local function deepCopy(value)
local copy = {}

for key, child in value do
copy[key] = if type(child) == "table" then deepCopy(child) else child
end

return copy
end

local function reconcileTable(data, defaults)
for key, default in defaults do
if data[key] == nil then
data[key] = if type(default) == "table" then deepCopy(default) else default
elseif type(data[key]) == "table" and type(default) == "table" then
reconcileTable(data[key], default)
end
end
end

local function reconcile(data)
reconcileTable(data, Config.Template)
end

local function pushField(player, field)
local profile = loaded[player]

if profile then
Pulse.Events.DataSync:SendClient(player, { Field = field, Value = profile.Data[field] })
end
end

local function pushSnapshot(player)
local profile = loaded[player]

if profile then
Pulse.Events.DataSync:SendClient(player, { Snapshot = profile.Data })
end
end

local function flagInvalid(player, reason)
if Config.FlagInvalidMutations then
AntiExploit:Report(player, reason, "Low")
end
end

local function finiteNumber(value)
return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

--------------------------------------------------
-- load / save lifecycle

local function loadProfile(player)
local waited = 0
local data = nil
local ephemeral = false

while true do
local ok, result = Store.Load(player.UserId)

if ok then
data = result
break
end

if result == "ERROR" then
-- datastore unavailable (API off in Studio, platform outage):
-- keep the game playable with session-only data instead of
-- locking everyone out
warn("[PULSE] DataStore unavailable — using session-only data for " .. player.Name)
ephemeral = true
data = deepCopy(Config.Template)
break
end

-- LOCKED: the previous session is still saving
waited += Config.LoadRetryDelay

if waited >= Config.LoadTimeout or not player.Parent then
if player.Parent then
player:Kick("[PULSE] Your data is still saving — please rejoin in a moment.")
end
return
end

task.wait(Config.LoadRetryDelay)
end

if not player.Parent then return end

reconcile(data)
loaded[player] = { Data = data, Ephemeral = ephemeral }

Profiles.Ready:Fire(player)
pushSnapshot(player)

task.spawn(function()
while loaded[player] and player.Parent do
task.wait(Config.AutoSaveInterval)

local profile = loaded[player]
if not profile or profile.Ephemeral then break end

local ok, reason = Store.Save(player.UserId, profile.Data)

if not ok and reason == "LOCK_LOST" then
warn("[PULSE] Session lock lost for " .. player.Name .. " — another server took over")
loaded[player] = nil
break
end
end
end)
end

local function saveAndRelease(player)
local profile = loaded[player]
if not profile or profile.Released then return end

if not profile.Ephemeral then
local ok = Store.Release(player.UserId, profile.Data)

if not ok then
warn("[PULSE] Failed to release data session for " .. player.Name)
end
end

profile.Released = true
loaded[player] = nil
end

--------------------------------------------------
-- validated client mutations

Pulse.Requests.DataSet:Handle(function(player, payload)
local profile = loaded[player]
if not profile then return false end

if type(payload) ~= "table" or type(payload.Field) ~= "string" then
flagInvalid(player, "Malformed Data Mutation")
return false
end

local rules = Config.Fields[payload.Field]

if not rules or not rules.ClientWritable then
flagInvalid(player, "Forbidden Field Write: " .. tostring(payload.Field))
return false
end

if rules.Type == "number" and rules.IncrementOnly then
flagInvalid(player, "Absolute Set on IncrementOnly: " .. payload.Field)
return false
end

if not Validate.Value(rules, payload.Value) then
flagInvalid(player, "Invalid Value: " .. payload.Field)
return false
end

profile.Data[payload.Field] = payload.Value
pushField(player, payload.Field)

return true
end)

Pulse.Requests.DataIncrement:Handle(function(player, payload)
local profile = loaded[player]
if not profile then return false end

if type(payload) ~= "table" or type(payload.Field) ~= "string" then
flagInvalid(player, "Malformed Data Mutation")
return false
end

local rules = Config.Fields[payload.Field]

if not rules or not rules.ClientWritable or rules.Type ~= "number" then
flagInvalid(player, "Forbidden Field Increment: " .. tostring(payload.Field))
return false
end

if not finiteNumber(payload.Delta) then
flagInvalid(player, "Invalid Delta: " .. payload.Field)
return false
end

local delta = payload.Delta

if rules.IncrementOnly and delta <= 0 then
flagInvalid(player, "Negative Increment: " .. payload.Field)
return false
end

if rules.DeltaCap and math.abs(delta) > rules.DeltaCap then
flagInvalid(player, "Delta Over Cap: " .. payload.Field)
return false
end

local newValue = (profile.Data[payload.Field] or 0) + delta

if rules.Min and newValue < rules.Min then newValue = rules.Min end
if rules.Max and newValue > rules.Max then newValue = rules.Max end

profile.Data[payload.Field] = newValue
pushField(player, payload.Field)

return true
end)

--------------------------------------------------
-- public API

-- nil until the player'"'"'s data is loaded
function Profiles.Get(player)
return loaded[player]
end

-- pushes one field'"'"'s current value to the player (call after server-side edits)
function Profiles.Push(player, field)
pushField(player, field)
end

local started = false

function Profiles.Start()
if started then return end
started = true

for name, rules in Config.Fields do
if rules.Type == "table" then
assert(rules.Keys, "Table field needs Keys: " .. name)
end
end

for _, player in Players:GetPlayers() do
task.spawn(loadProfile, player)
end

Players.PlayerAdded:Connect(function(player)
task.spawn(loadProfile, player)
end)

Players.PlayerRemoving:Connect(saveAndRelease)

game:BindToClose(function()
-- shutdown safety net: the PlayerRemoving thread can be killed
-- mid-save when the session ends, so anything not yet released
-- gets saved here (profiles stay in `loaded` until they are)
for player, profile in loaded do
if not profile.Released and not profile.Ephemeral then
Store.Release(player.UserId, profile.Data)
profile.Released = true
end
end
end)
end

return Profiles