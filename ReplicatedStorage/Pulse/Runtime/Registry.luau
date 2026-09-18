local EventChannel = require(script.Parent.Parent.Core.Channels.EventChannel)
local RequestChannel = require(script.Parent.Parent.Core.Channels.RequestChannel)
local LocalEvent = require(script.Parent.Parent.Core.Channels.LocalEvent)
local LocalFunction = require(script.Parent.Parent.Core.Channels.LocalFunction)
local Constants = require(script.Parent.Parent.Core.Config.Constants)

local DEFAULT_EVENT_RATE = 20
local DEFAULT_REQUEST_RATE = 10

local Registry = {}

local function normalizeEvent(spec, id)
	local name, reliability, batch, rate

	if type(spec) == "string" then
		name, reliability, batch, rate = spec, "Reliable", false, DEFAULT_EVENT_RATE
	elseif type(spec) == "table" then
		name = spec[1]
		reliability = if spec.Unreliable then "Unreliable" else "Reliable"
		batch = spec.Batch == true
		rate = spec.Rate or DEFAULT_EVENT_RATE
	else
		error("Invalid event entry (expected string or table): " .. tostring(spec))
	end

	assert(type(name) == "string", "Event entry needs a name: " .. tostring(spec))
	assert(rate > 0, "Event rate must be positive: " .. name)

	return name, {
		Id = id,
		Reliability = reliability,
		Batch = batch,
		RateLimit = { Count = rate, Window = 1 },
	}
end

local function normalizeRequest(spec, id)
	local name, timeout, rate

	if type(spec) == "string" then
		name, timeout, rate = spec, Constants.DefaultRequestTimeout, DEFAULT_REQUEST_RATE
	elseif type(spec) == "table" then
		name = spec[1]
		timeout = spec.Timeout or Constants.DefaultRequestTimeout
		rate = spec.Rate or DEFAULT_REQUEST_RATE
	else
		error("Invalid request entry (expected string or table): " .. tostring(spec))
	end

	assert(type(name) == "string", "Request entry needs a name: " .. tostring(spec))

	return name, {
		Id = id,
		Timeout = timeout,
		RateLimit = { Count = rate, Window = 1 },
	}
end

local function appendSpecs(target, source)
	for _, spec in source do
		target[#target + 1] = spec
	end
end

function Registry.Build(definitions, context)
	local eventSpecs, requestSpecs = {}, {}
	appendSpecs(eventSpecs, definitions.Events)
	appendSpecs(requestSpecs, definitions.Requests)

	for _, groupModule in definitions.Groups or {} do
		local group = require(groupModule)
		appendSpecs(eventSpecs, group.Events or {})
		appendSpecs(requestSpecs, group.Requests or {})
	end

	local events, eventsById, requests, requestsById = {}, {}, {}, {}

	local eventId = 0
	for _, spec in eventSpecs do
		eventId += 1

		local name, definition = normalizeEvent(spec, eventId)
		assert(events[name] == nil, "Duplicate Pulse event: " .. name)

		events[name] = EventChannel.new(name, definition, context)
		eventsById[definition.Id] = events[name]
	end

	local requestId = 0
	for _, spec in requestSpecs do
		requestId += 1

		local name, definition = normalizeRequest(spec, requestId)
		assert(requests[name] == nil, "Duplicate Pulse request: " .. name)

		requests[name] = RequestChannel.new(name, definition, context)
		requestsById[definition.Id] = requests[name]
	end

	local localEvents, localFunctions = {}, {}

	for _, name in definitions.LocalEvents do
		localEvents[name] = LocalEvent.new(name)
	end

	for _, name in definitions.LocalFunctions do
		localFunctions[name] = LocalFunction.new(name)
	end

	return {
		Events = events,
		Requests = requests,
		EventsById = eventsById,
		RequestsById = requestsById,
		LocalEvents = localEvents,
		LocalFunctions = localFunctions,
	}
end

return Registry