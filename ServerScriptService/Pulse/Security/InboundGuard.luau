-- Policy gate for every structurally valid packet: a global flood budget plus
-- the per-channel RateLimit from the definition.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RateLimiter = require(ReplicatedStorage.Pulse.Core.Utilities.RateLimiter)

local GLOBAL_PACKETS_PER_SECOND = 150

local InboundGuard = {}

function InboundGuard.new(antiExploit)
local limiter = RateLimiter.new()

Players.PlayerRemoving:Connect(function(player)
limiter:Clear(player)
end)

return function(player, packetType, channelName, definition)
if not limiter:Allow(player, "_Global", { Count = GLOBAL_PACKETS_PER_SECOND, Window = 1 }) then
antiExploit:Report(player, "Packet Flood", "High")
return false
end

if not limiter:Allow(player, packetType .. ":" .. channelName, definition.RateLimit) then
antiExploit:Report(player, "Rate Limit Abuse", "Medium")
return false
end

return true
end
end

return InboundGuard