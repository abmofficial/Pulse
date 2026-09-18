local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Pulse = require(ReplicatedStorage:WaitForChild("Pulse"))
local AntiExploit = require(script.Parent.Security.AntiExploit)
local InboundGuard = require(script.Parent.Security.InboundGuard)
local Webhook = require(script.Parent.Logging.Webhook)
local DataProfiles = require(script.Parent.Data.Profiles)

DataProfiles.Start()

Webhook.Start()

Webhook.Log({
title = "[PULSE] Server Started",
color = 0x3498DB,
description = "Pulse v" .. Pulse.Version .. " security logging is online.",
fields = {
{ name = "Server", value = if game.JobId ~= "" then game.JobId else "Studio", inline = true },
{ name = "Players", value = tostring(#Players:GetPlayers()), inline = true },
},
timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
})

local antiExploit = AntiExploit.new()
antiExploit:Start()

Pulse:SetViolationHandler(function(player, reason, severity)
antiExploit:Report(player, reason, severity)
end)

Pulse:SetInboundGuard(InboundGuard.new(antiExploit))

print("[PULSE] Server initialized (v" .. Pulse.Version .. ")")