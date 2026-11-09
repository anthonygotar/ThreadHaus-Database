-- reserve.lua
-- Atomic stock reservation using a Lua script.
-- KEYS[1]: the stock key, e.g. stock:3706
-- ARGV[1]: quantity to reserve (usually 1)
-- Returns: remaining stock after decrement, or -1 if not enough stock.
-- The whole script runs atomically — no other command can execute between
-- the GET and the DECR, so no race condition is possible.

local current = tonumber(redis.call('GET', KEYS[1]))
if current == nil then
  return -1
end
local qty = tonumber(ARGV[1])
if current < qty then
  -- Not enough stock — return -1 to signal failure
  return -1
end
-- Enough stock — decrement and return new value
return redis.call('DECRBY', KEYS[1], qty)
