-- Snaps the player back if they move an impossible distance in one frame.
-- (Fixed: the decompiled version compared a Vector3 to a number and never
-- updated lastPos, so it errored as soon as you pressed Play.)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local TOLERANCE = 500

local function watch(character)
	local humanoid = character:WaitForChild("Humanoid")
	local rootPart = character:WaitForChild("HumanoidRootPart")
	while character.Parent and character:FindFirstChildOfClass("ForceField") do
		task.wait(1)
	end
	local lastPos = rootPart.Position
	while character.Parent and humanoid.Health > 0 do
		RunService.Heartbeat:Wait()
		if humanoid.Sit and not humanoid.SeatPart then
			humanoid.Sit = false
		end
		local newPos = rootPart.Position
		if (newPos - lastPos).Magnitude > TOLERANCE then
			rootPart.CFrame = CFrame.new(lastPos)
		else
			lastPos = newPos
		end
	end
end

-- This script lives in PlayerGui and is re-copied on every respawn,
-- so it only needs to watch the current character.
watch(player.Character or player.CharacterAdded:Wait())
