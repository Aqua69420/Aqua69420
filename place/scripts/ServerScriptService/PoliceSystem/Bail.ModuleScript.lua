--[[
	Bail  (child ModuleScript of PoliceSystem)   v254

	The bail decision at Police HQ booking, for cases that aren't cited and released:
	  * amount: $400 per star, +50% per prior arrest, -40% for turning yourself in
	  * no bail: a prior failure to appear, an escape on record, already out on bond
	    (serious / murder cases are held before they get here - see hqCustody)
	  * the detainee chooses on screen (BailClient): pay it, a bondsman (10% fee, gone for
	    good, the bondsman covers the rest), or stay in custody; another player can post it
	    for them at the HQ front desk while the offer is open
	  * posted = walked out with a COURT DATE (kept in the saved record, survives leaving)
	  * court (until the courthouse is built): show up at the HQ front desk inside the window
	    -> the case closes as time served and the bail goes back to whoever paid it
	  * miss it -> failure to appear: bond forfeited, a warrant (Warrant attribute, v260 uses
	    it), +1 failuresToAppear on the record = no bail next time

	init(ctx) ctx = { tell(player, kind, text), charge(player, amount) -> bool,
	                  payBank(player, amount), Records }
	offer(player, info) -> "posted" | "stay" | "denied"   (yields while the detainee decides)
	desk(player) -> bool   (the HQ front desk: court appearance / post someone's bail)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local B = {}
B.VERSION = 254

local CFG = {
	PerStar = 400,
	PriorStep = 0.5,
	TurnedInScale = 0.6,
	BondsmanCut = 0.10,
	DecideSeconds = 30,
	CourtIn = 20 * 60, -- court date: 20 real minutes after release
	CourtEarly = 5 * 60, -- can appear up to 5 minutes early
	CourtWindow = 5 * 60, -- ... and up to 5 minutes late
}
B.CFG = CFG

local ctx: any = nil
local offers: { [Player]: any } = {} -- open bail offers (detainee -> offer)
local remote: RemoteEvent? = nil

local function rec(player: Player): any
	return ctx.Records and ctx.Records.get(player) or {}
end

local function savePending(player: Player, pending: any?)
	if not ctx.Records then
		return
	end
	local r = ctx.Records.get(player)
	r.pendingCourt = pending
	if ctx.Records.touch then
		ctx.Records.touch(player)
	end
	player:SetAttribute("CourtDateAt", if pending then pending.due else nil)
end

function B.pending(player: Player): any?
	local p = rec(player).pendingCourt
	return if type(p) == "table" then p else nil
end

-- nil = no bail
function B.amountFor(player: Player, info: any): (number?, string?)
	local r = rec(player)
	if (tonumber(r.failuresToAppear) or 0) > 0 then
		return nil, "a failure to appear on your record"
	end
	if (tonumber(r.escapes) or 0) > 0 then
		return nil, "an escape on your record"
	end
	if B.pending(player) then
		return nil, "you're already out on bond"
	end
	local stars = math.max(1, tonumber(info.stars) or 1)
	local priors = math.max(0, tonumber(info.priors) or 0)
	local amount = CFG.PerStar * stars * (1 + CFG.PriorStep * priors)
	if info.turnedIn then
		amount *= CFG.TurnedInScale
	end
	return math.floor(amount / 50 + 0.5) * 50, nil
end

-- posted: release paperwork + court date
local function post(player: Player, o: any, how: string, payer: Player?)
	o.result = "posted"
	local refundTo = if how == "self" then player.UserId elseif how == "other" and payer then payer.UserId else nil
	savePending(player, {
		due = os.time() + CFG.CourtIn,
		amount = o.amount,
		refundTo = refundTo,
		how = how,
		recIndex = o.info.recIndex,
		charges = o.info.text,
	})
	if ctx.Records then
		ctx.Records.setOutcome(player, o.info.recIndex, "Bail", { bail = o.amount, bailHow = how })
	end
	ctx.tell(player, "Custody", ("Bail posted ($%d%s). Court date in %d minutes - be at the Police HQ front desk."):format(
		o.amount, if how == "bondsman" then ", by a bondsman" elseif how == "other" and payer then ", by " .. payer.Name else "",
		CFG.CourtIn // 60))
	print(("[Bail] POSTED %s $%d via %s%s"):format(player.Name, o.amount, how, if payer then " (" .. payer.Name .. ")" else ""))
end

function B.offer(player: Player, info: any): string
	local amount, why = B.amountFor(player, info)
	if not amount then
		ctx.tell(player, "Custody", "Bail denied: " .. tostring(why))
		print(("[Bail] DENIED %s (%s)"):format(player.Name, tostring(why)))
		return "denied"
	end
	local fee = math.max(50, math.floor(amount * CFG.BondsmanCut))
	local o = { amount = amount, fee = fee, info = info, result = nil, expires = os.clock() + CFG.DecideSeconds }
	offers[player] = o
	player:SetAttribute("BailOffered", amount)
	print(("[Bail] OFFER %s $%d (bondsman fee $%d)"):format(player.Name, amount, fee))
	if remote then
		remote:FireClient(player, { amount = amount, fee = fee, seconds = CFG.DecideSeconds, charges = info.text })
	end
	ctx.tell(player, "Custody", ("Bail set at $%d"):format(amount))
	while player.Parent and not o.result and os.clock() < o.expires do
		task.wait(0.25)
	end
	offers[player] = nil
	player:SetAttribute("BailOffered", nil)
	if remote and player.Parent then
		remote:FireClient(player, nil) -- close the panel
	end
	if o.result == "posted" then
		return "posted"
	end
	if not o.result then
		ctx.tell(player, "Custody", "No bail posted - you stay in custody")
	end
	return "stay"
end

-- HQ front desk. Returns true if it handled the visit.
function B.desk(player: Player): boolean
	local p = B.pending(player)
	if p then
		local now = os.time()
		if now < p.due - CFG.CourtEarly then
			ctx.tell(player, "Notice", ("Your court date is in %d minute(s) - come back then"):format(math.ceil((p.due - now) / 60)))
			return true
		end
		-- court (interim): time served, bail back to whoever paid it
		savePending(player, nil)
		if ctx.Records then
			ctx.Records.setOutcome(player, p.recIndex, "TimeServed", { court = os.time() })
		end
		local refundTo = p.refundTo and Players:GetPlayerByUserId(p.refundTo)
		if refundTo and p.amount then
			ctx.payBank(refundTo, p.amount)
			ctx.tell(refundTo, "Notice", ("$%d bail refunded - %s showed up for court"):format(p.amount, player.Name))
		end
		ctx.tell(player, "Notice", ("Court: case closed - time served%s"):format(if refundTo then ". Bail refunded." else ""))
		print(("[Bail] COURT %s appeared - time served"):format(player.Name))
		return true
	end
	-- someone in the holding cell has bail set: post it for them
	for detainee, o in offers do
		if detainee ~= player and detainee.Parent and not o.result then
			if ctx.charge(player, o.amount) then
				post(detainee, o, "other", player)
				ctx.tell(player, "Notice", ("You posted $%d bail for %s"):format(o.amount, detainee.Name))
			else
				ctx.tell(player, "Notice", ("%s's bail is $%d - you can't cover it"):format(detainee.Name, o.amount))
			end
			return true
		end
	end
	return false
end

-- court dates: reminders, and failures to appear
local function failToAppear(player: Player, p: any)
	savePending(player, nil)
	if ctx.Records then
		ctx.Records.note(player, "failuresToAppear")
		ctx.Records.setOutcome(player, p.recIndex, "FailureToAppear", { fta = os.time() })
	end
	player:SetAttribute("Warrant", "Failure to appear")
	ctx.tell(player, "Notice", ("You missed court. Bond forfeited ($%d) - there's a warrant out for you."):format(tonumber(p.amount) or 0))
	print(("[Bail] FAILURE TO APPEAR %s - warrant issued"):format(player.Name))
end

function B.init(c: any)
	ctx = c
	local folder = ReplicatedStorage:FindFirstChild("BailRemotes") or Instance.new("Folder")
	folder.Name = "BailRemotes"
	folder.Parent = ReplicatedStorage
	local r = folder:FindFirstChild("Offer") or Instance.new("RemoteEvent")
	r.Name = "Offer"
	r.Parent = folder
	remote = r :: RemoteEvent
	r.OnServerEvent:Connect(function(player, choice)
		local o = offers[player]
		if not o or o.result then
			return
		end
		if choice == "self" then
			if ctx.charge(player, o.amount) then
				post(player, o, "self")
			else
				ctx.tell(player, "Custody", ("You don't have $%d"):format(o.amount))
			end
		elseif choice == "bondsman" then
			if ctx.charge(player, o.fee) then
				post(player, o, "bondsman")
			else
				ctx.tell(player, "Custody", ("You can't even cover the bondsman's $%d"):format(o.fee))
			end
		elseif choice == "stay" then
			o.result = "stay"
		end
	end)
	task.spawn(function()
		while true do
			task.wait(15)
			local now = os.time()
			for _, player in Players:GetPlayers() do
				local p = B.pending(player)
				if p then
					player:SetAttribute("CourtDateAt", p.due)
					if now > p.due + CFG.CourtWindow then
						failToAppear(player, p)
					elseif not p.warned5 and now > p.due - 5 * 60 then
						p.warned5 = true
						ctx.tell(player, "Notice", "Reminder: your court date is in 5 minutes - Police HQ front desk")
					elseif not p.warned0 and now >= p.due then
						p.warned0 = true
						ctx.tell(player, "Notice", ("Court is now - you have %d minutes to get to the Police HQ front desk"):format(CFG.CourtWindow // 60))
					end
				end
			end
		end
	end)
	print(("[Bail] v%d ready: $%d per star, court in %d min"):format(B.VERSION, CFG.PerStar, CFG.CourtIn // 60))
end

return B
