-- DrugsClient (v252): what being high / drunk looks like. Reads the Intox_* attributes
-- the server's Drugs script keeps on the player. Everything here is local to you.
--   light:  blur, colour shift, a gentle sway
--   medium: tunnel vision, wobble, muffled sound
--   heavy:  warped colours, breathing screen edges, slow-motion feel
-- Each substance has its own look: alcohol = blurry and swaying, weed = soft and warm,
-- party pills = bright and saturated, stims = sharp and twitchy, heavy = dark and slow,
-- spice = sickly green, warped and pulsing. Also: Comedown (grey and dull), Overdosed.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local blur = Instance.new("BlurEffect")
blur.Name = "DrugBlur"
blur.Size = 0
blur.Parent = Lighting
local cc = Instance.new("ColorCorrectionEffect")
cc.Name = "DrugColor"
cc.Parent = Lighting

-- tunnel vision: four dark edges whose thickness breathes
local gui = Instance.new("ScreenGui")
gui.Name = "DrugVignette"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = -5
gui.Parent = player:WaitForChild("PlayerGui")
local edges = {}
for i, spec in { { 0, 0, 1, 0, 90 }, { 0, 1, 1, 0, -90 }, { 0, 0, 0, 1, 0 }, { 1, 0, 0, 1, 180 } } do
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 0
	f.AnchorPoint = Vector2.new(spec[1], spec[2])
	f.Position = UDim2.fromScale(spec[1], spec[2])
	local g = Instance.new("UIGradient")
	g.Rotation = spec[5]
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = f
	f.Parent = gui
	edges[i] = { frame = f, horizontal = spec[3] == 1 }
end

local function lvl(name: string): number
	return tonumber(player:GetAttribute("Intox_" .. name)) or 0
end

local defaultFov = camera.FieldOfView
local swayOffset = CFrame.new()
local baseReverb = SoundService.AmbientReverb
local touching = false

RunService:BindToRenderStep("DrugsCamera", Enum.RenderPriority.Camera.Value + 1, function()
	local t = os.clock()
	local alcohol, weed, party, stims, heavy, spice = lvl("Alcohol"), lvl("Weed"), lvl("Party"), lvl("Stims"), lvl("Heavy"), lvl("Spice")
	local comedown = (tonumber(player:GetAttribute("Comedown")) or 0) > 0
	local od = player:GetAttribute("Overdosed") == true
	local total = math.clamp(alcohol + weed * 0.6 + party * 0.7 + stims * 0.5 + heavy + spice * 1.3, 0, 2)

	-- blur: alcohol and heavy drugs smear everything; spice pulses
	local b = alcohol * 9 + weed * 4 + heavy * 10 + spice * (8 + math.sin(t * 3) * 5) + (if od then 18 else 0)
	blur.Size = math.clamp(b, 0, 28)

	-- colour: each drug has its own tint
	local sat = party * 0.9 + stims * 0.3 - heavy * 0.5 - (if comedown then 0.45 else 0) + spice * math.sin(t * 1.7) * 0.6
	local contrast = stims * 0.35 + party * 0.2 + spice * 0.3 - weed * 0.1
	local bright = party * 0.08 - heavy * 0.12 - (if od then 0.3 else 0)
	local tint = Color3.new(1, 1, 1)
	if spice > 0.05 then
		tint = Color3.new(1 - spice * 0.35, 1, 1 - spice * 0.5) -- sickly green
	elseif party > 0.05 then
		local h = (t * 0.15) % 1
		tint = Color3.new(1, 1, 1):Lerp(Color3.fromHSV(h, 0.5, 1), math.clamp(party, 0, 0.6))
	elseif weed > 0.05 then
		tint = Color3.new(1, 1 - weed * 0.08, 1 - weed * 0.2) -- warm
	elseif heavy > 0.05 then
		tint = Color3.new(1 - heavy * 0.2, 1 - heavy * 0.2, 1 - heavy * 0.05) -- cold and dark
	end
	cc.Saturation = math.clamp(sat, -0.9, 1)
	cc.Contrast = math.clamp(contrast, -0.3, 0.6)
	cc.Brightness = math.clamp(bright, -0.4, 0.2)
	cc.TintColor = tint

	-- tunnel vision that breathes (medium and up)
	local tunnel = math.clamp((total - 0.35) * 0.4 + (if od then 0.35 else 0), 0, 0.42)
	local breath = 1 + math.sin(t * (if stims > 0.2 then 4 else 1.4)) * 0.18 * math.clamp(total, 0, 1)
	for _, e in edges do
		local s = tunnel * breath
		e.frame.Size = if e.horizontal then UDim2.fromScale(1, s) else UDim2.fromScale(s, 1)
		e.frame.Visible = s > 0.005
	end

	-- sway / wobble: alcohol rolls, stims jitter, spice warps the field of view
	local roll = math.sin(t * 0.9) * alcohol * 0.06 + math.sin(t * 0.6) * heavy * 0.03
	local yaw = math.sin(t * 0.55) * alcohol * 0.025 + math.sin(t * 0.4) * weed * 0.01
	local jitter = stims * 0.004
	swayOffset = CFrame.Angles((math.random() - 0.5) * jitter, yaw + (math.random() - 0.5) * jitter, roll)
	if total > 0.02 then
		camera.CFrame = camera.CFrame * swayOffset
	end
	-- field of view and sound are only touched while something is in your system, so
	-- other scripts (scopes, cutscenes) keep control the rest of the time
	local active = total > 0.02 or od
	if active then
		if not touching then
			touching = true
			defaultFov = camera.FieldOfView
		end
		camera.FieldOfView = defaultFov + spice * math.sin(t * 2.3) * 12 + party * 4 - heavy * 4
		local muffle = heavy + spice + (if od then 1 else 0)
		SoundService.AmbientReverb = if muffle > 0.4 then Enum.ReverbType.UnderWater elseif alcohol > 0.5 then Enum.ReverbType.Hallway else baseReverb
	elseif touching then
		touching = false
		camera.FieldOfView = defaultFov
		SoundService.AmbientReverb = baseReverb
	end
end)
