-- Packet envelope codec. Binary fast path; returns nil when a payload can'"'"'t
-- pack so the caller falls back to the raw table path. One scratch writer is
-- reused for encoding.
local Constants = require(script.Parent.Parent.Config.Constants)
local Writer = require(script.Parent.BufferWriter)
local Reader = require(script.Parent.BufferReader)
local ValueCodec = require(script.Parent.ValueCodec)

local EVENT, REQUEST, RESPONSE, BATCH = 1, 2, 3, 4

local MaxArguments = Constants.MaxArguments

local scratch = Writer.new(128)

local function encodeEntries(writer, entries)
for _, entry in entries do
writer:U16(entry.Id)
writer:U8(#entry.Args)

for index = 1, #entry.Args do
ValueCodec.Encode(writer, entry.Args[index], 1)
end
end
end

local function packable(args)
if #args > MaxArguments then return false end

for index = 1, #args do
if not ValueCodec.CanPack(args[index], 1) then return false end
end

return true
end

local PacketCodec = {}

function PacketCodec.EncodeEvent(channelId, args)
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

function PacketCodec.EncodeRequest(channelId, requestId, args)
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

function PacketCodec.EncodeResponse(channelId, requestId, success, result)
if not ValueCodec.CanPack(result, 1) then return nil end

scratch:Reset()
scratch:U8(RESPONSE)
scratch:U16(channelId)
scratch:Varint(requestId)
scratch:Boolean(success)
ValueCodec.Encode(scratch, result, 1)

return scratch:ToBuffer()
end

function PacketCodec.EncodeBatch(entries)
scratch:Reset()
scratch:U8(BATCH)
scratch:Varint(#entries)
encodeEntries(scratch, entries)

return scratch:ToBuffer()
end

local function decode(data)
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

function PacketCodec.Decode(data)
local ok, kind, id, a, b, c = pcall(decode, data)

if ok then
return true, kind, id, a, b, c
end

return false
end

return PacketCodec