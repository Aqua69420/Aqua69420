-- Offline rules test for CasinoTables hold'em: bots play many hands, chips
-- must be conserved and no hand may stall.  lune run tools/tests/holdem.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local task = require("@lune/task")

local src = fs.readFile("place/scripts/ServerScriptService/CasinoTables.ModuleScript.lua")
local fakeGame = { GetService = function(_, name) return {} end }
local env = setmetatable({
	game = fakeGame,
	task = { delay = function(_, fn, ...) return task.defer(fn, ...) end, wait = task.wait, spawn = task.spawn, defer = task.defer },
	workspace = {},
}, { __index = getfenv and getfenv() or _G })
local chunk = luau.load(src, { debugName = "CasinoTables", environment = env })
local M = chunk()
local paid = 0
M.init({
	economy = function() return true end,
	validBet = function(_, _, bet) return bet end,
	pay = function(_, amount) paid += amount end,
	holdWin = function() end,
	machines = {},
	physicalCard = function() end,
	MAX_MULTIPLIER = 10000,
})

-- evaluator sanity
local function best(cards) local s, n = M.bestHand(cards) return s, n end
local _, n1 = best({ "AS", "KS", "QS", "JS", "10S", "2H", "3D" })
assert(n1 == "Straight flush", n1)
local _, n2 = best({ "AS", "2D", "3C", "4H", "5S", "9H", "KD" })
assert(n2 == "Straight", n2)
local a = best({ "AS", "AD", "KC", "KH", "2S", "3H", "4D" })
local b = best({ "AS", "AD", "QC", "QH", "KS", "3H", "4D" })
assert(a > b, "two pair kings beats queens")
local fh = best({ "2S", "2D", "2C", "3H", "3S", "9H", "KD" })
local fl = best({ "2H", "5H", "9H", "JH", "KH", "3S", "4D" })
assert(fh > fl, "full house beats flush")
print("evaluator ok")

-- a table with one "human" (driven as a bot) and three bots
local s = M._state("T1")
local human = { DisplayName = "Tester", Parent = true }
local r = M.handles.Holdem(human, {}, "T1", "Sit", 20000, { sb = 50, bb = 100 })
assert(r.ok, r.message)
for _ = 1, 3 do
	assert(M.handles.Holdem(human, {}, "T1", "AddBot").ok)
end
for i = 1, 6 do
	if s.seats[i] and not s.seats[i].bot then s.seats[i].bot = true end
end
local function chips()
	local t = 0
	for i = 1, 6 do if s.seats[i] then t += s.seats[i].stack end end
	if s.hand and s.phase == "Playing" then for _, hp in s.hand.players do t += hp.total end end
	return t
end
local start = chips()
local hands, stalls = 0, 0
for h = 1, 400 do
	-- refill busted players so the game keeps going
	for i = 1, 6 do if s.seats[i] and s.seats[i].stack <= 0 then s.seats[i].stack = 0 end end
	local ready = 0
	for i = 1, 6 do if s.seats[i] and s.seats[i].stack > 0 then ready += 1 end end
	if ready < 2 then break end
	M._startHand(s)
	local guard = 0
	while s.phase == "Playing" and guard < 4000 do
		task.wait()
		guard += 1
		-- bots act through task.delay -> defer; nothing else to do
	end
	if s.phase == "Playing" then stalls += 1 break end
	hands += 1
	local now = chips()
	assert(now == start, ("chips changed after hand %d: %d -> %d"):format(h, start, now))
end
print(("played %d hands, stalls %d, chips conserved (%d)"):format(hands, stalls, chips()))
assert(stalls == 0, "a hand stalled")
