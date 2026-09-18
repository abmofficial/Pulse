--[[
	RateLimiter - Token bucket rate limiter per player and key.
	Used for preventing spam and enforcing rate limits on network channels.

	Usage:
		local limiter = RateLimiter.new()
		if limiter:Allow(player, "MyEvent", { Count = 10, Window = 1 }) then
			-- Allow action
		end
]]

-- Type definitions (using comments since Luau doesn't support union types with | or ?)
-- type RateLimit = {
-- 	Count: number, -- Maximum tokens/requests allowed
-- 	Window: number, -- Time window in seconds
-- }
-- type Bucket = {
-- 	Tokens: number,
-- 	Capacity: number,
-- 	Rate: number, -- Tokens per second
-- 	Last: number, -- Last update time (os.clock)
-- }
-- type RateLimiter = {
-- 	_buckets: { [Player]: { [string]: Bucket } },
-- 	new: () -> RateLimiter,
-- 	Allow: (self: RateLimiter, player: Player, key: string, limit: RateLimit?) -> boolean,
-- 	Clear: (self: RateLimiter, player: Player) -> (),
-- }

local RateLimiter: RateLimiter = {}
RateLimiter.__index = RateLimiter

--- Creates a new rate limiter
--- @return RateLimiter
function RateLimiter.new(): RateLimiter
	return setmetatable({ _buckets = {} }, RateLimiter)
end

--- Checks if an action is allowed under the rate limit
--- @param player Player -- Player to check
--- @param key string -- Rate limit key (e.g., event name)
--- @param limit RateLimit? -- Limit configuration (nil = unlimited)
--- @return boolean -- True if allowed, false if rate limited
function RateLimiter:Allow(player: Player, key: string, limit: RateLimit?): boolean
	if not limit then return true end

	local playerBuckets = self._buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		self._buckets[player] = playerBuckets
	end

	local bucket = playerBuckets[key]
	local now = os.clock()

	if not bucket then
		bucket = {
			Tokens = limit.Count - 1,
			Capacity = limit.Count,
			Rate = limit.Count / math.max(limit.Window, 0.01),
			Last = now,
		}
		playerBuckets[key] = bucket
		return true
	end

	local elapsed = now - bucket.Last
	if elapsed > 0 then
		local tokens = bucket.Tokens + elapsed * bucket.Rate
		bucket.Tokens = if tokens >= bucket.Capacity then bucket.Capacity else tokens
		bucket.Last = now
	end

	if bucket.Tokens >= 1 then
		bucket.Tokens -= 1
		return true
	end

	return false
end

--- Clears all rate limit buckets for a player
--- @param player Player
function RateLimiter:Clear(player: Player)
	self._buckets[player] = nil
end

return RateLimiter