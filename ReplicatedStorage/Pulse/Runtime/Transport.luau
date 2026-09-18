local RunService = game:GetService("RunService")
local Constants = require(script.Parent.Parent.Core.Config.Constants)

local pulseModule = script.Parent.Parent
local reliable, unreliable

if RunService:IsServer() then
	local folder = Instance.new("Folder")
	folder.Name = Constants.TransportFolder

	reliable = Instance.new("RemoteEvent")
	reliable.Name = Constants.ReliableName
	reliable.Parent = folder

	unreliable = Instance.new("UnreliableRemoteEvent")
	unreliable.Name = Constants.UnreliableName
	unreliable.Parent = folder

	folder.Parent = pulseModule
else
	local folder = pulseModule:WaitForChild(Constants.TransportFolder)
	reliable = folder:WaitForChild(Constants.ReliableName)
	unreliable = folder:WaitForChild(Constants.UnreliableName)
end

local Transport = {}

function Transport.GetTransports()
	return reliable, unreliable
end

return Transport