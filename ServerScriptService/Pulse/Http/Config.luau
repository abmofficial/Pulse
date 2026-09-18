--[[
	SERVER ONLY. Holds all your webhooks and API endpoints, and the keys for
	them. Clients can never read this file, which is the point.

	Channel config (in ReplicatedStorage) is safe for clients to see. This
	file is different: if a client could read it they would have your webhook
	URLs and API keys.

	Adding an endpoint:
	    Endpoints.MyApi = {
	        Url = "https://api.example.com/v1/thing",
	        Method = "POST",                    -- default is GET
	        Headers = { Authorization = "Bearer ..." },
	        Rate = 5,                           -- max requests per second
	        Dedupe = true,                      -- share identical in-flight calls
	    }

	Calling it from server code:
	    local Http = require(game:GetService("ServerScriptService").Pulse.Http.Http)
	    local ok, data = Http.Request("MyApi", { hello = "world" })
	    Http.Queue("MyApi", { hello = "world" }, callback)   -- does not block

	Only endpoints listed here can be called. Anything else is an error.
	The wrapper also watches the total request budget (Roblox allows 500
	requests per minute per server) so you do not trip the limit by accident.
]]

local Config = {
	Enabled = true,

	-- Total requests per minute we let the whole server make. Keep it below
	-- 500, which is Roblox's real cap. Fresh servers start lower and ramp
	-- up over the first minutes.
	BudgetPerMinute = 300,
	ColdStartPerMinute = 60,
	RampUpMinutes = 3,

	-- Http.Queue buffers this many jobs. Extra ones are dropped and the
	-- callback gets a QUEUE_FULL error.
	MaxQueueSize = 100,

	-- Share identical in-flight GET requests between callers.
	DedupeGets = true,

	MaxRetries = 2,
	RetryBaseDelay = 0.5,
	DefaultRate = 10,

	Endpoints = {
		-- Used by Pulse's own security webhook logger (kick logs).
		PulseWebhook = {
			Url = "YOUR_DISCORD_WEBHOOK",
			Method = "POST",
			Rate = 5,
		},

		-- Your endpoints go here. Example (commented):
		-- MyApi = {
		--     Url = "https://api.example.com/v1/status",
		-- },
	},

	-- Optional: feature modules can declare endpoints in their own files.
	-- List the ModuleScript here and it merges into Endpoints above.
	Groups = {},
}

return Config
