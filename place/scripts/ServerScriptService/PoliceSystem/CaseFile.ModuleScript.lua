--[[
	CaseFile (v263b) - what the DA actually knows about each crime, for the court.

	Every crime that goes through Heat.addCrime is recorded as an INCIDENT:
	  { crime, charge, victim (a name - pedestrians and officers have names), place (the
	    landmark / building room), clock (the game time, "9:42 PM"), weapon (what was in your
	    hand), witnesses (people who could see it), officers (police who saw it), camera (inside a
	    mapped building = security cameras), count (repeats of the same crime folded together) }
	The victim's name comes from the killer's LastVictim attribute (set by CivilianServer for
	pedestrians and by the police for officers just before the crime is reported).
	LOCATION TRACKING: every player's whereabouts are logged every 20 s (place names, kept 40 min) -
	the DA's "cell-tower records".

	API
	  CF.init({ placeName = fn(pos) -> string, inBuilding = fn(pos) -> bool })
	  CF.onCrime(player, crimeName, pos, crime)      (chained into State.onCrime)
	  CF.caseFor(player) -> { incident }              most serious first
	  CF.trail(player, around: os.time, window) -> { { t, clock, place } }
	  CF.summaries(player) -> { string }              one line per incident (for the record)
	  CF.close(player)                                the case is over: start a new file
	Logs: [CaseFile]
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")

local CF = {}

local CHARGE = {
	Murder = "murder", CopKilled = "the murder of a police officer", AssaultOfficer = "assaulting an officer",
	ShotsFired = "unlawful discharge of a firearm", Assault = "assault", Robbery = "armed robbery",
	BankRobbery = "bank robbery", Burglary = "burglary", VehicleTheft = "grand theft auto", Drugs = "drug dealing",
	PrisonEscape = "escape from custody", HelicopterDown = "downing a police aircraft", ResistingArrest = "resisting arrest",
	Carjacking = "carjacking", PrisonTrespass = "trespassing on prison grounds", PrisonFenceBreach = "breaching the prison fence",
}
local SEVERITY = {
	CopKilled = 100, Murder = 90, HelicopterDown = 85, BankRobbery = 70, Robbery = 60, AssaultOfficer = 55, PrisonEscape = 50,
	Assault = 40, ShotsFired = 35, Carjacking = 34, VehicleTheft = 30, Burglary = 28, Drugs = 25, PrisonFenceBreach = 20,
	ResistingArrest = 15, PrisonTrespass = 10,
}

local ctx: any = { placeName = function() return "downtown" end, inBuilding = function() return false end }
local files: { [Player]: { any } } = {}
local trails: { [Player]: { any } } = {}

function CF.init(c: any)
	for k, v in c do ctx[k] = v end
	print("[CaseFile] ready: incidents, victims, witnesses, location tracking")
end

-- the game clock as a time of day ("9:42 PM")
local function clockText(): string
	local t = Lighting.ClockTime
	local h = math.floor(t)
	local m = math.floor((t - h) * 60)
	local suffix = if h >= 12 then "PM" else "AM"
	local h12 = h % 12
	if h12 == 0 then h12 = 12 end
	return ("%d:%02d %s"):format(h12, m, suffix)
end
CF.clockText = clockText

local function place(pos: Vector3): string
	local ok, name = pcall(ctx.placeName, pos)
	return if ok and type(name) == "string" then name else "downtown"
end

-- who could see it: humanoids within 80 studs with a clear line of sight
local function witnesses(player: Player, pos: Vector3): (number, number)
	local civilians, officers = 0, 0
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	if player.Character then table.insert(ignore, player.Character) end
	params.FilterDescendantsInstances = ignore
	-- only what's near: the parts within 80 studs, and the humanoids they belong to
	local humans: { [Humanoid]: boolean } = {}
	for _, part in workspace:GetPartBoundsInRadius(pos, 80) do
		local model = part.Parent
		local hum = model and model:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and model ~= player.Character then humans[hum] = true end
	end
	for m in humans do
		local root = m.Parent and m.Parent:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local dir = (root.Position + Vector3.new(0, 1.5, 0)) - (pos + Vector3.new(0, 2, 0))
			local hit = workspace:Raycast(pos + Vector3.new(0, 2, 0), dir, params)
			if not hit or hit.Instance:IsDescendantOf(m.Parent) then
				local model = m.Parent :: Instance
				local isCop = model:GetAttribute("PoliceUnit") ~= nil or model:GetAttribute("PoliceNPC") ~= nil
					or model.Name:find("Officer") ~= nil or model.Name:find("Police") ~= nil
				local p = Players:GetPlayerFromCharacter(model)
				if p and p.Team and (p.Team.Name:find("Police") or p.Team.Name:find("SWAT") or p.Team.Name:find("FBI")) then isCop = true end
				if isCop then officers += 1 else civilians += 1 end
			end
		end
	end
	return civilians, officers
end

function CF.onCrime(player: Player, crimeName: string, pos: Vector3?, _crime: any?)
	if not pos then return end
	local list = files[player]
	if not list then
		list = {}
		files[player] = list
	end
	local now = os.time()
	-- the same crime again right away (a burst of shots) folds into the last incident
	for i = #list, math.max(1, #list - 3), -1 do
		local inc = list[i]
		if inc.crime == crimeName and now - inc.t < 20 and (inc.pos - pos).Magnitude < 80 and crimeName ~= "Murder" and crimeName ~= "CopKilled" then
			inc.count += 1
			return
		end
	end
	local char = player.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	local victim = nil
	local at = tonumber(player:GetAttribute("LastVictimAt")) or 0
	if (crimeName == "Murder" or crimeName == "CopKilled" or crimeName == "Assault" or crimeName == "AssaultOfficer") and now - at <= 3 then
		victim = player:GetAttribute("LastVictim")
		player:SetAttribute("LastVictim", nil)
	end
	local civ, cops = witnesses(player, pos)
	local okB, inside = pcall(ctx.inBuilding, pos)
	local inc = {
		crime = crimeName,
		charge = CHARGE[crimeName] or crimeName:lower(),
		victim = if type(victim) == "string" then victim else nil,
		place = place(pos),
		clock = clockText(),
		t = now,
		pos = pos,
		weapon = tool and tool.Name or nil,
		witnesses = civ,
		officers = cops,
		camera = okB and inside == true,
		count = 1,
		severity = SEVERITY[crimeName] or 20,
	}
	table.insert(list, inc)
	while #list > 25 do table.remove(list, 1) end
	print(("[CaseFile] %s: %s%s at %s, %s%s | %d witness(es), %d officer(s)%s"):format(player.Name, inc.charge,
		if inc.victim then " of " .. inc.victim else "", inc.place, inc.clock, if inc.weapon then " with a " .. inc.weapon else "",
		civ, cops, if inc.camera then ", on camera" else ""))
end

function CF.caseFor(player: Player): { any }
	local out = table.clone(files[player] or {})
	table.sort(out, function(a, b)
		if a.severity ~= b.severity then return a.severity > b.severity end
		return a.t < b.t
	end)
	return out
end

-- one line per incident: "Murder of Maria Delgado - near Fremont Street, 9:42 PM (Glock)"
function CF.describe(inc: any): string
	local what = inc.charge:sub(1, 1):upper() .. inc.charge:sub(2)
	if inc.victim then what ..= " of " .. inc.victim end
	if inc.count > 1 then what ..= (" (x%d)"):format(inc.count) end
	return ("%s - %s, %s%s"):format(what, inc.place, inc.clock, if inc.weapon then " (" .. inc.weapon .. ")" else "")
end

function CF.summaries(player: Player): { string }
	local out = {}
	for _, inc in CF.caseFor(player) do
		table.insert(out, CF.describe(inc))
	end
	return out
end

-- where the player's phone was around a time (the cell-tower records)
function CF.trail(player: Player, around: number, window: number?): { any }
	local out = {}
	for _, b in trails[player] or {} do
		if math.abs(b.t - around) <= (window or 300) then table.insert(out, b) end
	end
	return out
end

function CF.close(player: Player)
	files[player] = nil
end

-- location tracking: a breadcrumb every 20 s, whenever the place name changes (kept 40 min)
task.spawn(function()
	while true do
		task.wait(20)
		local now = os.time()
		for _, p in Players:GetPlayers() do
			local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if r then
				local list = trails[p]
				if not list then
					list = {}
					trails[p] = list
				end
				local name = place(r.Position)
				local last = list[#list]
				if not last or last.place ~= name then
					table.insert(list, { t = now, clock = clockText(), place = name })
				end
				while #list > 0 and now - list[1].t > 40 * 60 do table.remove(list, 1) end
			end
		end
	end
end)
Players.PlayerRemoving:Connect(function(p)
	files[p] = nil
	trails[p] = nil
end)

return CF
