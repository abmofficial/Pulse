--!native
-- "Warn" = formatting issues a game bug could cause (never kicks on its
-- own); "Critical" = packets a legitimate client can never send (kick).
local RunService = game:GetService("RunService")
local PacketCodec = require(script.Parent.Parent.Core.Serialization.PacketCodec)
local PayloadValidator = require(script.Parent.Parent.Core.Utilities.PayloadValidator)

local IS_SERVER = RunService:IsServer()
local unpack = table.unpack

local Dispatcher = {}

local eventsById, requestsById, inboundGuard, violationHandler

function Dispatcher.Configure(events, requests)
	eventsById = events
	requestsById = requests
end

function Dispatcher.SetInboundGuard(callback)
	inboundGuard = callback
end

function Dispatcher.SetViolationHandler(callback)
	violationHandler = callback
end

local function flag(player, reason, severity)
	if IS_SERVER and violationHandler then
		violationHandler(player, reason, severity)
	end
end

local function dispatchEvent(player, event, args)
	if inboundGuard and not inboundGuard(player, "Event", event.Name, event._definition, args) then
		return false
	end

	event:_Dispatch(player, unpack(args))
	return true
end

local function processTable(player, packet, reliability)
	if type(packet.Type) ~= "string" or type(packet.Id) ~= "number" then
		flag(player, "Malformed Packet", "Warn")
		return
	end

	if packet.Type == "Event" then
		local event = eventsById[packet.Id]
		if not event then flag(player, "Unknown Channel", "Critical") return end
		if event._definition.Reliability ~= reliability then flag(player, "Reliability Mismatch", "Critical") return end

		local args = packet.Args
		if type(args) ~= "table" or not PayloadValidator.ValidateArguments(args) then
			flag(player, "Invalid Payload", "Warn")
			return
		end

		dispatchEvent(player, event, args)

	elseif packet.Type == "Request" then
		if reliability ~= "Reliable" then flag(player, "Reliability Mismatch", "Critical") return end

		local request = requestsById[packet.Id]
		if not request then flag(player, "Unknown Channel", "Critical") return end

		if type(packet.RequestId) ~= "number" then flag(player, "Malformed Packet", "Warn") return end

		local args = packet.Args
		if type(args) ~= "table" or not PayloadValidator.ValidateArguments(args) then
			flag(player, "Invalid Payload", "Warn")
			return
		end

		if inboundGuard and not inboundGuard(player, "Request", request.Name, request._definition, args) then return end

		request:_HandleIncoming(player, packet.RequestId, args)

	elseif packet.Type == "Response" then
		if reliability ~= "Reliable" then flag(player, "Reliability Mismatch", "Critical") return end

		local request = requestsById[packet.Id]
		if not request then return end

		if type(packet.RequestId) ~= "number" then flag(player, "Malformed Packet", "Warn") return end

		local result = packet.Result
		if type(result) == "table" and not PayloadValidator.ValidateValue(result) then
			flag(player, "Invalid Payload", "Warn")
			return
		end

		request:_ReceiveResponse(packet.RequestId, packet.Success == true, result)
	else
		flag(player, "Malformed Packet", "Warn")
	end
end

local function processBinary(player, data, reliability)
	local ok, kind, id, a, b, c = PacketCodec.Decode(data)
	if not ok then
		flag(player, "Malformed Packet", "Warn")
		return
	end

	if kind == "Event" then
		local event = eventsById[id]
		if not event then flag(player, "Unknown Channel", "Critical") return end
		if event._definition.Reliability ~= reliability then flag(player, "Reliability Mismatch", "Critical") return end

		dispatchEvent(player, event, a)

	elseif kind == "Request" then
		if reliability ~= "Reliable" then flag(player, "Reliability Mismatch", "Critical") return end

		local request = requestsById[id]
		if not request then flag(player, "Unknown Channel", "Critical") return end

		if inboundGuard and not inboundGuard(player, "Request", request.Name, request._definition, b) then return end

		request:_HandleIncoming(player, a, b)

	elseif kind == "Response" then
		if reliability ~= "Reliable" then flag(player, "Reliability Mismatch", "Critical") return end

		local request = requestsById[id]
		if not request then return end -- late response to an expired request is normal

		request:_ReceiveResponse(a, b == true, c)

	elseif kind == "Batch" then
		for index = 1, #id do
			local entry = id[index]
			local event = eventsById[entry.Id]

			if not event then
				flag(player, "Unknown Channel", "Critical")
				return
			end

			dispatchEvent(player, event, entry.Args)
		end
	else
		flag(player, "Malformed Packet", "Warn")
	end
end

function Dispatcher.Process(player, data, reliability)
	if type(data) == "table" then
		processTable(player, data, reliability)
	elseif typeof(data) == "buffer" then
		processBinary(player, data, reliability)
	else
		flag(player, "Malformed Packet", "Warn")
	end
end

return Dispatcher