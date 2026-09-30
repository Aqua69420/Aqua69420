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

local PRICES = { Shiv = 250, Pills = 120, Lockpick = 25000 } -- v215: one inmate sells lockpicks, at a price
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
	-- v226: a housed inmate is never cuffed (a stale flag left by a fallback cell
	-- placement used to block every punch)
	local plr = hum.Parent and Players:GetPlayerFromCharacter(hum.Parent)
	if plr and plr:GetAttribute("CustodyOwner") == "INCARCERATED" then
		return false
	end
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
	co: boolean?,
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
local resolveScene -- forward (v218 forced-choice scenes)

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

-- v226: correctional officers can be talked to (their respect is its own score)
local CO_NAMES = { "Reyes", "Walsh", "Okafor", "Brennan", "Castillo", "Hughes", "Nakamura", "Doyle", "Petrov", "Grant", "Morales", "Fitch" }
local cos: { [Model]: Npc } = {}
local function registerCO(model: Instance)
	if not model:IsA("Model") or cos[model] then
		return
	end
	local hum = model:FindFirstChildOfClass("Humanoid") or model:WaitForChild("Humanoid", 5)
	local root = model:FindFirstChild("HumanoidRootPart") or model:WaitForChild("HumanoidRootPart", 5)
	if not hum or not root or not hum:IsA("Humanoid") or not root:IsA("BasePart") then
		return
	end
	local n: Npc = {
		model = model,
		hum = hum,
		root = root :: BasePart,
		name = "C.O. " .. pick(CO_NAMES),
		gang = nil,
		dealer = false,
		lastSaid = 0,
		co = true,
	}
	cos[model] = n
	setupPrompt(n)
	local prompt = (root :: BasePart):FindFirstChild("SocietyTalk") :: ProximityPrompt?
	if prompt then
		prompt.ActionText = "Talk to CO"
		prompt.ObjectText = n.name
	end
	model.Destroying:Connect(function()
		cos[model] = nil
	end)
end
do
	local CollectionService = game:GetService("CollectionService")
	for _, m in CollectionService:GetTagged("PrisonCO") do
		task.spawn(registerCO, m)
	end
	CollectionService:GetInstanceAddedSignal("PrisonCO"):Connect(function(m)
		task.spawn(registerCO, m)
	end)
end

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

-- v226 CO RESPECT: how the correctional officers see you (-100..100), separate
-- from gang respect. Earned by talking to COs; high respect gets favors and
-- second chances, low respect gets searches and trips to solitary.
local function getCORespect(player: Player): number
	return tonumber(player:GetAttribute("CORespect")) or 0
end

local function addCORespect(player: Player, delta: number, why: string?)
	if delta == 0 then
		return
	end
	player:SetAttribute("CORespect", math.clamp(math.floor(getCORespect(player) + delta + 0.5), -100, 100))
	if why then
		notice(player, ("COs %s%d respect (%s)"):format(if delta > 0 then "+" else "", delta, why))
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
-- v229 RIOT STATE: the prison's mood. Three things feed it:
--   * gang anger - each gang's anger at its rival (fights, beatdowns)
--   * CO anger   - how provoked the inmates are by the officers (shakedowns,
--                  rough handling, trips to solitary)
--   * tension    - the overall temperature of the place
-- Past a point it boils over: a gang war (rival crews brawl) or a full riot
-- where inmates turn on the officers. Published on the PrisonSociety folder
-- (PrisonTension / COAnger / GangAnger_XX / Riot) for the client panel.
---------------------------------------------------------------------------
local Riot = {
	tension = 15,
	coAnger = 10,
	gangAnger = {} :: { [string]: number },
	active = false,
	cause = "",
	rioters = {} :: { [any]: number }, -- Npc -> hits landed
	coHits = {} :: { [Player]: number },
	lastRiot = -600,
	lastGangWar = -300,
	lastWarning = 0,
}
for _, k in GANG_ORDER do
	Riot.gangAnger[k] = 10
end

local function riotPublish()
	folder:SetAttribute("PrisonTension", math.floor(Riot.tension + 0.5))
	folder:SetAttribute("COAnger", math.floor(Riot.coAnger + 0.5))
	for k, v in Riot.gangAnger do
		folder:SetAttribute("GangAnger_" .. k, math.floor(v + 0.5))
	end
	folder:SetAttribute("Riot", Riot.active)
end

-- the hottest rival pair (the average anger of two rival gangs at each other)
local function riotGangHeat(): (number, string?)
	local best, bestKey = 0, nil
	for _, k in GANG_ORDER do
		local r = GANGS[k].rival
		local v = ((Riot.gangAnger[k] or 0) + (Riot.gangAnger[r] or 0)) / 2
		if v > best then
			best, bestKey = v, k
		end
	end
	return best, bestKey
end

-- the single "anger level" of the prison, 0..100
local function riotLevel(): number
	local gang = riotGangHeat()
	return Riot.tension * 0.45 + Riot.coAnger * 0.35 + gang * 0.2
end

-- tension: overall; gang: that gang gets angrier at its rival; co: at the officers
local function riotHeat(tension: number, gang: string?, gangDelta: number?, co: number?)
	Riot.tension = math.clamp(Riot.tension + tension, 0, 100)
	if gang and Riot.gangAnger[gang] then
		Riot.gangAnger[gang] = math.clamp(Riot.gangAnger[gang] + (gangDelta or tension * 1.5), 0, 100)
	end
	if co then
		Riot.coAnger = math.clamp(Riot.coAnger + co, 0, 100)
	end
	riotPublish()
end
riotPublish()

local riotOnCOHit -- forward: a player punched a correctional officer

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
	-- v227: fists land with a dull thud (no sword swoosh); the shiv still slashes
	local s = Instance.new("Sound")
	s.SoundId = if blade then "rbxasset://sounds/swordslash.wav" else "rbxasset://sounds/collide.wav"
	s.Volume = if blade then 0.6 else 0.8
	s.PlaybackSpeed = if blade then 1.1 else 0.55
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
	if cos[model] then
		riotOnCOHit(player, cos[model])
		return
	end
	local n = npcs[model]
	local victim = Players:GetPlayerFromCharacter(model)
	if isInmate(player) and (n or (victim and isInmate(victim))) then
		reportPlayerFight(player)
	end
	if not n then
		return
	end
	if n.gang then
		riotHeat(0.6, n.gang, 1, nil)
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
	if not char or not hum or not root then
		return
	end
	if isCuffed(hum) then
		PunchRE:FireClient(player, "blocked", "You can't swing while cuffed")
		return
	end
	if hum.Sit then
		PunchRE:FireClient(player, "blocked", "Stand up to fight")
		return
	end
	local now = os.clock()
	if now - (lastPunch[player] or 0) < (if blade then 0.75 else PUNCH_COOLDOWN) then
		return
	end
	lastPunch[player] = now
	swing(char)
	-- v227: a slightly wider reach so a punch at someone right beside you still lands
	local target = targetInFront(char, root, PUNCH_RANGE + 1)
	if not target then
		PunchRE:FireClient(player, "miss")
		return
	end
	local troot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	if troot then
		hitSound(troot, blade)
	end
	onPlayerHit(player, target, if blade then SHIV_DAMAGE else FIST_DAMAGE)
	local thum = target:FindFirstChildOfClass("Humanoid")
	PunchRE:FireClient(player, "hit", target.Name, thum and thum.Health or 0, thum and thum.MaxHealth or 100)
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
	-- v229: every trip to the hole winds the block up against the COs
	if not Riot.active and why ~= "rioting" and why ~= "inciting a riot" then
		riotHeat(1.5, nil, nil, if target:IsA("Player") then 4 else 2.5)
	end
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
					local blind = (tonumber(player:GetAttribute("COBlindEyeUntil")) or 0) > os.time()
					if blind then
						notice(player, "The CO looks the other way...")
					elseif getCORespect(player) >= 50 then
						-- the COs like you: one warning instead of the hole
						addCORespect(player, -20, "caught fighting - let off with a warning")
						notice(player, "CO: \"Break it up. That's your one warning.\"")
					else
						confiscate(player)
						notice(player, "A CO caught you fighting - you're going to solitary")
						addCORespect(player, -8, "fighting")
						discipline(player, "fighting")
					end
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
	-- v229: a scrap between rivals makes both crews angrier at each other
	riotHeat(2, a.gang, 6, nil)
	if b.gang then
		riotHeat(0, b.gang, 6, nil)
	end
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
		if Riot.active then
			continue
		end
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
type Session = { token: number, npc: Npc, kind: string, expires: number, answered: boolean, stage: string, scene: any?, sceneEnds: number?, depth: number? }
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
		gang = if gang then gang.name elseif s.npc.co then ("Correctional Officer · your CO respect %d"):format(getCORespect(player)) else "Unaffiliated",
		color = if gang then gang.color elseif s.npc.co then Color3.fromRGB(70, 130, 220) else Color3.fromRGB(150, 150, 150),
		text = text,
		options = options,
		seconds = if s.scene and s.sceneEnds then math.max(0.5, s.sceneEnds - os.clock())
			elseif s.kind == "approach" and not s.answered then math.max(1, s.expires - os.clock())
			else nil,
		forced = s.scene ~= nil,
	})
	say(s.npc.model, text, 5)
end

local function mainOptions(player: Player, n: Npc): { { id: string, text: string } }
	if n.co then
		return {
			{ id = "co_respect", text = "Show respect, officer" },
			{ id = "co_favor", text = "Ask for a favor" },
			{ id = "co_snitch", text = "Give up some information" },
			{ id = "co_mouth", text = "Mouth off" },
			{ id = "leave", text = "Walk away" },
		}
	end
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
	if n.co and not isInmate(player) then
		notice(player, "COs only talk to inmates in here")
		return
	end
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
	if n.co then
		local r = getCORespect(player)
		text = if r >= 50 then pick({ "What do you need? Make it quick.", "You've been keeping your nose clean. What's up?" })
			elseif r <= -40 then pick({ "You again. Watch yourself.", "Give me one reason, inmate. One." })
			else pick({ "Keep it short, inmate.", "What.", "Talk." })
	elseif mood == "hostile" then
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
			if s.scene and s.sceneEnds and (os.clock() > s.sceneEnds or walkedOff) then
				-- no backing out: running the clock down (or walking off) picks for you
				resolveScene(player, s, s.scene.timeout, true)
			elseif s.scene then
				-- mid-scene: the conversation can't just end
			elseif os.clock() > s.expires or walkedOff or not free2(n) then
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


---------------------------------------------------------------------------
-- v218 forced-choice scenes (Telltale style): picking a topic starts a scene
-- with 4 answers and a countdown. There is no "walk away" - when the clock runs
-- out (or you walk off) the silent option is chosen for you. Answers have
-- consequences: respect, rival respect, fights, a CO noticing (solitary),
-- contraband, cash.
---------------------------------------------------------------------------
local SCENE_TIME = 10
type Outcome = { say: { string }, rep: number?, rival: number?, fight: number?, co: number?, item: string?, cash: number?, notice: string?, next: string?, crew: boolean?,
	corep: number?, needs: number?, fail: any?, sentence: number?, blindEye: number?, snitch: boolean?, gamble: number?, search: number? }
local SCENES: { [string]: { line: { string }, options: { { text: string, tone: string, out: Outcome } }, timeout: Outcome } } = {
	joke = {
		line = { "Go on then, comedian. Make me laugh.", "You think you're funny? Prove it.", "Everybody's a comedian in here. Your turn." },
		options = {
			{ text = "Roast the guards", tone = "bold", out = { say = { "HAH! Officer Donut, I'm stealing that.", "Keep it down... but that was good." }, rep = 7, co = 0.15, notice = "A CO heard that." } },
			{ text = "Joke about myself", tone = "calm", out = { say = { "Heh. At least you know what you are.", "Alright, that's fair." }, rep = 3 } },
			{ text = "Joke about his crew", tone = "risky", out = { say = { "You wanna say that again?", "Say one more word about my people." }, rep = -12, fight = 0.5, next = "trash" } },
			{ text = "Joke about his mama", tone = "hostile", out = { say = { "...You're dead.", "Oh, you done messed up now." }, rep = -22, fight = 0.85, co = 0.35 } },
		},
		timeout = { say = { "...That's it? You froze up.", "Yeah, that's what I thought. Boring." }, rep = -4, notice = "You choked. He'll remember that." },
	},
	respect = {
		line = { "Respect, huh? Then do me a favor. Hold something for me.", "Words are cheap. Hold this for me till count.", "You wanna show respect? Keep this in your cell." },
		options = {
			{ text = "Hold it for him", tone = "risky", out = { say = { "Good. Don't get caught.", "That's respect. We're good." }, rep = 10, item = "Shiv", co = 0.25, notice = "You're holding contraband now." } },
			{ text = "\"What's in it for me?\"", tone = "bold", out = { say = { "Smart. Here, for your trouble.", "Business man, huh? Fine." }, rep = 2, item = "Pills", next = "deal" } },
			{ text = "\"I don't do favors\"", tone = "calm", out = { say = { "Then don't talk to me about respect.", "Noted." }, rep = -5 } },
			{ text = "Tell a CO about it", tone = "hostile", out = { say = { "You a SNITCH?", "Snitches get stitches, fish." }, rep = -35, rival = 3, fight = 0.7, notice = "Word travels fast. Everyone knows you snitched." } },
		},
		timeout = { say = { "Too slow. Forget I asked.", "Hesitation. That tells me everything." }, rep = -6 },
	},
	deal = {
		line = { "You like business? I got a bigger job. $500 up front, double back tomorrow." },
		options = {
			{ text = "Pay the $500", tone = "risky", out = { say = { "Pleasure doing business.", "You'll see it back. Probably." }, cash = 500, rep = 8 } },
			{ text = "Haggle him down", tone = "bold", out = { say = { "Hah. You got guts. Fine, forget the fee." }, rep = 4 } },
			{ text = "Walk it back", tone = "calm", out = { say = { "Thought so. Small time." }, rep = -3 } },
			{ text = "Threaten to report him", tone = "hostile", out = { say = { "Now you're threatening me?" }, rep = -20, fight = 0.75 } },
		},
		timeout = { say = { "Clock's ticking and you're standing there. No deal." }, rep = -3 },
	},
	trash = {
		line = { "You got something to say to me?", "Say it again. To my face.", "Oh, you wanna go?" },
		options = {
			{ text = "Back down", tone = "calm", out = { say = { "Yeah. Walk it off, fish.", "Smart move." }, rep = -6 } },
			{ text = "Stare him down", tone = "bold", out = { say = { "...Tch. Not worth it.", "You got some nerve." }, rep = 8, fight = 0.45 } },
			{ text = "Swing first", tone = "hostile", out = { say = { "Oh it's ON!", "BIG mistake." }, rep = -10, fight = 1, co = 0.55, notice = "Every CO saw you start that." } },
			{ text = "Call your crew over", tone = "risky", out = { say = { "You need backup? Pathetic.", "Bring 'em. I'll wait." }, rep = -8, crew = true, fight = 0.4 } },
		},
		timeout = { say = { "Nothing? Then I'll say it for you.", "Silence. Figures." }, rep = -8, fight = 0.7 },
	},
}

-- v226: talking to the COs
SCENES.co_respect = {
	line = { "Keep it short, inmate.", "You want something?", "Make it quick." },
	options = {
		{ text = "\"Just saying thanks for keeping it calm, sir.\"", tone = "calm", out = { say = { "...Noted.", "Appreciate it. Stay out of trouble." }, corep = 6 } },
		{ text = "Offer to help clean the block", tone = "calm", out = { say = { "Mop's in the closet. Don't make me regret it.", "Good. Show me." }, corep = 10, notice = "You spent the afternoon mopping. The COs noticed." } },
		{ text = "Ask how his day is going", tone = "bold", out = { say = { "...Long. Thanks for asking.", "Same as yesterday. Move along." }, corep = 4, gamble = 5 } },
		{ text = "Complain about the food", tone = "risky", out = { say = { "Write a letter to the governor.", "It's prison, not a buffet." }, corep = -4 } },
	},
	timeout = { say = { "Nothing? Then move along." }, corep = -2 },
}
SCENES.co_favor = {
	line = { "A favor? Depends who's asking.", "Favors are earned, inmate." },
	options = {
		{ text = "Extra phone time", tone = "calm", out = { needs = 15, say = { "Fine. Ten minutes. Don't abuse it." }, corep = 1, notice = "Extra phone time - small wins.",
			fail = { say = { "Phone's for inmates I trust. Not you." }, corep = -1 } } },
		{ text = "Put in a good word with the parole board", tone = "bold", out = { needs = 50, say = { "You've earned it. I'll write it up." }, sentence = -120, notice = "A CO vouched for you: 2 minutes off your sentence.",
			fail = { say = { "A good word? For you? Earn it first." }, corep = -3 } } },
		{ text = "Ask him to look the other way tonight", tone = "risky", out = { needs = 70, say = { "I didn't see anything. For a while." }, blindEye = 300, corep = -5, notice = "The COs will look the other way for 5 minutes.",
			fail = { say = { "Are you asking me to break the rules?" }, corep = -12, co = 0.3 } } },
		{ text = "Slip him $500", tone = "risky", out = { needs = 0, cash = 500, say = { "...I'll see what I can do." }, corep = 12, sentence = -60, notice = "The CO pocketed it. A minute off your sentence.",
			fail = { say = { "BRIBING AN OFFICER?!" }, corep = -30, co = 0.8 } } },
	},
	timeout = { say = { "If you can't ask, don't waste my time." }, corep = -2 },
}
SCENES.co_snitch = {
	line = { "Information? Go on.", "You got something for me?" },
	options = {
		{ text = "Tell him who's dealing on the block", tone = "risky", out = { say = { "Good to know. We'll take it from here." }, corep = 12, snitch = true, notice = "If the yard finds out you talked..." } },
		{ text = "Warn him about a planned fight", tone = "calm", out = { say = { "Appreciate the heads up." }, corep = 8, snitch = true } },
		{ text = "Make something up", tone = "risky", out = { say = { "...We'll see if that checks out." }, gamble = 12, corep = -6 } },
		{ text = "Change your mind", tone = "calm", out = { say = { "Then stop wasting my time." }, corep = -3 } },
	},
	timeout = { say = { "Thought so. Nothing." }, corep = -2 },
}
SCENES.co_mouth = {
	line = { "What did you just say to me?", "Say that again, inmate." },
	options = {
		{ text = "\"Nothing, officer.\"", tone = "calm", out = { say = { "That's what I thought." }, corep = -2 } },
		{ text = "\"You heard me.\"", tone = "hostile", out = { say = { "Keep talking. See where it gets you." }, corep = -12, co = 0.35 } },
		{ text = "Spit at his feet", tone = "hostile", out = { say = { "That's it. You're done." }, corep = -25, co = 0.85, search = 1 } },
		{ text = "Laugh it off", tone = "bold", out = { say = { "Something funny? No? Then move." }, corep = -5, search = 0.3 } },
	},
	timeout = { say = { "Silent now? Smart. Barely." }, corep = -6, co = 0.2 },
}

local function startScene(player: Player, s: Session, id: string)
	local sc = SCENES[id]
	if not sc then
		return
	end
	s.stage = "scene"
	s.scene = sc
	s.depth = (s.depth or 0) + 1
	s.sceneEnds = os.clock() + SCENE_TIME
	s.expires = s.sceneEnds + 1
	s.token += 1 -- old buttons stop working
	local opts = {}
	for i, o in sc.options do
		table.insert(opts, { id = "scene" .. i, text = o.text, tone = o.tone })
	end
	sendDialogue(player, s, pick(sc.line), opts)
end

resolveScene = function(player: Player, s: Session, out: Outcome, timedOut: boolean?)
	local n = s.npc
	local gang = n.gang and GANGS[n.gang]
	s.scene = nil
	s.sceneEnds = nil
	s.answered = true
	-- v226: CO favors depend on your standing with the COs
	if out.needs and getCORespect(player) < out.needs and out.fail then
		out = out.fail
	end
	if out.corep then
		local d = out.corep
		if out.gamble and math.random() < 0.5 then
			d += out.gamble
		end
		addCORespect(player, d, if timedOut then "froze up" else nil)
	end
	if out.sentence then
		local adjust = ServerStorage:FindFirstChild("PrisonSentenceAdjust")
		if adjust then
			pcall(adjust.Invoke, adjust, player, out.sentence)
		end
	end
	if out.blindEye then
		player:SetAttribute("COBlindEyeUntil", os.time() + out.blindEye)
	end
	if out.snitch then
		local keys = {}
		for k in GANGS do
			table.insert(keys, k)
		end
		local g = keys[math.random(1, #keys)]
		if math.random() < 0.4 then
			addRep(player, g, -20, "word got out you snitched")
		end
	end
	if out.search and math.random() < out.search then
		task.delay(1, function()
			confiscate(player)
		end)
	end
	addRep(player, n.gang, out.rep or 0, if timedOut then "froze up" else "chose")
	if out.rival and gang then
		setRep(player, gang.rival, getRep(player, gang.rival) + out.rival)
	end
	if out.crew then
		local mine = player:GetAttribute("PrisonGang")
		if type(mine) == "string" and GANGS[mine] then
			addRep(player, mine, 5, "called the crew")
			notice(player, GANGS[mine].name .. " have your back")
		else
			notice(player, "Nobody's coming. You don't have a crew.")
		end
	end
	if out.cash and out.cash > 0 then
		if not economy("Charge", player, out.cash) then
			out = { say = { "You ain't even got it? You wasted my time." }, fight = 0.6 }
		end
	end
	if out.item == "Shiv" then
		giveShiv(player)
	elseif out.item == "Pills" then
		givePills(player)
	end
	if out.notice then
		notice(player, out.notice)
	end
	local line = pick(out.say)
	local fights = out.fight and math.random() < out.fight
	if out.co and math.random() < out.co then
		task.delay(1.5, function()
			notice(player, "A correctional officer saw that - you're going to solitary")
			discipline(player, "caught in the act")
		end)
	end
	if out.next and not fights and (s.depth or 0) < 3 and SCENES[out.next] then
		say(n.model, line, 3)
		s.expires = os.clock() + 5
		task.delay(1.2, function()
			if sessions[player] == s then
				startScene(player, s, out.next :: string)
			end
		end)
		return
	end
	say(n.model, line, 4)
	closeDialogue(player)
	if fights then
		task.delay(0.4, function()
			attack(n, player, 20)
		end)
	end
end

DialogueRE.OnServerEvent:Connect(function(player, token, choice)
	local s = sessions[player]
	if not s or s.token ~= token or type(choice) ~= "string" then
		return
	end
	if s.scene then
		-- mid-scene only the scene's own answers count (no backing out)
		local idx = tonumber(string.match(choice, "^scene(%d)$"))
		local opt = idx and s.scene.options[idx]
		if opt then
			resolveScene(player, s, opt.out, false)
		end
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
	elseif choice == "respect" or choice == "joke" or choice == "trash" then
		startScene(player, s, choice)
	elseif n.co and string.sub(choice, 1, 3) == "co_" and SCENES[choice] then
		startScene(player, s, choice)
	elseif choice == "trash_legacy" then
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
		local wares = {
			{ id = "buy_shiv", text = ("Shiv - $%d"):format(math.floor(PRICES.Shiv * discount)) },
			{ id = "buy_pills", text = ("Prison Pills - $%d"):format(math.floor(PRICES.Pills * discount)) },
		}
		if n.model:GetAttribute("LockpickDealer") then
			table.insert(wares, { id = "buy_lockpick", text = ("Lockpick - $%d"):format(math.floor(PRICES.Lockpick * discount)) })
		end
		table.insert(wares, { id = "back", text = "Nah, never mind" })
		sendDialogue(player, s, if discount < 1 then "For you? Friends price." else "Cash only. No refunds.", wares)
	elseif choice == "buy_lockpick" and n.model:GetAttribute("LockpickDealer") and s.stage == "shop" then
		local price = math.floor(PRICES.Lockpick * (if mood == "friendly" then 0.8 else 1))
		local lockpicks = ServerStorage:FindFirstChild("Lockpicks")
		if not lockpicks then
			reply(player, s, "Fresh out. Come back later.", 0, nil, false)
		elseif economy("Charge", player, price) then
			pcall(lockpicks.Invoke, lockpicks, "Give", player)
			local tool = player:FindFirstChildOfClass("Backpack") and player.Backpack:FindFirstChild("Lockpick")
			if tool then
				tool:SetAttribute("Contraband", true)
			end
			addRep(player, n.gang, 5)
			reply(player, s, "Pick any door in here. You didn't get it from me.", 0, nil, false)
		else
			reply(player, s, ("$%d. Not a dollar less."):format(price), 0, nil, false)
		end
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
				elseif n.model:GetAttribute("LockpickDealer") and math.random() < 0.3 then
					line = pick({ "Every door in here has a weakness.", "Need to get somewhere you shouldn't? Talk to me.", "Picks aren't cheap. Freedom never is." })
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

-- v215: there's always exactly one inmate who can get you a lockpick
task.spawn(function()
	while true do
		task.wait(10)
		local current = nil
		local pool = {}
		for model, n in npcs do
			if model:GetAttribute("LockpickDealer") then
				current = n
			elseif n.hum.Health > 0 then
				table.insert(pool, n)
			end
		end
		if not current and #pool > 0 then
			local n = pick(pool)
			n.dealer = true
			n.model:SetAttribute("Dealer", true)
			n.model:SetAttribute("LockpickDealer", true)
			setupPrompt(n)
			local prompt = n.root:FindFirstChild("SocietyTalk")
			if prompt then
				prompt.ObjectText = n.name .. " (connected)"
			end
		end
	end
end)

---------------------------------------------------------------------------
-- v229 RIOTS
---------------------------------------------------------------------------
local RIOT_LINES = {
	start = { "BURN IT DOWN!", "THEY CAN'T HOLD ALL OF US!", "GET THE COs!", "IT'S GOING DOWN!", "NO MORE!", "TAKE THE BLOCK!" },
	co = { "Not so tough now, huh?!", "Where's your baton now?!", "This is for the hole!", "Get him!" },
	gang = { "Tonight we settle it!", "Your crew's finished!", "This our yard now!" },
	subdued = { "Alright! Alright!", "I'm down, I'm down!", "Get off me!", "I give!" },
	warn = { "Something's gonna pop off...", "These COs pushing too hard, man.", "Whole block's on edge.", "It's gonna blow, watch." },
	coProvoke = { "Wall. Now.", "You got a problem, inmate?", "Move it, or you're going in the hole.", "Shakedown. Strip the bunk.", "Keep running your mouth." },
	inmateBack = { "Man, get off me!", "This is harassment!", "Every day with this...", "Y'all gonna push somebody too far." },
}

local RIOT_MIN_GAP = 300 -- seconds between riots
local RIOT_LEVEL = 62 -- the anger level where a riot can break out
local GANG_WAR_HEAT = 72 -- rival crews this angry go to war

local function broadcast(inmateText: string, outsideText: string?)
	for _, p in Players:GetPlayers() do
		if isInmate(p) then
			notice(p, inmateText)
		elseif outsideText then
			notice(p, outsideText)
		end
	end
end

local function nearestCO(pos: Vector3, radius: number, minHealth: number): Npc?
	local best, bestD = nil, radius
	for _, co in cos do
		if co.model.Parent and co.hum.Health > minHealth then
			local d = (co.root.Position - pos).Magnitude
			if d < bestD and math.abs(co.root.Position.Y - pos.Y) < 14 then
				best, bestD = co, d
			end
		end
	end
	return best
end

local function riotAlive(n: Npc): boolean
	return Riot.rioters[n] ~= nil and n.model.Parent ~= nil and n.hum.Health > 0
end

local function subdue(n: Npc, by: Npc?)
	if Riot.rioters[n] == nil then
		return
	end
	Riot.rioters[n] = nil
	n.model:SetAttribute("Rioting", nil)
	n.hum.Health = math.max(n.hum.Health, 20)
	n.hum:MoveTo(n.root.Position)
	say(n.model, pick(RIOT_LINES.subdued), 3)
	if by then
		say(by.model, pick({ "Stay down!", "On the ground!", "Hands behind your back!" }), 3)
	end
	releaseNpc(n)
end

-- one rioter's behaviour: go after COs, rivals, or a player they hate
local function runRioter(n: Npc)
	local target: Model? = nil
	local nextPick, nextHit = 0, 0
	while Riot.active and riotAlive(n) do
		if os.clock() >= nextPick then
			nextPick = os.clock() + 1.5
			target = nil
			local pos = n.root.Position
			-- the officers are the main target, unless this is a gang war
			local wantCO = Riot.cause ~= "gang" or math.random() < 0.35
			local co = wantCO and nearestCO(pos, 90, 20) or nil
			if co then
				target = co.model
			else
				-- a rival still standing
				local rival = n.gang and GANGS[n.gang].rival
				local bestD = 45
				if rival then
					for other in Riot.rioters do
						if other.gang == rival and riotAlive(other) then
							local d = (other.root.Position - pos).Magnitude
							if d < bestD then
								target, bestD = other.model, d
							end
						end
					end
				end
				-- or a player inmate this crew has a problem with / who's with the COs
				if not target then
					for _, p in Players:GetPlayers() do
						local _, proot = charInfo(p.Character)
						if proot and isInmate(p) and (hostileTo(p, n.gang) or getCORespect(p) >= 60) then
							local d = (proot.Position - pos).Magnitude
							if d < bestD then
								target, bestD = p.Character, d
							end
						end
					end
				end
				if not target then
					co = nearestCO(pos, 200, 20)
					target = co and co.model or nil
				end
			end
		end
		local thum, troot = charInfo(target)
		if n.hum.Sit then
			n.hum.Sit = false
			n.hum.Jump = true
		end
		if target and thum and troot and thum.Health > 0 then
			local d = (troot.Position - n.root.Position).Magnitude
			if d > 3.5 then
				n.hum:MoveTo(troot.Position)
			else
				n.hum:MoveTo(n.root.Position)
				n.root.CFrame = CFrame.lookAt(n.root.Position, Vector3.new(troot.Position.X, n.root.Position.Y, troot.Position.Z))
			end
			if d <= PUNCH_RANGE and os.clock() >= nextHit then
				nextHit = os.clock() + 0.8 + math.random() * 0.5
				swing(n.model)
				hitSound(troot, false)
				local victimNpc = npcs[target :: Model]
				if cos[target :: Model] then
					-- officers go down but aren't beaten to death
					thum.Health = math.max(12, thum.Health - NPC_FIST_DAMAGE)
					if math.random() < 0.3 then
						say(n.model, pick(RIOT_LINES.co), 2.5)
					end
				elseif victimNpc then
					thum.Health = math.max(8, thum.Health - 6)
				else
					local victim = Players:GetPlayerFromCharacter(target)
					if victim and not isCuffed(thum) then
						thum:TakeDamage(NPC_FIST_DAMAGE)
					end
				end
				Riot.rioters[n] = (Riot.rioters[n] or 0) + 1
			end
		else
			-- nobody to hit: roam the block and shout
			if math.random() < 0.05 then
				say(n.model, pick(RIOT_LINES.start), 2.5)
			end
			n.hum:MoveTo(n.root.Position + Vector3.new(math.random(-14, 14), 0, math.random(-14, 14)))
		end
		task.wait(0.3)
	end
	if Riot.rioters[n] ~= nil then
		Riot.rioters[n] = nil
		n.model:SetAttribute("Rioting", nil)
		releaseNpc(n)
	end
end

local function recruit(n: Npc, line: { string })
	if Riot.rioters[n] ~= nil or not take(n) then
		return false
	end
	Riot.rioters[n] = 0
	n.model:SetAttribute("Rioting", true)
	if math.random() < 0.6 then
		say(n.model, pick(line), 3)
	end
	task.spawn(runRioter, n)
	return true
end

local function rioterCount(): number
	local c = 0
	for n in Riot.rioters do
		if riotAlive(n) then
			c += 1
		end
	end
	return c
end

local function endRiot(suppressed: boolean)
	if not Riot.active then
		return
	end
	Riot.active = false
	local ringleaders = {}
	for n, hits in Riot.rioters do
		table.insert(ringleaders, { n = n, hits = hits })
		if n.model.Parent then
			n.model:SetAttribute("Rioting", nil)
			n.hum:MoveTo(n.root.Position)
			releaseNpc(n)
		end
	end
	table.clear(Riot.rioters)
	-- the worst offenders go to solitary
	table.sort(ringleaders, function(a, b)
		return a.hits > b.hits
	end)
	for i = 1, math.min(3, #ringleaders) do
		local n = ringleaders[i].n
		if n.model.Parent and n.hum.Health > 0 then
			discipline(n.model, "rioting")
		end
	end
	-- players on camera swinging at officers pay for it; the ones who kept out earn a little trust
	local adjust = ServerStorage:FindFirstChild("PrisonSentenceAdjust")
	for _, p in Players:GetPlayers() do
		if not isInmate(p) then
			continue
		end
		local hits = Riot.coHits[p] or 0
		if hits >= 2 then
			notice(p, "Cameras caught you attacking officers: solitary, +5:00 on your sentence")
			addCORespect(p, -20, "rioting")
			if adjust then
				pcall(adjust.Invoke, adjust, p, 300)
			end
			discipline(p, "inciting a riot")
		elseif hits == 0 then
			addCORespect(p, 5, "stayed out of the riot")
		end
	end
	table.clear(Riot.coHits)
	-- the pressure is let out
	Riot.tension = 18
	Riot.coAnger = math.max(8, Riot.coAnger * 0.35)
	for k, v in Riot.gangAnger do
		Riot.gangAnger[k] = math.max(8, v * 0.5)
	end
	Riot.lastRiot = os.clock()
	folder:SetAttribute("RiotLockdownUntil", os.time() + 150)
	riotPublish()
	broadcast(
		if suppressed then "Riot suppressed. FACILITY LOCKDOWN - everyone back to your cells." else "The riot burned itself out. FACILITY LOCKDOWN - back to your cells.",
		"News: the prison riot is over - the facility is on lockdown"
	)
	print(("[PrisonSociety] RIOT ENDED (%s)"):format(if suppressed then "suppressed" else "burned out"))
end

local function startRiot(cause: string)
	if Riot.active then
		return
	end
	Riot.active = true
	Riot.cause = cause
	table.clear(Riot.coHits)
	riotPublish()
	local level = riotLevel()
	local why = if cause == "co" then "The inmates have had enough of the COs"
		elseif cause == "gang" then "A gang war boiled over"
		else "The whole prison boiled over"
	broadcast("RIOT! " .. why .. " - fight the COs, pick a side, or keep your head down.",
		"Breaking news: a riot has broken out at the State Prison")
	-- who joins: more inmates the angrier the place is, crews most of all
	local joined = 0
	for _, n in npcs do
		if free(n) and n.hum.Health > 30 then
			local chance = 0.35 + level / 220
			if n.gang then
				chance += (Riot.gangAnger[n.gang] or 0) / 400
			end
			if math.random() < chance and recruit(n, if cause == "gang" then RIOT_LINES.gang else RIOT_LINES.start) then
				joined += 1
			end
		end
	end
	print(("[PrisonSociety] RIOT STARTED cause=%s level=%d rioters=%d"):format(cause, math.floor(level), joined))
	if joined < 2 then
		endRiot(true)
		return
	end
	local initial = joined
	local started = os.clock()
	local duration = 110 + math.random(0, 70)
	-- officers respond: they converge on rioters and put them down
	task.spawn(function()
		local nextCall = 0
		while Riot.active do
			if os.clock() >= nextCall then
				nextCall = os.clock() + 12
				local spots = {}
				for n in Riot.rioters do
					if riotAlive(n) then
						table.insert(spots, n.root.Position)
					end
				end
				for i = 1, math.min(4, #spots) do
					local pos = spots[math.random(1, #spots)]
					task.spawn(callCO, pos)
				end
			end
			for _, co in cos do
				if not (co.model.Parent and co.hum.Health > 0) then
					continue
				end
				local best: Npc?, bestD = nil, 7
				for n in Riot.rioters do
					if riotAlive(n) then
						local d = (n.root.Position - co.root.Position).Magnitude
						if d < bestD then
							best, bestD = n, d
						end
					end
				end
				if best then
					swing(co.model)
					hitSound(best.root, false)
					best.hum.Health = math.max(1, best.hum.Health - 16)
					if best.hum.Health <= 30 then
						subdue(best, co)
					end
				end
			end
			-- the riot spreads while it's going well for the inmates
			if math.random() < 0.08 then
				for _, n in npcs do
					if free(n) and n.hum.Health > 30 and math.random() < 0.25 then
						recruit(n, RIOT_LINES.start)
					end
				end
			end
			local left = rioterCount()
			if left == 0 or left < math.max(2, initial * 0.25) then
				endRiot(true)
				break
			end
			if os.clock() - started > duration then
				endRiot(false)
				break
			end
			task.wait(0.6)
		end
	end)
end

-- a gang war: the two angriest rival crews brawl; the COs wade in
local function startGangWar(gang: string)
	local rival = GANGS[gang].rival
	Riot.lastGangWar = os.clock()
	local sideA, sideB = {}, {}
	for _, n in npcs do
		if free(n) and n.hum.Health > 40 then
			if n.gang == gang then
				table.insert(sideA, n)
			elseif n.gang == rival then
				table.insert(sideB, n)
			end
		end
	end
	if #sideA == 0 or #sideB == 0 then
		return
	end
	broadcast(("Gang war! %s and %s are going at it"):format(GANGS[gang].name, GANGS[rival].name))
	print(("[PrisonSociety] GANG WAR %s vs %s (%d vs %d)"):format(gang, rival, #sideA, #sideB))
	for i = 1, math.min(4, #sideA, #sideB) do
		task.spawn(npcFight, sideA[i], sideB[i])
	end
	-- the anger comes out in the fight; the COs cracking heads winds everyone up
	Riot.gangAnger[gang] = math.max(10, Riot.gangAnger[gang] - 30)
	Riot.gangAnger[rival] = math.max(10, Riot.gangAnger[rival] - 30)
	riotHeat(10, nil, nil, 6)
end

riotOnCOHit = function(player: Player, co: Npc)
	if Riot.active then
		Riot.coHits[player] = (Riot.coHits[player] or 0) + 1
		if Riot.coHits[player] == 1 then
			-- the crews respect someone who stands up to the COs
			for _, k in GANG_ORDER do
				addRep(player, k, 3)
			end
			notice(player, "The block saw you swing at a CO")
		end
		addCORespect(player, -6)
		return
	end
	-- outside a riot, hitting an officer is a trip to the hole - and the block cheers
	say(co.model, pick({ "Assault on staff!", "You just made a big mistake.", "Get on the ground!" }), 3)
	addCORespect(player, -15, "assaulting a CO")
	for _, n in freeNpcsNear(co.root.Position, 40) do
		if math.random() < 0.4 then
			say(n.model, pick({ "OHHH!", "He hit the CO!", "About time somebody did!" }), 2.5)
		end
	end
	riotHeat(5, nil, nil, 6)
	if isInmate(player) then
		confiscate(player)
		discipline(player, "assaulting staff")
	end
end

-- COs provoking inmates: random shakedowns and rough handling
task.spawn(function()
	while true do
		task.wait(math.random(45, 90))
		if Riot.active then
			continue
		end
		local list = {}
		for _, co in cos do
			if co.model.Parent and co.hum.Health > 0 then
				table.insert(list, co)
			end
		end
		if #list == 0 then
			continue
		end
		local co = pick(list)
		local near = freeNpcsNear(co.root.Position, 28)
		if #near == 0 then
			continue
		end
		local n = pick(near)
		say(co.model, pick(RIOT_LINES.coProvoke), 3.5)
		task.delay(1.2, function()
			if n.model.Parent then
				say(n.model, pick(RIOT_LINES.inmateBack), 3.5)
			end
		end)
		local rough = math.random() < 0.3 + Riot.coAnger / 400
		if rough and n.hum.Health > 30 then
			n.hum.Health -= 15
			riotHeat(3, n.gang, 4, 7)
		else
			riotHeat(1, n.gang, 1, 3)
		end
	end
end)

-- cooling off, warnings, and boiling over
task.spawn(function()
	while true do
		task.wait(15)
		if Riot.active then
			continue
		end
		-- things calm down slowly on their own (faster during a lockdown)
		local lockdown = (tonumber(folder:GetAttribute("RiotLockdownUntil")) or 0) > os.time()
		local cool = if lockdown then 2.5 else 0.6
		Riot.tension = math.max(5, Riot.tension - cool)
		Riot.coAnger = math.max(5, Riot.coAnger - cool * 0.7)
		for k, v in Riot.gangAnger do
			Riot.gangAnger[k] = math.max(5, v - cool * 0.5)
		end
		-- a crowded prison simmers: more inmates on the floor, more friction
		local out = 0
		for _, n in npcs do
			if free(n) then
				out += 1
			end
		end
		if out >= 10 then
			Riot.tension = math.min(100, Riot.tension + 0.4)
		end
		riotPublish()
		if lockdown then
			continue
		end
		local level = riotLevel()
		local gangHeat, hotGang = riotGangHeat()
		if level >= RIOT_LEVEL - 12 and os.clock() - Riot.lastWarning > 120 then
			Riot.lastWarning = os.clock()
			for _, n in npcs do
				if free(n) and math.random() < 0.3 then
					say(n.model, pick(RIOT_LINES.warn), 4)
				end
			end
			broadcast("The prison is on edge - you can feel it (anger " .. math.floor(level) .. "/100)")
		end
		if hotGang and gangHeat >= GANG_WAR_HEAT and os.clock() - Riot.lastGangWar > 180 and math.random() < 0.5 then
			startGangWar(hotGang)
		elseif level >= RIOT_LEVEL and os.clock() - Riot.lastRiot > RIOT_MIN_GAP and math.random() < (level - RIOT_LEVEL + 8) / 60 then
			local gang = riotGangHeat()
			local cause = if Riot.coAnger >= Riot.tension and Riot.coAnger >= gang then "co"
				elseif gang > Riot.tension then "gang"
				else "tension"
			startRiot(cause)
		end
	end
end)

-- Studio / admin testing: ServerStorage.PrisonRiot:Invoke("start" | "gangwar" | "end" | "status")
do
	local fn = ServerStorage:FindFirstChild("PrisonRiot") or Instance.new("BindableFunction")
	fn.Name = "PrisonRiot"
	fn.OnInvoke = function(action)
		if action == "start" then
			startRiot("co")
		elseif action == "gangwar" then
			local _, g = riotGangHeat()
			startGangWar(g or "EK")
		elseif action == "end" then
			endRiot(true)
		end
		return { level = riotLevel(), tension = Riot.tension, co = Riot.coAnger, active = Riot.active }
	end
	fn.Parent = ServerStorage
end

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

-- v226: what the COs think of you plays out on its own. Every so often a CO who is
-- near an inmate reacts to their standing: low respect means cell searches, shake-
-- downs and trips to solitary for nothing much; high respect earns small favors.
-- Respect also drifts slowly back toward zero.
task.spawn(function()
	while true do
		task.wait(45)
		for _, player in Players:GetPlayers() do
			if not isInmate(player) then
				continue
			end
			local r = getCORespect(player)
			if r ~= 0 and math.random() < 0.5 then
				player:SetAttribute("CORespect", r - math.sign(r))
			end
			local _, root = charInfo(player.Character)
			if not root then
				continue
			end
			local nearCO: Npc? = nil
			for _, co in cos do
				if co.model.Parent and co.hum.Health > 0 and (co.root.Position - root.Position).Magnitude < 30 then
					nearCO = co
					break
				end
			end
			if not nearCO then
				continue
			end
			if r <= -60 and math.random() < 0.35 then
				say(nearCO.model, pick({ "You. Against the wall.", "I've had it with you. Let's go.", "Attitude check - solitary." }), 4)
				notice(player, "The COs have had enough of you - you're going to solitary")
				confiscate(player)
				addCORespect(player, 25) -- a stint in the hole resets things a little
				discipline(player, "disrespecting staff")
			elseif r <= -30 and math.random() < 0.4 then
				say(nearCO.model, pick({ "Shakedown. Arms out.", "Random search. Don't move." }), 4)
				notice(player, "A CO searched you")
				confiscate(player)
				riotHeat(1, nil, nil, 2.5)
			elseif r >= 60 and math.random() < 0.25 then
				say(nearCO.model, pick({ "You're alright, inmate.", "Keep it up and I'll put in a word for you." }), 4)
				local adjust = ServerStorage:FindFirstChild("PrisonSentenceAdjust")
				if adjust then
					pcall(adjust.Invoke, adjust, player, -30)
				end
				notice(player, "A CO put in a good word - 30 seconds off your sentence")
			end
		end
	end
end)

print("[PrisonSociety] ready: gangs, contraband, fights, CO respect, riots")
