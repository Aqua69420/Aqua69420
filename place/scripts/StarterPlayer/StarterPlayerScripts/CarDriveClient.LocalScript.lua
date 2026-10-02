-- Resident traffic visuals run independently of player vehicle controls.
-- The server retains collisions, routing and the authoritative pose.
task.spawn(function()
 local Collection=game:GetService("CollectionService")
 local Run=game:GetService("RunService")
 local tracked,active={},{}
 local function remove(car)
  local entry=tracked[car]
  if entry then entry.connection:Disconnect();tracked[car]=nil;active[car]=nil end
 end
 local function add(car)
  if tracked[car] or not car:IsA("Model") then return end
  local pose=car:GetAttribute("TrafficPose")
  local entry={goal=pose or car:GetPivot(),shown=pose or car:GetPivot()}
  entry.connection=car:GetAttributeChangedSignal("TrafficPose"):Connect(function()
   local nextPose=car:GetAttribute("TrafficPose")
   if typeof(nextPose)=="CFrame" then entry.goal=nextPose end
  end)
  tracked[car]=entry
 end
 Collection:GetInstanceAddedSignal("SmoothResidentTraffic"):Connect(add)
 Collection:GetInstanceRemovedSignal("SmoothResidentTraffic"):Connect(remove)
 for _,car in Collection:GetTagged("SmoothResidentTraffic") do add(car) end
 local refresh=0
 Run:BindToRenderStep("ResidentTrafficVisuals",Enum.RenderPriority.Camera.Value+1,function(dt)
  local camera=workspace.CurrentCamera
  if not camera then return end
  refresh-=dt
  if refresh<=0 then
   refresh=0.5
   local candidates={}
   for car,entry in tracked do
    if car:IsDescendantOf(workspace) and car:GetAttribute("TrafficActive")==true then
     local distance=(entry.goal.Position-camera.CFrame.Position).Magnitude
     if distance<500 then table.insert(candidates,{car=car,entry=entry,distance=distance}) end
    end
   end
   table.sort(candidates,function(a,b) return a.distance<b.distance end)
   local selected={}
   for i=1,math.min(40,#candidates) do
    local item=candidates[i];selected[item.car]=item.entry
    if not active[item.car] then item.entry.shown=item.entry.goal;item.entry.resting=false end
   end
   for car,entry in active do if not selected[car] and car.Parent then car:PivotTo(entry.goal) end end
   active=selected
  end
  local alpha=1-math.exp(-math.min(dt,0.1)/0.07)
  for car,entry in active do
   if car.Parent and car:GetAttribute("TrafficActive")==true then
    if entry.resting and entry.restGoal==entry.goal then continue end
    if (entry.goal.Position-entry.shown.Position).Magnitude>35 then entry.shown=entry.goal
    else entry.shown=entry.shown:Lerp(entry.goal,alpha) end
    entry.resting=(entry.goal.Position-entry.shown.Position).Magnitude<0.005 and entry.goal.LookVector:Dot(entry.shown.LookVector)>0.999999
    if entry.resting then entry.shown=entry.goal;entry.restGoal=entry.goal end
    car:PivotTo(entry.shown)
   end
  end
 end)
end)
-- CarDriveClient
-- Runs the controls of the car you're driving on your own machine, so steering
-- and throttle react instantly (the server hands you physics ownership of the
-- car when you sit in the driver's seat). Tuning values come from attributes
-- that ServerScriptService.CarServer puts on the VehicleSeat.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local function collect(car)
	local spins, steers = {}, {}
	for _, obj in ipairs(car:GetDescendants()) do
		if obj:IsA("HingeConstraint") then
			if obj.Name == "Spin" and obj:GetAttribute("Sign") then
				table.insert(spins, obj)
			elseif obj.Name == "SteerHinge" then
				table.insert(steers, obj)
			end
		end
	end
	return spins, steers
end

---------------------------------------------------------------------------
-- GTA IV handling: cars with a GTAHandling line run ReplicatedStorage.GTAVehicle on
-- this machine. W/S throttle, brake and reverse, A/D steer, SPACE = handbrake (it
-- doesn't jump you out of the car - F gets you out).
---------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local handbrakeDown = false

---------------------------------------------------------------------------
-- Skid marks (restored): dark strips where a tyre locks (handbrake) or slides.
-- Drawn here at once, and sent through ReplicatedStorage.SkidMarks so everyone
-- else sees them too (SkidMarksRelay). They fade after a while; at most MAX_SKIDS.
---------------------------------------------------------------------------
local Debris = game:GetService("Debris")
local MAX_SKIDS, SKID_LIFE = 500, 30
local skidFolder = workspace:FindFirstChild("SkidMarks") or Instance.new("Folder")
skidFolder.Name = "SkidMarks"
skidFolder.Parent = workspace
local skidList = {}
local function drawSkid(a, b, n, width)
	local len = (b - a).Magnitude
	if len < 0.05 or len > 12 then return end
	local p = Instance.new("Part")
	p.Name = "Skid"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromRGB(22, 22, 22)
	p.Transparency = 0.3
	p.Size = Vector3.new(width, 0.04, len + 0.15)
	p.CFrame = CFrame.lookAt((a + b) / 2 + n * 0.03, b + n * 0.03, n)
	p.Parent = skidFolder
	table.insert(skidList, p)
	while #skidList > MAX_SKIDS do
		local old = table.remove(skidList, 1)
		if old then old:Destroy() end
	end
	Debris:AddItem(p, SKID_LIFE)
end
local skidRemote = ReplicatedStorage:WaitForChild("SkidMarks", 10)
if skidRemote then
	skidRemote.OnClientEvent:Connect(function(segs)
		if type(segs) ~= "table" then return end
		for _, s in segs do
			if typeof(s[1]) == "Vector3" and typeof(s[2]) == "Vector3" and typeof(s[3]) == "Vector3" then
				drawSkid(s[1], s[2], s[3], tonumber(s[4]) or 0.8)
			end
		end
	end)
end
local pendingSkids, lastSkidSend = {}, 0
-- after each physics step: extend the mark under every tyre that is locked / sliding
local function laySkids(st, speed)
	for _, w in st.wheels do
		local sliding = w.contact and w.hitPos and speed > 8
			and (w.locked or (w.slipping and (w.slipSpeed or 0) > 6) or (w.slipSpeed or 0) > 14)
		if sliding then
			local pos, n = w.hitPos, w.hitNormal or Vector3.yAxis
			if w.skidLast and (pos - w.skidLast).Magnitude >= 1.2 then
				local width = math.clamp(math.min(w.part.Size.X, w.part.Size.Y, w.part.Size.Z), 0.5, 1.4)
				drawSkid(w.skidLast, pos, n, width)
				table.insert(pendingSkids, { w.skidLast, pos, n, width })
				w.skidLast = pos
			elseif not w.skidLast then
				w.skidLast = pos
			end
		else
			w.skidLast = nil
		end
	end
	if #pendingSkids > 0 and os.clock() - lastSkidSend > 0.25 and skidRemote then
		lastSkidSend = os.clock()
		skidRemote:FireServer(pendingSkids)
		pendingSkids = {}
	end
end

local function driveGTA(humanoid, seat, car)
	local okM, Vehicle = pcall(require, ReplicatedStorage:WaitForChild("GTAVehicle", 10))
	local okD, data = pcall(require, ReplicatedStorage:WaitForChild("GTAHandlingData", 10))
	if not okM or not okD then
		warn("[GTAHandling] client couldn't load the handling modules")
		return
	end
	Vehicle.configure(data)
	local lines = Vehicle.parse(tostring(data.Text or ""), data.Columns)
	local h = lines[seat:GetAttribute("GTAHandling")]
	local st = h and Vehicle.new(car, seat, h, data.MetersToStuds or 2.8)
	if not st then
		return
	end
	Vehicle.ignore(st, { player.Character })
	ContextActionService:BindActionAtPriority("GTAHandbrake", function(_, state)
		handbrakeDown = state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change
		return Enum.ContextActionResult.Sink -- Space never jumps you out
	end, true, 3000, Enum.KeyCode.Space, Enum.KeyCode.ButtonX)
	pcall(function()
		ContextActionService:SetTitle("GTAHandbrake", "Handbrake")
	end)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	local drunkSteer = 0
	local connection
	-- PreSimulation: its dt is the time physics will actually simulate (a hitchy frame's
	-- Heartbeat dt is longer than that - pushing for it overshot gravity and hopped the car)
	connection = RunService.PreSimulation:Connect(function(dt)
		if humanoid.SeatPart ~= seat or not car.Parent then
			connection:Disconnect()
			ContextActionService:UnbindAction("GTAHandbrake")
			handbrakeDown = false
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			return
		end
		local throttle, steer = seat.ThrottleFloat, seat.SteerFloat
		if math.abs(throttle) < 0.05 then
			if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then throttle = 1
			elseif UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then throttle = -1 end
		end
		if math.abs(steer) < 0.05 then
			if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then steer = -1
			elseif UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then steer = 1 end
		end
		-- v252 impairment: lagging hands and drift
		local impaired = tonumber(player:GetAttribute("Impairment")) or 0
		if impaired > 0.1 then
			drunkSteer += (steer - drunkSteer) * (1 - math.clamp(impaired * 0.9, 0, 0.85))
			steer = math.clamp(drunkSteer + (math.sin(os.clock() * 0.7) * 0.6 + math.sin(os.clock() * 1.9) * 0.4) * impaired * 0.45, -1, 1)
		else
			drunkSteer = steer
		end
		if seat:GetAttribute("VehicleDestroyed") then
			throttle = 0
		end
		local res = Vehicle.step(st, dt, { throttle = throttle, steer = steer, handbrake = handbrakeDown })
		pcall(laySkids, st, seat.AssemblyLinearVelocity.Magnitude)
	end)
end

local function drive(humanoid, seat)
	local car = seat.Parent
	while car and car ~= workspace and not car:GetAttribute("CarName") do
		car = car.Parent
	end
	if car == workspace then
		car = nil
	end
	if not car or not seat:GetAttribute("TopSpeed") then
		return -- not one of the rebuilt cars
	end
	if seat:GetAttribute("GTAHandling") then
		driveGTA(humanoid, seat, car)
		return
	end

	local spins, steers = collect(car)
	local topSpeed = seat:GetAttribute("TopSpeed")
	local reverseSpeed = seat:GetAttribute("ReverseSpeed")
	local driveTorque = seat:GetAttribute("DriveTorque")
	local brakeTorque = seat:GetAttribute("BrakeTorque")
	local coastTorque = seat:GetAttribute("CoastTorque")
	local maxSteer = seat:GetAttribute("MaxSteerAngle")
	local minSteer = seat:GetAttribute("MinSteerAngle")
	local steerDirection = seat:GetAttribute("SteerDirection") or 1

	local drunkSteer = 0 -- v252: the steering you actually get when impaired
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if humanoid.SeatPart ~= seat or not car.Parent then
			connection:Disconnect()
			return
		end

		local throttle=seat.ThrottleFloat
		local steer=seat.SteerFloat
		-- Studio/legacy VehicleSeats occasionally fail to update ThrottleFloat/
		-- SteerFloat. Keyboard fallback keeps rebuilt cars driveable.
		if math.abs(throttle)<0.05 then
			if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then throttle=1
			elseif UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then throttle=-1 end
		end
		if math.abs(steer)<0.05 then
			if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then steer=-1
			elseif UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then steer=1 end
		end
		local velocity = seat.AssemblyLinearVelocity
		local forwardSpeed = velocity:Dot(seat.CFrame.LookVector)
		local speed = math.abs(forwardSpeed)

		-- v113: police spike strips set TireDamage (0..1) on the seat: lower top speed and a
		-- wobble in the steering until it wears off (server clears it after a while).
		local tire = tonumber(seat:GetAttribute("TireDamage")) or 0
		local liveTop = topSpeed * (1 - math.clamp(tire, 0, 0.9))
		if tire > 0 and speed > 4 then
			-- v215: shredded tyres fight you: a hard pull to one side, a violent
			-- shimmy, and slides that come and go
			local pull = tonumber(seat:GetAttribute("TirePull")) or 1
			local t = os.clock()
			local shimmy = math.sin(t * 9.1) * 0.35 + math.sin(t * 3.7) * 0.25
			local slide = if math.sin(t * 1.3) > 0.75 then pull * 0.5 else 0
			steer = math.clamp(steer + (pull * 0.3 + shimmy + slide) * tire, -1, 1)
			throttle *= 1 - 0.35 * tire -- the rims bite: sluggish acceleration
		end
		-- v252: impaired driving (Drugs sets Impairment 0..1 on the player): the
		-- steering lags behind your hands, the car drifts, and you brake late
		local impaired = tonumber(Players.LocalPlayer:GetAttribute("Impairment")) or 0
		if impaired > 0.1 then
			local t = os.clock()
			local lag = math.clamp(impaired * 0.9, 0, 0.85)
			drunkSteer = drunkSteer + (steer - drunkSteer) * (1 - lag)
			local drift = (math.sin(t * 0.7) * 0.6 + math.sin(t * 1.9) * 0.4) * impaired * 0.45
			steer = math.clamp(drunkSteer + drift, -1, 1)
			if throttle < 0 and forwardSpeed > 2 then
				throttle *= 1 - impaired * 0.6 -- brakes late and soft
			end
		else
			drunkSteer = steer
		end
		-- a burning / destroyed car doesn't drive
		if seat:GetAttribute("VehicleDestroyed") then
			throttle, liveTop = 0, 0
		end

		-- Steering: full lock when slow, tighter at speed.
		local fraction = math.clamp(speed / topSpeed, 0, 1)
		local maxAngle = maxSteer + (minSteer - maxSteer) * fraction
		for _, hinge in ipairs(steers) do
			hinge.TargetAngle = -steer * maxAngle * steerDirection
		end

		-- Throttle / brake / reverse.
		local target, torque
		if math.abs(throttle) < 0.05 then
			target, torque = 0, coastTorque
		elseif forwardSpeed * throttle < -1 then
			target, torque = 0, brakeTorque -- pressing against the way you're moving = brake
		elseif throttle > 0 then
			target, torque = throttle * liveTop, driveTorque
		else
			target, torque = throttle * reverseSpeed, driveTorque
		end
		for _, hinge in ipairs(spins) do
			hinge.AngularVelocity = target / hinge:GetAttribute("Radius") * hinge:GetAttribute("Sign")
			hinge.MotorMaxTorque = torque
		end
	end)
end

local function onCharacter(character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Seated:Connect(function(active,seatPart)
		if active and seatPart and seatPart:IsA("VehicleSeat") then drive(humanoid,seatPart) end
	end)
	task.defer(function()
		local seat=humanoid.SeatPart
		if seat and seat:IsA("VehicleSeat") then drive(humanoid,seat) end
	end)
end

if player.Character then
	task.spawn(onCharacter, player.Character)
end
player.CharacterAdded:Connect(onCharacter)

-- F: get in the nearest car (GTA style) / get out. The server walks you to the door.
UserInputService.InputBegan:Connect(function(input, processed)
	-- "processed" is also set when a ProximityPrompt grabs F, so only a focused text box blocks it
	if input.KeyCode ~= Enum.KeyCode.F or UserInputService:GetFocusedTextBox() then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root then
		return
	end
	local remote = ReplicatedStorage:FindFirstChild("CarEnterExit")
	if not remote then
		return
	end
	if hum.SeatPart then
		remote:FireServer(nil) -- out
		return
	end
	-- any car close by: your own, someone else's, or traffic (that's a carjacking)
	-- (a plain distance scan: a spatial query skipped seats with CanQuery off - player cars)
	local best, bestD = nil, 16
	for _, part in workspace:GetDescendants() do
		if part:IsA("VehicleSeat") and not part.Occupant then
			local d = (part.Position - root.Position).Magnitude
			if d < bestD then
				best, bestD = part, d
			end
		end
	end
	-- a traffic car's own (invisible) F carjack prompt handles those
	if best and not best:FindFirstChild("Carjack") then
		remote:FireServer(best)
	end
end)
