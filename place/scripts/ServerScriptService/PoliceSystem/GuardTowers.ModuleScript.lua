--[[
	GuardTowers  (child ModuleScript of PoliceSystem)   v245

	One sniper + one spotlight per mapped GuardTower zone (or SniperPost / Spotlight
	points when mapped). Targets are ONLY:
	  * escapees (EscapeInProgress) and inmates OUTSIDE the prison walls  -> Perimeter rules
	  * inmates inside a mapped KillZone (between the fences)               -> KillZone rules
	Never anyone in the yard or other normal areas.

	Perimeter: alarm, "STOP! Get on the ground!", a warning shot, then fire to kill.
	KillZone:  alarm, one shout, then fire.
	StunZone:  (v245b) a KillZone whose Description says STUN / NON LETHAL, or ZoneType StunZone:
	           alarm, shout, then rubber bullets (never lethal, knock down for a few seconds)
	           and troops dispatched to the spot.
	Hands up (surrender) = hold fire. Spotlights sweep at night and lock onto targets.
	The alarm sets Workspace attribute PrisonLockdown for 2 minutes and calls ctx.alarm
	(radio + police response). A sniper kill of an escaping inmate calls ctx.sniperKill
	(counts as a prison death: profile wipe).

	init(ctx) ctx = { F, Util, outside(pos)->bool, isInmate(player)->bool, surrendered(player)->bool,
	                  tell(player, kind, text), notifyAll(text), alarm(player, pos), sniperKill(player) }
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local T = {}
T.VERSION = 245 -- v245b: stun zones

local CFG = {
	Range = 450, -- studs a tower covers
	ShoutDelay = 3, -- after the shout, before the warning shot
	WarnDelay = 2.5, -- after the warning shot, before firing to kill
	KillZoneDelay = 2, -- kill zone: shout, then fire
	FireInterval = 2.4, -- slow, aimed shots
	Damage = 45,
	HitChanceNear = 0.7, -- under 150 studs
	HitChanceFar = 0.4, -- at max range
	AlarmCooldown = 60,
	LockdownSeconds = 120,
	SweepDegrees = 70,
	SweepSeconds = 9,
	-- v245b non-lethal stun zone
	StunDelay = 2.5, -- shout, then rubber bullets
	StunInterval = 3,
	StunDamage = 8,
	StunMinHealth = 15, -- rubber bullets never take you below this
	StunKnockdown = 3, -- seconds on the ground
	StunHitChance = 0.75,
}
T.CFG = CFG

local ctx: any = nil
local towers: { any } = {}
local targets: { [Player]: any } = {}
local lastAlarm = -math.huge
local folder: Folder? = nil

local function night(): boolean
	local t = Lighting.ClockTime
	return t < 6.5 or t > 18.5
end

local function rayParams(ignore: { Instance }): RaycastParams
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = ignore
	return p
end

local function makePost(i: number, pos: Vector3, outward: Vector3): any
	local f = folder :: Folder
	local look = ctx.Util.safeUnit(Vector3.new(outward.X, 0, outward.Z), Vector3.zAxis)
	-- the sniper: a simple anchored marksman figure (no AI, it only aims and fires)
	local m = Instance.new("Model")
	m.Name = "TowerSniper_" .. i
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2, 2.4, 1)
	body.Color = Color3.fromRGB(35, 45, 60)
	body.Anchored = true
	body.CanCollide = false
	body.CFrame = CFrame.lookAt(pos + Vector3.new(0, 1.2, 0), pos + Vector3.new(0, 1.2, 0) + look)
	body.Parent = m
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.Color = Color3.fromRGB(205, 165, 125)
	head.Anchored = true
	head.CanCollide = false
	head.CFrame = body.CFrame * CFrame.new(0, 1.85, 0)
	head.Parent = m
	local rifle = Instance.new("Part")
	rifle.Name = "Rifle"
	rifle.Size = Vector3.new(0.25, 0.25, 3.2)
	rifle.Color = Color3.fromRGB(20, 20, 20)
	rifle.Anchored = true
	rifle.CanCollide = false
	rifle.CFrame = body.CFrame * CFrame.new(0.6, 0.8, -1.4)
	rifle.Parent = m
	m.PrimaryPart = body
	m.Parent = f
	-- the spotlight
	local lamp = Instance.new("Part")
	lamp.Name = "TowerSpotlight_" .. i
	lamp.Size = Vector3.new(1.4, 1.4, 1.4)
	lamp.Material = Enum.Material.Neon
	lamp.Color = Color3.fromRGB(255, 245, 210)
	lamp.Anchored = true
	lamp.CanCollide = false
	lamp.CanQuery = false
	lamp.CFrame = CFrame.lookAt(pos + Vector3.new(0, 4.5, 0), pos + Vector3.new(0, 4.5, 0) + look - Vector3.new(0, 0.35, 0))
	lamp.Parent = f
	local light = Instance.new("SpotLight")
	light.Range = 60
	light.Angle = 28
	light.Brightness = 6
	light.Face = Enum.NormalId.Front
	light.Enabled = false
	light.Parent = lamp
	return { i = i, pos = pos, eye = head.Position, look = look, model = m, body = body, head = head, rifle = rifle,
		lamp = lamp, light = light, nextShot = 0 }
end

local function aimAt(t: any, at: Vector3)
	local cf = CFrame.lookAt(t.body.Position, Vector3.new(at.X, t.body.Position.Y, at.Z))
	t.body.CFrame = cf
	t.head.CFrame = cf * CFrame.new(0, 1.85, 0)
	t.rifle.CFrame = CFrame.lookAt((cf * CFrame.new(0.6, 0.8, -1.4)).Position, at)
end

local function tracer(from: Vector3, to: Vector3)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 220, 140)
	local d = (to - from).Magnitude
	p.Size = Vector3.new(0.12, 0.12, d)
	p.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -d / 2)
	p.Parent = folder
	Debris:AddItem(p, 0.08)
end

local function canSee(t: any, char: Model, part: BasePart): boolean
	local dir = part.Position - t.eye
	local hit = Workspace:Raycast(t.eye, dir, rayParams({ folder :: Instance }))
	return hit == nil or hit.Instance:IsDescendantOf(char) or (hit.Position - t.eye).Magnitude >= dir.Magnitude - 2
end

-- v245b: a mapped kill zone marked non-lethal (description) or a StunZone
local function isStunZone(z: any): boolean
	local inst = z.instance
	if not inst then return false end
	if inst:GetAttribute("ZoneType") == "StunZone" then return true end
	local d = string.upper(tostring(inst:GetAttribute("Description") or "") .. " " .. inst.Name)
	return string.find(d, "STUN", 1, true) ~= nil or string.find(d, "NON LETHAL", 1, true) ~= nil
		or string.find(d, "NON-LETHAL", 1, true) ~= nil or string.find(d, "RUBBER", 1, true) ~= nil
end

-- what rules apply to this player right now: "Perimeter", "KillZone", "StunZone" or nil
local function ruleFor(player: Player, pos: Vector3): string?
	local escaping = player:GetAttribute("EscapeInProgress") == true
	local inmate = ctx.isInmate(player)
	local feet = pos - Vector3.new(0, 3, 0)
	-- v245c: kill / stun zones are restricted ground for EVERYONE except police and
	-- staff (a citizen climbing the fences gets the same treatment as an inmate)
	local law = false
	pcall(function() law = (ctx.isStaff and ctx.isStaff(player)) or ctx.Util.isLaw(player) end)
	if not law or escaping or inmate then
		-- lethal zones win where a lethal and a stun zone overlap
		local stun = false
		for _, z in ctx.F.zones("Prison", "KillZone") do
			if ctx.F.inZone(z, feet, 2) then
				if isStunZone(z) then stun = true else return "KillZone" end
			end
		end
		for _, z in ctx.F.zones("Prison", "StunZone") do
			if ctx.F.inZone(z, feet, 2) then stun = true end
		end
		if stun then return "StunZone" end
	end
	-- the perimeter (outside the walls) only concerns inmates and escapees
	if not escaping and not inmate then return nil end
	if ctx.outside(pos) then return "Perimeter" end
	for _, z in ctx.F.zones("Prison", "Perimeter") do
		if ctx.F.inZone(z, feet, 2) then return "Perimeter" end
	end
	return nil
end

local function raiseAlarm(player: Player, pos: Vector3, rule: string)
	if os.clock() - lastAlarm < CFG.AlarmCooldown then return end
	lastAlarm = os.clock()
	Workspace:SetAttribute("PrisonLockdown", true)
	task.delay(CFG.LockdownSeconds, function() Workspace:SetAttribute("PrisonLockdown", nil) end)
	print(("[GuardTowers] ALARM %s in the %s - lockdown %ds"):format(player.Name, rule, CFG.LockdownSeconds))
	pcall(ctx.notifyAll, "PRISON ALARM - escape attempt! The prison is in lockdown.")
	pcall(ctx.alarm, player, pos)
end

local function shoot(t: any, player: Player, char: Model, hum: Humanoid, part: BasePart, warning: boolean)
	local from = t.rifle.Position
	local dist = (part.Position - from).Magnitude
	if warning then
		-- into the ground a few studs in front of them
		local miss = part.Position + Vector3.new(math.random(-4, 4), -3, math.random(-4, 4))
		tracer(from, miss)
		return
	end
	local chance = CFG.HitChanceFar + (CFG.HitChanceNear - CFG.HitChanceFar) * math.clamp(1 - (dist - 150) / (CFG.Range - 150), 0, 1)
	if math.random() < chance then
		tracer(from, part.Position)
		-- v245c: only an inmate / escapee's death is a prison death (profile wipe);
		-- a trespassing citizen just dies
		local prisoner = player:GetAttribute("EscapeInProgress") == true or ctx.isInmate(player)
		if prisoner and hum.Health - CFG.Damage <= 0 then
			player:SetAttribute("PrisonKilledBy", "Tower sniper")
			player:SetAttribute("TowerSniperKill", true)
		end
		hum:TakeDamage(CFG.Damage)
		if hum.Health <= 0 then
			print(("[GuardTowers] %s shot dead by tower %d%s"):format(player.Name, t.i, if prisoner then "" else " (trespasser)"))
			if prisoner then pcall(ctx.sniperKill, player) end
		end
	else
		tracer(from, part.Position + Vector3.new(math.random(-6, 6), math.random(-2, 4), math.random(-6, 6)))
	end
end

-- v245b: rubber bullet - hurts, never kills, knocks them down
local function stunShot(t: any, player: Player, hum: Humanoid, part: BasePart)
	local from = t.rifle.Position
	if math.random() >= CFG.StunHitChance then
		tracer(from, part.Position + Vector3.new(math.random(-5, 5), math.random(-2, 3), math.random(-5, 5)))
		return
	end
	tracer(from, part.Position)
	local dmg = math.min(CFG.StunDamage, math.max(0, hum.Health - CFG.StunMinHealth))
	if dmg > 0 then hum:TakeDamage(dmg) end
	hum.PlatformStand = true
	player:SetAttribute("TowerStunned", true)
	pcall(ctx.tell, player, "Custody", "TOWER: Rubber rounds! Stay down - officers are on the way.")
	print(("[GuardTowers] %s hit with a rubber round by tower %d"):format(player.Name, t.i))
	task.delay(CFG.StunKnockdown, function()
		if hum.Parent then hum.PlatformStand = false end
		player:SetAttribute("TowerStunned", nil)
	end)
end

local function step(now: number)
	local isNight = night()
	local sweep = math.sin(now / CFG.SweepSeconds * math.pi * 2) * math.rad(CFG.SweepDegrees)
	-- who is a target, and which tower is best placed for them
	local engaged: { [any]: { player: Player, char: Model, hum: Humanoid, part: BasePart, rule: string } } = {}
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local st = targets[player]
		if hum and root and root:IsA("BasePart") and hum.Health > 0 then
			local rule = ruleFor(player, root.Position)
			if rule then
				local best, bestD = nil, CFG.Range
				for _, t in towers do
					local d = (root.Position - t.eye).Magnitude
					if d < bestD and canSee(t, char, root) then best, bestD = t, d end
				end
				if best then
					if not st or st.rule ~= rule then
						st = { rule = rule, stage = "seen", at = now }
						targets[player] = st
						raiseAlarm(player, root.Position, rule)
						if rule == "StunZone" then
							pcall(ctx.tell, player, "Custody", "TOWER: Restricted area! Get on the ground or we fire rubber rounds!")
						elseif rule == "KillZone" then
							pcall(ctx.tell, player, "Custody", "TOWER: You are in the kill zone! Get down!")
						else
							pcall(ctx.tell, player, "Custody", "TOWER: STOP! Get on the ground!")
						end
						print(("[GuardTowers] %s spotted by tower %d (%s, %.0f studs)"):format(player.Name, best.i, rule, bestD))
					end
					engaged[best] = { player = player, char = char, hum = hum, part = root, rule = rule }
				end
			else
				targets[player] = nil
			end
		else
			targets[player] = nil
		end
	end
	for _, t in towers do
		local e = engaged[t]
		t.light.Enabled = isNight or e ~= nil
		if e then
			local st = targets[e.player]
			aimAt(t, e.part.Position)
			t.lamp.CFrame = CFrame.lookAt(t.lamp.Position, e.part.Position)
			local surrendered = ctx.surrendered(e.player)
			if surrendered then
				st.held = true
			elseif now >= t.nextShot then
				local since = now - st.at
				if e.rule == "StunZone" then
					if since >= CFG.StunDelay then
						t.nextShot = now + CFG.StunInterval
						stunShot(t, e.player, e.hum, e.part)
					end
				elseif e.rule == "KillZone" then
					if since >= CFG.KillZoneDelay then
						t.nextShot = now + CFG.FireInterval
						shoot(t, e.player, e.char, e.hum, e.part, false)
					end
				elseif st.stage == "seen" and since >= CFG.ShoutDelay then
					st.stage = "warned"
					st.at = now
					t.nextShot = now + CFG.WarnDelay
					pcall(ctx.tell, e.player, "Custody", "TOWER: Warning shot! Next one won't miss.")
					shoot(t, e.player, e.char, e.hum, e.part, true)
				elseif st.stage == "warned" then
					t.nextShot = now + CFG.FireInterval
					shoot(t, e.player, e.char, e.hum, e.part, false)
				end
			end
		else
			-- idle: sweep outward (only visible at night)
			local dir = CFrame.fromAxisAngle(Vector3.yAxis, sweep) * t.look
			t.lamp.CFrame = CFrame.lookAt(t.lamp.Position, t.lamp.Position + dir * 30 - Vector3.new(0, 9, 0))
			if t.body.CFrame.LookVector:Dot(t.look) < 0.98 then aimAt(t, t.eye + t.look * 50) end
		end
	end
end

function T.init(c: any): number
	ctx = c
	local F = ctx.F
	local old = Workspace:FindFirstChild("GuardTowerPosts")
	if old then old:Destroy() end
	local f = Instance.new("Folder")
	f.Name = "GuardTowerPosts"
	f.Parent = Workspace
	folder = f
	towers = {}
	local prison = F.get("Prison")
	if not prison then return 0 end
	local center = Vector3.zero
	for _, z in prison.zones do center += z.center end
	center /= math.max(1, #prison.zones)
	local posts = F.points("Prison", "SniperPost")
	if #posts > 0 then
		for i, p in posts do
			table.insert(towers, makePost(i, p.position, p.cframe.LookVector))
		end
	else
		for i, z in F.zones("Prison", "GuardTower") do
			local hit = Workspace:Raycast(z.center + Vector3.new(0, 2, 0), Vector3.new(0, -12, 0))
			local floor = if hit then hit.Position else z.center
			table.insert(towers, makePost(i, floor, z.center - center))
		end
	end
	task.spawn(function()
		while folder and folder.Parent do
			local ok, err = pcall(step, os.clock())
			if not ok then warn("[GuardTowers] " .. tostring(err)) end
			task.wait(0.4)
		end
	end)
	local lethal, stun = 0, #F.zones("Prison", "StunZone")
	for _, z in F.zones("Prison", "KillZone") do
		if isStunZone(z) then stun += 1 else lethal += 1 end
	end
	print(("[GuardTowers] v%d: %d tower(s) manned (%s), lethal zones=%d stun zones=%d perimeter zones=%d"):format(T.VERSION, #towers,
		if #posts > 0 then "SniperPost points" else "GuardTower zones", lethal, stun, #F.zones("Prison", "Perimeter")))
	return #towers
end

return T
