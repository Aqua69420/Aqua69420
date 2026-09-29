--[[
	PoliceAI · Perception
	Line-of-sight checks with per-officer / per-incident caching and distance LOD, so a
	squad of officers doesn't raycast every frame. Anything seen is reported into the
	incident's shared knowledge. Distance alone never removes knowledge: an officer on the
	call keeps eyes on the suspect out to TrackRange as long as the line of sight is clear.
]]

local Perception = {}
local Ctx, Tuning, Log, Util, Knowledge

local FOV_COS = 0

function Perception.bind(ctx)
	Ctx = ctx
	Tuning, Log, Util, Knowledge = ctx.Tuning, ctx.Log, ctx.Util, ctx.Knowledge
	FOV_COS = math.cos(math.rad(Tuning.Perception.FOV / 2))
end

local function sightEntry(cop: any, inc: any): any
	local cache = cop.aiSight
	if not cache then
		cache = setmetatable({}, { __mode = "k" })
		cop.aiSight = cache
	end
	local e = cache[inc]
	if not e then
		e = { visible = false, seen = -math.huge, since = 0, nextAt = 0 }
		cache[inc] = e
	end
	return e
end

-- Keep CopAI's legacy memory in sync so tryShoot's reaction time / settle accuracy works.
local function syncAware(cop: any, player: Player, visible: boolean, now: number)
	local aware = cop.aware
	if not aware then
		return
	end
	local mem = aware[player]
	if visible then
		if not mem or not mem.visible then
			mem = { seen = now, since = now, visible = true }
			aware[player] = mem
		end
		mem.seen = now
		mem.visible = true
	elseif mem then
		mem.visible = false
	end
end

-- Does this officer see the incident's suspect right now? Cached with LOD.
function Perception.officer(cop: any, inc: any, now: number, force: boolean?): boolean
	local e = sightEntry(cop, inc)
	if not force and now < e.nextAt then
		return e.visible
	end
	local P = Tuning.Perception
	local visible = false
	local char, hum, root = Util.charInfo(inc.player)
	local dist = math.huge
	if char and hum and root and cop.head and cop.head.Parent then
		local part = Util.aimPart(char) or root
		local eye = cop.head.Position
		local delta = part.Position - eye
		dist = delta.Magnitude
		local assigned = cop.pursuit == inc.pursuit
		local tracking = now - e.seen < P.TrackMemory
		local range = if assigned or tracking then P.TrackRange else P.DetectRange
		if dist <= range then
			local inView = dist <= P.NoticeRange or tracking
			if not inView then
				if assigned and Knowledge.fresh(inc) then
					-- the radio says where he is: the officer looks there
					inView = true
				else
					local look = cop.root.CFrame.LookVector
					inView = look:Dot(Util.safeUnit(delta, look)) >= FOV_COS
				end
			end
			if inView then
				visible = Util.canSee(eye, char, part, { cop.model }, hum.SeatPart)
				if not visible and hum.SeatPart then
					visible = Util.canSee(eye, char, hum.SeatPart, { cop.model }, hum.SeatPart)
				elseif not visible and dist < 160 then
					visible = Util.canSee(eye, char, root, { cop.model }, hum.SeatPart)
				end
			end
		end
		if visible then
			if not e.visible then
				e.since = now
			end
			e.seen = now
			Knowledge.observe(inc, "VISUAL", root.Position, root.AssemblyLinearVelocity, cop, hum.SeatPart)
		end
	end
	e.visible = visible
	local interval = if dist < 90 then P.IntervalNear elseif dist < 320 then P.IntervalMid else P.IntervalFar
	e.nextAt = now + interval * (0.85 + math.random() * 0.3)
	syncAware(cop, inc.player, visible, now)
	return visible
end

function Perception.sawRecently(cop: any, inc: any, now: number, window: number): boolean
	local e = cop.aiSight and cop.aiSight[inc]
	return e ~= nil and now - e.seen <= window
end

function Perception.visibleSince(cop: any, inc: any): number?
	local e = cop.aiSight and cop.aiSight[inc]
	return if e and e.visible then e.since else nil
end

-- Uninvolved patrol officer: would he notice this suspect? (FOV + detect range)
function Perception.detect(cop: any, inc: any, now: number): boolean
	local k = inc.knowledge
	if not cop.root or (cop.root.Position - k.pos).Magnitude > Tuning.Perception.DetectRange + 120 then
		return false
	end
	return Perception.officer(cop, inc, now, false)
end

-- A cruiser's crew looking out (two officers: effectively all-round vision).
function Perception.cruiser(van: any, inc: any, now: number, range: number?): boolean
	local e = van.aiSight
	if not e then
		e = setmetatable({}, { __mode = "k" })
		van.aiSight = e
	end
	local s = e[inc]
	if not s then
		s = { visible = false, nextAt = 0, seen = -math.huge }
		e[inc] = s
	end
	if now < s.nextAt then
		return s.visible
	end
	s.nextAt = now + Tuning.Perception.CruiserInterval * (0.85 + math.random() * 0.3)
	local visible = false
	local char, hum, root = Util.charInfo(inc.player)
	if char and hum and root and van.body and van.body.Parent then
		local eye = van.body.Position + Vector3.new(0, (van.cfg and van.cfg.Size.Y or 5) * 0.5 + 0.6, 0)
		local part = Util.aimPart(char) or root
		if (part.Position - eye).Magnitude <= (range or Tuning.Perception.CruiserRange) then
			visible = Util.canSee(eye, char, part, { van.model }, hum.SeatPart)
			if not visible and hum.SeatPart then
				-- the car itself (roof, doors, rear end) is as good as seeing the driver
				visible = Util.canSee(eye, char, hum.SeatPart, { van.model }, hum.SeatPart)
			end
		end
		if visible then
			s.seen = now
			Knowledge.observe(inc, "CRUISER", root.Position, root.AssemblyLinearVelocity, van, hum.SeatPart)
		end
	end
	s.visible = visible
	return visible
end

function Perception.cruiserSaw(van: any, inc: any, now: number, window: number): boolean
	local e = van.aiSight and van.aiSight[inc]
	return e ~= nil and now - e.seen <= window
end

-- Can an officer standing at `fromPos` see a model (e.g. the suspect's known car)?
function Perception.canSeeModel(fromPos: Vector3, model: Model, ignore: { Instance }?): boolean
	local ok, pivot = pcall(function()
		return model:GetPivot().Position
	end)
	if not ok then
		return false
	end
	local dir = pivot - fromPos
	local hit = Util.cast(fromPos, dir, ignore)
	if not hit then
		return true
	end
	return hit.Instance:IsDescendantOf(model) or (hit.Position - fromPos).Magnitude >= dir.Magnitude - 3
end

return Perception
