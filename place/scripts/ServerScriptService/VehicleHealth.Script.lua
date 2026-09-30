-- VehicleHealth (v215)
-- While a player sits in a car, the CAR takes the hits instead of the player:
--   * the car has 20x the occupant's max health (2,000 for a normal player)
--   * police bullets and player guns hit the car (ServerStorage.VehicleDamage,
--     called by PoliceSystem.Weapons and WeaponsServer), and any other damage a
--     seated player takes (crashes, explosions...) is moved onto the car
--   * at zero the car catches fire, burns for a few seconds and explodes
-- Car health is on the car model: VehicleHealth / VehicleMaxHealth attributes
-- (the client draws a yellow bar next to the green health bar).

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local HEALTH_MULTIPLIER = 20
local BURN_TIME = 4.5
local WRECK_TIME = 25

-- the car a seated humanoid is in: the top model under Workspace that holds the seat
local function carOf(hum: Humanoid): Model?
	local seat = hum.SeatPart
	if not seat or not (seat:IsA("VehicleSeat") or seat:IsA("Seat")) then
		return nil
	end
	local model: Instance? = seat:FindFirstAncestorWhichIsA("Model")
	while model and model.Parent and model.Parent ~= Workspace and model.Parent:IsA("Model") do
		model = model.Parent
	end
	if not model or not model:IsA("Model") then
		return nil
	end
	-- a car has a driver's seat somewhere
	if not model:FindFirstChildWhichIsA("VehicleSeat", true) then
		return nil
	end
	-- police / resident traffic NPC cars are not player cars
	if model:GetAttribute("TrafficActive") == true then
		return nil
	end
	return model
end

local function ensureHealth(car: Model, hum: Humanoid)
	if car:GetAttribute("VehicleMaxHealth") == nil then
		local max = math.max(100, hum.MaxHealth) * HEALTH_MULTIPLIER
		car:SetAttribute("VehicleMaxHealth", max)
		car:SetAttribute("VehicleHealth", max)
	end
end

local wrecked: { [Model]: boolean } = {}

local function occupants(car: Model): { Humanoid }
	local out = {}
	for _, seat in car:GetDescendants() do
		if (seat:IsA("VehicleSeat") or seat:IsA("Seat")) and seat.Occupant then
			table.insert(out, seat.Occupant)
		end
	end
	return out
end

local function wreck(car: Model)
	if wrecked[car] then
		return
	end
	wrecked[car] = true
	car:SetAttribute("VehicleHealth", 0)
	car:SetAttribute("VehicleDestroyed", true)
	local seat = car:FindFirstChildWhichIsA("VehicleSeat", true)
	if seat then
		seat:SetAttribute("VehicleDestroyed", true)
	end
	local core: BasePart? = car.PrimaryPart or seat
	if not core then
		for _, d in car:GetDescendants() do
			if d:IsA("BasePart") then
				core = d
				break
			end
		end
	end
	if not core then
		return
	end
	-- the engine catches fire
	local fire = Instance.new("Fire")
	fire.Size = 10
	fire.Heat = 14
	fire.Parent = core
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(40, 40, 40)
	smoke.Opacity = 0.6
	smoke.Size = 12
	smoke.RiseVelocity = 8
	smoke.Parent = core
	for _, hum in occupants(car) do
		local plr = Players:GetPlayerFromCharacter(hum.Parent)
		if plr then
			local r = game:GetService("ReplicatedStorage"):FindFirstChild("PrisonSociety")
			local notice = r and r:FindFirstChild("Notice")
			if notice then
				notice:FireClient(plr, "YOUR CAR IS ON FIRE - GET OUT!")
			end
		end
	end
	task.delay(BURN_TIME, function()
		if not car.Parent then
			return
		end
		local blast = Instance.new("Explosion")
		blast.Position = core.Position
		blast.BlastRadius = 14
		blast.BlastPressure = 250000
		blast.DestroyJointRadiusPercent = 1
		blast.Parent = Workspace
		for _, d in car:GetDescendants() do
			if d:IsA("BasePart") then
				d.Color = d.Color:Lerp(Color3.fromRGB(25, 22, 20), 0.85)
				d.Material = Enum.Material.CorrodedMetal
			elseif d:IsA("VehicleSeat") then
				d.Disabled = true
			end
		end
		if seat then
			seat.Disabled = true
			seat.MaxSpeed = 0
		end
		Debris:AddItem(car, WRECK_TIME)
	end)
end

-- apply `amount` damage to the car this humanoid sits in; returns what's left for the humanoid
local function absorb(hum: Humanoid, amount: number): number
	if amount <= 0 then
		return amount
	end
	local car = carOf(hum)
	if not car or wrecked[car] then
		return amount
	end
	ensureHealth(car, hum)
	local health = tonumber(car:GetAttribute("VehicleHealth")) or 0
	health -= amount
	car:SetAttribute("VehicleHealth", math.max(0, health))
	if health <= 0 then
		wreck(car)
	end
	return 0
end

local fn = ServerStorage:FindFirstChild("VehicleDamage") or Instance.new("BindableFunction")
fn.Name = "VehicleDamage"
fn.OnInvoke = function(hum: any, amount: any): number
	if typeof(hum) ~= "Instance" or not hum:IsA("Humanoid") then
		return tonumber(amount) or 0
	end
	return absorb(hum, tonumber(amount) or 0)
end
fn.Parent = ServerStorage

-- anything else that hurts a seated player (crashes, explosions, other weapons)
-- is moved onto the car as long as the car is alive
local function watch(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then
		return
	end
	local last = hum.Health
	hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
		local car = carOf(hum)
		if car then
			ensureHealth(car, hum)
		end
		last = hum.Health
	end)
	hum.HealthChanged:Connect(function(health)
		if health < last and health > 0 then
			local car = carOf(hum)
			if car and not wrecked[car] then
				local lost = last - health
				absorb(hum, lost)
				hum.Health = last -- the car took it
				return
			end
		end
		last = health
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		watch(player, char)
	end)
	if player.Character then
		watch(player, player.Character)
	end
end)
for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(function(char)
		watch(player, char)
	end)
	if player.Character then
		task.spawn(watch, player, player.Character)
	end
end

print("[VehicleHealth] cars take the hits (x" .. HEALTH_MULTIPLIER .. " health), burn and explode at zero")
