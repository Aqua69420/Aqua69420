-- DayNightCycle (v200)
-- Advances Lighting.ClockTime so the prison schedule (Config.PrisonSchedule in
-- PoliceSystem: Count / Chow / Programs / Yard / Lockdown) actually changes.
-- One full in-game day takes DAY_LENGTH_MINUTES real minutes.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local DAY_LENGTH_MINUTES = 24 -- 1 in-game hour per real minute
local START_HOUR = 9 -- servers start in the morning

Lighting.ClockTime = START_HOUR
local hoursPerSecond = 24 / (DAY_LENGTH_MINUTES * 60)
local accumulated = 0

RunService.Heartbeat:Connect(function(dt)
	-- write a few times a second, not every frame (replication)
	accumulated += dt
	if accumulated < 0.25 then
		return
	end
	Lighting.ClockTime = (Lighting.ClockTime + accumulated * hoursPerSecond) % 24
	accumulated = 0
end)

print(("[DayNightCycle] %d-minute days, starting at %02d:00"):format(DAY_LENGTH_MINUTES, START_HOUR))
