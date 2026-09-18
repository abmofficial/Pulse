--[[
SERVER ONLY. Clients never see this file.

This is what player data looks like, and what the rules are for changing
it. The client cannot change data directly. It can only ask, and every
ask is checked against these rules on the server first.

Start with the Template. Add one field to the Template and one matching
rule to Fields, and repeat. Every Template field needs a rule in Fields.

Field options:
    Type           number, string, boolean, or table
    Min / Max      lower and upper bound. Used to clamp numbers.
    MaxString      max length of a string. Default 100.
    Keys           required for table fields. A whitelist of child rules.
    ClientWritable true = the player may ask to change this field through
                   DataSet / DataIncrement. Leave it out and only server
                   code can change the field; client asks get rejected
                   and flagged. Rule of thumb: money and stats stay
                   server-only.
    IncrementOnly  true = the player can only make a number go up, never
                   down.
    DeltaCap       the most a player may change a number by in one ask.

Example, step by step.
Want a field called "Coins" that:
    - starts at 0
    - is a number
    - never goes below 0
    - the player can increase, but only by 100 or less at a time

Template:  Coins = 0,
Fields:    Coins = {
               Type = "number",
               Min = 0,
               ClientWritable = true,
               IncrementOnly = true,
               DeltaCap = 100,
           }

Server-only edits (no limits, trusted):
    local Data = require(game.ServerScriptService.Pulse.Data.Profiles)
    local profile = Data.Get(player)
    profile.Data.Coins += 500
    Data.Push(player, "Coins")   -- send the new value to the player'"'"'s UI
]]

local Config = {
-- Name of the DataStore that holds all player data.
DataStoreName = "PulsePlayerData",

-- Bump this if you change the schema and need to migrate old records.
Version = 1,

-- Seconds between saves per player. Lower is safer but uses more
-- DataStore requests.
AutoSaveInterval = 120,
-- Seconds to wait if another server still holds the session before
-- kicking the player.
LoadTimeout = 30,
-- Seconds before a crashed server'"'"'s session lock can be taken over.
SessionLockTimeout = 90,
LoadRetryDelay = 3,

-- Debug configuration
Debug = {
	-- Enable verbose logging for debugging purposes
	Enabled = false,
	-- Log all incoming/outgoing packets (can be very verbose)
	LogPackets = false,
	-- Log all validation failures
	LogValidationFailures = false,
	-- Log all security violations with extra detail
	LogSecurityDetails = false,
	-- Enable additional consistency checks
	ConsistencyChecks = false,
	-- Show debug information in warnings
	VerboseWarnings = false,
},

FlagInvalidMutations = true,

-- What a brand new player starts with. Every field here needs a rule
-- in Fields below.
Template = {
Money = 0,
Bank = 0,
Coins = 0,
Level = 1,
Settings = {
Music = true,
Quality = "Auto",
},
},

Fields = {
-- Server-only stats. No ClientWritable, so client asks are rejected.
Money = { Type = "number", Min = 0, Max = 1e15 },
Bank = { Type = "number", Min = 0, Max = 1e15 },
Level = { Type = "number", Min = 1, Max = 10000 },

-- Player can ask to increase, by 100 or less at a time, never down.
Coins = {
Type = "number",
Min = 0,
Max = 1e15,
ClientWritable = true,
IncrementOnly = true,
DeltaCap = 100,
},

-- Table field: only these exact keys are allowed, with these types.
Settings = {
Type = "table",
ClientWritable = true,
Keys = {
Music = { Type = "boolean" },
Quality = { Type = "string", MaxString = 16 },
},
},
},

-- ------------------------------------------------------------------
-- Optional: edit player data from OUTSIDE the game. This bridges to
-- Roblox Open Cloud, so a dashboard, a bot, or your own server can
-- read and write the same data while the game is offline. See the
-- README, section OPEN CLOUD, for the full setup.
-- You need: Open Cloud enabled for the place, and an "Experience"
-- API key with Standard DataStore scope. Paste it here, set Enabled=true.
OpenCloud = {
Enabled = false,
ApiKey = "",
},
}

return Config