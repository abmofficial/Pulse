local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new()
return setmetatable({ _buckets = {} }, RateLimiter)
end

function RateLimiter:Allow(player, key, limit)
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

function RateLimiter:Clear(player)
self._buckets[player] = nil
end

return RateLimiter