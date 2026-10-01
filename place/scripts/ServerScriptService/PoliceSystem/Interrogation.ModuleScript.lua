--[[
	Interrogation  (child ModuleScript of PoliceSystem)   v246-v249

	v248 CRIME LOG - the secret truth of who did what. Every crime that goes through
	  Heat.addCrime is logged as an "event"; crimes of the same kind within LinkWindow
	  seconds and LinkRadius studs are the same event, its members are co-defendants.
	  Roles: Planner (first in on a robbery / burglary), Shooter (any violent crime),
	  Driver (did it from a vehicle seat), Lookout / Accomplice. Each member has an
	  evidence strength the police can prove (0-1), never shown to the suspect.
	  Co-defendants in custody are interviewed in different rooms and can't chat.

	v246 INTERROGATION - serious crimes, accomplices or thin evidence. A hold clock
	  (HoldSeconds, ~48 h of game time); Miranda; a clear "I want a lawyer" ends it,
	  "I'm not saying anything" pauses it; tactics: bluffs, "your buddy talked", good
	  cop, family, silence. Emotions: anxiety, fear, anger, exhaustion.

	v247 QTEs - the character wants to talk; the player fights it (bite, breath, nerve,
	  eye, slip; plus "say it clearly" for the lawyer request when anxious). Difficulty
	  follows the pressure. Small miss = nervous tell; bigger = slip (evidence up);
	  collapse = confession (the whole crew named).

	v249 SNITCHING - tell the truth, blame someone (crewmate, someone who got away,
	  an invented person), minimise, or deny. Stories are cross-checked against the log;
	  two people blaming the same person is believed; lies are caught (false statement).
	  First to give new info gets the best deal. Snitch jacket (leaks -> SnitchedOn,
	  the gang-hit hook), protective custody on request, underground access burned.

	Outputs (player attributes + Records): InterrogationEvidence, Confessed,
	NamedAccomplices, LawyeredUp, Cooperative, CooperationDeal, FalseStatements.
	run() returns { secsScale, extraCharges, ... } that the custody flow applies.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local I = {}
I.VERSION = 249

I.CFG = {
	HoldSeconds = 480, -- ~48 h of game time before you must see a judge
	LinkWindow = 180, -- seconds: crimes this close in time ...
	LinkRadius = 260, -- ... and space are one event (co-defendants)
	EventMemory = 1800, -- an arrest this long after the crime still links to it
	ChoiceTimeout = 30,
	QTETimeout = 14,
	SilenceBreak = 20, -- "I'm not saying anything": the detective leaves this long
	MaxRounds = 9,
	QTEPressure = 35, -- a QTE when pressure is at least this
	FalseStatementScale = 1.15,
	DealNew = 0.5, -- first to give new info (planner / shooter they didn't have)
	DealConfirm = 0.8,
	DealKnown = 0.95,
	MinimiseBelieved = 0.9,
	LeakChance = 0.5, -- a snitch's paperwork leaks to the gangs
}
local CFG = I.CFG

local LOGGED = {
	Robbery = "Robbery", BankRobbery = "Robbery", Burglary = "Robbery", VehicleTheft = "Theft",
	Murder = "Violence", CopKilled = "Violence", AssaultOfficer = "Violence", ShotsFired = "Violence", Assault = "Violence",
	Drugs = "Drugs", HelicopterDown = "Violence",
}
local VIOLENT = { Murder = true, CopKilled = true, AssaultOfficer = true, ShotsFired = true, Assault = true, HelicopterDown = true }
local ROLE_RANK = { Planner = 4, Shooter = 4, Driver = 2, Lookout = 1, Accomplice = 1 }

local ctx: any = nil
local events: { any } = {}
local sessions: { [Player]: any } = {}
local roomsInUse: { [Instance]: Player } = {}
local nextEventId = 0

local remote = ReplicatedStorage:FindFirstChild("Interrogation")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "Interrogation"
	remote.Parent = ReplicatedStorage
end
I.remote = remote

local function send(player: Player, ...)
	if player.Parent then (remote :: RemoteEvent):FireClient(player, ...) end
end

---------------------------------------------------------------------------
-- v248 crime log
---------------------------------------------------------------------------
local function memberOf(ev: any, player: Player): any?
	return ev.members[player.UserId]
end

function I.onCrime(player: Player, crimeName: string, pos: Vector3?, crime: any?)
	local family = LOGGED[crimeName]
	if not family or not pos then return end
	local now = os.clock()
	local ev = nil
	for i = #events, 1, -1 do
		local e = events[i]
		if now - e.last > CFG.LinkWindow then break end
		if e.family == family and (e.pos - pos).Magnitude <= CFG.LinkRadius then ev = e; break end
	end
	if not ev then
		nextEventId += 1
		ev = { id = nextEventId, family = family, crime = crimeName, pos = pos, t = now, last = now,
			members = {}, order = 0, talked = {}, blames = {}, named = {} }
		table.insert(events, ev)
		while #events > 60 do table.remove(events, 1) end
	end
	ev.last = now
	if VIOLENT[crimeName] and not VIOLENT[ev.crime] then ev.crime = crimeName end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local inVehicle = hum ~= nil and hum.SeatPart ~= nil and hum.SeatPart:IsA("VehicleSeat")
	local m = memberOf(ev, player)
	if not m then
		ev.order += 1
		local role = if VIOLENT[crimeName] then "Shooter"
			elseif inVehicle then "Driver"
			elseif ev.order == 1 and family == "Robbery" then "Planner"
			elseif ev.order == 1 then "Accomplice"
			else "Lookout"
		local evidence = 0.35 + (if crime and crime.Witness then 0.2 else 0) + math.random() * 0.25
		m = { userId = player.UserId, name = player.Name, player = player, role = role, evidence = math.min(0.95, evidence), crimes = {} }
		ev.members[player.UserId] = m
		print(("[CrimeLog] event #%d %s: %s joins as %s (evidence %.2f)"):format(ev.id, ev.crime, player.Name, role, m.evidence))
	else
		-- violence upgrades the role; repeated crimes add evidence
		if VIOLENT[crimeName] and m.role ~= "Shooter" and m.role ~= "Planner" then m.role = "Shooter" end
		m.evidence = math.min(0.95, m.evidence + 0.05)
	end
	m.crimes[crimeName] = true
	player:SetAttribute("CrimeEventId", ev.id)
end

-- the most recent event this player is part of (still relevant at arrest time)
function I.eventFor(player: Player): any?
	local now = os.clock()
	for i = #events, 1, -1 do
		local e = events[i]
		if now - e.last > CFG.EventMemory then break end
		if memberOf(e, player) then return e end
	end
	return nil
end

function I.coDefendants(player: Player): { any }
	local out = {}
	local ev = I.eventFor(player)
	if ev then
		for uid, m in ev.members do
			if uid ~= player.UserId then table.insert(out, m) end
		end
	end
	return out
end

function I.shouldInterrogate(player: Player, keys: { [string]: boolean }, stars: number): (boolean, string)
	local ev = I.eventFor(player)
	local m = ev and memberOf(ev, player)
	if #I.coDefendants(player) > 0 then return true, "accomplices involved" end
	if keys.Murder or keys.CopKilled or keys.BankRobbery or keys.Robbery or keys.HelicopterDown then return true, "serious crime" end
	if m and m.evidence < 0.45 then return true, "thin evidence" end
	return false, "case is solid"
end

---------------------------------------------------------------------------
-- co-defendants can't talk to each other while in custody (legacy chat mute)
---------------------------------------------------------------------------
local chatService: any = nil
local function getChat(): any?
	if chatService then return chatService end
	local runner = ServerScriptService:FindFirstChild("ChatServiceRunner")
	local mod = runner and runner:FindFirstChild("ChatService")
	if mod then
		local ok, cs = pcall(require, mod)
		if ok then chatService = cs end
	end
	return chatService
end

local function muteBetween(a: Player, b: Player, on: boolean)
	local cs = getChat()
	if not cs then return end
	pcall(function()
		local sa, sb = cs:GetSpeaker(a.Name), cs:GetSpeaker(b.Name)
		if sa and sb then
			if on then sa:AddMutedSpeaker(b.Name); sb:AddMutedSpeaker(a.Name)
			else sa:RemoveMutedSpeaker(b.Name); sb:RemoveMutedSpeaker(a.Name) end
		end
	end)
end

function I.isolate(player: Player, on: boolean)
	for _, m in I.coDefendants(player) do
		if m.player and m.player.Parent then muteBetween(player, m.player, on) end
	end
end

---------------------------------------------------------------------------
-- rooms
---------------------------------------------------------------------------
function I.reserveRoom(player: Player): any?
	if not ctx or not ctx.F then return nil end
	local F = ctx.F
	local list = {}
	for _, t in { "PoliceHQ", "CityJail", "Prison" } do
		for _, z in F.zones(t, "Interrogation", true) do table.insert(list, z) end
		if #list > 0 then break end
	end
	for _, z in list do
		local who = roomsInUse[z.instance]
		if not who or not who.Parent or not sessions[who] then
			roomsInUse[z.instance] = player
			return z
		end
	end
	return nil
end

function I.releaseRoom(zone: any?)
	if zone then roomsInUse[zone.instance] = nil end
end

---------------------------------------------------------------------------
-- the session
---------------------------------------------------------------------------
local TACTICS = {
	{ key = "bluff", line = "We've got you on camera. Prints on everything. This is your chance to explain.", a = 12, f = 6, n = 0 },
	{ key = "goodcop", line = "Look, I get it. Things got out of hand. Just tell me your side and I'll see what I can do.", a = -4, f = -2, n = -4 },
	{ key = "family", line = "Think about your family. You want them reading about this in the news?", a = 6, f = 12, n = 4 },
	{ key = "silence", line = "...", a = 10, f = 4, n = 2, wait = 10 },
	{ key = "partner", line = "Your buddy in the other room is talking. He says this was all you.", a = 15, f = 6, n = 10, big = true },
	{ key = "death", line = "This is a capital case. The DA is talking about the death penalty.", a = 10, f = 20, n = 0, big = true },
}
local THOUGHTS = {
	"Just tell them, it'll be easier...", "Don't say anything. Don't say anything.", "They're bluffing. Right?",
	"My hands won't stop shaking.", "How long have I been in here?", "Maybe if I explain...",
}
local QTE_KINDS = { "bite", "breath", "nerve", "eye", "slip" }

local function clamp(v: number): number return math.clamp(v, 0, 100) end

local function pressure(s: any): number
	local e = s.emo
	return (e.anxiety + e.fear + e.exhaustion) / 3 + e.anger * 0.2
end

local function pushMeters(s: any)
	send(s.player, "meters", s.emo, s.holdEnds - os.time())
end

local function await(s: any, kind: string, timeout: number): any
	s.waiting = kind
	s.answer = nil
	local t0 = os.clock()
	while s.answer == nil and os.clock() - t0 < timeout and s.alive() do task.wait(0.1) end
	s.waiting = nil
	return s.answer
end

-- v247: run one QTE on the client and get a score 0-1 back
local function qte(s: any, kind: string?, hard: boolean?): number
	local k = kind or QTE_KINDS[math.random(1, #QTE_KINDS)]
	local diff = math.clamp(pressure(s) / 100 + (if hard then 0.25 else 0), 0.2, 0.95)
	s.qteId += 1
	send(s.player, "qte", k, diff, s.qteId)
	local res = await(s, "qte", CFG.QTETimeout)
	local score = if type(res) == "number" then math.clamp(res, 0, 1) else 0
	print(("[Interrogation] QTE %s %s diff=%.2f score=%.2f"):format(s.player.Name, k, diff, score))
	return score
end

local function deal(s: any, scale: number, why: string)
	if scale < s.dealScale then
		s.dealScale = scale
		s.cooperative = true
		send(s.player, "say", "DETECTIVE", ("That's useful. I'll tell the DA you cooperated (%s)."):format(why), nil)
	end
end

local function falseStatement(s: any, what: string)
	s.falseStatements += 1
	s.credibility = math.max(0, s.credibility - 0.35)
	s.emo.anxiety = clamp(s.emo.anxiety + 15)
	s.emo.anger = clamp(s.emo.anger + 5)
	send(s.player, "say", "DETECTIVE", "That's not what the evidence says. " .. what .. " Lying to us is a crime too.", nil)
	print(("[Interrogation] FALSE STATEMENT %s: %s"):format(s.player.Name, what))
end

-- v249: name someone. target = member (co-defendant), or "ghost" / "invented"
local function blame(s: any, targetKey: string)
	local ev, me = s.ev, s.member
	if not ev or not me then
		falseStatement(s, "There's nobody else on this case.")
		return
	end
	local target = nil
	for _, m in ev.members do
		if m.name == targetKey and m.userId ~= me.userId then target = m end
	end
	local key = if target then target.name else targetKey
	ev.blames[key] = (ev.blames[key] or 0) + 1
	local corroborated = targetKey ~= "ghost" and (ev.blames[key] or 0) >= 2
	local truthful = target ~= nil
	if not truthful and not corroborated then
		local someoneFree = false
		for _, m in s.knownMembers do
			if not (m.player and m.player.Parent and ctx.inCustody and ctx.inCustody(m.player)) then someoneFree = true end
		end
		if targetKey == "ghost" and someoneFree then
			-- someone really got away and the evidence can't rule it out
			send(s.player, "say", "DETECTIVE", "Someone who got away. Convenient. We'll look into it.", nil)
			s.credibility = math.max(0, s.credibility - 0.1)
		else
			falseStatement(s, "Nobody puts that person at the scene.")
		end
		return
	end
	-- believed: what is it worth?
	local alreadyNamed = ev.named[key] == true
	ev.named[key] = true
	table.insert(s.namedList, key)
	if target and target.player and target.player.Parent then
		target.evidence = math.min(0.98, target.evidence + 0.25)
		-- charge the person named: a wanted level if they're out there
		if ctx.inCustody and not ctx.inCustody(target.player) and ctx.Heat then
			pcall(ctx.Heat.addCrime, target.player, ev.crime, nil)
			print(("[Interrogation] %s named %s -> charged / wanted"):format(s.player.Name, key))
		end
	end
	local myRank = ROLE_RANK[me.role] or 1
	local theirRank = target and ROLE_RANK[target.role] or 2
	local first = #ev.talked == 0 or ev.talked[1] == me.userId
	if not table.find(ev.talked, me.userId) then table.insert(ev.talked, me.userId) end
	if alreadyNamed then
		deal(s, CFG.DealKnown, "they already knew")
	elseif theirRank > myRank and first then
		deal(s, CFG.DealNew, "new information on the " .. string.lower(target and target.role or "ringleader"))
	else
		deal(s, CFG.DealConfirm, "it confirms what we suspected")
	end
	-- the snitch jacket
	s.snitched = true
	s.player:SetAttribute("SnitchJacket", true)
	s.player:SetAttribute("UndergroundBurned", true)
	if math.random() < CFG.LeakChance then
		s.player:SetAttribute("SnitchedOn", true) -- v237 gang-hit hook
		print(("[Interrogation] %s's statement leaked - snitch jacket"):format(s.player.Name))
	end
end

local function confess(s: any, reason: string)
	s.confessed = true
	s.evidence = math.min(0.99, s.evidence + 0.4)
	send(s.player, "say", s.player.Name, "Fine. FINE. I did it. And I wasn't alone...", nil)
	print(("[Interrogation] CONFESSION %s (%s)"):format(s.player.Name, reason))
	for _, m in s.knownMembers do blame(s, m.name) end
end

local function choicesFor(s: any): { any }
	local list = {
		{ key = "silent", text = "\"I'm not saying anything.\"" },
		{ key = "lawyer", text = "\"I want a lawyer.\"" },
		{ key = "deny", text = "\"I didn't do anything.\"" },
	}
	if s.member then
		table.insert(list, { key = "truth", text = "Tell the truth" })
		if s.member.role ~= "Shooter" and s.member.role ~= "Planner" then
			table.insert(list, { key = "minimise", text = "\"I was just the " .. string.lower(s.member.role == "Driver" and "driver" or "lookout") .. ".\"" })
		end
		for _, m in s.knownMembers do
			table.insert(list, { key = "blame", arg = m.name, text = "Blame " .. m.name })
		end
		table.insert(list, { key = "blame", arg = "ghost", text = "Blame someone who got away" })
	else
		table.insert(list, { key = "truth", text = "Admit it" })
	end
	if s.snitched and not s.pc then
		table.insert(list, { key = "pc", text = "Ask for protective custody" })
	end
	return list
end

local function handleChoice(s: any, choice: any)
	local key = if type(choice) == "table" then choice.key else "silent"
	local arg = if type(choice) == "table" then choice.arg else nil
	print(("[Interrogation] CHOICE %s %s %s"):format(s.player.Name, tostring(key), tostring(arg or "")))
	if key == "lawyer" then
		-- a clear request ends it; anxious suspects have to get the words out (QTE)
		local clear = s.counsel or s.emo.anxiety < 55 or qte(s, "lawyer") >= 0.6
		if clear then
			s.lawyered = true
			send(s.player, "say", "DETECTIVE", "...Okay. Interview over. We'll get you your lawyer.", nil)
			return "end"
		end
		send(s.player, "say", s.player.Name, "\"Maybe... maybe I should get a lawyer?\"", nil)
		send(s.player, "say", "DETECTIVE", "Maybe? Let's keep talking for now.", nil)
		return "continue"
	elseif key == "silent" then
		s.silences += 1
		send(s.player, "say", "DETECTIVE", "Suit yourself. I'll be back.", nil)
		s.emo.exhaustion = clamp(s.emo.exhaustion + 8)
		s.emo.anxiety = clamp(s.emo.anxiety + 5)
		pushMeters(s)
		local t0 = os.clock()
		while os.clock() - t0 < CFG.SilenceBreak and s.alive() and os.time() < s.holdEnds do task.wait(0.5) end
		return if s.silences >= 3 then "end" else "continue"
	elseif key == "deny" then
		if s.evidence >= 0.7 then
			falseStatement(s, "We can put you right there.")
		else
			send(s.player, "say", "DETECTIVE", "Sure you didn't.", nil)
			s.emo.anger = clamp(s.emo.anger + 6)
		end
		return "continue"
	elseif key == "truth" then
		confess(s, "told the truth")
		return "end"
	elseif key == "minimise" then
		local role = s.member and s.member.role
		if role == "Driver" or role == "Lookout" or role == "Accomplice" then
			send(s.player, "say", "DETECTIVE", "That matches what we have. Small fish.", nil)
			deal(s, CFG.MinimiseBelieved, "minor role")
			s.cooperative = true
		else
			falseStatement(s, "You were a lot more than that.")
		end
		return "continue"
	elseif key == "blame" then
		blame(s, tostring(arg))
		return "continue"
	elseif key == "pc" then
		s.pc = true
		s.player:SetAttribute("ProtectiveCustody", true)
		send(s.player, "say", "DETECTIVE", "Protective custody. You'll be isolated - no yard, no gangs. Everyone will know why.", nil)
		return "continue"
	end
	return "continue"
end

--[[ run(player, opts) - yields until the interview ends.
	opts = { keys, stars, priors, counsel (bool: retained lawyer), alive() -> bool }
	returns { secsScale, extraCharges, confessed, lawyered, cooperative, evidence } ]]
function I.run(player: Player, opts: any): any
	local ev = I.eventFor(player)
	local me = ev and memberOf(ev, player)
	local known = {}
	if ev then
		for uid, m in ev.members do
			if uid ~= player.UserId then table.insert(known, m) end
		end
	end
	local keys = opts.keys or {}
	local priors = tonumber(opts.priors) or 0
	local s = {
		player = player, ev = ev, member = me, knownMembers = known,
		holdEnds = os.time() + CFG.HoldSeconds,
		emo = {
			anxiety = clamp(25 + (if priors == 0 then 15 else -5 * math.min(priors, 3))),
			fear = clamp(if keys.CopKilled then 40 elseif keys.Murder then 30 elseif keys.BankRobbery then 20 else 10),
			anger = 10, exhaustion = 0,
		},
		evidence = if me then me.evidence else 0.5,
		credibility = 1, dealScale = 1, falseStatements = 0, silences = 0, namedList = {},
		confessed = false, lawyered = false, cooperative = false, snitched = false, pc = false,
		counsel = opts.counsel == true, qteId = 0,
		alive = opts.alive or function() return player.Parent ~= nil end,
	}
	sessions[player] = s
	I.isolate(player, true)
	print(("[Interrogation] START %s event=%s role=%s evidence=%.2f co-defendants=%d"):format(player.Name,
		tostring(ev and ev.id), tostring(me and me.role), s.evidence, #known))
	send(player, "open", { holdEnds = s.holdEnds, emo = s.emo, hold = CFG.HoldSeconds })
	send(player, "say", "DETECTIVE", "You have the right to remain silent. Anything you say can and will be used against you. You have the right to an attorney. Do you understand?", nil)
	task.wait(3)
	local rounds = 0
	local stop = false
	while not stop and s.alive() and os.time() < s.holdEnds and rounds < CFG.MaxRounds do
		rounds += 1
		-- the detective's move
		local pool = {}
		for _, t in TACTICS do
			if t.key == "partner" and #known == 0 then continue end
			if t.key == "death" and not (keys.Murder or keys.CopKilled) then continue end
			table.insert(pool, t)
		end
		local t = pool[math.random(1, #pool)]
		local line = t.line
		if t.key == "partner" then
			line = ("%s in the other room is talking. Says you %s it."):format(known[math.random(1, #known)].name,
				if me and me.role == "Shooter" then "pulled the trigger" else "planned")
		end
		send(player, "say", "DETECTIVE", line, nil)
		if t.wait then
			local t0 = os.clock()
			while os.clock() - t0 < t.wait and s.alive() do task.wait(0.5) end
		end
		s.emo.anxiety = clamp(s.emo.anxiety + t.a)
		s.emo.fear = clamp(s.emo.fear + t.f)
		s.emo.anger = clamp(s.emo.anger + t.n)
		s.emo.exhaustion = clamp(s.emo.exhaustion + 6)
		pushMeters(s)
		if s.emo.anxiety > 50 and math.random() < 0.6 then
			send(player, "thought", THOUGHTS[math.random(1, #THOUGHTS)])
		end
		-- v247: keep your mouth shut
		if pressure(s) >= CFG.QTEPressure or t.big then
			local score = qte(s, nil, t.big)
			if score >= 0.7 then
				s.emo.anxiety = clamp(s.emo.anxiety - 8)
				send(player, "thought", "Breathe. Say nothing.")
			elseif score >= 0.4 then
				s.emo.anxiety = clamp(s.emo.anxiety + 8)
				send(player, "say", "DETECTIVE", "You're sweating. Something on your mind?", nil)
			elseif score >= 0.15 then
				s.evidence = math.min(0.99, s.evidence + 0.12)
				send(player, "say", player.Name, "\"I- I wasn't even driving that- ...\"", nil)
				send(player, "say", "DETECTIVE", "Driving what?", nil)
			else
				confess(s, "cracked under pressure")
				stop = true
			end
			pushMeters(s)
		end
		if stop or not s.alive() then break end
		send(player, "choices", choicesFor(s))
		local choice = await(s, "choice", CFG.ChoiceTimeout)
		if not s.alive() then break end
		if handleChoice(s, choice or { key = "silent" }) == "end" then stop = true end
		pushMeters(s)
	end
	if os.time() >= s.holdEnds then
		send(player, "say", "DETECTIVE", "Time's up. You're going in front of a judge.", nil)
	end
	-- outputs
	local scale = s.dealScale
	local extra = {}
	if s.falseStatements > 0 then
		scale *= math.min(1.5, CFG.FalseStatementScale ^ s.falseStatements)
		table.insert(extra, "False statement to police")
	end
	player:SetAttribute("InterrogationEvidence", math.floor(s.evidence * 100) / 100)
	player:SetAttribute("Confessed", s.confessed or nil)
	player:SetAttribute("LawyeredUp", s.lawyered or nil)
	player:SetAttribute("Cooperative", s.cooperative or nil)
	player:SetAttribute("CooperationDeal", if s.dealScale < 1 then s.dealScale else nil)
	player:SetAttribute("NamedAccomplices", if #s.namedList > 0 then table.concat(s.namedList, ", ") else nil)
	player:SetAttribute("FalseStatements", if s.falseStatements > 0 then s.falseStatements else nil)
	local result = { secsScale = scale, extraCharges = extra, confessed = s.confessed, lawyered = s.lawyered,
		cooperative = s.cooperative, evidence = s.evidence, named = s.namedList, snitched = s.snitched, protective = s.pc }
	send(player, "close", { scale = scale, confessed = s.confessed, lawyered = s.lawyered, named = s.namedList,
		falseStatements = s.falseStatements, protective = s.pc })
	print(("[Interrogation] END %s rounds=%d confessed=%s lawyer=%s deal=%.2f false=%d named=[%s] -> time x%.2f"):format(
		player.Name, rounds, tostring(s.confessed), tostring(s.lawyered), s.dealScale, s.falseStatements,
		table.concat(s.namedList, ","), scale))
	sessions[player] = nil
	return result
end

function I.active(player: Player): boolean
	return sessions[player] ~= nil
end

;(remote :: RemoteEvent).OnServerEvent:Connect(function(player: Player, kind: any, a: any, b: any)
	local s = sessions[player]
	if not s then return end
	if kind == "choice" and s.waiting == "choice" and type(a) == "table" then
		-- only accept a choice that was actually offered
		for _, c in choicesFor(s) do
			if c.key == a.key and (c.arg == nil or c.arg == a.arg) then s.answer = c; return end
		end
	elseif kind == "qte" and s.waiting == "qte" and a == s.qteId and type(b) == "number" then
		s.answer = b
	end
end)

Players.PlayerRemoving:Connect(function(p)
	sessions[p] = nil
	for zone, who in roomsInUse do if who == p then roomsInUse[zone] = nil end end
end)

function I.init(c: any)
	ctx = c
	print(("[Interrogation] v%d ready (crime log, interrogation, QTEs, snitching)"):format(I.VERSION))
end

return I
