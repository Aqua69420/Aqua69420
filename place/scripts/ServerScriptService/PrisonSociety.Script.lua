-- PrisonSociety (v211)
-- Life among the NPC inmates (Workspace.PrisonNPCs, spawned by PoliceSystem's
-- prison life):
--   * Gangs, told apart by bandana colour:
--       Eastside Kings (red)  <-> Iron Syndicate (black)
--       Desert Saints (orange) <-> The Lifers (blue)
--     Some inmates are unaffiliated (no bandana).
--   * Inmates chatter (speech bubbles), walk up to player inmates and talk to
--     them. Answer with the dialogue box - ignoring them costs respect.
--   * Reputation per gang (player attributes Rep_EK / Rep_IS / Rep_DS / Rep_TL,
--     -100..100). Gaining with a gang costs a little with its rival. Low
--     respect makes that gang's members jump you; high respect lets you join.
--   * Dealers sell contraband: a Shiv and Prison Pills.
--   * Rival inmates fight in the common areas; correctional officers run over
--     and break it up (ServerStorage.PrisonCOResponse, from PoliceSystem).
--   * Fist fighting everywhere: click (or the PUNCH button on touch) with no
--     tool out. Punching a gang member makes the whole crew come for you.
-- NPCs are only ever taken while free (not InCell); "SocietyBusy" tells the
-- prison life walker to leave them alone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

---------------------------------------------------------------------------
-- config
---------------------------------------------------------------------------
local GANGS = {
	EK = { key = "EK", name = "Eastside Kings", color = Color3.fromRGB(200, 28, 28), rival = "IS" },
	IS = { key = "IS", name = "Iron Syndicate", color = Color3.fromRGB(22, 22, 24), rival = "EK" },
	DS = { key = "DS", name = "Desert Saints", color = Color3.fromRGB(240, 130, 20), rival = "TL" },
	TL = { key = "TL", name = "The Lifers", color = Color3.fromRGB(30, 80, 205), rival = "DS" },
}
local GANG_ORDER = { "EK", "IS", "DS", "TL" }
local UNAFFILIATED_CHANCE = 0.25
local DEALER_CHANCE = 0.22

local PRICES = { Shiv = 250, Pills = 120 }
local FIST_DAMAGE = 10
local SHIV_DAMAGE = 24
local NPC_FIST_DAMAGE = 7
local PUNCH_COOLDOWN = 0.5
local PUNCH_RANGE = 5

local HOSTILE_REP = -40 -- that gang attacks you on sight
local RIVAL_HOSTILE_REP = -20 -- ... or this low when you ride with their rival
local JOIN_REP = 40
local APPROACH_ANSWER_TIME = 18

local FIRST_NAMES = {
	"Marcus", "Dre", "Tony", "Luis", "Big Mike", "Kev", "Rico", "Sal", "Jimmy", "Ray", "Deshawn", "Vic",
	"Manny", "Chuy", "Frankie", "Boone", "Earl", "Cash", "Tre", "Duke", "Nico", "Gus", "Moe", "Otis",
	"Snake", "Tiny", "Ghost", "Smokey", "Lefty", "Books", "Preacher", "Spider",
}

local LINES = {
	general = {
		"Chow was nasty today.", "Three more years, man. Three.", "Who took my honey bun?",
		"CO's been on me all day.", "I didn't do it, for real.", "Can't wait for yard.",
		"Anybody got a stamp?", "My lawyer ain't called back in weeks.", "Keep your head down in here.",
		"Heard they're shaking down the block tonight.", "This mattress is a brick.", "Commissary's a ripoff.",
		"Who's got the good noodles?", "Somebody turn that TV up.", "I'm innocent. Ask anybody.",
	},
	gang = {
		EK = { "Kings run this tier.", "Red stays together.", "Syndicate better stay on their side." },
		IS = { "Syndicate don't forget.", "Iron don't bend.", "Kings talking big again." },
		DS = { "Saints look after their own.", "Desert heat, baby.", "Lifers think they own the yard." },
		TL = { "Lifers been here longest.", "We ain't going nowhere.", "Saints need to learn some respect." },
	},
	dealer = { "Psst. I got what you need.", "Shivs, pills... come talk to me.", "Best prices on the block." },
	hostile = { "You got some nerve showing your face.", "Watch yourself, fish.", "You're done in here." },
	friendly = { "Good to see you.", "You're alright, you know that?", "Holler if you need anything." },
	neutral = { "Who's this new fish?", "You looking at something?", "New face on the block." },
	fight = { "FIGHT! FIGHT!", "Oh it's going down!", "Get him!", "CO's coming, CO's coming!" },
	taunt = { "You wanna go? Let's go!", "I warned you!", "Come here!", "Wrong block, fish!" },
	ignored = { "Oh, you're gonna ignore me? Alright.", "Cold. I'll remember that.", "Too good to talk, huh?" },
	brokenUp = { "Aight, aight!", "This ain't over.", "I'm cool, I'm cool!" },
}

local APPROACH = {
	{ text = "Yo, new fish. You know who runs this block?", kind = "intro" },
	{ text = "You got a smoke? Or some noodles?", kind = "ask" },
	{ text = "What you in for?", kind = "chat" },
	{ text = "You look like you could use a friend in here.", kind = "chat" },
	{ text = "You been talking to the other crew?", kind = "ask" },
}

---------------------------------------------------------------------------
-- remotes
---------------------------------------------------------------------------
local folder = ReplicatedStorage:FindFirstChild("PrisonSociety") or Instance.new("Folder")
folder.Name = "PrisonSociety"
folder.Parent = ReplicatedStorage
local function remote(name: string): RemoteEvent
	local r = folder:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = folder
	end
	return r :: RemoteEvent
end
local DialogueRE = remote("Dialogue")
local PunchRE = remote("Punch")
local NoticeRE = remote("Notice")

-- gang table for the client's reputation panel
local gangInfo = folder:FindFirstChild("Gangs") or Instance.new("Folder")
gangInfo.Name = "Gangs"
gangInfo.Parent = folder
for index, key in GANG_ORDER do
	local g = GANGS[key]
	local v = gangInfo:FindFirstChild(key) or Instance.new("Color3Value")
	v.Name = key
	v.Value = g.color
	v:SetAttribute("GangName", g.name)
	v:SetAttribute("Order", index)
	v.Parent = gangInfo
end

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
local function pick<T>(list: { T }): T
	return list[math.random(1, #list)]
end

local function economy(action: string, player: Player, amount: number?): any
	local fn = ServerStorage:FindFirstChild("Economy")
	if not fn then
		return nil
	end
	local ok, result = pcall(fn.Invoke, fn, action, player, amount)
	return ok and result
end

local function notice(player: Player, text: string)
	NoticeRE:FireClient(player, text)
end

local function charInfo(model: Model?): (Humanoid?, BasePart?)
	if not model then
		return nil, nil
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hum and root and hum.Health > 0 then
		return hum, root
	end
	return nil, nil
end

local function flatDist(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function npcFolder(): Instance?
	return Workspace:FindFirstChild("PrisonNPCs")
end

local function isInmate(player: Player): boolean
	return player:GetAttribute("CustodyOwner") == "INCARCERATED"
end

local function isCuffed(hum: Humanoid): boolean
	return hum:GetAttribute("PoliceCuffed") == true
end

---------------------------------------------------------------------------
-- speech bubbles
---------------------------------------------------------------------------
local function say(model: Model, text: string, seconds: number?)
	local head = model:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local old = head:FindFirstChild("SocietyBubble")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "SocietyBubble"
	gui.Size = UDim2.fromOffset(220, 46)
	gui.StudsOffset = Vector3.new(0, 3.1, 0)
	gui.MaxDistance = 55
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(250, 250, 250)
	label.BackgroundTransparency = 0.08
	label.TextColor3 = Color3.fromRGB(20, 20, 20)
	label.Font = Enum.Font.GothamMedium
	label.TextScaled = true
	label.TextWrapped = true
	label.Text = text
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = label
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 18
	limit.Parent = label
	gui.Parent = head
	task.delay(seconds or 4.5, function()
		if gui.Parent then
			gui:Destroy()
		end
	end)
end

---------------------------------------------------------------------------
-- bandanas
---------------------------------------------------------------------------
local function addBandana(model: Model, gangKey: string?)
	local head = model:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	for _, name in { "GangBandana", "GangBandanaKnot" } do
		local old = head:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local gang = gangKey and GANGS[gangKey]
	if not gang then
		return
	end
	local size = head.Size
	local function piece(name: string, partSize: Vector3, offset: CFrame)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = partSize
		p.Color = gang.color
		p.Material = Enum.Material.Fabric
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
		p.Anchored = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CFrame = head.CFrame * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = p
		weld.Parent = p
		p.Parent = head
	end
	-- a band around the forehead, knotted at the back
	piece("GangBandana", Vector3.new(size.X * 1.04, size.Y * 0.26, size.Z * 1.06), CFrame.new(0, size.Y * 0.24, 0))
	piece("GangBandanaKnot", Vector3.new(size.X * 0.3, size.Y * 0.22, size.Z * 0.3), CFrame.new(0, size.Y * 0.2, size.Z * 0.6))
end

---------------------------------------------------------------------------
-- NPC registry
---------------------------------------------------------------------------
type Npc = {
	model: Model,
	hum: Humanoid,
	root: BasePart,
	name: string,
	gang: string?,
	dealer: boolean,
	lastSaid: number,
}
local npcs: { [Model]: Npc } = {}

local function gangOf(model: Model): string?
	local g = model:GetAttribute("Gang")
	return if type(g) == "string" and GANGS[g] then g else nil
end

local function free(n: Npc): boolean
	return n.model.Parent ~= nil
		and n.hum.Health > 0
		and not n.model:GetAttribute("InCell")
		and not n.model:GetAttribute("SocietyBusy")
end

-- an NPC in a dialogue/approach is "busy" by design; it only drops out if it died or went in
local function free2(n: Npc): boolean
	return n.model.Parent ~= nil and n.hum.Health > 0 and not n.model:GetAttribute("InCell")
end

local function take(n: Npc): boolean
	if not free(n) then
		return false
	end
	n.model:SetAttribute("SocietyBusy", true)
	return true
end

local function releaseNpc(n: Npc)
	if n.model.Parent then
		n.model:SetAttribute("SocietyBusy", nil)
	end
end

local openDialogue -- forward

local function setupPrompt(n: Npc)
	local prompt = n.root:FindFirstChild("SocietyTalk") :: ProximityPrompt?
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "SocietyTalk"
		prompt.ActionText = "Talk"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.T
		prompt.Parent = n.root
		prompt.Triggered:Connect(function(player)
			openDialogue(player, n, "talk")
		end)
	end
	local gang = n.gang and GANGS[n.gang]
	prompt.ObjectText = n.name .. (if gang then " · " .. gang.name else "") .. (if n.dealer then " (dealer)" else "")
end

local function register(model: Instance)
	if not model:IsA("Model") or not model:GetAttribute("PrisonNPCInmate") then
		return
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root then
		return
	end
	local existing = npcs[model]
	if existing then
		-- back out of the cell for the day: the bandana is still on
		setupPrompt(existing)
		return
	end
	if model:GetAttribute("Gang") == nil then
		model:SetAttribute("Gang", if math.random() < UNAFFILIATED_CHANCE then "" else pick(GANG_ORDER))
		model:SetAttribute("InmateName", pick(FIRST_NAMES))
		model:SetAttribute("Dealer", math.random() < DEALER_CHANCE)
	end
	local n: Npc = {
		model = model,
		hum = hum,
		root = root,
		name = tostring(model:GetAttribute("InmateName") or "Inmate"),
		gang = gangOf(model),
		dealer = model:GetAttribute("Dealer") == true,
		lastSaid = 0,
	}
	npcs[model] = n
	local gang = n.gang and GANGS[n.gang]
	hum.DisplayName = (if gang then "[" .. n.gang .. "] " else "") .. n.name
	addBandana(model, n.gang)
	setupPrompt(n)
	model.Destroying:Connect(function()
		npcs[model] = nil
	end)
	hum.Died:Connect(function()
		npcs[model] = nil
	end)
end

local function watchFolder(f: Instance)
	for _, m in f:GetChildren() do
		task.spawn(register, m)
	end
	f.ChildAdded:Connect(function(m)
		task.wait(1) -- the rig finishes dressing first
		register(m)
	end)
end

task.spawn(function()
	local f = npcFolder()
	while not f do
		task.wait(3)
		f = npcFolder()
	end
	watchFolder(f)
end)

local function freeNpcsNear(pos: Vector3, radius: number, filter: ((Npc) -> boolean)?): { Npc }
	local out = {}
	for _, n in npcs do
		if free(n) and flatDist(n.root.Position, pos) <= radius and math.abs(n.root.Position.Y - pos.Y) < 12 then
			if not filter or filter(n) then
				table.insert(out, n)
			end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- reputation
---------------------------------------------------------------------------
local function getRep(player: Player, key: string): number
	return tonumber(player:GetAttribute("Rep_" .. key)) or 0
end

local function setRep(player: Player, key: string, value: number)
	player:SetAttribute("Rep_" .. key, math.clamp(math.floor(value + 0.5), -100, 100))
end

local function addRep(player: Player, key: string?, delta: number, why: string?)
	if not key or not GANGS[key] or delta == 0 then
		return
	end
	setRep(player, key, getRep(player, key) + delta)
	-- getting in good with a crew costs you with their rivals
	if delta > 0 then
		local rival = GANGS[key].rival
		setRep(player, rival, getRep(player, rival) - delta * 0.4)
	end
	if why then
		notice(player, ("%s %s%d respect (%s)"):format(GANGS[key].name, if delta > 0 then "+" else "", delta, why))
	end
end

local grudge: { [Player]: { [string]: number } } = {}

local function hostileTo(player: Player, key: string?): boolean
	if not key then
		return false
	end
	local g = grudge[player]
	if g and g[key] and os.clock() < g[key] then
		return true
	end
	local mine = player:GetAttribute("PrisonGang")
	if mine == key then
		return false
	end
	local rep = getRep(player, key)
	if rep <= HOSTILE_REP then
		return true
	end
	return mine ~= nil and GANGS[key].rival == mine and rep <= RIVAL_HOSTILE_REP
end

local function holdGrudge(player: Player, key: string?, seconds: number)
	if not key then
		return
	end
	grudge[player] = grudge[player] or {}
	grudge[player][key] = os.clock() + seconds
end

local function moodFor(player: Player, n: Npc): string
	if not n.gang then
		return "neutral"
	end
	if hostileTo(player, n.gang) then
		return "hostile"
	end
	if player:GetAttribute("PrisonGang") == n.gang or getRep(player, n.gang) >= 25 then
		return "friendly"
	end
	return "neutral"
end

---------------------------------------------------------------------------
-- punching
---------------------------------------------------------------------------
local restC0: { [Motor6D]: CFrame } = {}
local swingSide: { [Instance]: boolean } = {}

local function swing(char: Model)
	local left = swingSide[char] == true
	swingSide[char] = not left
	local motor: Motor6D? = nil
	local r15 = char:FindFirstChild("UpperTorso") ~= nil
	if r15 then
		local arm = char:FindFirstChild(if left then "LeftUpperArm" else "RightUpperArm")
		motor = arm and arm:FindFirstChild(if left then "LeftShoulder" else "RightShoulder") :: Motor6D?
	else
		local torso = char:FindFirstChild("Torso")
		motor = torso and torso:FindFirstChild(if left then "Left Shoulder" else "Right Shoulder") :: Motor6D?
	end
	if not motor or not motor:IsA("Motor6D") then
		return
	end
	local m = motor :: Motor6D
	if not restC0[m] then
		restC0[m] = m.C0
		m.Destroying:Connect(function()
			restC0[m] = nil
		end)
	end
	local rest = restC0[m]
	-- arm straight out in front
	m.C0 = if r15 then rest * CFrame.Angles(math.rad(95), 0, 0)
		else rest * CFrame.Angles(0, 0, math.rad(if left then -95 else 95))
	task.delay(0.22, function()
		if m.Parent then
			m.C0 = rest
		end
	end)
end

local function hitSound(root: BasePart, blade: boolean)
	local s = Instance.new("Sound")
	s.SoundId = if blade then "rbxasset://sounds/swordslash.wav" else "rbxasset://sounds/swordlunge.wav"
	s.Volume = 0.6
	s.PlaybackSpeed = if blade then 1.1 else 0.7
	s.Parent = root
	s:Play()
	task.delay(2, function()
		s:Destroy()
	end)
end

-- the humanoid model in front of `root`, within reach
local function targetInFront(char: Model, root: BasePart, range: number): Model?
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local centre = root.Position + root.CFrame.LookVector * (range * 0.55)
	local best: Model?, bestD = nil, math.huge
	for _, part in Workspace:GetPartBoundsInRadius(centre, range * 0.7, params) do
		local model: Instance? = part.Parent
		while model and model ~= Workspace and not (model:IsA("Model") and model:FindFirstChildOfClass("Humanoid")) do
			model = model.Parent
		end
		if model and model ~= Workspace and model ~= char and model:IsA("Model") then
			local hum, troot = charInfo(model)
			if hum and troot then
				local d = (troot.Position - root.Position).Magnitude
				if d <= range + 1 and d < bestD then
					best, bestD = model, d
				end
			end
		end
	end
	return best
end

local attack -- forward
local reportPlayerFight -- forward (v212)

-- a player landed a hit on `model`
local function onPlayerHit(player: Player, model: Model, damage: number)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	hum:TakeDamage(damage)
	local n = npcs[model]
	local victim = Players:GetPlayerFromCharacter(model)
	if isInmate(player) and (n or (victim and isInmate(victim))) then
		reportPlayerFight(player)
	end
	if not n then
		return
	end
	if n.gang then
		local killed = hum.Health <= 0
		addRep(player, n.gang, if killed then -40 else -12, if killed then "killed a member" else "hit a member")
		holdGrudge(player, n.gang, 120)
	end
	if hum.Health > 0 then
		-- they fight back, and their crew joins in
		task.spawn(attack, n, player, 25)
	end
	if n.gang then
		local crew = freeNpcsNear(n.root.Position, 45, function(o)
			return o.gang == n.gang
		end)
		for i = 1, math.min(2, #crew) do
			task.spawn(attack, crew[i], player, 25)
		end
	end
end

local lastPunch: { [Player]: number } = {}

local function playerStrike(player: Player, blade: boolean)
	local char = player.Character
	local hum, root = charInfo(char)
	if not char or not hum or not root or isCuffed(hum) or hum.Sit then
		return
	end
	local now = os.clock()
	if now - (lastPunch[player] or 0) < (if blade then 0.75 else PUNCH_COOLDOWN) then
		return
	end
	lastPunch[player] = now
	swing(char)
	local target = targetInFront(char, root, PUNCH_RANGE)
	if not target then
		return
	end
	local troot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	if troot then
		hitSound(troot, blade)
	end
	onPlayerHit(player, target, if blade then SHIV_DAMAGE else FIST_DAMAGE)
end

PunchRE.OnServerEvent:Connect(function(player)
	local char = player.Character
	if char and char:FindFirstChildOfClass("Tool") then
		return -- tools do their own thing (the shiv stabs through Activated)
	end
	playerStrike(player, false)
end)

---------------------------------------------------------------------------
-- COs
---------------------------------------------------------------------------
local function callCO(pos: Vector3): Model?
	local fn = ServerStorage:FindFirstChild("PrisonCOResponse")
	if not fn or not fn:IsA("BindableFunction") then
		return nil
	end
	local ok, cop = pcall(fn.Invoke, fn, pos)
	return if ok and typeof(cop) == "Instance" and cop:IsA("Model") then cop else nil
end

local function coNear(cop: Model?, pos: Vector3, radius: number): boolean
	local root = cop and cop:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root ~= nil and (root.Position - pos).Magnitude <= radius
end

local function confiscate(player: Player)
	local found = false
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if container then
			for _, t in container:GetChildren() do
				if t:IsA("Tool") and t:GetAttribute("Contraband") then
					t:Destroy()
					found = true
				end
			end
		end
	end
	if found then
		notice(player, "A correctional officer confiscated your contraband")
	end
end

-- v212: fighters a CO catches go to solitary (PoliceSystem's PrisonExtras)
local lastInmateHit: { [Player]: number } = {}
local function discipline(target: Instance, why: string)
	local fn = ServerStorage:FindFirstChild("PrisonDiscipline")
	if fn and fn:IsA("BindableFunction") then
		task.spawn(function()
			pcall(fn.Invoke, fn, target, why)
		end)
	end
end

-- a player threw punches at an inmate: the nearest CO comes, and if the
-- player is still fighting when they arrive, it's solitary
local watchingFight: { [Player]: boolean } = {}
reportPlayerFight = function(player: Player)
	lastInmateHit[player] = os.clock()
	if watchingFight[player] or not isInmate(player) then
		return
	end
	watchingFight[player] = true
	task.spawn(function()
		local _, root = charInfo(player.Character)
		local cop = root and callCO(root.Position)
		local t0 = os.clock()
		while cop and os.clock() - t0 < 22 and player.Parent do
			local _, r = charInfo(player.Character)
			if r and coNear(cop, r.Position, 12) then
				if os.clock() - (lastInmateHit[player] or 0) < 12 then
					confiscate(player)
					notice(player, "A CO caught you fighting - you're going to solitary")
					discipline(player, "fighting")
				end
				break
			end
			task.wait(0.5)
		end
		watchingFight[player] = nil
	end)
end

---------------------------------------------------------------------------
-- an NPC goes after a player
---------------------------------------------------------------------------
local attacking: { [Player]: number } = {}

attack = function(n: Npc, player: Player, duration: number)
	if not take(n) then
		return
	end
	attacking[player] = (attacking[player] or 0) + 1
	say(n.model, pick(LINES.taunt), 3)
	local deadline = os.clock() + duration
	local cop: Model? = nil
	local called = false
	local nextHit = 0
	while os.clock() < deadline and n.model.Parent and n.hum.Health > 0 and not n.model:GetAttribute("InCell") do
		local phum, proot = charInfo(player.Character)
		if not phum or not proot or not player.Parent then
			break
		end
		local d = (proot.Position - n.root.Position).Magnitude
		if d > 90 then
			break -- they got away (or went back in their cell)
		end
		if n.hum.Sit then
			n.hum.Sit = false
			n.hum.Jump = true
		end
		if d > 3.5 then
			n.hum:MoveTo(proot.Position)
		else
			n.hum:MoveTo(n.root.Position)
			n.root.CFrame = CFrame.lookAt(n.root.Position, Vector3.new(proot.Position.X, n.root.Position.Y, proot.Position.Z))
		end
		if d <= PUNCH_RANGE and os.clock() >= nextHit then
			nextHit = os.clock() + 0.9 + math.random() * 0.5
			swing(n.model)
			if not isCuffed(phum) then
				phum:TakeDamage(NPC_FIST_DAMAGE)
				hitSound(proot, false)
			end
		end
		if not called and d < 12 and isInmate(player) then
			called = true
			task.spawn(function()
				cop = callCO(n.root.Position)
			end)
		end
		if cop and coNear(cop, n.root.Position, 11) then
			say(n.model, pick(LINES.brokenUp), 3)
			confiscate(player)
			notice(player, "Correctional officers broke up the fight")
			-- the aggressor goes to solitary; so does the player if they threw punches
			discipline(n.model, "fighting")
			if os.clock() - (lastInmateHit[player] or 0) < 25 then
				discipline(player, "fighting")
			end
			break
		end
		task.wait(0.3)
	end
	n.hum:MoveTo(n.root.Position)
	attacking[player] = math.max(0, (attacking[player] or 1) - 1)
	releaseNpc(n)
end

---------------------------------------------------------------------------
-- NPC vs NPC fights
---------------------------------------------------------------------------
local function npcFight(a: Npc, b: Npc)
	if not take(a) then
		return
	end
	if not take(b) then
		releaseNpc(a)
		return
	end
	say(a.model, pick(LINES.taunt), 3)
	for _, o in freeNpcsNear(a.root.Position, 35) do
		if math.random() < 0.5 then
			say(o.model, pick(LINES.fight), 3)
		end
	end
	local cop: Model? = nil
	task.spawn(function()
		cop = callCO((a.root.Position + b.root.Position) / 2)
	end)
	local deadline = os.clock() + 30
	local brokenUp = false
	local nextHit = { [a] = 0, [b] = 0.5 }
	local function alive(n: Npc)
		return n.model.Parent ~= nil and n.hum.Health > 0 and not n.model:GetAttribute("InCell")
	end
	while os.clock() < deadline and alive(a) and alive(b) do
		for _, pair in { { a, b }, { b, a } } do
			local me, them = pair[1], pair[2]
			local d = (them.root.Position - me.root.Position).Magnitude
			if me.hum.Sit then
				me.hum.Sit = false
				me.hum.Jump = true
			end
			if d > 3.2 then
				me.hum:MoveTo(them.root.Position)
			else
				me.hum:MoveTo(me.root.Position)
				me.root.CFrame = CFrame.lookAt(me.root.Position, Vector3.new(them.root.Position.X, me.root.Position.Y, them.root.Position.Z))
			end
			if d <= PUNCH_RANGE and os.clock() >= nextHit[me] then
				nextHit[me] = os.clock() + 0.8 + math.random() * 0.6
				swing(me.model)
				hitSound(them.root, false)
				-- inmate scraps aren't to the death
				them.hum.Health = math.max(12, them.hum.Health - 6)
			end
		end
		local mid = (a.root.Position + b.root.Position) / 2
		if cop and coNear(cop, mid, 11) then
			say(a.model, pick(LINES.brokenUp), 3)
			task.delay(0.8, function()
				if b.model.Parent then
					say(b.model, pick(LINES.brokenUp), 3)
				end
			end)
			brokenUp = true
			break
		end
		task.wait(0.3)
	end
	for _, n in { a, b } do
		n.hum:MoveTo(n.root.Position)
		releaseNpc(n)
		if brokenUp then
			discipline(n.model, "fighting")
		end
		task.delay(25, function()
			if n.hum.Parent and n.hum.Health > 0 then
				n.hum.Health = n.hum.MaxHealth
			end
		end)
	end
end

task.spawn(function()
	while true do
		task.wait(math.random(35, 70))
		local pool = {}
		for _, n in npcs do
			if n.gang and free(n) and n.hum.Health > 40 then
				table.insert(pool, n)
			end
		end
		if #pool >= 2 then
			local a = pick(pool)
			local rival = GANGS[a.gang :: string].rival
			local best: Npc?, bestD = nil, 60
			for _, b in pool do
				if b.gang == rival then
					local d = flatDist(a.root.Position, b.root.Position)
					if d < bestD and math.abs(a.root.Position.Y - b.root.Position.Y) < 10 then
						best, bestD = b, d
					end
				end
			end
			if best then
				task.spawn(npcFight, a, best)
			end
		end
	end
end)

---------------------------------------------------------------------------
-- contraband
---------------------------------------------------------------------------
local function contrabandTool(name: string, size: Vector3, color: Color3, tip: string): Tool
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.ToolTip = tip
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("Contraband", true)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = size
	handle.Color = color
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	return tool
end

local function giveShiv(player: Player)
	local tool = contrabandTool("Shiv", Vector3.new(0.18, 0.2, 1.3), Color3.fromRGB(150, 152, 158), "Homemade blade")
	tool.Handle.Material = Enum.Material.Metal
	tool.GripForward = Vector3.new(0, -1, 0)
	tool.GripUp = Vector3.new(0, 0, 1)
	local wrap = Instance.new("Part")
	wrap.Name = "Wrap"
	wrap.Size = Vector3.new(0.26, 0.26, 0.5)
	wrap.Color = Color3.fromRGB(70, 60, 50)
	wrap.Material = Enum.Material.Fabric
	wrap.CanCollide = false
	wrap.Massless = true
	wrap.CFrame = tool.Handle.CFrame * CFrame.new(0, 0, 0.45)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = tool.Handle
	weld.Part1 = wrap
	weld.Parent = wrap
	wrap.Parent = tool
	tool.Activated:Connect(function()
		playerStrike(player, true)
	end)
	tool.Parent = player:FindFirstChildOfClass("Backpack")
end

local function givePills(player: Player)
	local tool = contrabandTool("Prison Pills", Vector3.new(0.4, 0.55, 0.4), Color3.fromRGB(240, 240, 235), "Heals and speeds you up for a bit")
	local used = false
	tool.Activated:Connect(function()
		if used then
			return
		end
		local hum = charInfo(player.Character)
		if not hum then
			return
		end
		used = true
		hum.Health = math.min(hum.MaxHealth, hum.Health + 40)
		if not isCuffed(hum) then
			local base = hum.WalkSpeed
			hum.WalkSpeed = base + 5
			task.delay(15, function()
				if hum.Parent and not isCuffed(hum) and hum.WalkSpeed == base + 5 then
					hum.WalkSpeed = base
				end
			end)
		end
		notice(player, "You took the pills")
		tool:Destroy()
	end)
	tool.Parent = player:FindFirstChildOfClass("Backpack")
end

-- v212: items smuggled in on a contact visit (PrisonExtras)
do
	local fn = ServerStorage:FindFirstChild("PrisonContraband") or Instance.new("BindableFunction")
	fn.Name = "PrisonContraband"
	fn.OnInvoke = function(player: Player, item: string)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return false
		end
		if item == "Shiv" then
			giveShiv(player)
		else
			givePills(player)
		end
		return true
	end
	fn.Parent = ServerStorage
end

-- leaving prison: contraband and the bandana stay behind
local function watchCustody(player: Player)
	player:GetAttributeChangedSignal("CustodyOwner"):Connect(function()
		if isInmate(player) then
			if player.Character and player:GetAttribute("PrisonGang") then
				addBandana(player.Character, player:GetAttribute("PrisonGang"))
			end
			return
		end
		for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
			if container then
				for _, t in container:GetChildren() do
					if t:IsA("Tool") and t:GetAttribute("Contraband") then
						t:Destroy()
					end
				end
			end
		end
		if player.Character then
			addBandana(player.Character, nil)
		end
	end)
	player.CharacterAdded:Connect(function(char)
		local gang = player:GetAttribute("PrisonGang")
		if gang and isInmate(player) then
			char:WaitForChild("Head", 10)
			task.wait(1)
			addBandana(char, gang)
		end
	end)
end

---------------------------------------------------------------------------
-- dialogue
---------------------------------------------------------------------------
type Session = { token: number, npc: Npc, kind: string, expires: number, answered: boolean, stage: string }
local sessions: { [Player]: Session } = {}
local tokenSeq = 0

local function closeDialogue(player: Player)
	local s = sessions[player]
	sessions[player] = nil
	DialogueRE:FireClient(player, nil)
	if s then
		releaseNpc(s.npc)
	end
end

local function sendDialogue(player: Player, s: Session, text: string, options: { { id: string, text: string } })
	local gang = s.npc.gang and GANGS[s.npc.gang]
	DialogueRE:FireClient(player, {
		token = s.token,
		name = s.npc.name,
		gang = gang and gang.name or "Unaffiliated",
		color = gang and gang.color or Color3.fromRGB(150, 150, 150),
		text = text,
		options = options,
		seconds = if s.kind == "approach" and not s.answered then math.max(1, s.expires - os.clock()) else nil,
	})
	say(s.npc.model, text, 5)
end

local function mainOptions(player: Player, n: Npc): { { id: string, text: string } }
	local opts = {
		{ id = "respect", text = "Show respect" },
		{ id = "joke", text = "Crack a joke" },
	}
	if n.dealer then
		table.insert(opts, { id = "shop", text = "What you selling?" })
	end
	if n.gang and player:GetAttribute("PrisonGang") ~= n.gang then
		table.insert(opts, { id = "join", text = "I want in with " .. GANGS[n.gang].name })
	end
	table.insert(opts, { id = "trash", text = "Talk trash" })
	table.insert(opts, { id = "leave", text = "Walk away" })
	return opts
end

openDialogue = function(player: Player, n: Npc, kind: string, opener: string?)
	if sessions[player] then
		closeDialogue(player)
	end
	if not take(n) then
		if kind == "talk" then
			notice(player, n.name .. " is busy")
		end
		return
	end
	local _, proot = charInfo(player.Character)
	if proot then
		n.hum:MoveTo(n.root.Position)
		n.root.CFrame = CFrame.lookAt(n.root.Position, Vector3.new(proot.Position.X, n.root.Position.Y, proot.Position.Z))
	end
	tokenSeq += 1
	local s: Session = {
		token = tokenSeq,
		npc = n,
		kind = kind,
		expires = os.clock() + (if kind == "approach" then APPROACH_ANSWER_TIME else 40),
		answered = false,
		stage = "main",
	}
	sessions[player] = s
	local mood = moodFor(player, n)
	local text = opener or pick(LINES[mood])
	if mood == "hostile" then
		text = pick(LINES.hostile)
	elseif n.dealer and kind == "talk" then
		text = pick(LINES.dealer)
	end
	sendDialogue(player, s, text, mainOptions(player, n))
	-- timeout: an unanswered approach counts as ignoring them
	task.spawn(function()
		while sessions[player] == s do
			local _, root = charInfo(player.Character)
			local walkedOff = root == nil or (root.Position - n.root.Position).Magnitude > 22
			if os.clock() > s.expires or walkedOff or not free2(n) then
				if s.kind == "approach" and not s.answered then
					say(n.model, pick(LINES.ignored), 4)
					addRep(player, n.gang, -6, "ignored")
				end
				closeDialogue(player)
				return
			end
			task.wait(0.5)
		end
	end)
end

local chatted: { [Player]: { [Model]: number } } = {}

local function reply(player: Player, s: Session, text: string, delta: number?, why: string?, thenOptions: boolean?)
	delta = delta or 0
	if (delta :: number) > 0 then
		-- small talk wins respect once per inmate every couple of minutes
		chatted[player] = chatted[player] or {}
		local last = chatted[player][s.npc.model]
		if last and os.clock() - last < 120 then
			delta = 0
		else
			chatted[player][s.npc.model] = os.clock()
		end
	end
	addRep(player, s.npc.gang, delta :: number, why)
	if thenOptions then
		s.expires = os.clock() + 40
		sendDialogue(player, s, text, mainOptions(player, s.npc))
	else
		say(s.npc.model, text, 4)
		closeDialogue(player)
	end
end

DialogueRE.OnServerEvent:Connect(function(player, token, choice)
	local s = sessions[player]
	if not s or s.token ~= token or type(choice) ~= "string" then
		return
	end
	s.answered = true
	local n = s.npc
	local gang = n.gang and GANGS[n.gang]
	local mood = moodFor(player, n)
	if choice == "leave" then
		-- walking out on someone who came to you is still a snub, a small one
		if s.kind == "approach" then
			addRep(player, n.gang, -2)
		end
		say(n.model, if mood == "hostile" then "Yeah, keep walking." else "Aight.", 3)
		closeDialogue(player)
	elseif choice == "respect" then
		if mood == "hostile" then
			reply(player, s, "Respect gotta be earned back, fish.", 2, "respect", true)
		else
			reply(player, s, pick({ "Respect.", "Solid.", "I see you." }), 4, "respect", true)
		end
	elseif choice == "joke" then
		if math.random() < 0.55 then
			reply(player, s, pick({ "Hah! You're funny.", "Okay, that was good.", "Heh. Alright." }), 5, "joke landed", true)
		else
			reply(player, s, pick({ "...That ain't funny.", "You think you're a comedian?", "Not the time." }), -3, "joke flopped", true)
		end
	elseif choice == "trash" then
		addRep(player, n.gang, -15, "talked trash")
		if gang then
			-- their rivals enjoy it
			setRep(player, gang.rival, getRep(player, gang.rival) + 3)
		end
		say(n.model, pick(LINES.taunt), 3)
		closeDialogue(player)
		if math.random() < 0.45 or hostileTo(player, n.gang) then
			task.delay(0.3, function()
				attack(n, player, 20)
			end)
		end
	elseif choice == "join" then
		if not gang then
			return
		end
		if getRep(player, gang.key) >= JOIN_REP and not hostileTo(player, gang.key) then
			local old = player:GetAttribute("PrisonGang")
			player:SetAttribute("PrisonGang", gang.key)
			setRep(player, gang.key, math.max(getRep(player, gang.key), 60))
			setRep(player, gang.rival, getRep(player, gang.rival) - 30)
			if old and GANGS[old] and old ~= gang.key then
				addRep(player, old, -50, "left the crew")
			end
			if player.Character then
				addBandana(player.Character, gang.key)
			end
			notice(player, "You're with " .. gang.name .. " now")
			reply(player, s, "Welcome to " .. gang.name .. ". Wear the colors.", 0, nil, false)
		else
			reply(player, s, ("You gotta earn it first. (%d/%d respect)"):format(getRep(player, gang.key), JOIN_REP), -1, nil, true)
		end
	elseif choice == "shop" and n.dealer then
		if mood == "hostile" then
			reply(player, s, "I ain't selling to you.", 0, nil, false)
			return
		end
		s.stage = "shop"
		s.expires = os.clock() + 40
		local discount = if mood == "friendly" then 0.8 else 1
		sendDialogue(player, s, if discount < 1 then "For you? Friends price." else "Cash only. No refunds.", {
			{ id = "buy_shiv", text = ("Shiv - $%d"):format(math.floor(PRICES.Shiv * discount)) },
			{ id = "buy_pills", text = ("Prison Pills - $%d"):format(math.floor(PRICES.Pills * discount)) },
			{ id = "back", text = "Nah, never mind" },
		})
	elseif (choice == "buy_shiv" or choice == "buy_pills") and n.dealer and s.stage == "shop" then
		local item = if choice == "buy_shiv" then "Shiv" else "Pills"
		local price = math.floor(PRICES[item] * (if mood == "friendly" then 0.8 else 1))
		if economy("Charge", player, price) then
			if item == "Shiv" then
				giveShiv(player)
			else
				givePills(player)
			end
			addRep(player, n.gang, 3)
			reply(player, s, "Pleasure. Keep it out of sight.", 0, nil, false)
		else
			reply(player, s, "Come back when you got the money.", 0, nil, false)
		end
	elseif choice == "back" then
		s.stage = "main"
		reply(player, s, "Suit yourself.", 0, nil, true)
	end
end)

---------------------------------------------------------------------------
-- chatter, approaches and hostility
---------------------------------------------------------------------------
local lastApproach: { [Player]: number } = {}
local lastJump: { [Player]: number } = {}

task.spawn(function()
	while true do
		task.wait(2)
		local now = os.clock()
		-- ambient chatter
		for _, n in npcs do
			if free(n) and now - n.lastSaid > 12 and math.random() < 0.08 then
				n.lastSaid = now
				local line
				local charges = n.model:GetAttribute("Charges")
				if type(charges) == "string" and math.random() < 0.15 then
					line = pick({ "They got me on " .. string.lower(charges) .. ". Can you believe that?", "In for " .. string.lower(charges) .. ". Framed, obviously." })
				elseif n.dealer and math.random() < 0.4 then
					line = pick(LINES.dealer)
				elseif n.gang and math.random() < 0.35 then
					line = pick(LINES.gang[n.gang])
				else
					line = pick(LINES.general)
				end
				say(n.model, line)
			end
		end
		for _, player in Players:GetPlayers() do
			if not isInmate(player) then
				continue
			end
			local _, root = charInfo(player.Character)
			if not root then
				continue
			end
			-- a crew you've crossed comes for you
			if (attacking[player] or 0) == 0 and now - (lastJump[player] or 0) > 45 then
				local nearby = freeNpcsNear(root.Position, 55, function(n)
					return hostileTo(player, n.gang)
				end)
				if #nearby > 0 then
					lastJump[player] = now
					for i = 1, math.min(2, #nearby) do
						task.spawn(attack, nearby[i], player, 25)
					end
					continue
				end
			end
			-- somebody wanders over to talk
			if not sessions[player] and now - (lastApproach[player] or 0) > math.random(40, 75) then
				local nearby = freeNpcsNear(root.Position, 35)
				if #nearby > 0 then
					lastApproach[player] = now
					local n = pick(nearby)
					if take(n) then
						task.spawn(function()
							local t0 = os.clock()
							local arrived = false
							while os.clock() - t0 < 12 and free2(n) do
								local _, r = charInfo(player.Character)
								if not r then
									break
								end
								if (r.Position - n.root.Position).Magnitude < 6 then
									arrived = true
									break
								end
								if n.hum.Sit then
									n.hum.Sit = false
									n.hum.Jump = true
								end
								n.hum:MoveTo(r.Position)
								task.wait(0.3)
							end
							releaseNpc(n)
							if arrived and not sessions[player] then
								local a = pick(APPROACH)
								local opener = a.text
								if n.dealer and math.random() < 0.5 then
									opener = "Psst. You need anything? I got shivs, pills..."
								end
								openDialogue(player, n, "approach", opener)
							end
						end)
					end
				end
			end
		end
	end
end)

---------------------------------------------------------------------------
-- players
---------------------------------------------------------------------------
local function onPlayer(player: Player)
	for _, key in GANG_ORDER do
		if player:GetAttribute("Rep_" .. key) == nil then
			setRep(player, key, 0)
		end
	end
	watchCustody(player)
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayer, p)
end
Players.PlayerRemoving:Connect(function(player)
	if sessions[player] then
		releaseNpc(sessions[player].npc)
	end
	sessions[player] = nil
	grudge[player] = nil
	chatted[player] = nil
	lastPunch[player] = nil
	lastApproach[player] = nil
	lastJump[player] = nil
	attacking[player] = nil
end)

print("[PrisonSociety] ready: gangs, contraband, fights")
