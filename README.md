# Pulse Networking System

A robust, secure, and high-performance networking framework for Roblox games featuring client-server communication, data persistence, security measures, and HTTP integration.

## Features

- **Reliable & Unreliable Channels**: Choose between guaranteed delivery or low-latency messaging
- **Automatic Batching**: Coalesces multiple messages into single packets for efficiency
- **Rate Limiting & Flood Protection**: Built-in anti-abuse measures at global and per-channel levels
- **Data Persistence**: Secure player data storage with session locking and conflict resolution
- **HTTP Integration**: Server-only HTTP client with budget management, deduplication, and queuing
- **Security Framework**: Violation scoring, automatic kicking, and webhook logging
- **Type-Safe Serialization**: Compact binary protocol with type tagging and validation
- **Session Management**: Automatic data loading, saving, and conflict resolution

## Installation

Pulse is designed to work with [Rojo](https://rojo.space) for seamless synchronization between your file system and Roblox Studio.

### Prerequisites
- [Rojo 7+](https://github.com/rojo-rbx/rojo/releases)
- [Aftman](https://github.com/rojo-rbx/aftman) (for dependency management)

### Setup
1. Clone this repository or copy the Pulse folder structure into your project
2. Ensure your `default.project.json` matches the structure below
3. Run `rojo serve` to start the synchronization server
4. Connect Roblox Studio to the Rojo server at `localhost:34872`

## Project Structure

```
Pulse/
├── ReplicatedStorage/
│   └── Pulse/
│       ├── init.luau          # Main module (merged with folder)
│       ├── Core/
│       │   ├── Channels/      # Event/Request/LocalEvent/LocalFunction implementations
│       │   ├── Config/        # Constants and Definitions
│       │   ├── Serialization/ # Packet encoding/decoding utilities
│       │   └── Utilities/     # Signal, RateLimiter, PayloadValidator
│       └── Runtime/           # Transport, Registry, Dispatcher, Batcher
├── ServerScriptService/
│   └── Pulse/
│       ├── BootStrap.server.luau    # Server initialization
│       ├── Data/                    # Player data persistence
│       │   ├── Cloud.luau           # Open Cloud integration
│       │   ├── Config.luau          # Data schema and rules
│       │   ├── Profiles.luau        # Profile manager
│       │   ├── Store.luau           # DataStore access layer
│       │   └── Validate.luau        # Input validation
│       ├── Http/                    # Server-only HTTP client
│       │   ├── Config.luau          # HTTP configuration
│       │   └── Http.luau            # HTTP client with budget management
│       ├── Logging/
│       │   └── Webhook.luau         # Discord webhook logger
│       └── Security/                # Anti-exploit and inbound guard
│           ├── AntiExploit.luau
│           └── InboundGuard.luau
└── StarterPlayer/
    └── StarterPlayerScripts/
        └── Pulse/
            └── BootStrap.client.luau  # Client initialization
```

## Quick Start Guide

### 1. Defining Network Channels

Edit `ReplicatedStorage/Pulse/Core/Config/Definitions.luau` to define your events and requests:

```lua
local Definitions = {
	Events = {
		-- Required: Pulse data layer (do not remove)
		{ "DataSync", Rate = 60 },

		-- Example events:
		{ "PlayerJoined", Rate = 5 },           -- Reliable, 5/sec
		{ "ChatMessage", Unreliable = true, Rate = 20 }, -- Unreliable, 20/sec
		{ "PositionUpdate", Unreliable = true, Batch = true, Rate = 30 }, -- Batched
	},

	Requests = {
		-- Required: Pulse data layer (do not remove)
		{ "DataSet", Rate = 10 },
		{ "DataIncrement", Rate = 10 },

		-- Example requests:
		{ "PurchaseItem", Rate = 2, Timeout = 10 }, -- With timeout
		{ "GetPlayerStats", Rate = 5 },             -- Simple request
	},

	LocalEvents = {
		-- Events that fire locally (no network)
		{ "UIUpdated" },
		{ "InventoryChanged" },
	},

	LocalFunctions = {
		-- Functions callable locally (no network)
		{ "CalculateDamage" },
		{ "FormatCurrency" },
	},

	Groups = {
		-- Optional: Group related endpoints in separate modules
		-- { "CombatGroup", require(someModule) },
	},
}

return Definitions
```

### 2. Using Events (One-Way Communication)

#### Server to Client
```lua
-- Server-side
local Pulse = require(game:GetService("ReplicatedStorage").Pulse)

-- Send to specific player
Pulse.Events.ChatMessage:SendClient(player, "Hello world!")

-- Broadcast to all players
Pulse.Events.PositionUpdate:Broadcast({ x = 10, y = 5, z = 0 })

-- Listen for events
Pulse.Events.PlayerJoined:Listen(function(player)
	print(player.Name .. " has joined the game!")
end)
```

#### Client to Server
```lua
-- Client-side
local Pulse = require(game:GetService("ReplicatedStorage").Pulse)

-- Send to server
Pulse.Events.PlayerJoined:SendServer()
Pulse.Events.ChatMessage:SendServer("Hello from client!")

-- Listen for server events
Pulse.Events.PositionUpdate:Listen(function(data)
	-- Update local player position
	local character = game.Players.LocalPlayer.Character
	if character then
		character:SetPrimaryPartCFrame(CFrame.new(data.x, data.y, data.z))
	end
end)
```

### 3. Using Requests (Two-Way Communication)

#### Server Handling Requests
```lua
-- Server-side
local Pulse = require(game:GetService("ReplicatedStorage").Pulse)

-- Handle request with callback
Pulse.Requests.PurchaseItem:Handle(function(player, itemId, amount)
	-- Validate purchase
	if CanAfford(player, itemId, amount) then
		GiveItem(player, itemId, amount)
		return true, "Purchase successful!"
	else
		return false, "Insufficient funds"
	end
end)

-- Or use AskServer for immediate response
local success, message = Pulse.Requests.PurchaseItem:AskServer(player, "sword", 1)
if success then
	print(message)
else
	warn("Purchase failed: " .. message)
end
```

#### Client Making Requests
```lua
-- Client-side
local Pulse = require(game:GetService("ReplicatedStorage").Pulse)

-- Ask server and wait for response
local success, result = Pulse.Requests.GetPlayerStats:AskServer()
if success then
	print("Player level:", result.Level)
	print("Player coins:", result.Coins)
else
	warn("Failed to get stats: " .. tostring(result))
end

-- Fire-and-forget (no response needed)
Pulse.Requests.PurchaseItem:AskServer("health_potion", 2)
```

### 4. Local Events & Functions (Same-Context Communication)

```lua
-- LocalEvent (like BindableEvent)
local Pulse = require(game:GetService("ReplicatedStorage").Pulse)

-- Fire event
Pulse.LocalEvents.UIUpdated:Send({ screen = "Inventory", open = true })

-- Listen for event
Pulse.LocalEvents.UIUpdated:Listen(function(data)
	if data.screen == "Inventory" then
		InventoryGui.Visible = data.open
	end
end)

-- LocalFunction (like BindableFunction)
-- Register handler
Pulse.LocalFunctions.CalculateDamage:Handle(function(attacker, defender, weapon)
	return weapon.BaseDamage * attacker.StrengthMultiplier
end)

-- Call function
local damage = Pulse.LocalFunctions.CalculateDamage:Call(player, enemy, sword)
```

### 5. Player Data Persistence

The Pulse data system provides secure, validated player data storage.

#### Server-Side Data Access
```lua
local Pulse = require(game:GetService("ReplicatedStorage").Pulse)

-- Get player profile (nil until data is loaded)
local function onPlayerAdded(player)
	Pulse.Profiles.Ready:Connect(function()
		local profile = Pulse.Profiles.Get(player)
		if profile then
			-- Safe to access profile.Data
			local money = profile.Data.Money
			local level = profile.Data.Level
			
			-- Modify data (trusted server code)
			profile.Data.Money += 100
			
			-- Sync change to client
			Pulse.Profiles.Push(player, "Money")
		end
	end)
	
	-- Start loading profile for this player
	Pulse.Profiles.Start() -- Call once at game start
end

game.Players.PlayerAdded:Connect(onPlayerAdded)
```

#### Client Requesting Data Changes
```lua
-- Client-side (through validated requests)
local Pulse = require(game:GetService("ReplicatedStorage").Pulse)

-- Request to change a ClientWritable field
local success = Pulse.Requests.DataSet:AskServer({
	Field = "Coins",
	Value = 150
})

if success then
	print("Coin update requested!")
else
	warn("Server rejected coin update request")
end

-- Request to increment a field (with validation)
local success = Pulse.Requests.DataIncrement:AskServer({
	Field = "Coins",
	Delta = 50 -- Will be validated against rules
})

-- Listen for data sync events
Pulse.Events.DataSync:Listen(function(payload)
	if payload.Field then
		-- Single field update
		print("Field updated:", payload.Field, "=", payload.Value)
	elseif payload.Snapshot then
		-- Full data snapshot
		print("Received full data snapshot:")
		for field, value in pairs(payload.Snapshot) do
			print("  ", field, "=", value)
		end
	end
end)
```

#### Data Schema Configuration
Edit `ServerScriptService/Pulse/Data/Config.luau` to define your data structure:

```lua
local Config = {
	DataStoreName = "MyGamePlayerData", -- Change to your DataStore name
	Version = 2, -- Increment when changing schema
	AutoSaveInterval = 120, -- Seconds between saves
	LoadTimeout = 30, -- Seconds to wait for session lock
	SessionLockTimeout = 90, -- Seconds before taking over dead session
	LoadRetryDelay = 3, -- Seconds between load retries
	FlagInvalidMutations = true, -- Log invalid client attempts

	Template = {
		-- Default values for new players
		Money = 0,
		Bank = 0,
		Coins = 0,
		Level = 1,
		Experience = 0,
		Inventory = {
			-- Example: starting with basic items
			WoodSword = 1,
			LeatherArmor = 1,
		},
		Settings = {
			MusicVolume = 0.8,
			SFXVolume = 0.6,
			GraphicsQuality = "Medium",
		},
	},

	Fields = {
		-- Server-only fields (ClientWritable = false)
		Money = { Type = "number", Min = 0 },
		Bank = { Type = "number", Min = 0 },
		Level = { Type = "number", Min = 1, Max = 100 },
		Experience = { Type = "number", Min = 0 },

		-- Client-writable fields (with validation)
		Coins = {
			Type = "number",
			Min = 0,
			ClientWritable = true,
			IncrementOnly = true, -- Can only increase
			DeltaCap = 100, -- Max change per request
		},
		
		Experience = {
			Type = "number",
			Min = 0,
			ClientWritable = true,
			DeltaCap = 50,
		},
		
		Inventory = {
			Type = "table",
			ClientWritable = true,
			Keys = { -- Whitelist of allowed item types
				WoodSword = { Type = "number", Min = 0 },
				IronSword = { Type = "number", Min = 0 },
				LeatherArmor = { Type = "number", Min = 0 },
				IronArmor = { Type = "number", Min = 0 },
				HealthPotion = { Type = "number", Min = 0, Max = 10 },
			},
		},
		
		Settings = {
			Type = "table",
			ClientWritable = true,
			Keys = {
				MusicVolume = { Type = "number", Min = 0, Max = 1 },
				SFXVolume = { Type = "number", Min = 0, Max = 1 },
				GraphicsQuality = { Type = "string", MaxString = 10 },
			},
		},
	},

	-- Open Cloud configuration (for external data access)
	OpenCloud = {
		Enabled = false, -- Set to true when configured
		ApiKey = "", -- Your Roblox Open Cloud API key
	},
}

return Config
```

### 6. HTTP Integration (Server-Only)

The Pulse HTTP client includes budget management, deduplication, queuing, and retry logic.

#### Configuration
Edit `ServerScriptService/Pulse/Http/Config.luau`:

```lua
local Config = {
	Enabled = true, -- Master switch for HTTP functionality
	
	-- Rate limiting per endpoint (requests per second)
	DefaultRate = 5,
	
	-- Global budget (requests per minute)
	BudgetPerMinute = 300, -- Below Roblox's 500/min limit
	ColdStartPerMinute = 60, -- Starting budget for fresh servers
	RampUpMinutes = 3, -- Minutes to reach full budget
	
	-- Queue settings
	MaxQueueSize = 100, -- Maximum queued requests
	DedupeGets = true, -- Share identical GET requests
	
	-- Retry settings
	MaxRetries = 3,
	RetryBaseDelay = 0.5, -- Seconds
	DefaultRate = 10, -- Fallback rate limit
	
	-- Endpoints (whitelist only)
	Endpoints = {
		-- Security webhook for violation logging
		PulseWebhook = {
			Url = "https://discord.com/api/webhooks/your/webhook/url",
			Method = "POST",
			Rate = 5, -- 5 webhook posts per second max
		},
		
		-- Example API endpoints
		FetchPlayerData = {
			Url = "https://api.example.com/player/data",
			Method = "GET",
			Rate = 2,
		},
		
		SubmitGameEvent = {
			Url = "https://api.example.com/game/event",
			Method = "POST",
			Rate = 1,
		},
	},
	
	-- Optional: feature modules can declare endpoints in their own files
	Groups = {},
}

return Config
```

#### Using the HTTP Client
```lua
-- Server-side only
local Http = require(game:GetService("ServerScriptService").Pulse.Http.Http)

-- Make a request (validated, rate-limited, retried)
local success, data = Http.Request("FetchPlayerData", {
	playerId = tostring(player.UserId)
})

if success then
	local playerData = HttpService:JSONDecode(data)
	-- Process player data
else
	warn("HTTP request failed:", tostring(data))
end

-- Fire-and-forget (queued, non-blocking)
Http.Queue("SubmitGameEvent", {
	eventType = "PlayerDeath",
	playerId = tostring(player.UserId),
	timestamp = os.time()
}, function(ok, response)
	if ok then
		print("Game event submitted successfully")
	else
		warn("Failed to submit game event:", tostring(response))
	end
end)

-- Get HTTP statistics
local stats = Http.GetStats()
print("HTTP Stats:")
print("  Sent:", stats.Sent)
print("  Failed:", stats.Failed)
print("  Queued:", stats.Queued)
print("  Budget remaining:", stats.BudgetRemaining)
```

### 7. Security & Anti-Exploit System

Pulse includes automatic violation scoring, kicking, and webhook logging.

#### Configuration
The security system is configured via constants in the modules:
- `ServerScriptService/Pulse/Security/AntiExploit.luau`:
  - `SEVERITY_WEIGHTS`: Points per violation type
  - `THRESHOLD`: Score threshold for kicking (default: 100)
  - `DECAY_PER_MINUTE`: Points decay over time (default: 40/min)
  - `VIOLATION_SPAM_LIMIT`: Rate limit for warning spam

#### Automatic Protection
- **Global Packet Flood**: Limits total packets per second per player
- **Per-Channel Rate Limits**: Enforces RateLimit from channel definitions
- **Input Validation**: All client requests validated against schema
- **Session Locking**: Prevents data duplication exploits
- **Violation Scoring**: Tracks abuse and kicks when threshold exceeded
- **Webhook Logging**: Sends security events to Discord

#### Custom Security Handling
```lua
-- Override violation handling (optional)
local Pulse = require(game:GetService("ReplicatedStorage").Pulse)

-- Custom violation handler
Pulse:SetViolationHandler(function(player, reason, severity)
	-- Log to your own system
	warn(string.format("[SECURITY] %s: %s (%s)", player.Name, reason, severity))
	
	-- Take custom action (e.g., temporary ban instead of kick)
	if severity == "Critical" then
		-- Implement your own ban system
		BanPlayer(player, 24, reason) -- 24 hour ban
	end
end)

-- Custom inbound guard (optional)
local Pulse = require(game:GetService("ReplicatedStorage").Pulse)
local AntiExploit = require(game:GetService("ServerScriptService").Pulse.Security.AntiExploit)

Pulse:SetInboundGuard(function(player, packetType, channelName, definition)
	-- Custom logic before standard checks
	if player:GetRankInGroup(12345) >= 10 then -- Admin rank
		return true -- Allow admins to bypass rate limits
	end
	
	-- Return false to use standard Pulse checks
	return false
end)
```

### 8. Advanced Features

#### Batching Control
Events can be marked as `Batch = true` in Definitions to enable automatic batching:
```lua
{ "PositionUpdate", Unreliable = true, Batch = true, Rate = 30 }
```
The system will coalesce multiple PositionUpdate events from the same frame into a single packet.

#### Manual Batching
For more control, use the Batcher directly:
```lua
local Pulse = require(game:GetService("ReplicatedStorage").Pulse)

-- Queue multiple updates
Pulse.Runtime.Batcher.Queue("PositionUpdate", player, { x = 10, y = 5, z = 0 })
Pulse.Runtime.Batcher.Queue("PositionUpdate", player, { x = 11, y = 5, z = 0 })
-- Sent automatically on heartbeat
```

#### Custom Transports
Replace the default RemoteEvent/UnreliableRemoteEvent transports:
```lua
-- In Pulse.Runtime.Transport, you could implement:
-- WebSocket-based transport for web games
-- Custom encryption for sensitive data
-- Compression for large payloads
```

## Best Practices

### 1. Security First
- Never trust client data - always validate on server
- Use ClientWritable = false for server-only fields (money, stats, etc.)
- Implement rate limits on all requestable endpoints
- Monitor webhook logs for abuse patterns

### 2. Performance Optimization
- Use Unreliable + Batch for high-frequency data (position, input)
- Keep event payloads small - only send what changed
- Use DataSync events instead of individual field updates when possible
- Monitor HTTP budget with `Http.GetStats()`

### 3. Data Management
- Design your data schema carefully - changing it requires data migration
- Use default values in Template for forward compatibility
- Consider versioning your data format for major changes
- Archive old data instead of deleting when possible

### 4. Development Workflow
- Test with multiple clients to verify synchronization
- Use Studio's output window to monitor Pulse logs
- Check webhook for security events during testing
- Profile performance with Roblox's MicroProfiler

## API Reference

### Pulse Module (ReplicatedStorage.Pulse)
```lua
Pulse.Version           -- string: Current version from Constants
Pulse.IsServer          -- boolean: True if running on server
Pulse.Events            -- table: Event channels by name
Pulse.Requests          -- table: Request channels by name
Pulse.LocalEvents       -- table: LocalEvent instances by name
Pulse.LocalFunctions    -- table: LocalFunction instances by name

Pulse:SetViolationHandler(callback)  -- Set custom violation handler
Pulse:SetInboundGuard(func)          -- Set custom inbound guard function
```

### Event Channel
```lua
Event:SendServer(...)        -- Client → Server
Event:SendClient(player, ...) -- Server → Specific client
Event:Broadcast(...)         -- Server → All clients
Event:Listen(callback)       -- Register listener
Event:Once(callback)         -- Register one-time listener
Event:Wait()                 -- Yield until event fires
```

### Request Channel
```lua
Request:AskServer(...)       -- Client → Server (yields success, result)
Request:AskClient(player, ...) -- Server → Client (yields success, result)
Request:Handle(callback)     -- Set server handler
Request:Unhandle()           -- Remove handler
```

### LocalEvent
```lua
LocalEvent:Send(...)         -- Fire event
LocalEvent:Listen(callback)  -- Register listener
LocalEvent:Once(callback)    -- Register one-time listener
LocalEvent:Wait()            -- Yield until event fires
LocalEvent:Emit(...)         -- Alias for Send
LocalEvent:Destroy()         -- Clean up connections
```

### LocalFunction
```lua
LocalFunction:Handle(callback) -- Set handler
LocalFunction:Unhandle()       -- Remove handler
LocalFunction:Call(...)        -- Call function (yields result)
```

### Profiles Module (ServerScriptService.Pulse.Data.Profiles)
```lua
Profiles:Get(player)         -- Get player profile (nil until loaded)
Profiles:Push(player, field) -- Push field update to client
Profiles:Start()             -- Start loading profiles for all players
Profiles.Ready               -- Signal: Fires when player's profile loads
```

### HTTP Module (ServerScriptService.Pulse.Http.Http)
```lua
Http:Request(name, body, options)    -- Yielding request (ok, data/reason)
Http:Queue(name, body, callback, options) -- Fire-and-forget queued request
Http:GetStats()                      -- Get HTTP statistics table
Http:IsEnabled()                     -- Check if HTTP is enabled
```

## Troubleshooting

### "Module code did not return exactly one value"
- Check that all modules end with `return` statement
- Verify no syntax errors in required modules
- Ensure circular dependencies don't exist

### "Failed to deserialize JSON" (Rojo)
- Verify `default.project.json` has correct named-key structure
- Check for stray commas or missing braces
- Ensure file is saved as UTF-8 without BOM

### Data not syncing to client
- Verify field has `ClientWritable = true` in Config.Fields
- Check that you're calling `Profiles:Push(player, field)` after server changes
- Confirm client is listening to `Pulse.Events.DataSync`

### Requests timing out
- Increase Timeout value in request definition
- Check server handler returns success, result (not just true)
- Verify server isn't throwing errors in handler

### HTTP requests failing
- Verify `Config.Enabled = true` in Http/Config.luau
- Check endpoint URL is not empty
- Confirm `HttpService.HttpEnabled` is true in Studio settings
- Monitor budget with `Http:GetStats()`

### Players getting kicked unexpectedly
- Check webhook logs for violation details
- Adjust `THRESHOLD` in AntiExploit.lua if too sensitive
- Verify legitimate actions aren't triggering rate limits
- Consider adding game-specific exceptions to security logic

## Support

For issues, questions, or contributions:
- Check the [Troubleshooting Guide](#troubleshooting)
- Review the [API Reference](#api-reference)

## License

MIT License - feel free to use this in your personal and commercial Roblox games.

---

*Pulse: Making Roblox networking robust, secure, and simple.*
