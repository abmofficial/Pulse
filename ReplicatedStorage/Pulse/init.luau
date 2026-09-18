local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Constants = require(script.Core.Config.Constants)
local Definitions = require(script.Core.Config.Definitions)
local PacketCodec = require(script.Core.Serialization.PacketCodec)
local Transport = require(script.Runtime.Transport)
local Registry = require(script.Runtime.Registry)
local Dispatcher = require(script.Runtime.Dispatcher)
local Batcher = require(script.Runtime.Batcher)

local IS_SERVER = RunService:IsServer()
local reliable, unreliable = Transport.GetTransports()

local function packArgs(...)
	local count = select("#", ...)
	local args = table.create(count)

	for index = 1, count do
		local value = select(index, ...)
		assert(value ~= nil, "Pulse does not allow nil network arguments")
		args[index] = value
	end

	return args
end

local function send(data, target, player, isUnreliable)
	local transport = if isUnreliable then unreliable else reliable

	if IS_SERVER then
		if target == "Client" then
			transport:FireClient(player, data)
		elseif target == "All" then
			transport:FireAllClients(data)
		else
			error("[PULSE] Server cannot send to target: " .. tostring(target), 3)
		end
	else
		if target ~= "Server" then error("[PULSE] Client can only send to the server", 3) end
		transport:FireServer(data)
	end
end

local function sendDefinition(definition, data, target, player)
	send(data, target, player, definition.Reliability == "Unreliable")
end

local context = { IsServer = IS_SERVER }

function context.SendEvent(definition, target, player, ...)
	local args = packArgs(...)

	if definition.Batch and Batcher.Queue(target, player, definition.Id, args) then
		return
	end

	local data = PacketCodec.EncodeEvent(definition.Id, args)
	sendDefinition(definition, data or { Type = "Event", Id = definition.Id, Args = args }, target, player)
end

function context.SendRequest(definition, target, player, requestId, ...)
	local args = packArgs(...)

	local data = PacketCodec.EncodeRequest(definition.Id, requestId, args)
	sendDefinition(definition, data or { Type = "Request", Id = definition.Id, RequestId = requestId, Args = args }, target, player)
end

function context.SendResponse(definition, target, player, requestId, success, result)
	local data = PacketCodec.EncodeResponse(definition.Id, requestId, success, result)
	sendDefinition(definition, data or { Type = "Response", Id = definition.Id, RequestId = requestId, Success = success, Result = result }, target, player)
end

local registry = Registry.Build(Definitions, context)

Dispatcher.Configure(registry.EventsById, registry.RequestsById)
Batcher.Start(send)

if IS_SERVER then
	Players.PlayerRemoving:Connect(Batcher.Clear)

	reliable.OnServerEvent:Connect(function(player, data)
		Dispatcher.Process(player, data, "Reliable")
	end)

	unreliable.OnServerEvent:Connect(function(player, data)
		Dispatcher.Process(player, data, "Unreliable")
	end)
else
	reliable.OnClientEvent:Connect(function(data)
		Dispatcher.Process(nil, data, "Reliable")
	end)

	unreliable.OnClientEvent:Connect(function(data)
		Dispatcher.Process(nil, data, "Unreliable")
	end)
end

local Pulse = {}

Pulse.Version = Constants.Version
Pulse.IsServer = IS_SERVER
Pulse.Events = registry.Events
Pulse.Requests = registry.Requests
Pulse.LocalEvents = registry.LocalEvents
Pulse.LocalFunctions = registry.LocalFunctions

function Pulse:SetInboundGuard(callback)
	assert(IS_SERVER, "SetInboundGuard() can only be used on the server")
	assert(type(callback) == "function", "Inbound guard must be a function")
	Dispatcher.SetInboundGuard(callback)
end

function Pulse:SetViolationHandler(callback)
	assert(IS_SERVER, "SetViolationHandler() can only be used on the server")
	assert(type(callback) == "function", "Violation handler must be a function")
	Dispatcher.SetViolationHandler(callback)
end

return Pulse