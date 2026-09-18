--[[
	Pulse Core Constants
	Central configuration for the Pulse networking system.
	All values are tuned for typical Roblox game networking needs.
]]

-- Type definitions for better IDE support
type DebugConfig = {
	Enabled: boolean,
	LogPackets: boolean,
	LogValidationFailures: boolean,
	LogSecurityDetails: boolean,
	ConsistencyChecks: boolean,
	VerboseWarnings: boolean,
}

type ConstantsTable = {
	Version: string,
	TransportFolder: string,
	ReliableName: string,
	UnreliableName: string,
	MaxArguments: number,
	MaxString: number,
	MaxTableDepth: number,
	MaxTableSize: number,
	MaxRequestId: number,
	DefaultRequestTimeout: number,
	Debug: DebugConfig,
}

local Constants: ConstantsTable = {
	Version = "2.0.0",
	TransportFolder = "_Transport",
	ReliableName = "Reliable",
	UnreliableName = "Unreliable",
	MaxArguments = 16,
	MaxString = 8192,
	MaxTableDepth = 4,
	MaxTableSize = 64,
	MaxRequestId = 2000000000,
	DefaultRequestTimeout = 5,

	-- Debug configuration (can be overridden by Data.Config.Debug)
	Debug = {
		Enabled = false,
		LogPackets = false,
		LogValidationFailures = false,
		LogSecurityDetails = false,
		ConsistencyChecks = false,
		VerboseWarnings = false,
	},
}

return Constants