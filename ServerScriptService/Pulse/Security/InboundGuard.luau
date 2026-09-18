-- Policy gate for every structurally valid packet: a global flood budget plus
-- the per-channel RateLimit from the definition.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RateLimiter = require(ReplicatedStorage.Pulse.Core.Utilities.RateLimiter)
local DataConfig = require(script.Parent.Parent.Data.Config)

local GLOBAL_PACKETS_PER_SECOND = 150

-- Enhanced inbound guard configuration
local ENHANCED_GUARD = {
	-- Per-player packet tracking
	TrackPacketPatterns = true,
	MaxUniqueChannelsPerSecond = 20,
	
	-- Burst detection
	BurstDetectionEnabled = true,
	BurstThreshold = 30, -- packets in a short window
	BurstWindow = 0.5, -- seconds
	
	-- Packet size limits
	MaxPacketSize = 1024 * 10, -- 10KB
	MaxArgumentsPerPacket = 16,
	
	-- Validation
	ValidatePacketStructure = true,
	RejectMalformedPackets = true,
	
	-- Debug
	DebugLogRejections = false,
}

local InboundGuard = {}

local function getDebugConfig()
	return DataConfig.Debug or {}
end

local function debugLog(category, message, ...)
	local debugConfig = getDebugConfig()
	if debugConfig.Enabled and (debugConfig.LogSecurityDetails or debugConfig.VerboseWarnings) then
		warn(string.format("[PULSE DEBUG][InboundGuard][%s] " .. message, category, ...))
	end
end

function InboundGuard.new(antiExploit)
	local limiter = RateLimiter.new()
	local packetHistory = {}
	local burstTracker = {}

	Players.PlayerRemoving:Connect(function(player)
		limiter:Clear(player)
		packetHistory[player] = nil
		burstTracker[player] = nil
	end)

	return function(player, packetType, channelName, definition, packetData)
		-- Debug logging
		debugLog("CHECK", "Checking packet: type=%s, channel=%s, player=%s", packetType, channelName, player.Name)

		-- Global flood check
		if not limiter:Allow(player, "_Global", { Count = GLOBAL_PACKETS_PER_SECOND, Window = 1 }) then
			debugLog("REJECT", "Global packet flood detected for %s", player.Name)
			antiExploit:Report(player, "Packet Flood", "High")
			return false
		end

		-- Per-channel rate limit check
		if not limiter:Allow(player, packetType .. ":" .. channelName, definition.RateLimit) then
			debugLog("REJECT", "Channel rate limit exceeded: %s:%s for %s", packetType, channelName, player.Name)
			antiExploit:Report(player, "Rate Limit Abuse", "Medium")
			return false
		end

		-- Enhanced: Packet size validation
		if ENHANCED_GUARD.ValidatePacketStructure and packetData then
			local packetSize = 0
			if typeof(packetData) == "buffer" then
				packetSize = buffer.len(packetData)
			elseif type(packetData) == "table" then
				-- Rough estimate for table
				packetSize = #packetData * 50
			end

			if packetSize > ENHANCED_GUARD.MaxPacketSize then
				debugLog("REJECT", "Packet too large: %d bytes for %s", packetSize, player.Name)
				antiExploit:Report(player, "Oversized Packet", "Medium")
				return false
			end
		end

		-- Enhanced: Burst detection
		if ENHANCED_GUARD.BurstDetectionEnabled then
			local now = os.clock()
			local tracker = burstTracker[player]
			if not tracker then
				tracker = { packets = {}, count = 0 }
				burstTracker[player] = tracker
			end

			-- Clean old entries
			local cutoff = now - ENHANCED_GUARD.BurstWindow
			local newPackets = {}
			for _, t in tracker.packets do
				if t > cutoff then
					table.insert(newPackets, t)
				end
			end
			tracker.packets = newPackets
			tracker.count = #newPackets

			-- Add current packet
			table.insert(tracker.packets, now)
			tracker.count += 1

			if tracker.count > ENHANCED_GUARD.BurstThreshold then
				debugLog("REJECT", "Burst detected: %d packets in %.1fs for %s", tracker.count, ENHANCED_GUARD.BurstWindow, player.Name)
				antiExploit:Report(player, "Packet Burst", "High")
				return false
			end
		end

		-- Enhanced: Track unique channels per second
		if ENHANCED_GUARD.TrackPacketPatterns then
			local now = os.clock()
			local history = packetHistory[player]
			if not history then
				history = { channels = {}, lastReset = now }
				packetHistory[player] = history
			end

			-- Reset per second
			if now - history.lastReset >= 1 then
				history.channels = {}
				history.lastReset = now
			end

			local channelKey = packetType .. ":" .. channelName
			history.channels[channelKey] = (history.channels[channelKey] or 0) + 1

			if #history.channels > ENHANCED_GUARD.MaxUniqueChannelsPerSecond then
				debugLog("REJECT", "Too many unique channels: %d for %s", #history.channels, player.Name)
				antiExploit:Report(player, "Channel Spam", "Medium")
				return false
			end
		end

		debugLog("ALLOW", "Packet allowed: type=%s, channel=%s, player=%s", packetType, channelName, player.Name)
		return true
	end
end

return InboundGuard