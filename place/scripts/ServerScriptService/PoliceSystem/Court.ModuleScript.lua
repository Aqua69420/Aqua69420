--[[
	Court (v263-v266) - the day in court, at the Clark County Courthouse (workspace.Courthouse,
	built by tools/build_courthouse.luau; every seat and spot is a named part in CourtMarkers).

	PoliceSystem (PrisonFlow.courtDay) calls Court.run(player, ctx) between booking and the sentence:
	  ctx = { secs, text, stars, priors, interview (the interrogation result or nil), minor,
	          free (out on bail: they walked in themselves - no ride, no holding cell),
	          alive(), ride(dest) -> how, walk(goal, maxTime) -> how, tell(msg), cuff(), uncuff(),
	          setHold(pos) }
	  -> { verdict = "plea" | "guilty" | "guilty (some counts)" | "not guilty" | "dismissed",
	       secs = the sentence (0 when free), judge = name }

	THE DAY
	 1. A cruiser to the prisoner sally port; walked up the secure stair to court holding.
	 2. "All rise": the judge walks in from chambers; the bailiff brings the defendant to the
	    defendant's chair. (Jury trials: the jurors file in from the jury room.)
	 3. Arraignment: the charges and the MAXIMUM sentence.
	 4. Plea: counsel reads the DA's offer (counsel tier, a prepared case, a confession, a deal
	    made in the interview room, priors and the judge move it). Accept / negotiate (it can get
	    better, stay, or be pulled) / reject. Capital cases: no deal. Minor cases: a quick plea.
	 5. Trial - bench (judge only) or jury (12 jurors): three pieces of the State's case built from
	    the real arrest and interview, each answered: object / challenge the evidence / testify
	    (from the witness stand) / stay silent. Jury: they deliberate in the jury room; 10+ guilty
	    votes convicts, 2 or fewer acquits, between is a hung jury (a last offer, or it's dropped).
	    Guilty at trial carries the trial penalty; a close case convicts on some counts only.
	 6. Judges with memory: a named roster; the same judge can come back and remembers how your
	    last case went (saved in the record, rec.court).
	Lawyer hours bill through LawFirms. Logs: [Court]
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local PathfindingService = game:GetService("PathfindingService")

local Court = {}

local CFG = {
	MaxScale = 1.6, -- the maximum the judge reads out = the expected sentence x this
	OpenPleaScale = 0.85, -- pleading guilty with no deal
	TrialPenalty = 1.25, -- guilty on every count at trial
	SomeCountsScale = 1.0,
	BaseOffer = 0.65, -- the DA's first offer, as a share of the expected sentence
	MinorPleaScale = 0.75, -- minor cases: plead guilty at arraignment
}

local JUDGES = {
	{ name = "Judge Harlan Voss", tilt = 0.08, offer = 0.05, greet = "This court has no patience for excuses." },
	{ name = "Judge Ruth Okafor", tilt = 0, offer = 0, greet = "Let's be clear, and let's be quick." },
	{ name = "Judge Daniel Price", tilt = -0.06, offer = -0.05, greet = "Everyone gets a fair hearing in my courtroom." },
	{ name = "Judge Leonard Marsh", tilt = 0.02, offer = 0, greet = "Sit down, counsel. We have a full docket." },
}
local PROSECUTORS = { "ADA Carla Brennan", "ADA Michael Stone", "ADA Victor Hale" }
local FIRM_TIER = {
	["Public Defender"] = 1, ["Local Attorney"] = 2, ["Experienced Defense Counsel"] = 3, ["Criminal Defense Firm"] = 4,
	["Elite Defense Team"] = 5, ["National Trial Firm"] = 6, ["Premier Counsel"] = 7,
}

local Records: any = nil
local CaseFile: any = nil
function Court.init(c: any)
	Records = c.Records
	CaseFile = c.CaseFile
end

---------------------------------------------------------------------------
-- the building
---------------------------------------------------------------------------
local function markers(): Instance?
	local m = workspace:FindFirstChild("Courthouse")
	return m and m:FindFirstChild("CourtMarkers")
end

function Court.available(): boolean
	local f = markers()
	return f ~= nil and f:FindFirstChild("JudgeSeat") ~= nil and f:FindFirstChild("DefendantSeat") ~= nil
		and f:FindFirstChild("HoldingSpot") ~= nil
end

function Court.spot(name: string): BasePart?
	local f = markers()
	local p = f and f:FindFirstChild(name)
	return if p and p:IsA("BasePart") then p else nil
end
local spot = Court.spot

local function clock(secs: number): string
	secs = math.max(0, math.floor(secs))
	return ("%d:%02d"):format(secs // 60, secs % 60)
end

---------------------------------------------------------------------------
-- NPCs (PoliceSystem also uses these for the lawyer walking into the station)
---------------------------------------------------------------------------
local OUTFITS = {
	judge = { Color3.fromRGB(20, 20, 24), Color3.fromRGB(20, 20, 24) }, -- the robe
	lawyer = { Color3.fromRGB(35, 38, 48), Color3.fromRGB(30, 30, 36) },
	prosecutor = { Color3.fromRGB(64, 64, 70), Color3.fromRGB(40, 40, 44) },
	bailiff = { Color3.fromRGB(70, 80, 110), Color3.fromRGB(40, 46, 66) },
}
local SKIN = { Color3.fromRGB(234, 192, 160), Color3.fromRGB(198, 146, 110), Color3.fromRGB(141, 95, 64), Color3.fromRGB(92, 60, 40) }

function Court.npc(name: string, role: string, at: Vector3): Model?
	local ok, model = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		local o = OUTFITS[role]
		local top = if o then o[1] else Color3.fromHSV(math.random(), 0.35, 0.45 + math.random() * 0.35)
		local legs = if o then o[2] else Color3.fromHSV(math.random(), 0.25, 0.25 + math.random() * 0.3)
		desc.TorsoColor, desc.LeftArmColor, desc.RightArmColor = top, top, top
		desc.LeftLegColor, desc.RightLegColor = legs, legs
		desc.HeadColor = SKIN[math.random(1, #SKIN)]
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[Court] couldn't make an NPC: " .. tostring(model))
		return nil
	end
	model.Name = name
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayName = name
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		hum.NameDisplayDistance = 40
		hum.WalkSpeed = 11
	end
	model:SetAttribute("CourtNPC", role)
	model:PivotTo(CFrame.new(at + Vector3.new(0, 3, 0)))
	model.Parent = workspace
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		pcall(function() root:SetNetworkOwner(nil) end)
	end
	return model
end

-- walk an NPC to a goal (pathfinding; it's placed there if it gets stuck)
function Court.walk(model: Model?, goal: Vector3, timeout: number?): string
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	local root = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (hum and root and model) then return "no npc" end
	hum.Sit = false
	local deadline = os.clock() + (timeout or 40)
	local path = PathfindingService:CreatePath({ AgentRadius = 1.5, AgentHeight = 5, AgentCanJump = false })
	local ok = pcall(function() path:ComputeAsync(root.Position, goal) end)
	local points = if ok and path.Status == Enum.PathStatus.Success then path:GetWaypoints() else {}
	if #points == 0 then points = { { Position = goal } } :: any end
	for _, wp in points do
		if os.clock() > deadline or not model.Parent then break end
		hum:MoveTo(wp.Position)
		local t0 = os.clock()
		while model.Parent and (root.Position - wp.Position).Magnitude > 3.5 and os.clock() - t0 < 4 and os.clock() < deadline do
			task.wait(0.1)
		end
	end
	if model.Parent and (root.Position - goal).Magnitude > 6 then
		model:PivotTo(CFrame.new(goal + Vector3.new(0, 3, 0)))
		return "placed"
	end
	return "walked"
end

-- sit an NPC (or a player's humanoid) on a seat marker
function Court.seat(model: Model?, seatName: string): boolean
	local s = spot(seatName)
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	if not (s and s:IsA("Seat") and hum and model) then return false end
	if s.Occupant and s.Occupant ~= hum then return false end
	model:PivotTo(s.CFrame * CFrame.new(0, 2.5, 0))
	task.wait()
	s:Sit(hum)
	return true
end

---------------------------------------------------------------------------
-- talking (the PhoneCalls dialog card) and billing
---------------------------------------------------------------------------
local function card(player: Player, from: string, lines: { string }, options: { string }): number?
	local f = ServerStorage:FindFirstChild("Phone")
	if not (f and f:IsA("BindableFunction")) then return nil end
	local ok, how, idx = pcall(f.Invoke, f, "dialog", player, { from = from, lines = lines, options = options })
	if ok and how == "answered" then return idx end
	return nil
end
Court.card = card

local function bill(player: Player, activity: string, complexity: number?)
	local law = ServerStorage:FindFirstChild("LawFirms")
	if law and law:IsA("BindableFunction") then
		pcall(law.Invoke, law, "bill", player, activity, complexity)
	end
end

local function counselOf(player: Player): (string, number)
	local firm = tostring(player:GetAttribute("LawyerFirm") or player:GetAttribute("CounselName") or "Public Defender")
	return firm, FIRM_TIER[firm] or 1
end
Court.counselOf = counselOf

local function isCapital(text: string): boolean
	local t = text:lower()
	return t:find("death row", 1, true) ~= nil or t:find("5 police", 1, true) ~= nil or t:find("five police", 1, true) ~= nil
end

-- v263b: the DA builds the case from the case file - the real incidents: witnesses, officers who
-- saw it, the seized weapon (ballistics), security cameras, cell-tower records, other incidents.
-- -> evidence pieces (strongest first), and how much they add to the case's strength
local function caseEvidence(player: Player, incidents: { any }, iv: any?): ({ any }, number)
	local top = incidents[1]
	if not top then return {}, 0 end
	local items = {}
	local function add(line: string, kind: string, weight: number) table.insert(items, { line = line, kind = kind, weight = weight }) end
	local who = if top.victim then top.victim else "the victim"
	local deadly = top.crime == "Murder" or top.crime == "CopKilled"
	if top.officers > 0 then
		add(("%d police officer%s saw %s at %s, %s."):format(top.officers, if top.officers == 1 then "" else "s", top.charge, top.place, top.clock), "officer", 0.08)
	end
	if top.witnesses > 0 then
		add(("%d witness%s place you at %s around %s. One of them is here to testify."):format(top.witnesses, if top.witnesses == 1 then "" else "es", top.place, top.clock), "witness", 0.04 * math.min(top.witnesses, 4))
	end
	local seized = tostring(player:GetAttribute("SeizedProperty") or "")
	if top.weapon and deadly then
		local matched = seized:find(top.weapon, 1, true) ~= nil
		add(if matched then ("The %s taken from you at your arrest. Ballistics match the bullet that killed %s."):format(top.weapon, who)
			else ("Shell casings from a %s at the scene - the same kind of gun witnesses saw in your hand."):format(top.weapon), "physical", if matched then 0.12 else 0.06)
	elseif top.weapon then
		add(("The %s you were carrying at %s."):format(top.weapon, top.place), "physical", 0.05)
	end
	if top.camera then
		add(("Security cameras at %s recorded it - time-stamped %s."):format(top.place, top.clock), "video", 0.1)
	end
	if CaseFile then
		local trail = CaseFile.trail(player, top.t, 360)
		if #trail >= 1 then
			local stops = {}
			for i = math.max(1, #trail - 2), #trail do
				table.insert(stops, ("%s (%s)"):format(trail[i].place, trail[i].clock))
			end
			add("Cell-tower records put your phone at " .. table.concat(stops, ", then ") .. ".", "tracking", 0.05)
		end
	end
	if iv and iv.confessed then
		add("The recording of your statement in the interview room.", "statement", 0.15)
	end
	if iv and iv.named and #iv.named > 0 then
		add(("A sworn statement from %s naming you."):format(tostring(iv.named[1])), "witness", 0.05)
	end
	if #incidents > 1 then
		add(("A pattern: %d other incident%s - including %s."):format(#incidents - 1, if #incidents == 2 then "" else "s",
			if CaseFile then CaseFile.describe(incidents[2]) else incidents[2].charge), "record", 0.04)
	end
	table.sort(items, function(a, b) return a.weight > b.weight end)
	local bonus = 0
	for _, it in items do bonus += it.weight end
	return items, math.min(bonus, 0.3)
end

-- the State's evidence, built from the real arrest and interview (when there's no case file)
local function evidence(text: string, iv: any?): { { line: string, kind: string } }
	local list = {}
	local first = (text:split(",")[1] or text):gsub("^%s+", "")
	table.insert(list, { line = ("The arresting officer testifies: you were taken into custody for %s."):format(first), kind = "officer" })
	if iv and iv.confessed then
		table.insert(list, { line = "The recording of your statement in the interview room.", kind = "statement" })
	else
		table.insert(list, { line = "Body-camera and dash-camera footage of the arrest.", kind = "video" })
	end
	local t = text:lower()
	if iv and iv.named and #iv.named > 0 then
		table.insert(list, { line = ("A sworn statement from %s naming you."):format(tostring(iv.named[1])), kind = "witness" })
	elseif t:find("bank", 1, true) or t:find("robbery", 1, true) then
		table.insert(list, { line = "Security footage from inside the bank, and the vault's alarm log.", kind = "video" })
	elseif t:find("murder", 1, true) or t:find("assault", 1, true) then
		table.insert(list, { line = "The medical examiner's report and a witness who saw it.", kind = "witness" })
	else
		table.insert(list, { line = "An eyewitness who picked you out of a line-up.", kind = "witness" })
	end
	return list
end

-- how strong the State's case is (0..1): the chance a neutral judge convicts
local function caseStrength(ctx: any, tier: number, prepared: boolean): number
	local iv = ctx.interview
	local e = 0.5 + 0.05 * math.clamp(tonumber(ctx.stars) or 1, 0, 6)
	if iv then
		if iv.confessed then e += 0.25 end
		if iv.lawyered then e -= 0.05 end
		if iv.violation then e -= 0.2 end -- a detective crossed the line: the statement is tainted
		if iv.named and #iv.named > 0 then e += 0.03 end
	end
	if prepared then e -= 0.05 end
	e -= 0.03 * (tier - 1)
	return math.clamp(e, 0.1, 0.95)
end

---------------------------------------------------------------------------
-- THE DAY IN COURT
---------------------------------------------------------------------------
function Court.run(player: Player, ctx: any): any
	local alive = ctx.alive or function() return player.Parent ~= nil end
	local text = tostring(ctx.text or "")
	local secs = math.max(20, math.floor(tonumber(ctx.secs) or 60))
	local firm, tier = counselOf(player)
	local prepared = player:GetAttribute("CasePrepared") == true
	local capital = isCapital(text)
	local priors = tonumber(ctx.priors) or 0
	local iv = ctx.interview
	local incidents = if CaseFile then CaseFile.caseFor(player) else {}
	local items, evidenceBonus = caseEvidence(player, incidents, iv)
	local npcs: { Model } = {}
	local function add(m: Model?): Model?
		if m then table.insert(npcs, m) end
		return m
	end
	local function charOf()
		local c = player.Character
		return c, c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	end
	local function place(pos: Vector3)
		local _, _, r = charOf()
		if r then r.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)) end
	end
	local function sitIn(seatName: string)
		local s = spot(seatName)
		local _, hum, _ = charOf()
		if not (s and hum and s:IsA("Seat")) then return end
		hum.Sit = false
		task.wait(0.15)
		place(s.Position)
		task.wait(0.15)
		s:Sit(hum)
	end
	local function stand()
		local _, hum, _ = charOf()
		if hum then hum.Sit = false end
	end

	-- judges with memory
	local rec = if Records then Records.get(player) else {}
	rec.court = rec.court or {}
	local judge = JUDGES[math.random(1, #JUDGES)]
	if rec.court.lastJudge and math.random() < 0.4 then
		for _, j in JUDGES do
			if j.name == rec.court.lastJudge then judge = j end
		end
	end
	local returning = rec.court.lastJudge == judge.name
	local prosecutor = PROSECUTORS[math.random(1, #PROSECUTORS)]
	print(("[Court] CASE %s: %s | %s, %s for the State, counsel %s (tier %d)%s%s%s | %ds"):format(player.Name, text, judge.name, prosecutor,
		firm, tier, if prepared then ", prepared" else "", if capital then ", CAPITAL" else "", if ctx.minor then ", minor" else "", secs))
	player:SetAttribute("BookingState", "Court")
	player:SetAttribute("CourtJudge", judge.name)

	local result = { verdict = "guilty", secs = secs, judge = judge.name }
	local ok, err = pcall(function()
		------------------------------------------------------------ 1. to court
		-- (ctx.free: out on bail, they came themselves - no ride, no holding cell)
		if not ctx.free then ctx.tell("Court date - a cruiser is taking you to the Clark County Courthouse") end
		local drop = spot("PrisonerDropoff")
		if drop and ctx.ride and not ctx.free then
			local okR, how = pcall(ctx.ride, drop.Position)
			print(("[Court] RIDE %s: %s"):format(player.Name, tostring(if okR then how else "error: " .. tostring(how))))
			local _, _, r = charOf()
			if r and (r.Position - drop.Position).Magnitude > 60 then place(drop.Position) end
		end
		if not alive() then return end
		local hold = spot("HoldingSpot")
		if hold and not ctx.free then
			ctx.tell("Through the sally port - up the secure stair to court holding")
			local how = if ctx.walk then ctx.walk(hold.Position, 120) else "placed" -- the sally port, up the secure stair
			local _, _, r = charOf()
			if r and (r.Position - hold.Position).Magnitude > 12 then place(hold.Position) end
			if ctx.setHold then ctx.setHold(hold.Position + Vector3.new(0, 3, 0)) end
			print(("[Court] HOLDING %s (%s)"):format(player.Name, tostring(how)))
			ctx.tell("Court holding - waiting for your case to be called")
		end
		-- the courtroom fills: counsel at their tables, the bailiff, the clerk
		local function seated(name: string, role: string, seatName: string): Model?
			local s = spot(seatName)
			local m = add(Court.npc(name, role, if s then s.Position else Vector3.zero))
			if m then Court.seat(m, seatName) end
			return m
		end
		seated(prosecutor, "prosecutor", "ProsecutorSeat")
		local lawyer = seated(firm, "lawyer", "DefenseSeat")
		seated("Court Clerk", "bailiff", "CourtClerkSeat")
		local bs = spot("BailiffSpot")
		local bailiff = add(Court.npc("Bailiff", "bailiff", (if ctx.free then bs else hold or bs :: BasePart).Position))
		if ctx.free then ctx.tell("The clerk checks you in - the bailiff will take you into the courtroom") end
		task.wait(4)
		if not alive() then return end

		------------------------------------------------------------ 2. all rise
		-- the bailiff brings the defendant in
		local defSeat = spot("DefendantSeat")
		ctx.tell("The bailiff calls your case")
		if defSeat then
			if bailiff then task.spawn(Court.walk, bailiff, defSeat.Position + Vector3.new(0, 0, 4), 40) end
			local how = if ctx.walk then ctx.walk(defSeat.Position + Vector3.new(0, 2.4, 3), 90) else "placed" -- beside the chair
			print(("[Court] TO THE CHAIR %s (%s)"):format(player.Name, tostring(how)))
			ctx.uncuff()
			sitIn("DefendantSeat")
		end
		if bailiff and bs then task.spawn(Court.walk, bailiff, bs.Position, 20) end
		ctx.tell("\"All rise. The Superior Court of Clark County is now in session.\"")
		local chambers = spot("ChambersSpot")
		local judgeNpc = add(Court.npc(judge.name, "judge", if chambers then chambers.Position else (defSeat :: BasePart).Position))
		local js = spot("JudgeSeat")
		if judgeNpc and js then
			Court.walk(judgeNpc, js.Position + Vector3.new(0, 0, 3), 30)
			Court.seat(judgeNpc, "JudgeSeat")
		end
		task.wait(1)
		if not alive() then return end

		------------------------------------------------------------ 3. arraignment
		local maxSecs = math.floor(secs * CFG.MaxScale)
		local greet = if returning then
			(if rec.court.lastVerdict == "not guilty" then "Back again. Last time you walked out of here. Not today."
				else "Back in my courtroom. I remember you.")
			else judge.greet
		local reading = { greet, ("The People of the State of Nevada v. %s."):format(player.DisplayName) }
		if #incidents > 0 and CaseFile then
			for i = 1, math.min(4, #incidents) do
				table.insert(reading, ("Count %d: %s."):format(i, CaseFile.describe(incidents[i])))
			end
			if #incidents > 4 then
				table.insert(reading, ("...and %d more count%s."):format(#incidents - 4, if #incidents == 5 then "" else "s"))
			end
		else
			table.insert(reading, ("Charges: %s."):format(text))
		end
		table.insert(reading, ("Maximum sentence: %s.%s"):format(clock(maxSecs), if capital then " This is a capital case." else ""))
		card(player, judge.name, reading, { "Continue" })
		-- discovery: counsel walks you through what the DA has
		if #items > 0 then
			local lines = { "Here's what the DA has on you:" }
			for i = 1, math.min(4, #items) do table.insert(lines, "- " .. items[i].line) end
			card(player, firm .. " (your lawyer)", lines, { "OK" })
		end
		if not alive() then return end

		------------------------------------------------------------ 4. plea
		if ctx.minor and not capital then
			-- minor matters: plead guilty and get it over with, or a short bench trial
			local plea = math.floor(secs * CFG.MinorPleaScale)
			local c = card(player, firm .. " (your lawyer)", {
				("It's a minor matter. Plead guilty and the judge gives you %s."):format(clock(plea)),
				"Or plead not guilty and the judge hears it now.",
			}, { "Plead guilty", "Plead not guilty" })
			if not alive() then return end
			if c == 1 then
				result = { verdict = "plea", secs = plea, judge = judge.name }
				card(player, judge.name, { "The court accepts your plea.", ("Sentence: %s."):format(clock(plea)) }, { "OK" })
				bill(player, "plea")
				return
			end
		end
		local offerScale = CFG.BaseOffer - 0.04 * (tier - 1) + judge.offer
		if prepared then offerScale -= 0.05 end
		if iv and iv.confessed then offerScale += 0.15 end
		if iv and iv.lawyered then offerScale -= 0.03 end
		if iv and iv.secsScale and iv.secsScale < 1 then offerScale *= iv.secsScale end -- a deal from the interview room
		offerScale += math.min(0.2, 0.05 * priors)
		offerScale = math.clamp(offerScale, 0.3, 0.95)
		local offer = if capital or ctx.minor then nil else math.floor(secs * offerScale)
		local strength = math.clamp(caseStrength(ctx, tier, prepared) + evidenceBonus, 0.1, 0.97)
		if not ctx.minor then
			local pick = card(player, judge.name, { "How do you plead?" }, { "Not guilty", "Guilty", "Let my lawyer speak first" })
			if not alive() then return end
			if pick == 2 then
				result = { verdict = "plea", secs = math.floor(secs * CFG.OpenPleaScale), judge = judge.name }
				card(player, judge.name, { "The court accepts your plea of guilty.", ("Sentence: %s."):format(clock(result.secs)) }, { "OK" })
				bill(player, "plea")
				return
			end
		end
		local negotiations = 0
		while offer and alive() do
			local lines = {
				("The DA's offer: plead guilty and take %s instead of up to %s."):format(clock(offer), clock(maxSecs)),
				if strength > 0.7 then "Their case is strong. I'd think hard about it."
					elseif strength < 0.45 then "Their case has holes. We could win at trial." else "It could go either way at trial.",
			}
			if tier <= 1 then table.insert(lines, "(Public Defender) I have four more of these today.") end
			local opts = { "Accept the deal", "Negotiate", "Reject - go to trial" }
			if negotiations >= 2 then table.remove(opts, 2) end
			local choice = card(player, firm .. " (your lawyer)", lines, opts)
			if not alive() then return end
			local what = opts[choice or #opts]
			if what == "Accept the deal" then
				result = { verdict = "plea", secs = offer, judge = judge.name }
				card(player, judge.name, { "The court accepts the plea agreement.", ("Sentence: %s."):format(clock(offer)) }, { "OK" })
				bill(player, "plea")
				print(("[Court] PLEA %s: %ds"):format(player.Name, offer))
				return
			elseif what == "Negotiate" then
				negotiations += 1
				bill(player, "plea")
				local r = math.random()
				local improve = 0.25 + 0.08 * tier + (if prepared then 0.1 else 0)
				local pulled = math.max(0.05, 0.28 - 0.03 * tier)
				if r < improve then
					offer = math.floor(offer * (0.82 + math.random() * 0.08))
					card(player, prosecutor, { "Fine. That's as low as I go." }, { "OK" })
				elseif r < improve + pulled then
					card(player, prosecutor, { "You want to play games? The offer's off the table. See you at trial." }, { "..." })
					offer = nil
				else
					card(player, prosecutor, { "The offer stands. Take it or leave it." }, { "OK" })
				end
			else
				break
			end
		end
		if capital then
			card(player, prosecutor, { "The State is seeking the maximum. There will be no deal." }, { "..." })
		end
		if not alive() then return end

		------------------------------------------------------------ 5. trial
		local jury = false
		if not ctx.minor then
			local kind = card(player, judge.name, { "This case goes to trial. Bench or jury?" },
				{ "Bench trial (the judge decides - quicker)", "Jury trial (12 jurors - longer, less predictable)" })
			if not alive() then return end
			jury = kind == 2
		end
		local jurors: { Model } = {}
		if jury then
			ctx.tell("The jury files in from the jury room")
			local jr = spot("JuryRoomSpot")
			for i = 1, 12 do
				local m = add(Court.npc("Juror #" .. i, "juror", (jr or defSeat :: BasePart).Position + Vector3.new((i % 4) * 2, 0, (i // 4) * 2)))
				if m then table.insert(jurors, m) end
			end
			-- they walk in together (each one is seated wherever they are after 25 s)
			local done = 0
			for i, m in jurors do
				task.spawn(function()
					local seat = spot("JurorSeat" .. i)
					if seat then Court.walk(m, seat.Position + Vector3.new(0, 0, -3), 25) end
					Court.seat(m, "JurorSeat" .. i)
					done += 1
				end)
			end
			local t0 = os.clock()
			while done < #jurors and os.clock() - t0 < 30 do task.wait(0.5) end
		end
		local lean = strength + judge.tilt
		local testified = false
		-- the DA's three strongest pieces (from the case file), topped up with the general ones
		local pieces = {}
		for i = 1, math.min(3, #items) do table.insert(pieces, items[i]) end
		for _, ev in evidence(text, iv) do
			if #pieces >= 3 then break end
			table.insert(pieces, ev)
		end
		for i, ev in pieces do
			if not alive() then return end
			ctx.tell(("%s presents the State's evidence (%d/3)"):format(prosecutor, i))
			local opts = { "Object!", "Challenge the evidence", "Testify", "Stay silent" }
			if testified then table.remove(opts, 3) end
			local c = card(player, prosecutor, { ev.line }, opts)
			if not alive() then return end
			local what = opts[c or #opts]
			if what == "Object!" then
				if math.random() < 0.3 + 0.06 * tier then
					lean -= 0.08
					card(player, judge.name, { "Sustained. " .. (if jury then "The jury will disregard that." else "Move on, counsel.") }, { "OK" })
				else
					lean += 0.03
					card(player, judge.name, { "Overruled. Sit down, counsel." }, { "OK" })
				end
			elseif what == "Challenge the evidence" then
				local chance = 0.25 + 0.07 * tier + (if ev.kind == "statement" and iv and iv.violation then 0.3 else 0)
					+ (if ev.kind == "tracking" then 0.15 elseif ev.kind == "witness" then 0.08 elseif ev.kind == "video" or ev.kind == "physical" then -0.1 else 0)
				if math.random() < chance then
					lean -= 0.12
					card(player, firm, { if ev.kind == "statement" then "That statement wasn't taken by the book - and they know it."
						elseif ev.kind == "tracking" then "A cell tower covers half the city. That proves nothing."
						elseif ev.kind == "witness" then "Their witness admitted it was dark and they were across the street."
						elseif ev.kind == "physical" then "The chain of custody on that evidence has a gap. They know it."
						else "We just put a hole in that." }, { "OK" })
				else
					lean += 0.02
					card(player, firm, { "That didn't land. Let's move on." }, { "OK" })
				end
			elseif what == "Testify" then
				testified = true
				sitIn("WitnessSeat")
				local chance = 0.45 + (if prepared then 0.2 else 0) + 0.02 * tier
				local say = card(player, prosecutor, { "Where were you at the time of the crime?" },
					{ "Tell your story calmly", "Get angry at the prosecutor", "\"I don't recall.\"" })
				if say == 2 then chance -= 0.25 elseif say == 3 then chance -= 0.1 end
				if math.random() < chance then
					lean -= 0.15
					card(player, firm, { "That was good. They believed you." }, { "OK" })
				else
					lean += 0.15
					card(player, firm, { "...That hurt us." }, { "OK" })
				end
				sitIn("DefendantSeat")
			end
			task.wait(1)
		end
		lean = math.clamp(lean, 0.05, 0.97)
		bill(player, if jury then "jury" else "bench", 0.4) -- (a short trial)
		if not alive() then return end
		------------------------------------------------------------ 6. the verdict
		local verdict
		if jury then
			ctx.tell("Closing arguments. The jury retires to the jury room to deliberate...")
			for i, m in jurors do
				task.spawn(function()
					local seat = spot("JuryRoomSeat" .. i)
					if seat then
						Court.walk(m, seat.Position + Vector3.new(0, 0, 3), 25)
						Court.seat(m, "JuryRoomSeat" .. i)
					end
				end)
			end
			task.wait(14)
			for i, m in jurors do
				task.spawn(function()
					local seat = spot("JurorSeat" .. i)
					if seat then
						Court.walk(m, seat.Position + Vector3.new(0, 0, -3), 20)
						Court.seat(m, "JurorSeat" .. i)
					end
				end)
			end
			task.wait(10)
			local guilty = 0
			for _ = 1, 12 do
				if math.random() < math.clamp(lean + (math.random() - 0.5) * 0.4, 0, 1) then guilty += 1 end
			end
			print(("[Court] JURY %s: %d-%d (lean %.2f)"):format(player.Name, guilty, 12 - guilty, lean))
			if guilty >= 10 then
				verdict = "guilty"
			elseif guilty <= 2 then
				verdict = "not guilty"
			else
				card(player, judge.name, { ("The jury is deadlocked, %d to %d. I'm declaring a mistrial."):format(guilty, 12 - guilty) }, { "..." })
				if capital or math.random() < 0.5 then
					local last = math.floor(secs * 0.55)
					local c3 = card(player, prosecutor, { ("Rather than try it again: plead to %s and we're done."):format(clock(last)) }, { "Take it", "No - try me again" })
					if c3 == 1 then
						result = { verdict = "plea", secs = last, judge = judge.name }
						return
					end
					verdict = if math.random() < lean then "guilty" else "not guilty"
				else
					verdict = "dismissed"
				end
			end
		else
			ctx.tell("Closing arguments. The judge considers the verdict...")
			task.wait(4)
			verdict = if math.random() < lean then "guilty" else "not guilty"
			print(("[Court] BENCH %s: %s (lean %.2f)"):format(player.Name, verdict, lean))
		end
		if verdict == "guilty" then
			local some = lean < 0.6 and not capital
			result = { verdict = if some then "guilty (some counts)" else "guilty", secs = math.floor(secs * (if some then CFG.SomeCountsScale else CFG.TrialPenalty)), judge = judge.name }
			card(player, judge.name, {
				if jury then "Has the jury reached a verdict? ...\"We find the defendant GUILTY.\"" else "I find the defendant GUILTY.",
				if some then "On some of the counts." else "On all counts.",
				("Sentence: %s."):format(clock(result.secs)),
			}, { "..." })
			-- the victim's family speaks at a murder sentencing
			local top = incidents[1]
			if top and top.victim and (top.crime == "Murder" or top.crime == "CopKilled") then
				card(player, ("%s's family"):format(top.victim), {
					("Every day we wake up and %s isn't there. I hope you think about that, every day you're inside."):format(top.victim:split(" ")[1]),
				}, { "..." })
			end
		elseif verdict == "dismissed" then
			result = { verdict = "dismissed", secs = 0, judge = judge.name }
			card(player, judge.name, { "The State has dropped the charges. You're free to go." }, { "OK" })
		else
			result = { verdict = "not guilty", secs = 0, judge = judge.name }
			card(player, judge.name, {
				if jury then "Has the jury reached a verdict? ...\"We find the defendant NOT GUILTY.\"" else "I find the defendant NOT GUILTY.",
				"You're free to go. This court is adjourned.",
			}, { "OK" })
		end
		if lawyer and result.secs == 0 then
			card(player, firm, { "Go home. And stay out of trouble." }, { "OK" })
		end
	end)
	if not ok then
		warn("[Court] error in " .. player.Name .. "'s case: " .. tostring(err))
	end
	stand()
	task.delay(5, function()
		for _, m in npcs do
			if m.Parent then m:Destroy() end
		end
	end)
	rec.court.lastJudge = judge.name
	rec.court.lastVerdict = result.verdict
	rec.court.cases = (rec.court.cases or 0) + 1
	if Records and Records.touch then pcall(Records.touch, player) end
	player:SetAttribute("CourtJudge", nil)
	player:SetAttribute("CasePrepared", nil)
	if CaseFile then CaseFile.close(player) end -- the case is over: a fresh file for whatever comes next
	print(("[Court] VERDICT %s: %s, %ds (%s)"):format(player.Name, result.verdict, result.secs, judge.name))
	return result
end

return Court
