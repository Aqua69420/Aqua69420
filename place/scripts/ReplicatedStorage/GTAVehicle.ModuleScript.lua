--[[
	GTAVehicle - GTA IV style car physics driven by handling.dat values.

	The car's driver seat is the chassis. Each wheel (Essentials.LF/RF/LB/RB) is a
	suspension ray: spring + compression / rebound damping hold the body up; a tyre
	model turns slip into grip. Visual wheels stay on their hinges but don't touch the
	world (CarServer makes them massless and non-colliding).

	Units: handling.dat is in metres, km/h and multiples of g. One metre is
	Data.MetersToStuds studs, and the car feels real gravity (9.81 m/s2 in studs) - an
	upward force cancels the rest of Roblox's much stronger gravity - so every value
	means what it means in GTA.

	handling.dat (GTA IV) columns, in order (Data.Columns can override):
	  name mass dragMult percentSubmerged comX comY comZ driveBiasFront gears driveForce
	  driveInertia maxVel brakeForce brakeBiasFront steeringLock tractionMax tractionMin
	  tractionLateral tractionLongitudinal tractionSpringDeltaMax tractionBiasFront
	  suspForce suspCompDamp suspReboundDamp suspUpper suspLower suspRaise suspBiasFront
	  collisionDamage weaponDamage deformationDamage engineDamage seatOffset value
	  modelFlags handlingFlags
]]

local M = {}

-- tuning knobs (GTAHandlingData.TopSpeedScale / AccelScale override these)
M.TopSpeedScale = 1.2 -- real top speed vs handling.dat Tv (IV runs ~20% past it)
M.AccelScale = 1.3
M.AccelByLine = {} :: { [string]: number } -- per handling line, e.g. INFERNUS = 1.1
M.RideHeight = 0.3 -- studs the body rides higher than the model was built
M.BodyRoll = 1.8 -- studs below the contact patch the tyre forces act: more = more lean / nose dive (0 = stiff)

function M.configure(data: any)
	if type(data) == "table" then
		M.TopSpeedScale = tonumber(data.TopSpeedScale) or M.TopSpeedScale
		M.AccelScale = tonumber(data.AccelScale) or M.AccelScale
		M.BodyRoll = tonumber(data.BodyRoll) or M.BodyRoll
		if type(data.AccelByLine) == "table" then
			M.AccelByLine = {}
			for k, v in data.AccelByLine do
				M.AccelByLine[string.upper(tostring(k))] = tonumber(v)
			end
		end
	end
end

-- GTA IV handling.dat (the real file): A B C D E F G | Tt Tg Tf Ti Tv | Tb Tbb Thb | Ts |
-- Wc+ Wc- Wc-(lat) Ws+ Wbias | Sf Scd Srd Su Sl Sr Sb | Dc Dw Dd De | Ms Mv Mmf Mhf Ma
M.COLUMNS_IV = {
	"name", "mass", "dragMult", "percentSubmerged", "comX", "comY", "comZ",
	"driveBiasFront", "gears", "driveForce", "driveInertia", "maxVel",
	"brakeForce", "brakeBiasFront", "handbrakeForce", "steeringLock",
	"tractionMax", "tractionMin", "tractionLateral", "tractionSpringDeltaMax", "tractionBiasFront",
	"suspForce", "suspCompDamp", "suspReboundDamp", "suspUpper", "suspLower", "suspRaise", "suspBiasFront",
	"collisionDamage", "weaponDamage", "deformationDamage", "engineDamage",
	"seatOffset", "value", "modelFlags", "handlingFlags", "animGroup",
}

local DEFAULTS = {
	mass = 1500, dragMult = 6.0, comX = 0, comY = 0, comZ = 0, driveBiasFront = 0, gears = 5, driveForce = 0.18,
	driveInertia = 1, maxVel = 140, brakeForce = 0.22, brakeBiasFront = 0.65, handbrakeForce = 0.7, steeringLock = 35, tractionMax = 2.0,
	tractionMin = 1.8, tractionLateral = 20, tractionLongitudinal = 1, tractionSpringDeltaMax = 0.15,
	tractionBiasFront = 0.5, suspForce = 2.0, suspCompDamp = 1.0, suspReboundDamp = 1.4, suspUpper = 0.1,
	suspLower = -0.15, suspRaise = 0, suspBiasFront = 0.5,
}

-- Parse handling.dat text (any number of lines; ";" "#" "//" start comments).
-- Returns { [NAME] = handling table }. Unknown / short lines are skipped.
function M.parse(text: string, columns: { string }?): { [string]: any }
	local cols = columns or M.COLUMNS_IV
	local out = {}
	for line in string.gmatch(text .. "\n", "([^\r\n]*)\r?\n") do
		local clean = string.gsub(line, "^%s+", "")
		-- vehicle lines start with a letter; ; # comments and the % boat / ! bike /
		-- $ flying / ^ anim-group tables are skipped
		if string.match(clean, "^%a") then
			local tokens = {}
			for tok in string.gmatch(clean, "%S+") do
				table.insert(tokens, tok)
			end
			if #tokens >= 20 and not tonumber(tokens[1]) then
				local h = {}
				for k, v in DEFAULTS do
					h[k] = v
				end
				for i, key in cols do
					local tok = tokens[i]
					if tok then
						h[key] = if key == "name" or key == "modelFlags" or key == "handlingFlags" then tok else (tonumber(tok) or h[key])
					end
				end
				h.name = string.upper(tostring(h.name))
				out[h.name] = h
			end
		end
	end
	return out
end

-- one-line summary for the Output
function M.describe(h: any): string
	return ("%s: %.0fkg drag %.1f, drive %.2f x%d gears %s, top %.0fkm/h, brake %.2f hb %.2f, lock %.0f, grip %.2f/%.2f @%.1f deg, susp %.2f"):format(
		h.name, h.mass, h.dragMult, h.driveForce, h.gears,
		if h.driveBiasFront >= 0.99 then "FWD" elseif h.driveBiasFront <= 0.01 then "RWD" else "AWD",
		h.maxVel, h.brakeForce, h.handbrakeForce, h.steeringLock, h.tractionMax, h.tractionMin, h.tractionLateral, h.suspForce)
end

local WHEEL_NAMES = { "LF", "RF", "LB", "RB" }

-- builds the per-car state; `seat` is the driver's VehicleSeat (the chassis root)
function M.new(car: Model, seat: BasePart, h: any, metersToStuds: number): any
	local essentials = car:FindFirstChild("Essentials")
	local wheels = {}
	local sumZ = 0
	for _, name in WHEEL_NAMES do
		local w = essentials and essentials:FindFirstChild(name)
		if w and w:IsA("BasePart") then
			-- the server measures each wheel's place on the car when it builds it and stamps
			-- it on the wheel. A client measuring for itself the moment you sit in a freshly
			-- spawned car got it wrong (the car hadn't fully arrived): rays too short, the
			-- body sank onto the road and dragged - twitchy steering, handbrake circles.
			local stamped = w:GetAttribute("GTAOffset")
			local lp = if typeof(stamped) == "Vector3" then stamped else seat.CFrame:PointToObjectSpace(w.Position)
			if typeof(stamped) ~= "Vector3" and game:GetService("RunService"):IsServer() then
				w:SetAttribute("GTAOffset", lp)
			end
			-- ghost chassis (CarServer): the wheel is a visual on a Motor6D, posed every step
			local motor = w:FindFirstChild("GTAWheelMotor")
			local baseC0 = w:GetAttribute("GTABaseC0")
			table.insert(wheels, { part = w, offset = lp, radius = math.max(math.max(w.Size.X, w.Size.Y, w.Size.Z) / 2, 0.5),
				lastComp = nil, contact = false, spin = 0, angle = 0, drop = 0,
				motor = if motor and motor:IsA("Motor6D") then motor else nil,
				baseC0 = if typeof(baseC0) == "CFrame" then baseC0 else nil,
				axleSign = tonumber(w:GetAttribute("GTAAxleSign")) or 1 })
			sumZ += lp.Z
		end
	end
	if #wheels < 3 then
		return nil
	end
	local midZ = sumZ / #wheels
	local fronts, rears = 0, 0
	for _, w in wheels do
		w.front = w.offset.Z < midZ -- the seat looks down -Z
		if w.front then fronts += 1 else rears += 1 end
	end
	local spins, steers = {}, {}
	for _, obj in car:GetDescendants() do
		if obj:IsA("HingeConstraint") then
			if obj.Name == "Spin" and obj:GetAttribute("Sign") then
				-- the spin hinge lives in its wheel
				for _, w in wheels do
					if obj.Parent == w.part then
						w.hinge = obj
					end
				end
			elseif obj.Name == "SteerHinge" then
				table.insert(steers, obj)
			end
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { car }
	params.RespectCanCollide = true

	-- Yaw inertia. The Roblox car's mass sits mostly in a heavy ballast block in the
	-- middle, so it turns far too easily for its weight (a real car's mass is spread to
	-- its ends). Measure what Roblox has, work out what a real car this size has
	-- (m (L^2 + W^2) / 12), and scale the turning part of every tyre force by the ratio.
	local yawScale = 1
	local stampedYaw = seat:GetAttribute("GTAYawScale")
	if type(stampedYaw) == "number" then
		yawScale = stampedYaw
	else
		local com = seat.AssemblyCenterOfMass
		local up = seat.CFrame.UpVector
		local iRb = 0
		for _, p in car:GetDescendants() do
			if p:IsA("BasePart") and not p.Massless and p.AssemblyRootPart == seat.AssemblyRootPart then
				local m = p:GetMass()
				local d = p.Position - com
				d -= up * d:Dot(up)
				iRb += m * d:Dot(d) + m * (p.Size.X * p.Size.X + p.Size.Z * p.Size.Z) / 12
			end
		end
		local _, size = car:GetBoundingBox()
		local mass = seat.AssemblyMass
		local L, W = math.max(size.X, size.Z), math.min(size.X, size.Z)
		local iReal = mass * (L * L + W * W) / 12
		if iRb > 0 and iReal > 0 then
			yawScale = math.clamp(iRb / iReal, 0.1, 1.5)
		end
		print(("[GTAHandling] %s: yaw inertia roblox %.0f vs real %.0f -> turning forces x%.2f"):format(car.Name, iRb, iReal, yawScale))
		if game:GetService("RunService"):IsServer() then
			seat:SetAttribute("GTAYawScale", yawScale)
		end
	end

	return {
		car = car, seat = seat, h = h, S = metersToStuds, wheels = wheels, fronts = math.max(1, fronts), rears = math.max(1, rears),
		spins = spins, steers = steers, params = params, steer = 0, gear = 1, rpm = 0, yawScale = yawScale,
		anti = seat:FindFirstChild("GTAAntiGravity"), steerDirection = seat:GetAttribute("SteerDirection") or 1,
	}
end

-- add players / dropped things to the ray ignore list
function M.ignore(st: any, list: { Instance })
	local f = { st.car }
	for _, i in list do
		table.insert(f, i)
	end
	st.params.FilterDescendantsInstances = f
end

local function sign(x: number): number
	return if x > 0 then 1 elseif x < 0 then -1 else 0
end

-- a tyre impulse: the full push through the centre of mass, and the turning part with
-- its yaw (spin around the car's up axis) scaled to a real car's inertia
local function push(st: any, impulse: Vector3, at: Vector3, up: Vector3)
	local seat = st.seat
	local r = at - seat.AssemblyCenterOfMass
	local angular = r:Cross(impulse)
	local yaw = up * angular:Dot(up)
	seat:ApplyImpulse(impulse)
	seat:ApplyAngularImpulse((angular - yaw) + yaw * st.yawScale)
end

-- input = { throttle = -1..1 (S = brake / reverse), steer = -1..1, handbrake = bool }
function M.step(st: any, dt: number, input: any): any
	local seat, h, S = st.seat, st.h, st.S
	dt = math.clamp(dt, 1 / 240, 1 / 20)
	local G = 9.81 * S -- real gravity, in studs
	local mass = seat.AssemblyMass
	local cf = seat.CFrame
	local up, fwd = cf.UpVector, cf.LookVector
	-- WEIGHT: the car falls with full Roblox gravity (Gw) - heavy, planted, no moon jumps.
	-- The springs hold that real weight; the tyres grip as if gravity were real 1 g (G),
	-- so cornering / braking / acceleration stay GTA IV's (gripScale = G / Gw).
	local Gw = workspace.Gravity
	local gripScale = G / Gw
	local vel = seat.AssemblyLinearVelocity
	local fwdSpeed = vel:Dot(fwd)
	local speed = vel.Magnitude
	-- IV cars run ~20% past their handling.dat velocity (Infernus 160 -> ~192 km/h)
	local maxV = math.max(h.maxVel, 10) * M.TopSpeedScale / 3.6 * S

	-- steering: GTA IV turns in slowly, centres quicker, and locks less at speed
	-- the faster you go, the less the wheels turn (IV is heavy at speed):
	-- 20 km/h ~84% of full lock, 50 km/h 50%, 100 km/h ~28%, 130 km/h ~21% (~7 deg).
	-- (Measured on a test drive: 15 deg at 131 km/h sat right on the tyres' grip peak,
	-- the front bit instantly and swung the back out.)
	local kmhNow = math.abs(fwdSpeed) / S * 3.6
	local lockRad = math.rad(h.steeringLock) / (1 + (kmhNow / 50) ^ 1.4)
	-- GTA IV on PC keyboard: A/D are on/off, so the wheel is ramped - about 0.5 s from
	-- straight to full lock, about 0.3 s back to centre when you let go, and flicking
	-- A -> D swings through centre at the faster return rate before winding up again
	local target = math.clamp(input.steer or 0, -1, 1) * lockRad
	-- the ramp is relative to the lock you have NOW: at speed a tap winds on just as
	-- gradually (0.5 s to the reduced lock) instead of snapping to it
	local liveLock = math.max(lockRad, math.rad(2))
	local returning = math.abs(target) < math.abs(st.steer) or (target * st.steer < 0)
	local rate = liveLock / (if returning then 0.3 else 0.5) * dt
	st.steer += math.clamp(target - st.steer, -rate, rate)

	-- throttle / brake / reverse (S brakes while rolling forward, then reverses)
	local thr = math.clamp(input.throttle or 0, -1, 1)
	local drive, brake = 0, 0
	if thr > 0 then
		if fwdSpeed < -1.5 then brake = thr else drive = thr end
	elseif thr < 0 then
		if fwdSpeed > 1.5 then brake = -thr else drive = thr end
	end
	-- automatic gearbox: higher gears pull less
	local gears = math.max(1, math.floor(h.gears))
	local frac = math.clamp(math.abs(fwdSpeed) / maxV, 0, 1.2)
	local gear = math.clamp(math.floor(frac * gears) + 1, 1, gears)
	st.gear = if fwdSpeed < -1 and drive < 0 then -1 else gear
	local gearMult = 1.25 - 0.5 * (gear - 1) / math.max(1, gears - 1)
	st.rpm = math.clamp((frac * gears) % 1 * 0.8 + 0.2, 0, 1)
	local accel
	-- GTA IV performance: launch acceleration (in g) = 4.25 x driveForce^1.5. Simulated:
	--   Infernus 0.25 -> 0-100 km/h ~4.7 s, top ~187 km/h;  Sabre GT -> ~6.3 s, ~168;
	--   Admiral 0.17 -> ~9 s, ~161;  Bus 0.12 -> ~15 s, ~157;  Mule -> ~23 s, ~111.
	-- Power holds until near top speed, then runs out (no hard wall)
	local launch = 4.25 * math.max(h.driveForce, 0) ^ 1.5 * M.AccelScale * (M.AccelByLine[h.name] or 1)
	if drive >= 0 then
		local taper = math.clamp(1 - frac ^ 4, 0, 1)
		accel = launch * G * gearMult * taper
	else
		local revMax = maxV * 0.28
		accel = launch * G * 0.9 * math.clamp((revMax + fwdSpeed) / (revMax * 0.15), 0, 1)
	end
	local driveTotal = mass * accel * drive
	local brakeTotal = mass * h.brakeForce * 3.6 * G * brake

	local nW = #st.wheels
	local upper, lower = h.suspUpper * S, h.suspLower * S
	local travel = math.max(upper - lower, 0.1)
	local contacts = 0
	local dbgN, dbgLat, dbgComp = 0, Vector3.zero, {}
	for _, w in st.wheels do
		-- RideHeight lifts the body off the road (measured 0.29 studs clearance before:
		-- the body scraped in every corner); the wheels then sit on the road, not in it
		local attach = cf:PointToWorldSpace(w.offset) + up * (h.suspRaise * S - M.RideHeight)
		local origin = attach + up * upper
		local rayLen = travel + w.radius
		local hit = workspace:Raycast(origin, -up * rayLen, st.params)
		if not hit then
			w.contact = false
			w.skid = 0
			w.lastComp = 0
			w.spin = w.spin * 0.99
			continue
		end
		contacts += 1
		w.contact = true
		local dist = (hit.Position - origin).Magnitude
		local comp = math.clamp((rayLen - dist) / travel, 0, 1.6)
		-- where the wheel centre sits now, relative to where it was built (for the visual)
		w.drop = upper - (dist - w.radius) + h.suspRaise * S - M.RideHeight
		-- spring: at rest a wheel sits about half way through its travel (suspForce 2)
		local share = mass * Gw / nW
		local bias = (if w.front then h.suspBiasFront else 1 - h.suspBiasFront) * 2
		local k = share / 0.5 * (h.suspForce / 2) * bias
		local compVel = ((comp - (w.lastComp or comp)) * travel) / dt
		w.lastComp = comp
		local kPerStud = k / travel
		local crit = 2 * math.sqrt(kPerStud * (mass / nW))
		local dampValue = if compVel > 0 then h.suspCompDamp else h.suspReboundDamp
		-- the damper's kick is limited: a ray jumping onto a kerb edge reads a huge
		-- compression speed in one frame, which used to fire the car into the air
		local damper = math.clamp(compVel * crit * math.clamp(dampValue * 0.3, 0.05, 2.5), -share * 1.5, share * 1.5)
		local N = math.max(0, comp * k + damper)
		if comp >= 1 then
			N += (comp - 1) * k * 3 -- bump stop
		end
		N = math.min(N, share * 3.5) -- never more than 3.5x this wheel's share of the weight
		local Nspring = N
		N = N * gripScale -- tyre load at real-gravity scale (see WEIGHT above)

		-- tyre
		local n = hit.Normal
		local steerA = if w.front then st.steer else 0
		local wf = CFrame.fromAxisAngle(up, -steerA) * fwd
		wf = (wf - n * wf:Dot(n))
		wf = if wf.Magnitude > 1e-3 then wf.Unit else fwd
		local wr = wf:Cross(n)
		local pv = seat:GetVelocityAtPosition(hit.Position)
		local vf, vr = pv:Dot(wf), pv:Dot(wr)
		local tBias = (if w.front then h.tractionBiasFront else 1 - h.tractionBiasFront) * 2
		local muMax, muMin = h.tractionMax * tBias, h.tractionMin * tBias
		-- parked (no driver): all four wheels locked so the car doesn't roll away
		local handbrake = (input.handbrake == true and not w.front) or input.parked == true
		-- lateral: grip builds with slip angle to the peak, then falls to the sliding grip
		local slip = math.atan2(math.abs(vr), math.max(math.abs(vf), 3))
		local peak = math.rad(math.max(h.tractionLateral, 2))
		local mu = if slip <= peak then muMax * (slip / peak)
			else muMax + (muMin - muMax) * math.clamp((slip - peak) / (peak * 1.5), 0, 1)
		local wheelMass = mass / nW
		local fLat = -sign(vr) * math.min(mu * N, math.abs(vr) * wheelMass / dt)
		local planarSpeed = math.sqrt(vf * vf + vr * vr)
		if handbrake and planarSpeed > 0.5 then
			-- GTA IV handbrake: the rear wheels LOCK. A locked tyre slides on its sliding
			-- grip (tractionMin) against the direction it's actually moving - so it still
			-- holds the car sideways, the back steps out and the drift settles instead of
			-- spinning. Thb (handbrakeForce) = how much grip the locked tyre loses.
			-- (0.35 was too grippy: the tyres killed the sideways slide in a fraction of a
			-- second, so the car just turned. IV's handbrake breaks the rear properly loose.)
			local muLock = if input.parked then muMin else muMin * (1 - 0.75 * math.clamp(h.handbrakeForce, 0, 1))
			local f = muLock * N
			local fl = -vf / planarSpeed * f
			local fr = -vr / planarSpeed * f
			-- never more than it takes to stop that wheel's share this frame
			fl = sign(fl) * math.min(math.abs(fl), math.abs(vf) * wheelMass / dt)
			fr = sign(fr) * math.min(math.abs(fr), math.abs(vr) * wheelMass / dt)
			w.slipping = true
			w.skid = planarSpeed
			w.contactPos = hit.Position
			w.spin = 0
			local at = hit.Position - up * M.BodyRoll -- low virtual point: the body leans out in corners and dives under braking
			dbgN += N; dbgLat += wf * fl + wr * fr; table.insert(dbgComp, math.floor(comp * 100) / 100)
			push(st, (up * N + wf * fl + wr * fr) * dt, at, up)
			continue
		end
		-- longitudinal: engine (by drive bias), brakes (by brake bias), rolling
		local driveShare = if w.front then h.driveBiasFront / st.fronts else (1 - h.driveBiasFront) / st.rears
		local fLong = driveTotal * driveShare
		local brakeShare = if w.front then h.brakeBiasFront / st.fronts else (1 - h.brakeBiasFront) / st.rears
		local fBrake = brakeTotal * brakeShare
		if drive == 0 and brake == 0 then
			fBrake += mass * G * 0.07 / nW -- engine braking + rolling: off the gas an IV car slows, it doesn't coast forever
		end
		local cancel = math.abs(vf) * wheelMass / dt
		fLong += -sign(vf) * math.min(fBrake, cancel)
		-- friction circle: more than the tyre can give = wheelspin / lockup / slide
		-- cornering grip comes first, the engine / brakes get what's left: too much throttle
		-- spins the wheels up instead of letting the back end go. (Scaling both equally,
		-- measured: 6 deg of steering at 140 km/h on full throttle slid the car to 44 deg.)
		local gripLimit = math.max(muMax, 0.1) * N
		w.slipping = false
		if math.abs(fLat) > gripLimit then
			fLat = sign(fLat) * gripLimit
			w.slipping = true
		end
		local longRoom = math.sqrt(math.max(0, gripLimit * gripLimit - fLat * fLat))
		if math.abs(fLong) > longRoom then
			fLong = sign(fLong) * longRoom
			w.slipping = true
		end
		w.spin = vf / w.radius + (if w.slipping and drive ~= 0 and fLong * drive > 0 then drive * 25 else 0)
		-- skid marks / smoke (drawn by the driver's client): sliding sideways past the
		-- peak, or a wheel spinning / locking
		w.contactPos = hit.Position
		w.skid = if slip > peak * 1.3 and math.abs(vr) > 6 then math.abs(vr)
			elseif w.slipping then math.abs(vf) * 0.5 else 0
		-- forces act a little above the contact patch (GTA IV's body roll, without tipping every corner)
		local at = hit.Position - up * M.BodyRoll -- low virtual point: the body leans out in corners and dives under braking
		dbgN += N; dbgLat += wf * fLong + wr * fLat; table.insert(dbgComp, math.floor(comp * 100) / 100)
		push(st, (up * Nspring + wf * fLong + wr * fLat) * dt, at, up)
	end

	-- live numbers for tuning (read with require(GTAVehicle).debug on the driver's client)
	M.debug = { nOverWeight = dbgN / (mass * G), tyreG = dbgLat.Magnitude / (mass * G), comp = dbgComp,
		anti = if st.anti then st.anti.Force.Y else -1, mass = mass, steerDeg = math.deg(st.steer), contacts = contacts }
	if os.clock() - (st.dbgAt or 0) > 0.1 then
		st.dbgAt = os.clock()
		seat:SetAttribute("GTADebug", ("N/W=%.2f tyreG=%.2f steer=%.1f comp=%s anti=%.0f"):format(M.debug.nOverWeight, M.debug.tyreG, M.debug.steerDeg, table.concat(dbgComp, ","), M.debug.anti))
	end

	-- aerodynamic drag: grows with speed squared
	if speed > 1 then
		-- IV drag runs ~3 (slippery) .. 9 (bricks), 6 typical; small next to the engine,
		-- it mostly shapes how fast speed bleeds off when you lift
		local k = 0.04 * G / (maxV * maxV) * (h.dragMult / 6)
		seat:ApplyImpulse(-vel.Unit * k * speed * speed * mass * dt)
	end
	-- a touch of air control and self-righting when all wheels are off the ground (IV lets you rock the car)
	if contacts == 0 then
		local yaw = (input.steer or 0) * mass * 2
		seat:ApplyAngularImpulse(up * -yaw * dt)
	end

	-- wheels on screen
	-- ghost chassis: pose each visual wheel - suspension travel, steering, rolling
	for _, w in st.wheels do
		if w.motor and w.baseC0 then
			if not w.contact then
				w.drop = math.max(w.drop - 8 * dt, lower + h.suspRaise * S - M.RideHeight) -- droops when airborne
			end
			w.angle = (w.angle + w.spin * dt) % (math.pi * 2)
			local base = w.baseC0
			local steerRot = if w.front then CFrame.fromAxisAngle(Vector3.yAxis, -st.steer * st.steerDirection) else CFrame.identity
			w.motor.C0 = CFrame.new(base.Position + Vector3.new(0, w.drop, 0)) * steerRot * base.Rotation
				* CFrame.Angles(0, w.angle * w.axleSign, 0)
		elseif w.hinge then
			w.hinge.MotorMaxTorque = 200
			w.hinge.AngularVelocity = w.spin * (w.hinge:GetAttribute("Sign") or 1)
		end
	end
	for _, hinge in st.steers do
		hinge.TargetAngle = -math.deg(st.steer) * st.steerDirection
	end
	return { speed = fwdSpeed, kmh = math.abs(fwdSpeed) / S * 3.6, gear = st.gear, rpm = st.rpm, contacts = contacts }
end

return M
