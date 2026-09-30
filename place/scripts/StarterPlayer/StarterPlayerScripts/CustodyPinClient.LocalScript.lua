-- CustodyPinClient (v230)
-- After a reset in custody the server puts the new character in an intake cell,
-- but the player's own machine (which simulates its character) could keep that
-- character standing at its spawn point in the city - server-side teleports
-- never stuck. While the server sets the player attribute CustodyPinCF, this
-- script moves the character there from the client side too, so both agree.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

RunService.Heartbeat:Connect(function()
	local pin = player:GetAttribute("CustodyPinCF")
	if typeof(pin) ~= "CFrame" then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local offset = root.Position - pin.Position
	if Vector3.new(offset.X, 0, offset.Z).Magnitude > 6 or math.abs(offset.Y) > 8 then
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = pin
	end
end)
