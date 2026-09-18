-- Coalesces unreliable events fired in the same frame into one packet.
local RunService = game:GetService("RunService")
local ValueCodec = require(script.Parent.Parent.Core.Serialization.ValueCodec)
local PacketCodec = require(script.Parent.Parent.Core.Serialization.PacketCodec)

local batches = {}

local Batcher = {}

function Batcher.Queue(target, player, channelId, args)
	for index = 1, #args do
		if not ValueCodec.CanPack(args[index], 1) then
			return false
		end
	end

	local key = player or target
	local batch = batches[key]

	if not batch then
		batch = { Target = target, Player = player, Entries = {} }
		batches[key] = batch
	end

	batch.Entries[#batch.Entries + 1] = { Id = channelId, Args = args }
	return true
end

function Batcher.Start(deliver)
	RunService.Heartbeat:Connect(function()
		for key, batch in batches do
			batches[key] = nil

			local entries = batch.Entries
			local total = #entries

			-- one packet can hold at most 255 entries
			for index = 1, total, 200 do
				local chunk = table.create(math.min(200, total - index + 1))
				local chunkCount = 0

				for entryIndex = index, math.min(index + 199, total) do
					chunkCount += 1
					chunk[chunkCount] = entries[entryIndex]
				end

				deliver(PacketCodec.EncodeBatch(chunk), batch.Target, batch.Player, true)
			end
		end
	end)
end

function Batcher.Clear(player)
	batches[player] = nil
end

return Batcher
