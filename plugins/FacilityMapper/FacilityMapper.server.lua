--!nocheck
-- Facility Mapper (Studio plugin)  v6
-- Maps the prison, Police HQ, City Jail, law offices and city markers in the
-- same format the game's navigation already reads (the format of the original
-- prison map):
--   <Facility>.<MapFolder>/
--     Zones/<Name>        Folder: ZoneType, Category, TopY, BottomY ... + ControlPoints (polygon)
--     DoorMarkers/<Name>  Folder: Description, DoorType, Access ... + Center (Part) + DoorObject (ObjectValue)
--     Routes/<Name>       Folder: RouteType, Bidirectional ... + ControlPoints (path)
--     Points/<Name>       Part:   PointType (phones, sniper posts, booking desks, news station ...)
--   Seats anywhere in the facility get a SeatRole attribute (JudgeSeat, JurorSeat3 ...)
--
-- Tools: Zone (click corners, Enter to finish), Door (click a door), Route (click
-- points, Enter), Point (click a spot), Seat (click a seat), Select (click to pick,
-- then Delete / Apply edits). Backspace removes the last corner, Esc cancels.
-- Pick building: click any part of a building to make it the active facility.
-- Door / Seat / Select show a cyan box around what the next click will use.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

if RunService:IsRunning() then
	return -- edit mode only
end

local MAPPER_VERSION = 2

---------------------------------------------------------------------------
-- definitions
---------------------------------------------------------------------------
local FACILITY_TYPES = { "Prison", "Courthouse", "PoliceHQ", "CityJail", "LawOffice", "Bank", "City" }
-- building names tried (in order) when no model has been picked yet
local DEFAULT_MODEL = {
	Prison = { "CorrectionalFacility" }, Courthouse = { "Courthouse" }, PoliceHQ = { "PoliceHQ", "PoliceStation" },
	CityJail = { "CityJail" }, Bank = { "Bank" },
}

-- zone types: room = needs a door and is registered as a room/cell category;
-- navIgnore = not a walkable nav area (sniper zones and the like)
local ZONE_INFO = {
	Hallway = {}, Lobby = {}, Walkway = {}, Room = {}, Stairs = {}, Office = {}, Outside = {},
	Yard = {}, DayRoom = {}, BookingArea = {}, SallyPort = {}, ReleaseArea = {}, Garage = {},
	Evidence = {}, LockerRoom = {}, ConferenceRoom = {}, BankLobby = {}, Impound = {},
	-- street gang turf (city)
	TerritoryEK = {}, TerritoryIS = {}, TerritoryDS = {}, TerritoryTL = {},
	-- bank safe deposit vault
	DepositVault = { room = true }, TransferHolding = { room = true },
	-- courts
	JuryRoom = { room = true }, JudgeChambers = { room = true }, SecurityCheckpoint = {}, ClerkOffice = {},
	CourtLobby = {}, PressArea = {},
	-- rooms (need a mapped door)
	Interrogation = { room = true }, LegalVisit = { room = true }, Courtroom = { room = true },
	MunicipalCourt = { room = true }, CourtHolding = { room = true }, HoldingCell = { room = true },
	JailCell = { room = true }, ProtectiveCustody = { room = true }, GuardTower = { room = true },
	IntakeCell = { room = true }, BookingCell = { room = true }, OverflowHolding = { room = true },
	LongTermHolding = { room = true }, LowSecurity = { room = true }, MediumSecurity = { room = true },
	HighSecurity = { room = true }, MaximumSecurity = { room = true }, Supermax = { room = true },
	Solitary = { room = true }, DeathRow = { room = true }, ExecutionRoom = { room = true },
	ContactVisit = { room = true }, VisitPrisoner = { room = true }, VisitVisitor = { room = true },
	-- special, not walkable navigation
	KillZone = { navIgnore = true }, Perimeter = { navIgnore = true },
}
local ZONE_TYPES = {
	Prison = {
		"Interrogation", "Courtroom", "CourtHolding", "LegalVisit", "GuardTower", "KillZone", "Perimeter",
		"ProtectiveCustody", "JuryRoom", "JudgeChambers", "Hallway", "Stairs", "Room", "Walkway", "Yard",
		"IntakeCell", "BookingCell", "OverflowHolding", "LongTermHolding", "LowSecurity", "MediumSecurity",
		"HighSecurity", "MaximumSecurity", "Supermax", "Solitary", "DeathRow", "ExecutionRoom",
		"ContactVisit", "VisitPrisoner", "VisitVisitor",
	},
	Courthouse = {
		"Courtroom", "CourtHolding", "JuryRoom", "JudgeChambers", "SecurityCheckpoint", "CourtLobby", "ClerkOffice",
		"LegalVisit", "SallyPort", "PressArea", "Hallway", "Stairs", "Office", "Room",
	},
	PoliceHQ = {
		"SallyPort", "BookingArea", "HoldingCell", "Interrogation", "LegalVisit", "Lobby", "MunicipalCourt",
		"CourtHolding", "Hallway", "Stairs", "Office", "Evidence", "LockerRoom", "Garage", "Room",
	},
	CityJail = {
		"SallyPort", "BookingArea", "JailCell", "HoldingCell", "TransferHolding", "DayRoom", "Yard", "LegalVisit", "ReleaseArea",
		"Lobby", "Hallway", "Stairs", "Office", "Room",
	},
	LawOffice = { "Lobby", "Office", "ConferenceRoom", "Hallway", "Stairs", "Room" },
	Bank = { "DepositVault", "BankLobby", "Hallway", "Office", "Room" },
	City = { "TerritoryEK", "TerritoryIS", "TerritoryDS", "TerritoryTL", "Impound", "Outside", "Room" },
}
local POINT_TYPES = {
	Prison = { "BusBay", "PrisonPhone", "SniperPost", "Spotlight", "BailiffSpot", "CourtCam", "OfficerPost", "TurnInPoint", "DrugTestStation", "CommissaryWindow" },
	Courthouse = { "BailiffSpot", "CourtCam", "ClerkWindow", "MetalDetector", "VehicleDropoff", "TurnInPoint", "CourthouseSteps", "PressPodium", "OfficerPost" },
	PoliceHQ = { "BookingDesk", "TurnInPoint", "VehicleDropoff", "FrontDesk", "BailiffSpot", "CourtCam", "DetectivePost", "OfficerPost", "HoldingPhone", "MDTTerminal", "EvidenceLocker", "MugshotSpot", "PressPodium", "PoliceSpawn" },
	CityJail = { "BusDeparture", "BookingDesk", "VehicleDropoff", "ReleasePoint", "JailPhone", "OfficerPost", "TurnInPoint" },
	LawOffice = { "Reception", "WaitingArea" },
	Bank = { "DepositTerminal", "BoxWall", "TellerDesk", "BankerDesk" },
	City = {
		"NewsStation", "CourthouseSteps", "BailBondsOffice", "BullionDealer", "PawnShop", "UndergroundMetalBuyer",
		"PlateMakerSpot", "ChopShop", "ShadyDealer", "FixerSpot", "PrivateVaultSpot", "StashSpot", "Safehouse",
		"Bar", "LiquorStore", "DrugCorner", "Hospital", "ImpoundLot", "DealershipDesk",
	},
}
-- points that face a direction (placed facing where the camera looks)
local AIMED_POINT = { SniperPost = true, Spotlight = true, CourtCam = true, PressPodium = true }
local SEAT_ROLES = {
	"JudgeSeat", "DefendantSeat", "DefenseSeat", "ProsecutorSeat", "WitnessSeat", "JurorSeat", "GallerySeat",
	"SuspectSeat", "DetectiveSeat", "InmateVisitSeat", "LawyerVisitSeat", "LawyerSeat", "ClientSeat", "ReceptionSeat",
	"ConferenceSeat", "BarSeat",
}
local DOOR_TYPES = { "Normal", "CellDoor", "Secure", "Gate", "Exit", "SallyPort", "Release" }
local ACCESS = { "Staff", "Police", "Public", "Secure" }
local SECURITY = { "General", "Staff", "Secure", "Public" }
local ROUTE_TYPES = { "Escort", "Stairs", "BusUnloadLine", "Patrol", "Vehicle", "Walk" }

-- what each facility needs before the matching game features can use it
local CHECKLIST = {
	Prison = {
		{ kind = "point", type = "BusBay", min = 1 },
		{ kind = "zone", type = "Interrogation", min = 1 },
		{ kind = "zone", type = "Courtroom", min = 1 },
		{ kind = "seat", type = "JudgeSeat", min = 1 }, { kind = "seat", type = "DefendantSeat", min = 1 },
		{ kind = "seat", type = "DefenseSeat", min = 1 }, { kind = "seat", type = "ProsecutorSeat", min = 1 },
		{ kind = "seat", type = "WitnessSeat", min = 1 }, { kind = "seat", type = "JurorSeat", min = 12 },
		{ kind = "seat", type = "GallerySeat", min = 1 }, { kind = "point", type = "BailiffSpot", min = 1 },
		{ kind = "zone", type = "JuryRoom", min = 1 }, { kind = "zone", type = "CourtHolding", min = 0, optional = true },
		{ kind = "zone", type = "JudgeChambers", min = 0, optional = true },
		{ kind = "zone", type = "GuardTower", min = 1 }, { kind = "point", type = "SniperPost", min = 1 },
		{ kind = "point", type = "Spotlight", min = 1 }, { kind = "zone", type = "KillZone", min = 1 },
		{ kind = "zone", type = "Perimeter", min = 1 }, { kind = "point", type = "PrisonPhone", min = 2 },
		{ kind = "zone", type = "ProtectiveCustody", min = 0, optional = true },
		{ kind = "point", type = "CourtCam", min = 0, optional = true },
	},
	Courthouse = {
		{ kind = "zone", type = "Courtroom", min = 1 }, { kind = "zone", type = "CourtHolding", min = 1 },
		{ kind = "zone", type = "JuryRoom", min = 1 }, { kind = "zone", type = "JudgeChambers", min = 1 },
		{ kind = "zone", type = "SecurityCheckpoint", min = 1 }, { kind = "zone", type = "CourtLobby", min = 1 },
		{ kind = "zone", type = "SallyPort", min = 1 },
		{ kind = "seat", type = "JudgeSeat", min = 1 }, { kind = "seat", type = "DefendantSeat", min = 1 },
		{ kind = "seat", type = "DefenseSeat", min = 1 }, { kind = "seat", type = "ProsecutorSeat", min = 1 },
		{ kind = "seat", type = "WitnessSeat", min = 1 }, { kind = "seat", type = "JurorSeat", min = 12 },
		{ kind = "seat", type = "GallerySeat", min = 1 },
		{ kind = "point", type = "BailiffSpot", min = 1 }, { kind = "point", type = "ClerkWindow", min = 1 },
		{ kind = "point", type = "MetalDetector", min = 1 }, { kind = "point", type = "VehicleDropoff", min = 1 },
		{ kind = "point", type = "CourthouseSteps", min = 1 },
		{ kind = "point", type = "CourtCam", min = 0, optional = true },
		{ kind = "zone", type = "LegalVisit", min = 0, optional = true },
		{ kind = "zone", type = "PressArea", min = 0, optional = true },
	},
	PoliceHQ = {
		{ kind = "zone", type = "SallyPort", min = 1 }, { kind = "zone", type = "BookingArea", min = 1 },
		{ kind = "zone", type = "HoldingCell", min = 1 }, { kind = "zone", type = "Interrogation", min = 1 },
		{ kind = "zone", type = "LegalVisit", min = 1 }, { kind = "zone", type = "Lobby", min = 1 },
		{ kind = "zone", type = "MunicipalCourt", min = 0, optional = true },
		{ kind = "point", type = "BookingDesk", min = 1 }, { kind = "point", type = "TurnInPoint", min = 1 },
		{ kind = "point", type = "VehicleDropoff", min = 1 },
		{ kind = "point", type = "BailiffSpot", min = 0, optional = true },
		{ kind = "point", type = "CourtCam", min = 0, optional = true },
	},
	CityJail = {
		{ kind = "zone", type = "SallyPort", min = 1 }, { kind = "zone", type = "BookingArea", min = 1 },
		{ kind = "zone", type = "JailCell", min = 4 }, { kind = "zone", type = "DayRoom", min = 1 },
		{ kind = "zone", type = "ReleaseArea", min = 1 },
		{ kind = "point", type = "BookingDesk", min = 1 }, { kind = "point", type = "VehicleDropoff", min = 1 },
		{ kind = "point", type = "ReleasePoint", min = 1 },
		{ kind = "point", type = "BusDeparture", min = 1 },
		{ kind = "zone", type = "TransferHolding", min = 1 },
		{ kind = "zone", type = "Yard", min = 0, optional = true },
		{ kind = "zone", type = "LegalVisit", min = 0, optional = true },
		{ kind = "point", type = "JailPhone", min = 0, optional = true },
	},
	LawOffice = {
		{ kind = "firm" },
		{ kind = "point", type = "Reception", min = 1 },
		{ kind = "seat", type = "LawyerSeat", min = 1 }, { kind = "seat", type = "ClientSeat", min = 1 },
	},
	Bank = {
		{ kind = "zone", type = "DepositVault", min = 1 },
		{ kind = "point", type = "DepositTerminal", min = 1 },
		{ kind = "point", type = "BoxWall", min = 1 },
		{ kind = "point", type = "TellerDesk", min = 0, optional = true },
	},
	City = {
		{ kind = "point", type = "NewsStation", min = 1 },
		{ kind = "point", type = "BullionDealer", min = 1 },
		{ kind = "point", type = "StashSpot", min = 3 },
		{ kind = "point", type = "DrugCorner", min = 3 },
		{ kind = "point", type = "Bar", min = 1 },
		{ kind = "point", type = "Hospital", min = 1 },
		{ kind = "point", type = "ImpoundLot", min = 1 },
		{ kind = "point", type = "PrivateVaultSpot", min = 2 },
		{ kind = "point", type = "FixerSpot", min = 2 },
		{ kind = "point", type = "PawnShop", min = 0, optional = true },
		{ kind = "point", type = "UndergroundMetalBuyer", min = 0, optional = true },
		{ kind = "point", type = "LiquorStore", min = 0, optional = true },
		{ kind = "point", type = "Safehouse", min = 0, optional = true },
		{ kind = "zone", type = "TerritoryEK", min = 0, optional = true },
		{ kind = "zone", type = "TerritoryIS", min = 0, optional = true },
		{ kind = "zone", type = "TerritoryDS", min = 0, optional = true },
		{ kind = "zone", type = "TerritoryTL", min = 0, optional = true },
		-- (CourthouseSteps now belongs to the Courthouse facility)
		{ kind = "point", type = "PlateMakerSpot", min = 3 },
		{ kind = "point", type = "ShadyDealer", min = 1 },
		{ kind = "point", type = "ChopShop", min = 1 },
		{ kind = "point", type = "BailBondsOffice", min = 1 },
	},
}

local COLORS = {
	room = Color3.fromRGB(80, 200, 255), area = Color3.fromRGB(120, 230, 120), ignore = Color3.fromRGB(255, 70, 70),
	door = Color3.fromRGB(255, 160, 40), route = Color3.fromRGB(220, 120, 255), point = Color3.fromRGB(255, 240, 80),
	seat = Color3.fromRGB(255, 120, 190), selected = Color3.fromRGB(255, 255, 255), pending = Color3.fromRGB(255, 255, 0),
}

---------------------------------------------------------------------------
-- state
---------------------------------------------------------------------------
local state = {
	facilityType = "Prison",
	model = nil :: Instance?,
	mode = "Off", -- Zone / Door / Route / Point / Seat / Select / Building / Off
	prevMode = nil :: string?,
	zoneType = "Interrogation",
	pointType = "PrisonPhone",
	seatRole = "JudgeSeat",
	doorType = "Normal",
	access = "Staff",
	security = "General",
	routeType = "Escort",
	bidirectional = true,
	height = 20,
	flatten = true,
	pending = {} :: { Vector3 },
	selected = nil :: Instance?,
	overlay = true,
	labels = true,
}

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
local function safeName(value: string): string
	value = tostring(value or "")
	value = value:gsub("[^%w_%-%s]", ""):gsub("%s+", "_")
	return if value == "" then "Unnamed" else value:sub(1, 60)
end

local function uniqueName(folder: Instance, base: string): string
	base = safeName(base)
	if not folder:FindFirstChild(base) then
		return base
	end
	local n = 2
	while folder:FindFirstChild(base .. "_" .. n) do
		n += 1
	end
	return base .. "_" .. n
end

local function nextName(folder: Instance, base: string): string
	local n = 1
	while folder:FindFirstChild(base .. "_" .. n) do
		n += 1
	end
	return base .. "_" .. n
end

local function marker(name: string, cf: CFrame, parent: Instance, size: Vector3?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size or Vector3.new(0.1, 0.1, 0.1)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Locked = true
	p.CFrame = cf
	p.Parent = parent
	return p
end

local function record(label: string, fn: () -> ())
	local id = ChangeHistoryService:TryBeginRecording("FacilityMapper: " .. label)
	local ok, err = pcall(fn)
	if id then
		ChangeHistoryService:FinishRecording(id, if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel)
	end
	if not ok then
		warn("[FacilityMapper] " .. label .. " failed: " .. tostring(err))
	end
	return ok
end

local function mapFolderName(): string
	return if state.facilityType == "Prison" then "PrisonMap" else "FacilityMap"
end

local function facilityModel(): Instance?
	if state.facilityType == "City" then
		return workspace
	end
	if state.model and state.model.Parent then
		return state.model
	end
	-- a building marked with this facility type earlier, else a default name
	for _, c in workspace:GetChildren() do
		if c:GetAttribute("FacilityType") == state.facilityType and (c:IsA("Model") or c:IsA("Folder")) then
			state.model = c
			return c
		end
	end
	for _, name in DEFAULT_MODEL[state.facilityType] or {} do
		local found = workspace:FindFirstChild(name)
		if found then
			state.model = found
			return found
		end
	end
	return nil
end

-- the building a part belongs to: its ancestor directly under Workspace
local function buildingOf(inst: Instance?): Instance?
	local cur = inst
	while cur and cur.Parent and cur.Parent ~= workspace do
		cur = cur.Parent
	end
	if cur and cur.Parent == workspace and (cur:IsA("Model") or cur:IsA("Folder")) then
		return cur
	end
	return nil
end

local function mapRoot(create: boolean): Instance?
	local model = facilityModel()
	if not model then
		return nil
	end
	local name = if state.facilityType == "City" then "CityMap" else mapFolderName()
	local root = model:FindFirstChild(name)
	if not root and create then
		root = Instance.new("Folder")
		root.Name = name
		root:SetAttribute("FacilityType", state.facilityType)
		root:SetAttribute("MapperVersion", MAPPER_VERSION)
		root.Parent = model
	end
	if root and create then
		for _, sub in { "Zones", "DoorMarkers", "Routes", "Points" } do
			if not root:FindFirstChild(sub) then
				local f = Instance.new("Folder")
				f.Name = sub
				f.Parent = root
			end
		end
	end
	return root
end

local function sortedChildren(folder: Instance): { Instance }
	local list = folder:GetChildren()
	table.sort(list, function(a, b)
		local ia, ib = a:GetAttribute("Index"), b:GetAttribute("Index")
		if ia and ib then
			return ia < ib
		end
		return a.Name < b.Name
	end)
	return list
end

local function controlPoints(item: Instance): { Vector3 }
	local out = {}
	local cp = item:FindFirstChild("ControlPoints")
	if cp then
		for _, v in sortedChildren(cp) do
			if v:IsA("BasePart") then
				table.insert(out, v.Position)
			elseif v:IsA("Vector3Value") then
				table.insert(out, v.Value)
			end
		end
	end
	return out
end

local function pointInPoly(x: number, z: number, poly: { Vector3 }): boolean
	local inside = false
	local j = #poly
	for i = 1, #poly do
		local a, b = poly[i], poly[j]
		if (a.Z > z) ~= (b.Z > z) and x < (b.X - a.X) * (z - a.Z) / (b.Z - a.Z) + a.X then
			inside = not inside
		end
		j = i
	end
	return inside
end

local function distToPolyEdge(p: Vector3, poly: { Vector3 }): number
	local best = math.huge
	for i = 1, #poly do
		local a, b = poly[i], poly[i % #poly + 1]
		local ax, az, bx, bz = a.X, a.Z, b.X, b.Z
		local dx, dz = bx - ax, bz - az
		local len2 = dx * dx + dz * dz
		local t = if len2 > 0 then math.clamp(((p.X - ax) * dx + (p.Z - az) * dz) / len2, 0, 1) else 0
		local cx, cz = ax + dx * t, az + dz * t
		best = math.min(best, math.sqrt((p.X - cx) ^ 2 + (p.Z - cz) ^ 2))
	end
	return best
end

-- raycast from the mouse, skipping invisible parts (zone volumes, triggers)
local mouse = plugin:GetMouse()
local function mouseHit(): (Vector3?, BasePart?)
	local ray = mouse.UnitRay
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	for _ = 1, 12 do
		params.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
		if not hit then
			return nil, nil
		end
		local part = hit.Instance
		if part:IsA("BasePart") and part.Transparency >= 0.95 and not part:IsA("Seat") and not part:IsA("VehicleSeat") then
			table.insert(ignore, part)
		else
			return hit.Position, part :: BasePart
		end
	end
	return nil, nil
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
local toolbar = plugin:CreateToolbar("Facility Mapper")
local toggleButton = toolbar:CreateButton("Facility Mapper", "Map prison / HQ / jail / offices / city", "rbxassetid://4458901886")
toggleButton.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGui("FacilityMapperWidget",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 340, 720, 300, 400))
widget.Title = "Facility Mapper"
widget.Name = "FacilityMapper"

local theme = settings().Studio.Theme
local BG = theme:GetColor(Enum.StudioStyleGuideColor.MainBackground)
local TEXT = theme:GetColor(Enum.StudioStyleGuideColor.MainText)
local BTN = Color3.fromRGB(55, 60, 72)
local ON = Color3.fromRGB(40, 120, 200)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.fromScale(1, 1)
scroll.BackgroundColor3 = BG
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.Parent = widget
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 4)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scroll
local pad = Instance.new("UIPadding")
pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 12), UDim.new(0, 8), UDim.new(0, 8)
pad.Parent = scroll

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function label(text: string, bold: boolean?, height: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.LayoutOrder = nextOrder()
	l.Size = UDim2.new(1, 0, 0, height or 18)
	l.BackgroundTransparency = 1
	l.TextColor3 = TEXT
	l.Font = if bold then Enum.Font.SourceSansBold else Enum.Font.SourceSans
	l.TextSize = if bold then 16 else 14
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Text = text
	l.Parent = scroll
	return l
end

local function row(height: number?): Frame
	local f = Instance.new("Frame")
	f.LayoutOrder = nextOrder()
	f.Size = UDim2.new(1, 0, 0, height or 24)
	f.BackgroundTransparency = 1
	f.Parent = scroll
	local g = Instance.new("UIGridLayout")
	g.CellPadding = UDim2.fromOffset(3, 3)
	g.CellSize = UDim2.new(1 / 3, -3, 0, 22)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.Parent = f
	f.AutomaticSize = Enum.AutomaticSize.Y
	return f
end

local function button(parent: Instance, text: string, fn: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = BTN
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.SourceSansSemibold
	b.TextSize = 13
	b.TextScaled = false
	b.TextTruncate = Enum.TextTruncate.AtEnd
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = parent
	b.MouseButton1Click:Connect(fn)
	return b
end

local function textbox(placeholder: string, default: string?): TextBox
	local t = Instance.new("TextBox")
	t.LayoutOrder = nextOrder()
	t.Size = UDim2.new(1, 0, 0, 22)
	t.BackgroundColor3 = Color3.fromRGB(35, 38, 46)
	t.TextColor3 = Color3.new(1, 1, 1)
	t.PlaceholderText = placeholder
	t.PlaceholderColor3 = Color3.fromRGB(150, 150, 160)
	t.Text = default or ""
	t.ClearTextOnFocus = false
	t.Font = Enum.Font.SourceSans
	t.TextSize = 14
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Parent = scroll
	return t
end

-- forward declarations
local redraw, refreshUI, setMode

label("FACILITY MAPPER", true, 20)
local statusLabel = label("", false, 44)

label("1. Facility", true)
local facilityRow = row()
local facilityButtons = {}
for _, t in FACILITY_TYPES do
	facilityButtons[t] = button(facilityRow, t, function()
		state.facilityType = t
		state.model = nil
		state.selected = nil
		state.pending = {}
		if t == "Prison" then
			state.zoneType, state.pointType = "Interrogation", "PrisonPhone"
		else
			state.zoneType, state.pointType = ZONE_TYPES[t][1], POINT_TYPES[t][1]
		end
		refreshUI()
		redraw()
	end)
end
local facilityLabel = label("", false, 32)
local modelRow = row()
local function adoptModel(m: Instance)
	record("set facility", function()
		m:SetAttribute("FacilityType", state.facilityType)
	end)
	state.model = m
	print(("[FacilityMapper] %s building = %s"):format(state.facilityType, m:GetFullName()))
end
local pickBuildingButton = button(modelRow, "Pick building", function()
	if state.facilityType == "City" then
		return
	end
	setMode(if state.mode == "Building" then "Off" else "Building")
end)
button(modelRow, "Use selected model", function()
	local sel = Selection:Get()[1]
	-- a part works too: it resolves to the building it belongs to
	local m = if sel and sel.Parent == workspace and (sel:IsA("Model") or sel:IsA("Folder")) then sel else buildingOf(sel)
	if m and state.facilityType ~= "City" then
		adoptModel(m)
	else
		warn("[FacilityMapper] select the building (or any part of it) first - or press 'Pick building' and click it")
	end
	refreshUI()
	redraw()
end)
local restoreButton = button(modelRow, "Restore prison map", function() end)
local firmBox = textbox("Law firm name (LawOffice only), e.g. Premier Counsel")
button(row(), "Save firm name", function()
	local model = facilityModel()
	if model and state.facilityType == "LawOffice" and firmBox.Text ~= "" then
		record("firm", function()
			model:SetAttribute("Firm", firmBox.Text)
		end)
	end
	refreshUI()
end)

label("2. Tool", true)
local modeRow = row()
local modeButtons = {}
for _, m in { "Zone", "Door", "Route", "Point", "Seat", "Select" } do
	modeButtons[m] = button(modeRow, m, function()
		setMode(if state.mode == m then "Off" else m)
	end)
end
local helpLabel = label("", false, 48)
local hoverLabel = label("", false, 32)
hoverLabel.TextColor3 = Color3.fromRGB(90, 220, 255)

label("Type", true)
local typeRow = row()
local typeButtons: { TextButton } = {}

label("Details", true)
local nameBox = textbox("Name (blank = automatic)")
local descBox = textbox("Description (optional)")
local optRow = row()
local heightButton = button(optRow, "", function()
	state.height = if state.height >= 40 then 10 else state.height + 5
	refreshUI()
end)
local securityButton = button(optRow, "", function()
	state.security = SECURITY[(table.find(SECURITY, state.security) or 0) % #SECURITY + 1]
	refreshUI()
end)
local flattenButton = button(optRow, "", function()
	state.flatten = not state.flatten
	refreshUI()
end)
local doorRow = row()
local doorTypeButton = button(doorRow, "", function()
	state.doorType = DOOR_TYPES[(table.find(DOOR_TYPES, state.doorType) or 0) % #DOOR_TYPES + 1]
	refreshUI()
end)
local accessButton = button(doorRow, "", function()
	state.access = ACCESS[(table.find(ACCESS, state.access) or 0) % #ACCESS + 1]
	refreshUI()
end)
local routeButton = button(doorRow, "", function()
	state.routeType = ROUTE_TYPES[(table.find(ROUTE_TYPES, state.routeType) or 0) % #ROUTE_TYPES + 1]
	refreshUI()
end)

label("3. Actions", true)
local actionRow = row()
local finishPending, cancelPending, undoPoint, deleteSelected, applyEdits, placeAtCamera, validate, exportMap
button(actionRow, "Finish [Enter]", function() finishPending() end)
button(actionRow, "Undo pt [Bksp]", function() undoPoint() end)
button(actionRow, "Cancel [Esc]", function() cancelPending() end)
button(actionRow, "Delete selected", function() deleteSelected() end)
button(actionRow, "Apply edits", function() applyEdits() end)
button(actionRow, "Point at camera", function() placeAtCamera() end)
local selectedLabel = label("Selected: none", false, 32)

label("4. View", true)
local viewRow = row()
local overlayButton = button(viewRow, "", function()
	state.overlay = not state.overlay
	refreshUI()
	redraw()
end)
local labelsButton = button(viewRow, "", function()
	state.labels = not state.labels
	refreshUI()
	redraw()
end)
button(viewRow, "Refresh", function() redraw() end)

label("5. Checklist", true)
local checkRow = row()
button(checkRow, "Check this facility", function() validate() end)
button(checkRow, "Export backup", function() exportMap() end)
local checkLabel = label("Press 'Check this facility' to see what's still missing.", false, 20)
checkLabel.AutomaticSize = Enum.AutomaticSize.Y
checkLabel.RichText = true

---------------------------------------------------------------------------
-- overlay (editor-only adornments in CoreGui)
---------------------------------------------------------------------------
local overlay = CoreGui:FindFirstChild("FacilityMapperOverlay")
if overlay then
	overlay:Destroy()
end
overlay = Instance.new("Folder")
overlay.Name = "FacilityMapperOverlay"
overlay.Parent = CoreGui
local pendingFolder = Instance.new("Folder")
pendingFolder.Name = "Pending"
pendingFolder.Parent = CoreGui:FindFirstChild("FacilityMapperOverlay")

local function line(parent: Instance, a: Vector3, b: Vector3, color: Color3, thick: number?)
	local len = (b - a).Magnitude
	if len < 0.01 then
		return
	end
	local l = Instance.new("LineHandleAdornment")
	l.Adornee = workspace.Terrain
	l.CFrame = CFrame.lookAt(a, b)
	l.Length = len
	l.Thickness = thick or 3
	l.Color3 = color
	l.AlwaysOnTop = true
	l.ZIndex = 1
	l.Parent = parent
end

local function sphere(parent: Instance, p: Vector3, color: Color3, r: number?)
	local s = Instance.new("SphereHandleAdornment")
	s.Adornee = workspace.Terrain
	s.CFrame = CFrame.new(p)
	s.Radius = r or 0.4
	s.Color3 = color
	s.AlwaysOnTop = true
	s.ZIndex = 2
	s.Parent = parent
end

local function box(parent: Instance, cf: CFrame, size: Vector3, color: Color3, transparency: number?)
	local b = Instance.new("BoxHandleAdornment")
	b.Adornee = workspace.Terrain
	b.CFrame = cf
	b.Size = size
	b.Color3 = color
	b.Transparency = transparency or 0.5
	b.AlwaysOnTop = true
	b.ZIndex = 1
	b.Parent = parent
end

local function tag(parent: Instance, adornee: BasePart, text: string, color: Color3)
	if not state.labels then
		return
	end
	local g = Instance.new("BillboardGui")
	g.Adornee = adornee
	g.AlwaysOnTop = true
	g.Size = UDim2.fromOffset(180, 18)
	g.StudsOffset = Vector3.new(0, 2, 0)
	g.MaxDistance = 250
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 0.4
	t.BackgroundColor3 = Color3.new(0, 0, 0)
	t.TextColor3 = color
	t.Font = Enum.Font.SourceSansBold
	t.TextSize = 13
	t.Text = text
	t.Parent = g
	g.Parent = parent
end

local function zoneColor(zone: Instance): Color3
	local zt = tostring(zone:GetAttribute("ZoneType") or "")
	local info = ZONE_INFO[zt]
	if zone:GetAttribute("NavIgnore") or (info and info.navIgnore) then
		return COLORS.ignore
	end
	if zone:GetAttribute("Category") or (info and info.room) then
		return COLORS.room
	end
	return COLORS.area
end

local function seatsIn(model: Instance): { BasePart }
	local out = {}
	for _, d in model:GetDescendants() do
		if (d:IsA("Seat") or d:IsA("VehicleSeat")) and d:GetAttribute("SeatRole") then
			table.insert(out, d)
		end
	end
	return out
end

redraw = function()
	overlay:ClearAllChildren()
	pendingFolder = Instance.new("Folder")
	pendingFolder.Name = "Pending"
	pendingFolder.Parent = overlay
	if not state.overlay then
		return
	end
	local root = mapRoot(false)
	local model = facilityModel()
	if root then
		local zones = root:FindFirstChild("Zones")
		if zones then
			for _, zone in zones:GetChildren() do
				local pts = controlPoints(zone)
				local color = if zone == state.selected then COLORS.selected else zoneColor(zone)
				local thick = if zone == state.selected then 6 else 3
				for i = 1, #pts do
					line(overlay, pts[i], pts[i % #pts + 1], color, thick)
				end
				local cp = zone:FindFirstChild("ControlPoints")
				local first = cp and cp:GetChildren()[1]
				if first and first:IsA("BasePart") then
					tag(overlay, first, zone.Name .. " [" .. tostring(zone:GetAttribute("Category") or zone:GetAttribute("ZoneType") or "?") .. "]", color)
				end
			end
		end
		local doors = root:FindFirstChild("DoorMarkers")
		if doors then
			for _, d in doors:GetChildren() do
				local c = d:FindFirstChild("Center")
				if c and c:IsA("BasePart") then
					local sel = d == state.selected
					box(overlay, c.CFrame, c.Size + Vector3.new(0.2, 0.2, 0.2), if sel then COLORS.selected else COLORS.door, if sel then 0.2 else 0.55)
					tag(overlay, c, "DOOR " .. d.Name, COLORS.door)
				end
			end
		end
		local routes = root:FindFirstChild("Routes")
		if routes then
			for _, r in routes:GetChildren() do
				local pts = controlPoints(r)
				local color = if r == state.selected then COLORS.selected else COLORS.route
				for i = 1, #pts - 1 do
					line(overlay, pts[i] + Vector3.new(0, 0.5, 0), pts[i + 1] + Vector3.new(0, 0.5, 0), color, 2)
				end
				for _, p in pts do
					sphere(overlay, p + Vector3.new(0, 0.5, 0), color, 0.3)
				end
			end
		end
		local points = root:FindFirstChild("Points")
		if points then
			for _, p in points:GetChildren() do
				if p:IsA("BasePart") then
					local color = if p == state.selected then COLORS.selected else COLORS.point
					sphere(overlay, p.Position, color, 0.6)
					if AIMED_POINT[tostring(p:GetAttribute("PointType"))] then
						line(overlay, p.Position, p.Position + p.CFrame.LookVector * 6, color, 2)
					end
					tag(overlay, p, tostring(p:GetAttribute("PointType") or p.Name), color)
				end
			end
		end
	end
	if model then
		for _, s in seatsIn(model) do
			local color = if s == state.selected then COLORS.selected else COLORS.seat
			box(overlay, s.CFrame, s.Size + Vector3.new(0.3, 0.3, 0.3), color, 0.4)
			tag(overlay, s, tostring(s:GetAttribute("SeatRole")), color)
		end
	end
end

local function drawPending(hover: Vector3?)
	pendingFolder:ClearAllChildren()
	local pts = state.pending
	for i, p in pts do
		sphere(pendingFolder, p, COLORS.pending, 0.35)
		if i > 1 then
			line(pendingFolder, pts[i - 1], p, COLORS.pending, 4)
		end
	end
	if hover and #pts > 0 then
		line(pendingFolder, pts[#pts], hover, COLORS.pending, 2)
		if state.mode == "Zone" and #pts >= 2 then
			line(pendingFolder, hover, pts[1], COLORS.pending, 1)
		end
	end
end

---------------------------------------------------------------------------
-- baked prison map restore
---------------------------------------------------------------------------
local function restorePrisonMap()
	local facility = workspace:FindFirstChild("CorrectionalFacility")
	if not facility then
		warn("[FacilityMapper] Workspace.CorrectionalFacility not found")
		return
	end
	if facility:FindFirstChild("PrisonMap") then
		warn("[FacilityMapper] CorrectionalFacility.PrisonMap already exists - nothing to restore")
		return
	end
	local ps = ServerScriptService:FindFirstChild("PoliceSystem")
	local ok, source = pcall(function()
		return ps and ps.Source
	end)
	if not ok or type(source) ~= "string" then
		warn("[FacilityMapper] couldn't read ServerScriptService.PoliceSystem (allow script access for this plugin)")
		return
	end
	local startTag = "AUTHORED_PRISON_MAP=[==["
	local i = string.find(source, startTag, 1, true)
	local j = i and string.find(source, "]==]", i, true)
	if not i or not j then
		warn("[FacilityMapper] no baked prison map found in PoliceSystem")
		return
	end
	local data = HttpService:JSONDecode(string.sub(source, i + #startTag, j - 1))
	-- door parts by name for anchor matching
	local byName: { [string]: { BasePart } } = {}
	for _, d in facility:GetDescendants() do
		if d:IsA("BasePart") then
			byName[d.Name] = byName[d.Name] or {}
			table.insert(byName[d.Name], d)
		end
	end
	local function depth(path: string): number
		local _, n = string.gsub(path, "%.", "")
		return n
	end
	local linked, missing = 0, 0
	record("restore prison map", function()
		local root = Instance.new("Folder")
		root.Name = "PrisonMap"
		root:SetAttribute("FacilityType", "Prison")
		local function attrs(obj, values)
			for k, v in values or {} do
				obj:SetAttribute(k, v)
			end
		end
		for _, kind in { { "Zones", data.zones }, { "Routes", data.routes } } do
			local folder = Instance.new("Folder")
			folder.Name = kind[1]
			folder.Parent = root
			for _, rec in kind[2] or {} do
				local item = Instance.new("Folder")
				item.Name = rec.name
				attrs(item, rec.attrs)
				item.Parent = folder
				local cp = Instance.new("Folder")
				cp.Name = "ControlPoints"
				cp.Parent = item
				for _, pt in rec.points do
					local p = marker(pt.name, CFrame.new(pt.pos[1], pt.pos[2], pt.pos[3]), cp)
					attrs(p, pt.attrs)
				end
			end
		end
		local doors = Instance.new("Folder")
		doors.Name = "DoorMarkers"
		doors.Parent = root
		for _, rec in data.doors or {} do
			local m = Instance.new("Folder")
			m.Name = rec.name
			attrs(m, rec.attrs)
			m.Parent = doors
			local c = marker("Center", CFrame.new(table.unpack(rec.cf)), m, Vector3.new(table.unpack(rec.size)))
			local target = nil
			local a = rec.anchor
			if a then
				local want = Vector3.new(a.pos[1], a.pos[2], a.pos[3])
				local wantSize = Vector3.new(a.size[1], a.size[2], a.size[3])
				for _, part in byName[a.name] or {} do
					if part.ClassName == a.class and (part.Position - want).Magnitude < 0.25 and (part.Size - wantSize).Magnitude < 0.1 then
						target = part
						break
					end
				end
				-- climb from the clicked part to the bound door object
				local attrsRec = rec.attrs or {}
				if target and attrsRec.ClickedPartPath and attrsRec.BoundObjectPath then
					local up = depth(attrsRec.ClickedPartPath) - depth(attrsRec.BoundObjectPath)
					for _ = 1, up do
						if target.Parent and target.Parent ~= facility then
							target = target.Parent
						end
					end
				end
			end
			if target then
				local ov = Instance.new("ObjectValue")
				ov.Name = "DoorObject"
				ov.Value = target
				ov.Parent = m
				linked += 1
			else
				missing += 1
			end
			local _ = c
		end
		local points = Instance.new("Folder")
		points.Name = "Points"
		points.Parent = root
		root.Parent = facility
	end)
	print(("[FacilityMapper] restored the prison map: %d zones, %d doors linked, %d doors unmatched, %d routes"):format(
		#(data.zones or {}), linked, missing, #(data.routes or {})))
	if missing > 0 then
		warn("[FacilityMapper] some doors couldn't be matched to their door part - re-map those doors (they show without a DOOR box)")
	end
	redraw()
	refreshUI()
end
restoreButton.MouseButton1Click:Connect(restorePrisonMap)

---------------------------------------------------------------------------
-- creating things
---------------------------------------------------------------------------
local function guardPrison(): boolean
	if state.facilityType == "Prison" then
		local facility = workspace:FindFirstChild("CorrectionalFacility")
		if facility and not facility:FindFirstChild("PrisonMap") then
			warn("[FacilityMapper] Press 'Restore prison map' first - mapping the prison without the existing map would replace it with only your new zones")
			return false
		end
	end
	if not facilityModel() then
		warn("[FacilityMapper] no building yet: press 'Pick building' and click the building")
		return false
	end
	return true
end

local function createZone(pts: { Vector3 })
	if #pts < 3 then
		warn("[FacilityMapper] a zone needs at least 3 corners")
		return
	end
	if not guardPrison() then
		return
	end
	local root = mapRoot(true) :: Instance
	local zones = root:FindFirstChild("Zones") :: Instance
	local bottom = math.huge
	for _, p in pts do
		bottom = math.min(bottom, p.Y)
	end
	if state.flatten then
		bottom = pts[1].Y
	end
	local name = if nameBox.Text ~= "" then uniqueName(zones, nameBox.Text) else nextName(zones, state.zoneType)
	local info = ZONE_INFO[state.zoneType] or {}
	record("zone " .. name, function()
		local z = Instance.new("Folder")
		z.Name = name
		z:SetAttribute("PrisonZone", true)
		z:SetAttribute("FacilityZone", true)
		z:SetAttribute("Facility", state.facilityType)
		z:SetAttribute("MapperVersion", MAPPER_VERSION)
		z:SetAttribute("ZoneType", state.zoneType)
		if info.room then
			z:SetAttribute("Category", state.zoneType)
		end
		if info.navIgnore then
			z:SetAttribute("NavIgnore", true)
		end
		if descBox.Text ~= "" then
			z:SetAttribute("Description", descBox.Text)
		end
		z:SetAttribute("SecurityGroup", state.security)
		z:SetAttribute("Priority", 50)
		z:SetAttribute("BottomY", bottom)
		z:SetAttribute("TopY", bottom + state.height)
		local cp = Instance.new("Folder")
		cp.Name = "ControlPoints"
		cp.Parent = z
		for i, p in pts do
			local y = if state.flatten then pts[1].Y else p.Y
			marker(("P%03d"):format(i), CFrame.new(p.X, y, p.Z), cp)
		end
		z.Parent = zones
		state.selected = z
	end)
	print(("[FacilityMapper] ZONE %s type=%s corners=%d"):format(name, state.zoneType, #pts))
end

local function createRoute(pts: { Vector3 })
	if #pts < 2 then
		warn("[FacilityMapper] a route needs at least 2 points")
		return
	end
	if not guardPrison() then
		return
	end
	local root = mapRoot(true) :: Instance
	local routes = root:FindFirstChild("Routes") :: Instance
	local name = if nameBox.Text ~= "" then uniqueName(routes, nameBox.Text) else nextName(routes, state.routeType .. "Route")
	record("route " .. name, function()
		local r = Instance.new("Folder")
		r.Name = name
		r:SetAttribute("PrisonRoute", true)
		r:SetAttribute("Facility", state.facilityType)
		r:SetAttribute("MapperVersion", MAPPER_VERSION)
		r:SetAttribute("RouteType", state.routeType)
		r:SetAttribute("Bidirectional", state.bidirectional)
		r:SetAttribute("DefaultSpeed", 12)
		r:SetAttribute("SecurityGroup", "Any")
		if descBox.Text ~= "" then
			r:SetAttribute("Description", descBox.Text)
		end
		local cp = Instance.new("Folder")
		cp.Name = "ControlPoints"
		cp.Parent = r
		for i, p in pts do
			local m = marker(("P%03d"):format(i), CFrame.new(p), cp)
			m:SetAttribute("Index", i)
			m:SetAttribute("PointType", "Walk")
			m:SetAttribute("WaitSeconds", 0)
		end
		r.Parent = routes
		state.selected = r
	end)
	print(("[FacilityMapper] ROUTE %s type=%s points=%d"):format(name, state.routeType, #pts))
end

local function resolveDoor(part: BasePart): Instance
	-- Shift+click links just the part you clicked
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
		return part
	end
	local model = facilityModel()
	local cur: Instance? = part
	while cur and cur ~= model and cur ~= workspace do
		local n = string.lower(cur.Name)
		if (cur:IsA("BasePart") or cur:IsA("Model")) and (string.find(n, "door", 1, true) or string.find(n, "gate", 1, true)) then
			return cur
		end
		cur = cur.Parent
	end
	if part.Parent and part.Parent:IsA("Model") and part.Parent ~= model and part.Parent ~= workspace then
		return part.Parent
	end
	return part
end

local function pathOf(inst: Instance): string
	local parts = {}
	local cur: Instance? = inst
	while cur and cur ~= game do
		table.insert(parts, 1, cur.Name)
		cur = cur.Parent
	end
	return table.concat(parts, ".")
end

local function createDoor(part: BasePart)
	if not guardPrison() then
		return
	end
	local model = facilityModel()
	if state.facilityType ~= "City" and model and not part:IsDescendantOf(model) then
		warn("[FacilityMapper] that door isn't inside the active facility (" .. model.Name .. ")")
		return
	end
	local root = mapRoot(true) :: Instance
	local doors = root:FindFirstChild("DoorMarkers") :: Instance
	local target = resolveDoor(part)
	for _, d in doors:GetChildren() do
		local ov = d:FindFirstChild("DoorObject")
		if ov and ov.Value == target then
			warn("[FacilityMapper] that door is already mapped as " .. d.Name .. " (selected it)")
			state.selected = d
			redraw()
			refreshUI()
			return
		end
	end
	local cf, size
	if target:IsA("Model") then
		cf, size = target:GetBoundingBox()
	else
		cf, size = (target :: BasePart).CFrame, (target :: BasePart).Size
	end
	local name = if nameBox.Text ~= "" then uniqueName(doors, nameBox.Text) else nextName(doors, state.doorType .. "Door")
	record("door " .. name, function()
		local m = Instance.new("Folder")
		m.Name = name
		m:SetAttribute("PrisonDoorMarker", true)
		m:SetAttribute("FacilityDoor", true)
		m:SetAttribute("Facility", state.facilityType)
		m:SetAttribute("MapperVersion", MAPPER_VERSION)
		m:SetAttribute("DoorType", state.doorType)
		m:SetAttribute("Access", state.access)
		m:SetAttribute("Description", if descBox.Text ~= "" then descBox.Text else state.doorType .. " door")
		m:SetAttribute("BoundObjectPath", pathOf(target))
		m:SetAttribute("ClickedPartPath", pathOf(part))
		m:SetAttribute("CenterX", cf.Position.X)
		m:SetAttribute("CenterY", cf.Position.Y)
		m:SetAttribute("CenterZ", cf.Position.Z)
		m:SetAttribute("SizeX", size.X)
		m:SetAttribute("SizeY", size.Y)
		m:SetAttribute("SizeZ", size.Z)
		marker("Center", cf, m, size)
		local ov = Instance.new("ObjectValue")
		ov.Name = "DoorObject"
		ov.Value = target
		ov.Parent = m
		m.Parent = doors
		state.selected = m
	end)
	print(("[FacilityMapper] DOOR %s -> %s"):format(name, pathOf(target)))
end

local function createPoint(pos: Vector3, cfOverride: CFrame?)
	if not guardPrison() then
		return
	end
	local root = mapRoot(true) :: Instance
	local points = root:FindFirstChild("Points") :: Instance
	local cam = workspace.CurrentCamera
	local look = cam.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local cf = cfOverride
		or (if AIMED_POINT[state.pointType] then CFrame.lookAt(pos + Vector3.new(0, 1, 0), pos + Vector3.new(0, 1, 0) + look)
			elseif flat.Magnitude > 0.01 then CFrame.lookAt(pos + Vector3.new(0, 0.5, 0), pos + Vector3.new(0, 0.5, 0) + flat.Unit)
			else CFrame.new(pos + Vector3.new(0, 0.5, 0)))
	local name = if nameBox.Text ~= "" then uniqueName(points, nameBox.Text) else nextName(points, state.pointType)
	record("point " .. name, function()
		local p = marker(name, cf, points, Vector3.new(1, 1, 1))
		p:SetAttribute("FacilityPoint", true)
		p:SetAttribute("Facility", state.facilityType)
		p:SetAttribute("PointType", state.pointType)
		p:SetAttribute("MapperVersion", MAPPER_VERSION)
		if descBox.Text ~= "" then
			p:SetAttribute("Description", descBox.Text)
		end
		state.selected = p
	end)
	print(("[FacilityMapper] POINT %s type=%s"):format(name, state.pointType))
end

-- the Seat for whatever was clicked: the part itself, or the seat inside the clicked chair model
local function findSeat(part: BasePart?): BasePart?
	if not part then
		return nil
	end
	if part:IsA("Seat") or part:IsA("VehicleSeat") then
		return part
	end
	local chair = part.Parent
	if chair and chair:IsA("Model") and chair ~= workspace and chair.Parent ~= workspace then
		local best, bestDist = nil, math.huge
		for _, d in chair:GetDescendants() do
			if d:IsA("Seat") or d:IsA("VehicleSeat") then
				local dist = (d.Position - part.Position).Magnitude
				if dist < bestDist then
					best, bestDist = d, dist
				end
			end
		end
		return best
	end
	return nil
end

local function setSeatRole(clicked: BasePart)
	local part = findSeat(clicked)
	if not part then
		warn("[FacilityMapper] no Seat there: " .. clicked:GetFullName() .. " isn't a Seat and its chair has none")
		return
	end
	local model = facilityModel()
	if not model then
		return
	end
	local role = state.seatRole
	if role == "JurorSeat" then
		-- numbered 1..12 in the order you click them
		local used = {}
		for _, s in seatsIn(model) do
			local n = tonumber(string.match(tostring(s:GetAttribute("SeatRole")), "^JurorSeat(%d+)$"))
			if n and s ~= part then
				used[n] = true
			end
		end
		local n = 1
		while used[n] do
			n += 1
		end
		role = "JurorSeat" .. n
	end
	record("seat " .. role, function()
		part:SetAttribute("SeatRole", role)
		part:SetAttribute("Facility", state.facilityType)
	end)
	state.selected = part
	print(("[FacilityMapper] SEAT %s -> %s"):format(pathOf(part), role))
end

---------------------------------------------------------------------------
-- selecting / editing
---------------------------------------------------------------------------
local function pick(pos: Vector3, part: BasePart?): Instance?
	local root = mapRoot(false)
	local model = facilityModel()
	if part and model and (part:IsA("Seat") or part:IsA("VehicleSeat")) and part:GetAttribute("SeatRole") then
		return part
	end
	if not root then
		return nil
	end
	local doors = root:FindFirstChild("DoorMarkers")
	if doors and part then
		for _, d in doors:GetChildren() do
			local ov = d:FindFirstChild("DoorObject")
			if ov and ov.Value and (part == ov.Value or part:IsDescendantOf(ov.Value)) then
				return d
			end
		end
	end
	local points = root:FindFirstChild("Points")
	if points then
		for _, p in points:GetChildren() do
			if p:IsA("BasePart") and (p.Position - pos).Magnitude < 3 then
				return p
			end
		end
	end
	local routes = root:FindFirstChild("Routes")
	if routes then
		for _, r in routes:GetChildren() do
			for _, p in controlPoints(r) do
				if (p - pos).Magnitude < 2 then
					return r
				end
			end
		end
	end
	local zones = root:FindFirstChild("Zones")
	local best, bestArea = nil, math.huge
	if zones then
		for _, z in zones:GetChildren() do
			local pts = controlPoints(z)
			if #pts >= 3 and pointInPoly(pos.X, pos.Z, pts) then
				local b = tonumber(z:GetAttribute("BottomY")) or pts[1].Y
				local t = tonumber(z:GetAttribute("TopY")) or (b + 20)
				if pos.Y >= b - 3 and pos.Y <= t then
					local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
					for _, q in pts do
						minX, maxX, minZ, maxZ = math.min(minX, q.X), math.max(maxX, q.X), math.min(minZ, q.Z), math.max(maxZ, q.Z)
					end
					local area = (maxX - minX) * (maxZ - minZ)
					if area < bestArea then
						best, bestArea = z, area
					end
				end
			end
		end
	end
	return best
end

deleteSelected = function()
	local sel = state.selected
	if not sel or not sel.Parent then
		return
	end
	if sel:IsA("Seat") or sel:IsA("VehicleSeat") then
		record("clear seat role", function()
			sel:SetAttribute("SeatRole", nil)
		end)
	else
		local n = sel.Name
		record("delete " .. n, function()
			sel.Parent = nil
		end)
		print("[FacilityMapper] deleted " .. n)
	end
	state.selected = nil
	redraw()
	refreshUI()
end

applyEdits = function()
	local sel = state.selected
	if not sel or not sel.Parent then
		return
	end
	record("edit " .. sel.Name, function()
		if nameBox.Text ~= "" and not (sel:IsA("Seat") or sel:IsA("VehicleSeat")) then
			sel.Name = uniqueName(sel.Parent, nameBox.Text)
		end
		if descBox.Text ~= "" then
			sel:SetAttribute("Description", descBox.Text)
		end
		if sel:GetAttribute("PrisonZone") then
			local info = ZONE_INFO[state.zoneType] or {}
			sel:SetAttribute("ZoneType", state.zoneType)
			sel:SetAttribute("Category", if info.room then state.zoneType else nil)
			sel:SetAttribute("NavIgnore", if info.navIgnore then true else nil)
			sel:SetAttribute("SecurityGroup", state.security)
			local b = tonumber(sel:GetAttribute("BottomY")) or 0
			sel:SetAttribute("TopY", b + state.height)
		elseif sel:GetAttribute("PrisonDoorMarker") then
			sel:SetAttribute("DoorType", state.doorType)
			sel:SetAttribute("Access", state.access)
		elseif sel:GetAttribute("PrisonRoute") then
			sel:SetAttribute("RouteType", state.routeType)
		elseif sel:GetAttribute("FacilityPoint") then
			sel:SetAttribute("PointType", state.pointType)
		elseif sel:IsA("Seat") or sel:IsA("VehicleSeat") then
			sel:SetAttribute("SeatRole", state.seatRole)
		end
	end)
	redraw()
	refreshUI()
end

placeAtCamera = function()
	if state.mode ~= "Point" then
		warn("[FacilityMapper] switch to the Point tool first (useful for CourtCam / SniperPost: aim the Studio camera, then press)")
		return
	end
	local cam = workspace.CurrentCamera
	createPoint(cam.CFrame.Position, cam.CFrame)
	redraw()
	refreshUI()
end

finishPending = function()
	if state.mode == "Zone" then
		createZone(state.pending)
	elseif state.mode == "Route" then
		createRoute(state.pending)
	end
	state.pending = {}
	drawPending()
	redraw()
	refreshUI()
end

cancelPending = function()
	state.pending = {}
	drawPending()
	refreshUI()
end

undoPoint = function()
	table.remove(state.pending)
	drawPending()
	refreshUI()
end

---------------------------------------------------------------------------
-- checklist / export
---------------------------------------------------------------------------
validate = function()
	local lines = {}
	local model = facilityModel()
	local root = mapRoot(false)
	local list = CHECKLIST[state.facilityType] or {}
	if not model then
		checkLabel.Text = "<font color='#ff6060'>No facility model. Select the building in the Explorer and press 'Use selected model'.</font>"
		return
	end
	local zoneCount, pointCount, seatCount = {}, {}, {}
	local zonesFolder = root and root:FindFirstChild("Zones")
	local doorsFolder = root and root:FindFirstChild("DoorMarkers")
	if zonesFolder then
		for _, z in zonesFolder:GetChildren() do
			local t = tostring(z:GetAttribute("Category") or z:GetAttribute("ZoneType") or "")
			zoneCount[t] = (zoneCount[t] or 0) + 1
		end
	end
	if root and root:FindFirstChild("Points") then
		for _, p in root.Points:GetChildren() do
			local t = tostring(p:GetAttribute("PointType") or "")
			pointCount[t] = (pointCount[t] or 0) + 1
		end
	end
	for _, s in seatsIn(model) do
		local role = tostring(s:GetAttribute("SeatRole"))
		role = string.gsub(role, "%d+$", "")
		seatCount[role] = (seatCount[role] or 0) + 1
	end
	local missing = 0
	for _, item in list do
		local have, need, what
		if item.kind == "firm" then
			local firm = model:GetAttribute("Firm")
			have, need, what = if firm then 1 else 0, 1, "Firm name" .. (if firm then " (" .. tostring(firm) .. ")" else "")
		elseif item.kind == "zone" then
			have, need, what = zoneCount[item.type] or 0, item.min, item.type .. " zone"
		elseif item.kind == "point" then
			have, need, what = pointCount[item.type] or 0, item.min, item.type .. " point"
		else
			have, need, what = seatCount[item.type] or 0, item.min, item.type .. " seat"
		end
		local ok = have >= math.max(need, if item.optional then 0 else 1)
		if item.optional then
			table.insert(lines, ("<font color='#a0a0a0'>• %s: %d (optional)</font>"):format(what, have))
		elseif ok then
			table.insert(lines, ("<font color='#70e070'>✔ %s: %d</font>"):format(what, have))
		else
			missing += 1
			table.insert(lines, ("<font color='#ff6060'>✘ %s: %d / %d</font>"):format(what, have, math.max(need, 1)))
		end
	end
	-- every room needs a mapped door on (or near) its edge
	local doorless = {}
	if zonesFolder then
		local doorPos = {}
		if doorsFolder then
			for _, d in doorsFolder:GetChildren() do
				local c = d:FindFirstChild("Center")
				local ov = d:FindFirstChild("DoorObject")
				if c and c:IsA("BasePart") then
					table.insert(doorPos, c.Position)
				end
				if not (ov and ov.Value and ov.Value.Parent) then
					table.insert(lines, ("<font color='#ffb040'>⚠ door %s isn't linked to a door object - re-map it</font>"):format(d.Name))
				end
			end
		end
		for _, z in zonesFolder:GetChildren() do
			local cat = z:GetAttribute("Category")
			local info = ZONE_INFO[tostring(cat)]
			if cat and info and info.room and z:GetAttribute("MapperVersion") == MAPPER_VERSION then
				local pts = controlPoints(z)
				local found = false
				for _, p in doorPos do
					if #pts >= 3 and distToPolyEdge(p, pts) < 5 and math.abs(p.Y - pts[1].Y) < 12 then
						found = true
						break
					end
				end
				if not found then
					table.insert(doorless, z.Name)
				end
			end
			if #controlPoints(z) < 3 then
				table.insert(lines, ("<font color='#ffb040'>⚠ zone %s has fewer than 3 corners</font>"):format(z.Name))
			end
		end
	end
	for _, n in doorless do
		table.insert(lines, ("<font color='#ffb040'>⚠ room %s has no mapped door on its edge</font>"):format(n))
	end
	table.insert(lines, 1, if missing == 0
		then ("<b><font color='#70e070'>%s is ready (%d zones, %d doors)</font></b>"):format(state.facilityType,
			zonesFolder and #zonesFolder:GetChildren() or 0, doorsFolder and #doorsFolder:GetChildren() or 0)
		else ("<b><font color='#ff6060'>%s: %d thing(s) still missing</font></b>"):format(state.facilityType, missing))
	checkLabel.Text = table.concat(lines, "\n")
end

exportMap = function()
	local root = mapRoot(false)
	if not root then
		warn("[FacilityMapper] nothing mapped yet for " .. state.facilityType)
		return
	end
	local function attrsOf(obj)
		local t = {}
		for k, v in obj:GetAttributes() do
			if type(v) == "number" or type(v) == "string" or type(v) == "boolean" then
				t[k] = v
			end
		end
		return t
	end
	local function v3(v)
		return { v.X, v.Y, v.Z }
	end
	local data = { facility = state.facilityType, model = facilityModel() and pathOf(facilityModel()), zones = {}, doors = {}, routes = {}, points = {}, seats = {} }
	for _, kind in { { "Zones", data.zones }, { "Routes", data.routes } } do
		local folder = root:FindFirstChild(kind[1])
		if folder then
			for _, item in folder:GetChildren() do
				local rec = { name = item.Name, attrs = attrsOf(item), points = {} }
				local cp = item:FindFirstChild("ControlPoints")
				if cp then
					for _, p in sortedChildren(cp) do
						if p:IsA("BasePart") then
							table.insert(rec.points, { name = p.Name, attrs = attrsOf(p), pos = v3(p.Position) })
						end
					end
				end
				table.insert(kind[2], rec)
			end
		end
	end
	local doors = root:FindFirstChild("DoorMarkers")
	if doors then
		for _, d in doors:GetChildren() do
			local c = d:FindFirstChild("Center")
			local ov = d:FindFirstChild("DoorObject")
			local rec = { name = d.Name, attrs = attrsOf(d), target = ov and ov.Value and pathOf(ov.Value) or nil }
			if c and c:IsA("BasePart") then
				rec.cf = { c.CFrame:GetComponents() }
				rec.size = v3(c.Size)
			end
			table.insert(data.doors, rec)
		end
	end
	local points = root:FindFirstChild("Points")
	if points then
		for _, p in points:GetChildren() do
			if p:IsA("BasePart") then
				table.insert(data.points, { name = p.Name, attrs = attrsOf(p), cf = { p.CFrame:GetComponents() } })
			end
		end
	end
	local model = facilityModel()
	if model then
		for _, s in seatsIn(model) do
			table.insert(data.seats, { role = s:GetAttribute("SeatRole"), path = pathOf(s), pos = v3(s.Position) })
		end
	end
	local json = HttpService:JSONEncode(data)
	record("export", function()
		local folder = ServerStorage:FindFirstChild("FacilityMapExports") or Instance.new("Folder")
		folder.Name = "FacilityMapExports"
		folder.Parent = ServerStorage
		local name = state.facilityType .. (if state.facilityType == "LawOffice" and model then "_" .. safeName(tostring(model:GetAttribute("Firm") or model.Name)) else "")
		local old = folder:FindFirstChild(name)
		if old then
			old:Destroy()
		end
		local s = Instance.new("StringValue")
		s.Name = name
		s.Value = json
		s.Parent = folder
	end)
	print(("[FacilityMapper] exported %s: %d zones, %d doors, %d routes, %d points, %d seats -> ServerStorage.FacilityMapExports"):format(
		state.facilityType, #data.zones, #data.doors, #data.routes, #data.points, #data.seats))
end

---------------------------------------------------------------------------
-- modes & input
---------------------------------------------------------------------------
local HELP = {
	Off = "Pick a tool. Colours: blue = rooms, green = areas, red = sniper zones, orange = doors, purple = routes, yellow = points, pink = seats.",
	Zone = "Click the corners of the floor area, then Enter. Backspace removes a corner, Esc cancels. Rooms (blue) need a door on their edge.",
	Door = "Click a door (or gate). The whole door model is linked. Set Door type / Access first.",
	Route = "Click points along the walking path (e.g. up a staircase), then Enter. BusUnloadLine = the walk from the prison bus bay to intake.",
	Point = "Click a spot. Aimed points (SniperPost, Spotlight, CourtCam) face where the camera looks - or use 'Point at camera'.",
	Seat = "Click a Seat to give it the chosen role. JurorSeat numbers itself 1-12 in click order.",
	Select = "Click a zone / door / route / point / seat to select it, then Delete or change the fields and Apply edits.",
	Building = "Click any part of the building. The whole building (its model under Workspace) becomes the active facility.",
}

-- hover preview: a cyan box around whatever the next click would use
local hoverBox = CoreGui:FindFirstChild("FacilityMapperHover")
if hoverBox then
	hoverBox:Destroy()
end
hoverBox = Instance.new("SelectionBox")
hoverBox.Name = "FacilityMapperHover"
hoverBox.Color3 = Color3.fromRGB(90, 220, 255)
hoverBox.SurfaceColor3 = Color3.fromRGB(90, 220, 255)
hoverBox.SurfaceTransparency = 0.85
hoverBox.LineThickness = 0.08
hoverBox.Parent = CoreGui

local function hoverTarget(pos: Vector3?, part: BasePart?): (Instance?, string)
	if not part then
		return nil, ""
	end
	local mode = state.mode
	if mode == "Building" then
		local b = buildingOf(part)
		return b, if b then "Building: " .. b.Name else "Not part of a building model: " .. part:GetFullName()
	elseif mode == "Door" then
		local t = resolveDoor(part)
		local root = mapRoot(false)
		local doors = root and root:FindFirstChild("DoorMarkers")
		if doors then
			for _, d in doors:GetChildren() do
				local ov = d:FindFirstChild("DoorObject")
				if ov and ov.Value == t then
					return t, "Door: " .. pathOf(t) .. "  (already mapped as " .. d.Name .. ")"
				end
			end
		end
		return t, "Door: " .. pathOf(t) .. "  (Shift = just this part)"
	elseif mode == "Seat" then
		local s = findSeat(part)
		if not s then
			return nil, "No seat: " .. part:GetFullName()
		end
		local role = s:GetAttribute("SeatRole")
		return s, "Seat: " .. pathOf(s) .. (if role then "  (now " .. tostring(role) .. ")" else "")
	elseif mode == "Select" and pos then
		local p = pick(pos, part)
		if not p then
			return nil, "Nothing mapped here"
		end
		local ov = p:FindFirstChild("DoorObject")
		local adornee = if ov and ov:IsA("ObjectValue") then ov.Value elseif p:IsA("BasePart") then p else nil
		return adornee, "Select: " .. p.Name
	end
	return nil, "Surface: " .. pathOf(part)
end

local function updateHover()
	if state.mode == "Off" or not widget.Enabled then
		hoverBox.Adornee = nil
		hoverLabel.Text = ""
		return
	end
	local pos, part = mouseHit()
	local target, text = hoverTarget(pos, part)
	hoverBox.Adornee = if target and (target:IsA("BasePart") or target:IsA("Model")) then target else nil
	hoverLabel.Text = text
end

setMode = function(m: string)
	if m == "Building" and state.mode ~= "Building" then
		state.prevMode = state.mode -- go back to this tool after the building is picked
	end
	state.mode = m
	state.pending = {}
	drawPending()
	hoverBox.Adornee = nil
	hoverLabel.Text = ""
	if m == "Off" then
		plugin:Deactivate()
	else
		plugin:Activate(true)
	end
	refreshUI()
end

plugin.Deactivation:Connect(function()
	if state.mode ~= "Off" then
		state.mode = "Off"
		state.pending = {}
		drawPending()
		hoverBox.Adornee = nil
		hoverLabel.Text = ""
		refreshUI()
	end
end)

mouse.Button1Down:Connect(function()
	if state.mode == "Off" or not widget.Enabled then
		return
	end
	local pos, part = mouseHit()
	if not pos then
		return
	end
	if state.mode == "Building" then
		local b = buildingOf(part)
		if b then
			adoptModel(b)
			setMode(state.prevMode or "Off")
			redraw()
		else
			warn("[FacilityMapper] that isn't part of a building model: " .. (if part then part:GetFullName() else "nothing"))
		end
		return
	end
	-- no building chosen yet: clicking a door / seat picks the building it belongs to
	if (state.mode == "Door" or state.mode == "Seat") and part and state.facilityType ~= "City" and not facilityModel() then
		local b = buildingOf(part)
		if b then
			adoptModel(b)
		end
	end
	if state.mode == "Zone" or state.mode == "Route" then
		if state.mode == "Zone" and #state.pending >= 3 and (pos - state.pending[1]).Magnitude < 1.5 then
			finishPending() -- clicked back on the first corner
			return
		end
		table.insert(state.pending, pos)
		drawPending()
		refreshUI()
	elseif state.mode == "Door" then
		if part then
			createDoor(part)
			redraw()
			refreshUI()
		end
	elseif state.mode == "Point" then
		createPoint(pos)
		redraw()
		refreshUI()
	elseif state.mode == "Seat" then
		if part then
			setSeatRole(part)
			redraw()
			refreshUI()
		end
	elseif state.mode == "Select" then
		state.selected = pick(pos, part)
		if state.selected then
			Selection:Set({ state.selected })
		end
		redraw()
		refreshUI()
	end
end)

mouse.Move:Connect(function()
	if (state.mode == "Zone" or state.mode == "Route") and #state.pending > 0 then
		local pos = mouseHit()
		drawPending(pos)
	end
	updateHover()
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or state.mode == "Off" then
		return
	end
	if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
		finishPending()
	elseif input.KeyCode == Enum.KeyCode.Backspace then
		undoPoint()
	elseif input.KeyCode == Enum.KeyCode.Escape then
		cancelPending()
	end
end)

---------------------------------------------------------------------------
-- UI refresh
---------------------------------------------------------------------------
local function typeOptions(): ({ string }?, string?, ((string) -> ())?)
	if state.mode == "Building" then
		return nil, nil, nil
	elseif state.mode == "Point" then
		return POINT_TYPES[state.facilityType], state.pointType, function(v) state.pointType = v end
	elseif state.mode == "Seat" then
		return SEAT_ROLES, state.seatRole, function(v) state.seatRole = v end
	elseif state.mode == "Door" then
		return DOOR_TYPES, state.doorType, function(v) state.doorType = v end
	elseif state.mode == "Route" then
		return ROUTE_TYPES, state.routeType, function(v) state.routeType = v end
	end
	return ZONE_TYPES[state.facilityType], state.zoneType, function(v) state.zoneType = v end
end

refreshUI = function()
	for t, b in facilityButtons do
		b.BackgroundColor3 = if t == state.facilityType then ON else BTN
	end
	for m, b in modeButtons do
		b.BackgroundColor3 = if m == state.mode then ON else BTN
	end
	pickBuildingButton.Visible = state.facilityType ~= "City"
	pickBuildingButton.BackgroundColor3 = if state.mode == "Building" then ON else BTN
	pickBuildingButton.Text = if state.mode == "Building" then "Click the building..." else "Pick building"
	local model = facilityModel()
	local root = mapRoot(false)
	facilityLabel.Text = if model
		then ("Active: %s -> %s%s"):format(state.facilityType, model:GetFullName(), if root then "" else "  (no map yet)")
		else ("Active: %s -> no model found. Select the building Model and press 'Use selected model'."):format(state.facilityType)
	local prison = workspace:FindFirstChild("CorrectionalFacility")
	restoreButton.Visible = state.facilityType == "Prison"
	restoreButton.Text = if prison and prison:FindFirstChild("PrisonMap") then "Prison map OK" else "Restore prison map"
	restoreButton.BackgroundColor3 = if prison and prison:FindFirstChild("PrisonMap") then Color3.fromRGB(40, 110, 60) else Color3.fromRGB(170, 70, 30)
	firmBox.Visible = state.facilityType == "LawOffice"
	helpLabel.Text = HELP[state.mode] or ""
	-- type buttons for the current tool
	for _, b in typeButtons do
		b:Destroy()
	end
	table.clear(typeButtons)
	local options, current, setter = typeOptions()
	for _, v in options or {} do
		local b = button(typeRow, v, function()
			setter(v)
			refreshUI()
		end)
		b.BackgroundColor3 = if v == current then ON else BTN
		table.insert(typeButtons, b)
	end
	heightButton.Text = "Height " .. state.height
	securityButton.Text = "Security: " .. state.security
	flattenButton.Text = if state.flatten then "Flat floor: on" else "Flat floor: off"
	doorTypeButton.Text = "Door: " .. state.doorType
	accessButton.Text = "Access: " .. state.access
	routeButton.Text = "Route: " .. state.routeType
	overlayButton.Text = if state.overlay then "Overlay: on" else "Overlay: off"
	labelsButton.Text = if state.labels then "Labels: on" else "Labels: off"
	local sel = state.selected
	selectedLabel.Text = if sel and sel.Parent then "Selected: " .. sel:GetFullName() else "Selected: none"
	local pendingText = if #state.pending > 0 then ("  |  %d point(s) placed"):format(#state.pending) else ""
	statusLabel.Text = ("Tool: %s%s"):format(state.mode, pendingText)
end

toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toggleButton:SetActive(widget.Enabled)
	if widget.Enabled then
		redraw()
	else
		setMode("Off")
		overlay:ClearAllChildren()
	end
end)
plugin.Unloading:Connect(function()
	if overlay then
		overlay:Destroy()
	end
	hoverBox:Destroy()
end)

refreshUI()
if widget.Enabled then
	redraw()
end
print("[FacilityMapper] loaded - click 'Facility Mapper' in the Plugins tab")
