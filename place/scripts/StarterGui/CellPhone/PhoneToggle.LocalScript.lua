-- PhoneToggle (v196)
-- Slides the cell phone down off-screen and back. Button at the bottom of the
-- screen, or press N. The phone keeps working while hidden (timers, notifications).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local gui = script.Parent
local outline = gui:WaitForChild("Outline")
local player = Players.LocalPlayer

local SHOWN = outline.Position
local HIDDEN = UDim2.new(SHOWN.X.Scale, SHOWN.X.Offset, 1.02, 0)
local KEY = Enum.KeyCode.N

local hidden = player:GetAttribute("PhoneHidden") == true
local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local button = Instance.new("TextButton")
button.Name = "PhoneToggleButton"
button.AnchorPoint = Vector2.new(0.5, 1)
button.Size = UDim2.new(0, 120, 0, 26)
button.BackgroundColor3 = Color3.fromRGB(24, 26, 30)
button.BackgroundTransparency = 0.15
button.TextColor3 = Color3.fromRGB(235, 235, 235)
button.Font = Enum.Font.GothamBold
button.TextSize = 13
button.AutoButtonColor = true
button.ZIndex = 10
button.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = button

local function place()
	-- sits centred under the phone, at the bottom edge of the screen
	local x = SHOWN.X.Scale + outline.Size.X.Scale / 2
	button.Position = UDim2.new(x, SHOWN.X.Offset + outline.Size.X.Offset / 2, 1, -4)
	button.Text = if hidden then "Phone  [N]" else "Hide phone  [N]"
	button.Visible = outline.Visible
end

local function apply(animate: boolean)
	local goal = if hidden then HIDDEN else SHOWN
	if animate then
		TweenService:Create(outline, tweenInfo, { Position = goal }):Play()
	else
		outline.Position = goal
	end
	player:SetAttribute("PhoneHidden", hidden)
	place()
end

local function toggle()
	hidden = not hidden
	apply(true)
end

button.MouseButton1Click:Connect(toggle)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= KEY then
		return
	end
	if UserInputService:GetFocusedTextBox() then
		return
	end
	if outline.Visible then
		toggle()
	end
end)
-- The start menu reveals the phone after "Play"; show the button with it.
outline:GetPropertyChangedSignal("Visible"):Connect(place)

apply(false)
