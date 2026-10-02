--[[
	LawFirms (v257) - law offices, retainers, hourly billing, the 3 AM call.

	Firms (spec 9.1): Public Defender, Local Attorney, Experienced Defense Counsel,
	Criminal Defense Firm, Elite Defense Team, National Trial Firm, Premier Counsel.

	OFFICES: every building mapped as a LawOffice (Facility Mapper) is a firm's office.
	The firm is the Firm attribute on the building or its FacilityMap; an office
	without one is used as the Local Attorney's office (and the log says so). The
	receptionist stands at the Reception point (or LawyerSeat / the first room).
	At reception: get a quote, put the firm on retainer, see your legal bill, top up
	the trust balance, end the retainer. Criminal Defense Firm and up only sign a
	retainer IN PERSON; the cheaper ones also take it over the phone (Lawyer button).

	MONEY (spec 9.2-9.3):
	  * retainer = a trust balance; hours are billed against it at the firm's rate
	  * on retainer BEFORE an arrest: a billing-cycle fee (every CycleSeconds), 25% off
	    the hourly rate, an instant call when you're arrested, bail -20% (Bail module),
	    and the firm is used at prison booking without paying again
	  * hired after the arrest: the full retainer up front (frozen money can't pay -
	    AssetFreeze already holds it), full rate
	  * trust running low -> the lawyer calls for a top-up; can't pay -> debt, then
	    they withdraw and a Public Defender is appointed
	3 AM (spec 9.4): the game clock (Lighting.ClockTime) 22:00-06:00 is night; cheap
	firms often sleep through the arrest call (voicemail, then "Sorry, I was asleep...").

	Saved in the criminal record (Records, rec.lawyer). Attributes: CounselRetained,
	LawyerFirm, LawyerTrust, LawyerDebt, LawyerPresent. Logs: [Law]
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local FIRMS = {
	{ name = "Public Defender", retainer = 0, rate = 0, night = 0.25, inPerson = false },
	{ name = "Local Attorney", retainer = 10000, rate = 250, night = 0.35, inPerson = false },
	{ name = "Experienced Defense Counsel", retainer = 50000, rate = 650, night = 0.6, inPerson = false },
	{ name = "Criminal Defense Firm", retainer = 250000, rate = 1600, night = 0.85, inPerson = true, junior = true },
	{ name = "Elite Defense Team", retainer = 1000000, rate = 4500, night = 1, inPerson = true },
	{ name = "National Trial Firm", retainer = 5000000, rate = 9000, night = 1, inPerson = true },
	{ name = "Premier Counsel", retainer = 10000000, rate = 15000, night = 1, inPerson = true },
}
local BY_NAME = {}
for i, f in FIRMS do f.tier = i; BY_NAME[f.name] = f end

local CFG = {
	CycleSeconds = 30 * 60, -- one billing cycle (a game "month")
	CycleShare = 0.05, -- cycle fee = 5% of the retainer
	RetainedDiscount = 0.25, -- hourly rate off while on retainer
	LowTrustHours = 2, -- top-up call below this many hours
	MaxUnpaidCalls = 2, -- then they withdraw
}

-- hours per activity (spec 9.2)
local HOURS = {
	call = { 0.5, 1 }, interrogation = { 1, 3 }, bail = { 2, 4 }, plea = { 1, 3 }, motions = { 3, 8 },
	bench = { 8, 15 }, jury = { 20, 60 }, appeal = { 15, 30 }, meeting = { 0.5, 1.5 },
}

local Records: any = nil
local F: any = nil
task.spawn(function()
	local ps = ServerScriptService:WaitForChild("PoliceSystem", 30)
	for _ = 1, 30 do
		if ps then
			local rm, fm = ps:FindFirstChild("Records"), ps:FindFirstChild("Facilities")
			if rm and not Records then local ok, m = pcall(require, rm); if ok then Records = m end end
			if fm and not F then local ok, m = pcall(require, fm); if ok then F = m end end
		end
		if Records and F then break end
		task.wait(1)
	end
end)

local function phone(): BindableFunction?
	local f = ServerStorage:FindFirstChild("Phone")
	return if f and f:IsA("BindableFunction") then f else nil
end

local function money(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then out = out:sub(2) end
	return (if n < 0 then "-$" else "$") .. out
end

local function notice(p: Player, text: string)
	local r = game:GetService("ReplicatedStorage"):FindFirstChild("PhoneCalls")
	if r and r:IsA("RemoteEvent") and p.Parent then r:FireClient(p, "notice", text) end
end

-- the dialog card (no ringing) -> option index or nil
local function dialog(p: Player, from: string, lines: { string }, options: { string }): number?
	local f = phone()
	if not f then return nil end
	local ok, how, idx = pcall(f.Invoke, f, "dialog", p, { from = from, lines = lines, options = options })
	if ok and how == "answered" then return idx end
	return nil
end

local function call(p: Player, spec: any): (string?, number?)
	local f = phone()
	if not f then notice(p, tostring(spec.from) .. ": " .. table.concat(spec.lines or {}, " ")); return nil, nil end
	local ok, how, idx = pcall(f.Invoke, f, "call", p, spec)
	if ok then return how, idx end
	return nil, nil
end

---------------------------------------------------------------------------
-- the account (saved in the record)
---------------------------------------------------------------------------
local function acct(p: Player): any
	if not Records then return {} end
	local rec = Records.get(p)
	rec.lawyer = rec.lawyer or { firm = nil, retained = false, trust = 0, debt = 0, hours = 0, billed = 0, nextCycle = 0, unpaid = 0, log = {} }
	rec.lawyer.log = rec.lawyer.log or {}
	return rec.lawyer
end

local function save(p: Player)
	local a = acct(p)
	p:SetAttribute("CounselRetained", if a.retained then a.firm else nil)
	p:SetAttribute("LawyerFirm", a.firm)
	p:SetAttribute("LawyerTrust", math.floor(a.trust or 0))
	p:SetAttribute("LawyerDebt", if (a.debt or 0) > 0 then math.floor(a.debt) else nil)
	if Records and Records.touch then pcall(Records.touch, p) end
end

local function rateFor(a: any): number
	local f = BY_NAME[a.firm or ""]
	if not f then return 0 end
	return math.floor(f.rate * (if a.retained then 1 - CFG.RetainedDiscount else 1))
end

local function isNight(): boolean
	local t = Lighting.ClockTime
	return t >= 22 or t < 6
end

local function available(p: Player): number
	local c, b = p:FindFirstChild("Cash"), p:FindFirstChild("Money")
	return (if c and c:IsA("IntValue") then c.Value else 0) + (if b and b:IsA("IntValue") then b.Value else 0)
end

local function charge(p: Player, amount: number): boolean
	amount = math.floor(amount)
	if available(p) < amount then return false end
	-- v257b: through the Economy, so the dirty-money share (v255) stays right
	local eco = ServerStorage:FindFirstChild("Economy")
	if eco and eco:IsA("BindableFunction") then
		local ok, paid = pcall(eco.Invoke, eco, "Charge", p, amount)
		return ok and paid == true
	end
	local c, b = p:FindFirstChild("Cash") :: IntValue?, p:FindFirstChild("Money") :: IntValue?
	local fromCash = if c then math.min(c.Value, amount) else 0
	if c then c.Value -= fromCash end
	if b and amount - fromCash > 0 then b.Value -= amount - fromCash end
	return true
end

local withdraw -- forward

-- bill an activity -> hours billed
local function bill(p: Player, activity: string, complexity: number?): number
	local a = acct(p)
	local f = BY_NAME[a.firm or ""]
	if not f or f.rate <= 0 then return 0 end
	local r = HOURS[activity] or HOURS.call
	local hours = (r[1] + math.random() * (r[2] - r[1])) * (complexity or 1)
	hours = math.floor(hours * 10 + 0.5) / 10
	local cost = math.floor(hours * rateFor(a))
	a.hours = (a.hours or 0) + hours
	a.billed = (a.billed or 0) + cost
	a.trust = (a.trust or 0) - cost
	if a.trust < 0 then
		a.debt = (a.debt or 0) - a.trust
		a.trust = 0
	end
	table.insert(a.log, 1, ("%s: %.1f h = %s"):format(activity, hours, money(cost)))
	while #a.log > 8 do table.remove(a.log) end
	save(p)
	print(("[Law] BILL %s %s %.1fh %s (trust %s, debt %s)"):format(p.Name, activity, hours, money(cost), money(a.trust), money(a.debt or 0)))
	-- running low: the lawyer calls for a top-up
	if a.trust < rateFor(a) * CFG.LowTrustHours then
		task.spawn(function()
			local need = math.floor(math.max(f.retainer * 0.25, rateFor(a) * 10) + (a.debt or 0))
			local how, idx = call(p, {
				from = f.name, kind = "lawyer", legal = true, expires = 300,
				lines = { ("Your trust balance is %s%s. We need %s to keep working your case."):format(money(a.trust),
					if (a.debt or 0) > 0 then (" and you owe us %s"):format(money(a.debt)) else "", money(need)) },
				options = { ("Pay %s now"):format(money(need)), "I can't right now" },
			})
			if how == "answered" and idx == 1 and charge(p, need) then
				local pay = need - (a.debt or 0)
				a.debt = 0
				a.trust += pay
				a.unpaid = 0
				save(p)
				notice(p, ("%s: trust topped up to %s"):format(f.name, money(a.trust)))
				print(("[Law] TOPUP %s %s"):format(p.Name, money(need)))
			else
				a.unpaid = (a.unpaid or 0) + 1
				save(p)
				if a.unpaid >= CFG.MaxUnpaidCalls and (a.debt or 0) > 0 then withdraw(p, "unpaid bills") end
			end
		end)
	end
	return hours
end

withdraw = function(p: Player, why: string)
	local a = acct(p)
	local old = a.firm
	a.firm = "Public Defender"
	a.retained = false
	a.trust = 0
	a.unpaid = 0
	save(p)
	if p:GetAttribute("CounselName") and p:GetAttribute("CounselName") ~= "Public Defender" then
		p:SetAttribute("CounselName", "Public Defender")
	end
	notice(p, ("%s has withdrawn from your case (%s). A Public Defender has been appointed. You still owe %s."):format(tostring(old), why, money(a.debt or 0)))
	print(("[Law] WITHDREW %s from %s (%s) debt=%s"):format(tostring(old), p.Name, why, money(a.debt or 0)))
end

---------------------------------------------------------------------------
-- quotes
---------------------------------------------------------------------------
local function caseKind(p: Player): (string, string, number)
	local text = string.lower(tostring(p:GetAttribute("CaseCharges") or p:GetAttribute("Charges") or ""))
	if text:find("murder") or text:find("officer") then return "murder / cop killing", "jury", 1.6 end
	if text:find("bank") or text:find("robbery") or text:find("escape") then return "armed robbery / heist", "jury", 1.2 end
	if text ~= "" then return "felony / misdemeanor", "bench", 1 end
	return "no open case", "bench", 1
end

local function quoteLines(p: Player, f: any): { string }
	local kind, trial, cx = caseKind(p)
	local a = acct(p)
	local rate = if a.firm == f.name and a.retained then math.floor(f.rate * (1 - CFG.RetainedDiscount)) else f.rate
	local r = HOURS[trial]
	local lo, hi = math.floor(r[1] * cx), math.floor(r[2] * cx)
	local lines = {
		("Retainer: %s  |  Hourly: %s"):format(money(f.retainer), money(f.rate)),
		("Your case: %s. A %s trial runs %d-%d h, about %s-%s."):format(kind, trial, lo, hi, money(lo * rate), money(hi * rate)),
		("On retainer before trouble: %s every billing cycle, %d%% off the hourly rate, we pick up when you're arrested."):format(
			money(f.retainer * CFG.CycleShare), math.floor(CFG.RetainedDiscount * 100)),
	}
	if f.tier >= 5 and kind == "no open case" then table.insert(lines, "(Frankly, for parking tickets you don't need us.)") end
	if f.tier <= 2 and cx >= 1.6 then table.insert(lines, "(A homicide is out of our depth. You want a bigger firm.)") end
	return lines
end

local function billLines(p: Player): { string }
	local a = acct(p)
	if not a.firm or a.firm == "Public Defender" then return { "You have no paid counsel." .. (if (a.debt or 0) > 0 then " Old debt: " .. money(a.debt) else "") } end
	local lines = {
		("Counsel: %s%s"):format(a.firm, if a.retained then " (on retainer)" else ""),
		("Trust balance: %s  |  Rate: %s/h  |  Hours billed: %.1f (%s)"):format(money(a.trust or 0), money(rateFor(a)), a.hours or 0, money(a.billed or 0)),
	}
	if (a.debt or 0) > 0 then table.insert(lines, "Unpaid: " .. money(a.debt)) end
	if a.retained then table.insert(lines, ("Next billing cycle in %d min."):format(math.max(0, math.ceil(((a.nextCycle or 0) - os.time()) / 60)))) end
	for i = 1, math.min(4, #a.log) do table.insert(lines, a.log[i]) end
	return lines
end

-- sign on (retainer before an arrest, or hiring for an open case)
local function signOn(p: Player, f: any, retainerOnly: boolean): boolean
	local a = acct(p)
	local fee = if retainerOnly then math.floor(f.retainer * CFG.CycleShare) else f.retainer
	if f.rate <= 0 then
		a.firm, a.retained, a.trust = f.name, false, 0
		save(p)
		return true
	end
	if not charge(p, fee) then
		notice(p, ("You need %s (frozen money doesn't count)."):format(money(fee)))
		return false
	end
	local same = a.firm == f.name
	if not same then a.hours, a.billed, a.log, a.trust = 0, 0, {}, 0 end
	a.firm = f.name
	a.retained = retainerOnly or (same and a.retained)
	if not retainerOnly then a.trust = (a.trust or 0) + fee end
	a.nextCycle = os.time() + CFG.CycleSeconds
	a.unpaid = 0
	save(p)
	print(("[Law] SIGNED %s with %s (%s, %s)"):format(p.Name, f.name, if retainerOnly then "retainer" else "hired", money(fee)))
	return true
end

---------------------------------------------------------------------------
-- v257b LEGAL VISITS (spec 9.6): an inmate's lawyer in the prison visiting rooms.
-- Glass for routine talks, contact when there's a lot to go over. Pay the lawyer a lot
-- extra on a contact visit and they slip you something; elite lawyers are searched
-- less, cheap ones are riskier and may give you up to save themselves.
---------------------------------------------------------------------------
local COURIER = {
	{ name = "Cash ($1,000)", item = "Cash", minTier = 2, rateHours = 2, extra = 1000 },
	{ name = "Pills", item = "Pills", minTier = 2, rateHours = 3, extra = 0 },
	{ name = "Spice", item = "Spice", minTier = 3, rateHours = 4, extra = 0 },
	{ name = "Lockpick", item = "Lockpick", minTier = 4, rateHours = 8, extra = 0 },
	{ name = "Shiv", item = "Shiv", minTier = 6, rateHours = 10, extra = 0 },
}
-- chance a CO search finds it, by firm tier (1 = PD ... 7 = Premier)
local SEARCH = { 0.5, 0.35, 0.25, 0.18, 0.1, 0.08, 0.05 }
local visiting: { [Player]: boolean } = {}

local function serving(p: Player): boolean
	return p:GetAttribute("SentenceEnd") ~= nil and p:GetAttribute("Visiting") == nil
end

local function giveContraband(p: Player, item: string)
	if item == "Cash" then
		local eco = ServerStorage:FindFirstChild("Economy")
		if eco then pcall(eco.Invoke, eco, "AddCash", p, 1000) end
	elseif item == "Lockpick" then
		local lp = ServerStorage:FindFirstChild("Lockpicks")
		if lp then
			pcall(lp.Invoke, lp, "Give", p)
			local bp = p:FindFirstChildOfClass("Backpack")
			local tool = bp and bp:FindFirstChild("Lockpick")
			if tool then tool:SetAttribute("Contraband", true) end
		end
	else
		local fn = ServerStorage:FindFirstChild("PrisonContraband")
		if fn then pcall(fn.Invoke, fn, p, item) end
	end
end

-- the conversation in the visiting room (runs inside PrisonExtras' legal visit)
local function visitTalk(p: Player, info: any): any
	local a = acct(p)
	local f = BY_NAME[a.firm or ""] or FIRMS[1]
	local result = { caught = false }
	local secs = math.max(0, (tonumber(p:GetAttribute("SentenceEnd")) or os.time()) - os.time())
	local kind = caseKind(p)
	local intro = {
		if f.tier <= 1 then "Public Defender's office. I've got ten minutes." else "Good to see you. This room is privileged - nobody's listening.",
		("Time left: %d:%02d. Charges: %s."):format(secs // 60, secs % 60, kind),
	}
	for _ = 1, 6 do
		local opts, acts = {}, {}
		local function add(t: string, fn: () -> boolean?) table.insert(opts, t); table.insert(acts, fn) end
		add("Go over my case", function()
			dialog(p, f.name, {
				if f.tier >= 5 then "We're reviewing every step of your arrest. If they cut corners, we'll find it." else "Keep your head down, no write-ups. Good behaviour is your best argument right now.",
				"An appeal goes through the prison court once you have a trial conviction.",
			}, { "OK" })
			bill(p, "meeting")
			return false
		end)
		add("Send a message to my crew", function()
			dialog(p, f.name, { "I'll pass it on. Attorney-client - it never happened." }, { "OK" })
			bill(p, "call")
			print(("[Law] MESSAGE OUT %s via %s"):format(p.Name, f.name))
			return false
		end)
		if info.contact and f.rate > 0 then
			add("Slip me something...", function()
				local items, list = {}, {}
				for _, c in COURIER do
					if f.tier >= c.minTier then
						local price = math.floor(rateFor(a) * c.rateHours + c.extra)
						table.insert(items, { c = c, price = price })
						table.insert(list, ("%s - %s"):format(c.name, money(price)))
					end
				end
				if #items == 0 then
					dialog(p, f.name, { "I'm going to pretend you didn't ask that." }, { "OK" })
					return false
				end
				table.insert(list, "Never mind")
				local idx = dialog(p, f.name, { "(quietly) That's... not something I do. For the right fee." }, list)
				local pick = idx and items[idx]
				if not pick then return false end
				if not charge(p, pick.price) then
					dialog(p, f.name, { "Not with what you've got. Frozen money doesn't count." }, { "OK" })
					return false
				end
				print(("[Law] COURIER %s: %s brings %s for %s"):format(p.Name, f.name, pick.c.item, money(pick.price)))
				if math.random() < (SEARCH[f.tier] or 0.3) then
					result.caught = true
					notice(p, ("CAUGHT - the COs searched %s and found the %s"):format(f.name, pick.c.name))
					local report = ServerStorage:FindFirstChild("ReportCrime")
					if report then pcall(report.Invoke, report, p, "Smuggling contraband into a prison", 2) end
					-- cheap lawyers save themselves
					if f.tier <= 2 and math.random() < 0.5 then
						notice(p, f.name .. " told the COs it was all your idea.")
					end
					print(("[Law] COURIER CAUGHT %s / %s - lawyer drops the case"):format(p.Name, f.name))
					withdraw(p, "caught smuggling contraband for you")
					return true
				end
				giveContraband(p, pick.c.item)
				notice(p, ("%s slid it over under the table: %s"):format(f.name, pick.c.name))
				return false
			end)
		end
		add("That's all", function() return true end)
		local idx = dialog(p, f.name .. " - legal visit", intro, opts)
		intro = { "Anything else?" }
		if not idx or not acts[idx] or acts[idx]() then break end
	end
	return result
end

local function requestVisit(p: Player, contact: boolean)
	if visiting[p] then return end
	local fn = ServerStorage:FindFirstChild("LegalVisit")
	if not (fn and fn:IsA("BindableFunction")) then
		notice(p, "Legal visits aren't available right now.")
		return
	end
	local a = acct(p)
	local firm = a.firm or "Public Defender"
	visiting[p] = true
	notice(p, ("%s is coming for a %s visit."):format(firm, if contact then "contact" else "glass"))
	task.wait(if (BY_NAME[firm] or FIRMS[1]).tier >= 5 then 10 else 30) -- the better the firm, the sooner
	if p.Parent and serving(p) then
		local ok, res, why = pcall(fn.Invoke, fn, p, firm, contact, visitTalk)
		if not ok or res ~= true then
			notice(p, "The visit couldn't happen: " .. tostring(if ok then why else res))
		end
	end
	visiting[p] = nil
end

---------------------------------------------------------------------------
-- v257b IN-PERSON MEETINGS (spec 9.5): the lawyer books a time at the office.
-- On time = a prepared case (CasePrepared - plea and court read it); late = billed
-- waiting; no-show = billed anyway and the lawyer gets annoyed (twice = they drop you).
-- MeetingAt / MeetingPlace / MeetingWith attributes drive the client's marker.
---------------------------------------------------------------------------
local offices: { [string]: Vector3 } = {}
local MEETING = { Lead = 150, Window = 150, Reach = 14 }

local function scheduleMeeting(p: Player, reason: string)
	local a = acct(p)
	local f = BY_NAME[a.firm or ""]
	if not f or f.rate <= 0 or p:GetAttribute("MeetingAt") then return end
	local place = offices[f.name]
	if not place then
		-- no office mapped for this firm: they do it over the phone
		local how = call(p, { from = f.name, kind = "lawyer", legal = true, expires = 300,
			lines = { ("We need to go over your case (%s). Let's do it now, on the phone."):format(reason) }, options = { "OK" } })
		if how == "answered" then
			bill(p, "meeting")
			p:SetAttribute("CasePrepared", true)
		end
		return
	end
	local due = os.time() + MEETING.Lead
	p:SetAttribute("MeetingAt", due)
	p:SetAttribute("MeetingPlace", place)
	p:SetAttribute("MeetingWith", f.name)
	print(("[Law] MEETING booked %s with %s (%s) in %d s"):format(p.Name, f.name, reason, MEETING.Lead))
	call(p, { from = f.name, kind = "lawyer", legal = true, expires = 120,
		lines = { ("Come to the office in %d minutes - %s. It has to be in person."):format(math.ceil(MEETING.Lead / 60), reason),
			"Watch for patrols on the way." }, options = { "I'll be there" } })
	-- wait for them at the office
	task.spawn(function()
		local arrived = nil
		while p.Parent and os.time() < due + MEETING.Window do
			local char = p.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and (root.Position - place).Magnitude <= MEETING.Reach and p:GetAttribute("CustodyStage") == nil then
				arrived = os.time()
				break
			end
			task.wait(1)
		end
		p:SetAttribute("MeetingAt", nil)
		p:SetAttribute("MeetingPlace", nil)
		p:SetAttribute("MeetingWith", nil)
		if not p.Parent then return end
		if arrived then
			local late = arrived > due
			if late then bill(p, "call") end -- the waiting time
			dialog(p, f.name, {
				if late then "You're late. We bill for waiting, you know." else "Right on time. Sit down.",
				("We went through everything for your case (%s). You're as ready as we can make you."):format(reason),
			}, { "OK" })
			bill(p, "meeting")
			p:SetAttribute("CasePrepared", true)
			a.annoyed = 0
			save(p)
			print(("[Law] MEETING %s attended%s"):format(p.Name, if late then " (late)" else ""))
		else
			bill(p, "meeting")
			a.annoyed = (a.annoyed or 0) + 1
			save(p)
			print(("[Law] MEETING %s no-show (%d)"):format(p.Name, a.annoyed))
			if a.annoyed >= 2 then
				withdraw(p, "missed meetings")
			else
				call(p, { from = f.name, kind = "lawyer", legal = true, expires = 300,
					lines = { "You didn't show. We billed you for the hour anyway. Do it again and find another lawyer." }, options = { "Sorry" } })
			end
		end
	end)
end

---------------------------------------------------------------------------
-- the menu (office reception, or the phone's Lawyer button)
---------------------------------------------------------------------------
local busy: { [Player]: boolean } = {}
local function menu(p: Player, office: any?)
	if busy[p] then return end
	busy[p] = true
	local a = acct(p)
	local inCustody = p:GetAttribute("CustodyStage") ~= nil
	local firm = if office then BY_NAME[office.firm] else BY_NAME[a.firm or ""]
	if firm and firm.rate <= 0 and not office then firm = nil end
	local from = if office and not office.phone then office.firm .. " - Reception" elseif firm then firm.name else "Lawyer"
	if not firm then
		-- phone with no lawyer: pick a firm to call
		local names = {}
		for i = 2, #FIRMS do names[i - 1] = FIRMS[i].name end
		table.insert(names, "Hang up")
		local idx = dialog(p, "Call a lawyer", { "Who do you call?" }, names)
		busy[p] = nil
		if idx and idx < #names then
			local f = FIRMS[idx + 1]
			-- 3 AM: cheap firms don't pick up
			if isNight() and math.random() > f.night then
				notice(p, f.name .. ": voicemail. \"Leave a message after the tone...\"")
				return
			end
			menu(p, { firm = f.name, phone = true })
		end
		return
	end
	local byPhone = office == nil or office.phone == true
	local opts, acts = {}, {}
	local function add(t: string, fn: () -> ()) table.insert(opts, t); table.insert(acts, fn) end
	add("Get a quote", function()
		dialog(p, firm.name, quoteLines(p, firm), { "OK" })
	end)
	if not (a.firm == firm.name and a.retained) and firm.rate > 0 and not inCustody then
		add(("Put %s on retainer (%s per cycle)"):format(firm.name, money(firm.retainer * CFG.CycleShare)), function()
			if byPhone and firm.inPerson then
				dialog(p, firm.name, { "We only sign new clients in person. Come by the office." }, { "OK" })
				return
			end
			if signOn(p, firm, true) then
				dialog(p, firm.name, { "Welcome aboard. Keep this number - day or night." }, { "OK" })
			end
		end)
	end
	if firm.rate > 0 and (inCustody or p:GetAttribute("CourtDateAt")) then
		add(("Hire for your open case (retainer %s)"):format(money(firm.retainer)), function()
			if byPhone and firm.inPerson and not inCustody then
				dialog(p, firm.name, { "Come to the office to sign. Bring the retainer." }, { "OK" })
				return
			end
			if signOn(p, firm, false) then
				dialog(p, firm.name, { ("Retained. %s in trust. We bill %s an hour against it."):format(money(acct(p).trust or 0), money(rateFor(acct(p)))) }, { "OK" })
				bill(p, "call")
			end
		end)
	end
	-- v257b: serving time - your lawyer comes to the prison
	if serving(p) and a.firm == firm.name and not visiting[p] then
		add("Request a legal visit (glass)", function() task.spawn(requestVisit, p, false) end)
		if firm.rate > 0 then
			add("Request a legal visit (contact)", function() task.spawn(requestVisit, p, true) end)
		end
	end
	if a.firm == firm.name and firm.rate > 0 then
		add("See my legal bill", function() dialog(p, firm.name .. " - Legal bill", billLines(p), { "OK" }) end)
		local amt = math.max(firm.rate * 10, 1000)
		add(("Top up trust (%s)"):format(money(amt)), function()
			if charge(p, amt) then
				local pay = amt
				if (a.debt or 0) > 0 then local d = math.min(a.debt, pay); a.debt -= d; pay -= d end
				a.trust = (a.trust or 0) + pay
				save(p)
				notice(p, ("Trust balance: %s"):format(money(a.trust)))
			else
				notice(p, "You can't cover that.")
			end
		end)
		if a.retained then
			add("End the retainer", function()
				a.retained = false
				save(p)
				notice(p, firm.name .. " is no longer on retainer.")
			end)
		end
	end
	add("Leave", function() end)
	local body = { if not byPhone then "\"Good day. How can the firm help you?\"" else "\"Law office, how can I help?\"" }
	local idx = dialog(p, from, body, opts)
	busy[p] = nil
	if idx and acts[idx] then acts[idx]() end
end

---------------------------------------------------------------------------
-- offices
---------------------------------------------------------------------------
local function setupOffices()
	if not F then warn("[Law] Facilities not available - no offices"); return end
	local used = {}
	for _, b in F.ofType("LawOffice") do
		local model = b.model
		local mapRoot = b.root
		local firm = (model and model:GetAttribute("Firm")) or (mapRoot and mapRoot:GetAttribute("Firm")) or b.firm
		local how = "Firm attribute"
		if not (type(firm) == "string" and BY_NAME[firm]) then
			firm = if not used["Local Attorney"] then "Local Attorney" else nil
			how = "no Firm attribute - used as the Local Attorney"
		end
		if not firm then
			print(("[Law] office %s has no Firm attribute - skipped (set Firm on the building)"):format(tostring(model and model.Name)))
		else
			used[firm] = true
			local pos, where = nil, "stand-in: first room"
			for _, pt in b.points or {} do if pt.pointType == "Reception" then pos, where = pt.position, "Reception point" end end
			if not pos then for _, s in b.seats or {} do if s.role == "LawyerSeat" then pos, where = s.position, "LawyerSeat" end end end
			if not pos then
				local z = (b.zones or {})[1]
				pos = z and z.center + Vector3.new(0, 3, 0)
			end
			if pos then
				local part = Instance.new("Part")
				part.Name = "LawReception_" .. firm
				part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
				part.Transparency = 1
				part.Size = Vector3.one
				part.Position = pos
				part.Parent = Workspace
				local prompt = Instance.new("ProximityPrompt")
				prompt.ActionText = "Talk to reception"
				prompt.ObjectText = firm
				prompt.HoldDuration = 0.3
				prompt.MaxActivationDistance = 10
				prompt.RequiresLineOfSight = false
				prompt.Parent = part
				local office = { firm = firm, pos = pos }
				offices[firm] = pos
				prompt.Triggered:Connect(function(p) task.spawn(menu, p, office) end)
				print(("[Law] office: %s in %s (%s, %s)"):format(firm, tostring(model and model.Name), how, where))
			end
		end
	end
	for _, f in FIRMS do
		if f.rate > 0 and not used[f.name] then print("[Law] no office mapped for " .. f.name .. " (LawOffice building with Firm = \"" .. f.name .. "\")") end
	end
end

---------------------------------------------------------------------------
-- hooks: arrest call (3 AM rule), interrogation, bail hearing, booking, cycles
---------------------------------------------------------------------------
local function onArrest(p: Player)
	local a = acct(p)
	local f = BY_NAME[a.firm or ""]
	if not (f and a.retained and f.rate > 0) then return end
	local night = isNight()
	local answers = (not night) or math.random() < f.night
	if answers then
		p:SetAttribute("LawyerPresent", true)
		local junior = night and f.junior and math.random() < 0.5
		notice(p, ("%s picked up. %s"):format(f.name, if junior then "A junior associate is on the way." else "Your lawyer is on the way - say nothing."))
		bill(p, "call")
		print(("[Law] ARREST CALL %s -> %s answered (%s)"):format(p.Name, f.name, if night then "night" else "day"))
	else
		notice(p, ("%s: voicemail. Nobody picks up at this hour."):format(f.name))
		print(("[Law] ARREST CALL %s -> %s slept through it"):format(p.Name, f.name))
		task.delay(240, function()
			if p.Parent then
				call(p, { from = f.name, kind = "lawyer", legal = true, expires = 300,
					lines = { "Sorry, I was asleep... What did you tell them?" }, options = { "Nothing", "...Some things" } })
			end
		end)
	end
end

local function watch(p: Player)
	p:GetAttributeChangedSignal("CustodyStage"):Connect(function()
		local s = p:GetAttribute("CustodyStage")
		if s == "Arrest" and not p:GetAttribute("LawyerCalledThisCase") then
			p:SetAttribute("LawyerCalledThisCase", true)
			task.spawn(onArrest, p)
		elseif s == nil then
			p:SetAttribute("LawyerCalledThisCase", nil)
			p:SetAttribute("LawyerPresent", nil)
			-- v257b: out on bond with a court date - paid counsel books a case review
			task.delay(20, function()
				if p.Parent and p:GetAttribute("CourtDateAt") and p:GetAttribute("CustodyStage") == nil then
					scheduleMeeting(p, "case review before your court date")
				end
			end)
		end
	end)
	-- a new case starts unprepared
	p:GetAttributeChangedSignal("LastArrestAt"):Connect(function()
		p:SetAttribute("CasePrepared", nil)
	end)
	p:GetAttributeChangedSignal("BookingState"):Connect(function()
		if p:GetAttribute("BookingState") == "Interrogation" and p:GetAttribute("LawyerPresent") then
			bill(p, "interrogation")
		end
	end)
	p:GetAttributeChangedSignal("BailOffered"):Connect(function()
		if p:GetAttribute("BailOffered") then
			local a = acct(p)
			if a.firm and a.firm ~= "Public Defender" then bill(p, "bail") end
		end
	end)
	p:GetAttributeChangedSignal("CounselName"):Connect(function()
		local n = p:GetAttribute("CounselName")
		if n and n ~= "Public Defender" and acct(p).firm == n then
			local _, trial, cx = caseKind(p)
			bill(p, trial, cx)
		end
	end)
	task.delay(8, function() if p.Parent and Records then save(p) end end)
end
Players.PlayerAdded:Connect(watch)
for _, p in Players:GetPlayers() do task.spawn(watch, p) end
Players.PlayerRemoving:Connect(function(p) busy[p] = nil end)

-- billing cycles for retained clients
task.spawn(function()
	while true do
		task.wait(20)
		if Records then
			for _, p in Players:GetPlayers() do
				local a = acct(p)
				if a.retained and (a.nextCycle or 0) > 0 and os.time() >= a.nextCycle then
					local f = BY_NAME[a.firm or ""]
					if f then
						local fee = math.floor(f.retainer * CFG.CycleShare)
						a.nextCycle = os.time() + CFG.CycleSeconds
						if charge(p, fee) then
							notice(p, ("%s retainer: %s billed for this cycle."):format(f.name, money(fee)))
						else
							a.retained = false
							notice(p, ("%s retainer lapsed - you couldn't pay %s."):format(f.name, money(fee)))
						end
						save(p)
					end
				end
			end
		end
	end
end)

---------------------------------------------------------------------------
-- API: ServerStorage.LawFirms
--   ("hireAtBooking", player, firmName) -> true | reason   (PoliceSystem SelectCounsel)
--   ("menu", player)                                        (phone Lawyer button)
--   ("bill", player, activity, complexity) -> hours
--   ("retained", player) -> firm name or nil
---------------------------------------------------------------------------
do
	local fn = ServerStorage:FindFirstChild("LawFirms") or Instance.new("BindableFunction")
	fn.Name = "LawFirms"
	fn.OnInvoke = function(action, p, x, y)
		if typeof(p) ~= "Instance" or not p:IsA("Player") then return nil end
		if action == "hireAtBooking" then
			local f = BY_NAME[tostring(x)]
			if not f then return "Unknown counsel" end
			local a = acct(p)
			if f.rate <= 0 or (a.firm == f.name and (a.retained or (a.trust or 0) > 0)) then
				print(("[Law] BOOKING %s uses %s"):format(p.Name, f.name))
				if f.rate <= 0 then a.firm = f.name; save(p) end
				return true
			end
			if signOn(p, f, false) then return true end
			return ("You need %s for the %s retainer"):format(money(f.retainer), f.name)
		elseif action == "menu" then
			task.spawn(menu, p, nil)
			return true
		elseif action == "bill" then
			return bill(p, tostring(x), tonumber(y))
		elseif action == "retained" then
			local a = acct(p)
			return if a.retained then a.firm else nil
		elseif action == "meeting" then
			-- v257b: other scripts (plea offers, trial prep) book an in-person meeting
			task.spawn(scheduleMeeting, p, tostring(x or "your case"))
			return true
		elseif action == "legalVisit" then
			task.spawn(requestVisit, p, x == true)
			return true
		end
		return nil
	end
	fn.Parent = ServerStorage
end

task.delay(10, function()
	local ok, err = pcall(setupOffices)
	if not ok then warn("[Law] office setup failed: " .. tostring(err)) end
	print("[Law] v257 ready")
end)
