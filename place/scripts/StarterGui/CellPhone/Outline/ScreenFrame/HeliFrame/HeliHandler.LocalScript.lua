-- Helicopter shop app: the helicopter models aren't in this copy of the map,
-- so the app just says so instead of taking money for nothing.
local frame = script.Parent
for _, child in ipairs(frame:GetChildren()) do
	if child:IsA("GuiObject") and child.Name ~= "Title" and child.Name ~= "Home" then
		child.Visible = false
	end
end
local title = frame:FindFirstChild("Title")
if title then
	local note = title:Clone()
	note.Name = "OutOfStock"
	note.Text = "No helicopters in stock right now."
	note.Position = UDim2.new(0, 0, 0.35, 0)
	note.Size = UDim2.new(1, 0, 0.2, 0)
	note.TextScaled = true
	note.Parent = frame
end
