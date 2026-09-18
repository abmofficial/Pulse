--[[
	Packet envelope codec. Binary fast path; returns nil when a payload can't
	pack so the caller falls back to the raw table path. One scratch writer is
	reused for encoding.

	Packet Types:
	- EVENT (1): One-way event notification
	- REQUEST (2): Request with expected response
	- RESPONSE (3): Response to a request
	- BATCH (4): Multiple events batched together

	Encoding Format:
	[Type: u8][ChannelId: u16][Payload...]
	- EVENT: [ArgCount: u8][Args...]
	- REQUEST: [RequestId: varint][ArgCount: u8][Args...]
	- RESPONSE: [RequestId: varint][Success: bool][Result...]
	- BATCH: [Count: varint][Entries...] where Entry = [ChannelId: u16][ArgCount: u8][Args...]
]]

--!native

-- Type definitions (using comments since Luau doesn't support union types with |)
-- PacketKind = "Event" | "Request" | "Response" | "Batch"
-- EncodeResult = buffer | nil
-- DecodeResult = { success: boolean, kind: string?, channelId: number?, requestId: number?, args: {any}?, success: boolean?, result: any?, entries: {{Id: number, Args: {any}}}? }

local Constants = require(script.Parent.Parent.Config.Constants)
local Writer = require(script.Parent.BufferWriter)
local Reader = require(script.Parent.BufferReader)
local ValueCodec = require(script.Parent.ValueCodec)

local EVENT, REQUEST, RESPONSE, BATCH = 1, 2, 3, 4

local MaxArguments = Constants.MaxArguments

local scratch = Writer.new(128)

local function encodeEntries(writer: any, entries: {{Id: number, Args: {any}}})
	for _, entry in entries do
		writer:U16(entry.Id)
		writer:U8(#entry.Args)

		for index = 1, #entry.Args do
			ValueCodec.Encode(writer, entry.Args[index], 1)
		end
	end
end

local function packable(args: {any}): boolean
	if #args > MaxArguments then return false end

	for index = 1, #args do
		if not ValueCodec.CanPack(args[index], 1) then return false end
	end

	return true
end

local PacketCodec = {}

--- Encodes an event packet
--- @param channelId number -- The channel ID
--- @param args {any} -- Arguments to encode
--- @return EncodeResult -- Encoded buffer or nil if not packable
function PacketCodec.EncodeEvent(channelId: number, args: {any}): EncodeResult
	if not packable(args) then return nil end

	scratch:Reset()
	scratch:U8(EVENT)
	scratch:U16(channelId)
	scratch:U8(#args)

	for index = 1, #args do
		ValueCodec.Encode(scratch, args[index], 1)
	end

	return scratch:ToBuffer()
end

--- Encodes a request packet
--- @param channelId number -- The channel ID
--- @param requestId number -- Unique request ID
--- @param args {any} -- Arguments to encode
--- @return EncodeResult -- Encoded buffer or nil if not packable
function PacketCodec.EncodeRequest(channelId: number, requestId: number, args: {any}): EncodeResult
	if not packable(args) then return nil end

	scratch:Reset()
	scratch:U8(REQUEST)
	scratch:U16(channelId)
	scratch:Varint(requestId)
	scratch:U8(#args)

	for index = 1, #args do
		ValueCodec.Encode(scratch, args[index], 1)
	end

	return scratch:ToBuffer()
end

--- Encodes a response packet
--- @param channelId number -- The channel ID
--- @param requestId number -- Request ID this responds to
--- @param success boolean -- Whether the request succeeded
--- @param result any -- Result data
--- @return EncodeResult -- Encoded buffer or nil if not packable
function PacketCodec.EncodeResponse(channelId: number, requestId: number, success: boolean, result: any): EncodeResult
	if not ValueCodec.CanPack(result, 1) then return nil end

	scratch:Reset()
	scratch:U8(RESPONSE)
	scratch:U16(channelId)
	scratch:Varint(requestId)
	scratch:Boolean(success)
	ValueCodec.Encode(scratch, result, 1)

	return scratch:ToBuffer()
end

--- Encodes a batch of events
--- @param entries {{Id: number, Args: {any}}} -- Batch entries
--- @return EncodeResult -- Encoded buffer
function PacketCodec.EncodeBatch(entries: {{Id: number, Args: {any}}}): EncodeResult
	scratch:Reset()
	scratch:U8(BATCH)
	scratch:Varint(#entries)
	encodeEntries(scratch, entries)

	return scratch:ToBuffer()
end

-- Decode returns multiple possible tuple types depending on packet kind
-- Event: "Event", channelId, args
-- Request: "Request", channelId, requestId, args
-- Response: "Response", channelId, requestId, success, result
-- Batch: "Batch", entries
local function decode(data: buffer)
	local reader = Reader.new(data)
	local kind = reader:U8()

	if kind == EVENT then
		local channelId = reader:U16()
		local argc = reader:U8()
		if argc > MaxArguments then error("too many arguments") end

		local args = table.create(argc)
		for index = 1, argc do
			args[index] = ValueCodec.Decode(reader, 1)
		end

		return "Event", channelId, args

	elseif kind == REQUEST then
		local channelId = reader:U16()
		local requestId = reader:Varint()
		local argc = reader:U8()
		if argc > MaxArguments then error("too many arguments") end

local args = table.create(argc)
for index = 1, argc do
args[index] = ValueCodec.Decode(reader, 1)
end

return "Request", channelId, requestId, args

elseif kind == RESPONSE then
local channelId = reader:U16()
local requestId = reader:Varint()
local success = reader:Boolean()
local result = ValueCodec.Decode(reader, 1)

return "Response", channelId, requestId, success, result

elseif kind == BATCH then
local count = reader:Varint()
if count > 255 then error("batch too large") end

local entries = table.create(count)
for index = 1, count do
local channelId = reader:U16()
local argc = reader:U8()
if argc > MaxArguments then error("too many arguments") end

local args = table.create(argc)
for argIndex = 1, argc do
args[argIndex] = ValueCodec.Decode(reader, 1)
end

entries[index] = { Id = channelId, Args = args }
end

return "Batch", entries
end

error("unknown packet kind: " .. kind)
end

function PacketCodec.Decode(data: buffer): DecodeResult
	local ok, kind, id, a, b, c = pcall(decode, data)

	if ok then
		return true, kind, id, a, b, c
	end

	return false
end

return PacketCodec