-- Builds workspace.Courthouse (run once in Studio's Edit datamodel; v263).
-- Modelled on the courthouse in 12 Angry Men (1957) - the New York County Courthouse at
-- 60 Centre Street: the grand staircase and the giant Corinthian portico of the opening
-- shot, the marble rotunda, the courtroom and the jury room.
--
-- A REAL TWO-STOREY BUILDING behind the facade (local: x = depth, back -88 .. front +88;
-- z = width -116 .. 116; front = +X). Ground F0..F1 (32 high), upper F1..ROOF (48 high).
--   front    grand staircase (18 x 0.5-stud steps) -> portico -> 3 bronze doors -> VESTIBULE
--   centre   THE ROTUNDA: a circular drum (r 34) with a ring of green marble columns carrying a
--            circular gallery at the upper floor, an upper order of columns, clerestory windows
--            above the roof, and a REAL hollow coffered dome with an oculus and lantern
--            THE STAIR HALL: an imperial staircase - central flight to a landing (Lady Justice in a
--            niche), twin return flights up to a bridge into the rotunda gallery
--   both floors  corridors z +-(40..52) the whole depth; rooms beyond them
--   ground   Clerk | Records | Restrooms | Jury Assembly || Law Library | Attorney Conf A, B |
--            Witness Waiting | Court Officers || back: sally port, holding cells, secure stair
--   upper    MAIN COURTROOM | Jury Room | Press Room || Judge's Chambers | Robing | Courtroom Dept. 2 |
--            Witness Room || back: court holding || front: the upper hall behind the portico
-- The build checks every room (and the trial routes) with PathfindingService.
--
-- Markers (CourtMarkers): JudgeSeat, WitnessSeat, DefendantSeat, DefenseSeat, ProsecutorSeat,
--   JurorSeat1-12, GallerySeat1-n, JuryRoomSeat1-12 | BailiffSpot, ClerkWindow, ClerkSpot,
--   MetalDetector, CourthouseSteps, VehicleDropoff, PrisonerDropoff, HoldingSpot, JuryRoomSpot,
--   ChambersSpot, RotundaSpot, Room_<name> (the middle of every room)
-- Placed on the user's lot (Workspace["Caesars Palace2"].FacilityMap Courtroom zone:
-- x 1700..2267, z -1810..-1501). Local +X = world +Z (the north road).
do
	local prev = workspace:FindFirstChild("Courthouse")
	if prev then prev:Destroy() end -- before the ground ray, or it lands on the old roof
end
local CENTER = Vector3.new(1983.7, 0, -1665)
local GROUND = workspace:Raycast(CENTER + Vector3.new(0, 600, 0), Vector3.new(0, -700, 0))
local GY = if GROUND then GROUND.Position.Y else 1
local BASE = CFrame.new(CENTER.X, GY, CENTER.Z) * CFrame.Angles(0, math.rad(-90), 0)

local FY = 9 -- podium height: the floor is this far above the street
local HX, HZ = 88, 116 -- half depth / half width of the building
local IH = 30 -- inside height of the ordinary rooms

local model = Instance.new("Model")
model.Name = "Courthouse"
local markers = Instance.new("Folder")
markers.Name = "CourtMarkers"
markers.Parent = model
local groups: { [string]: Model } = {}
local current: Instance = model
local function group(name: string)
	local g = groups[name]
	if not g then
		g = Instance.new("Model")
		g.Name = name
		g.Parent = model
		groups[name] = g
	end
	current = g
end

local C = {
	marble = Color3.fromRGB(240, 237, 230), marbleWarm = Color3.fromRGB(232, 226, 212), marbleGrey = Color3.fromRGB(204, 200, 192),
	marbleDark = Color3.fromRGB(58, 56, 54), marbleGreen = Color3.fromRGB(56, 82, 70), granite = Color3.fromRGB(150, 146, 140),
	plaster = Color3.fromRGB(236, 230, 214), panel = Color3.fromRGB(96, 60, 34), panelDark = Color3.fromRGB(62, 38, 22),
	wood = Color3.fromRGB(122, 80, 46), glass = Color3.fromRGB(190, 210, 222), bronze = Color3.fromRGB(150, 110, 60),
	brass = Color3.fromRGB(204, 168, 88), roof = Color3.fromRGB(110, 140, 128), jury = Color3.fromRGB(206, 200, 176),
	black = Color3.fromRGB(26, 26, 28), light = Color3.fromRGB(255, 240, 210), tile = Color3.fromRGB(214, 220, 222),
	leather = Color3.fromRGB(90, 40, 30), green = Color3.fromRGB(46, 90, 60), books = Color3.fromRGB(120, 40, 36),
}
local M = Enum.Material

---------------------------------------------------------------------------
-- part helpers
---------------------------------------------------------------------------
local function put(p: BasePart, cf: CFrame, color: Color3, material: Enum.Material?, parent: Instance?): BasePart
	p.Anchored = true
	p.CFrame = BASE * cf
	p.Color = color
	p.Material = material or M.Marble
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent or current
	return p
end

local function block(name: string, size: Vector3, pos: Vector3, color: Color3?, material: Enum.Material?, rotY: number?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	put(p, CFrame.new(pos) * CFrame.Angles(0, rotY or 0, 0), color or C.marble, material)
	return p
end

-- decoration that players shouldn't snag on
local function deco(name: string, size: Vector3, pos: Vector3, color: Color3?, material: Enum.Material?, rotY: number?): Part
	local p = block(name, size, pos, color, material, rotY)
	p.CanCollide = false
	return p
end

local function cylinder(name: string, length: number, diameter: number, pos: Vector3, color: Color3?, material: Enum.Material?, axis: string?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(length, diameter, diameter)
	local rot = if axis == "x" then CFrame.identity elseif axis == "z" then CFrame.Angles(0, math.rad(90), 0) else CFrame.Angles(0, 0, math.rad(90))
	put(p, CFrame.new(pos) * rot, color or C.marble, material)
	return p
end

local function ball(name: string, d: number, pos: Vector3, color: Color3?, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(d, d, d)
	put(p, CFrame.new(pos), color or C.marble, material)
	return p
end

local function wedge(name: string, size: Vector3, cf: CFrame, color: Color3?, material: Enum.Material?): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Size = size
	put(w, cf, color or C.marble, material)
	return w
end

local function light(part: BasePart, range: number, brightness: number?)
	local l = Instance.new("PointLight")
	l.Range = range * 0.7
	l.Brightness = (brightness or 1.1) * 0.35 -- marble is bright: lights stay soft
	l.Color = Color3.fromRGB(255, 232, 196)
	l.Shadows = false
	l.Parent = part
end

local function lamp(pos: Vector3, range: number, brightness: number?)
	local g = ball("Light", 1.8, pos, C.light, M.Neon)
	g.CanCollide = false
	light(g, range, brightness)
end

local function marker(name: string, pos: Vector3)
	local p = block(name, Vector3.one, pos, Color3.new(1, 1, 0))
	p.Transparency = 1
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	p.Parent = markers
	return p
end

local function chair(name: string, pos: Vector3, face: Vector3, color: Color3?, noBack: boolean?)
	local s = Instance.new("Seat")
	s.Name = name
	s.Size = Vector3.new(2.2, 0.6, 2.2)
	put(s, CFrame.lookAt(pos, pos + face), color or C.panelDark, M.Wood, markers)
	if not noBack then
		local back = Instance.new("Part")
		back.Name = name .. "Back"
		back.Size = Vector3.new(2.08, 2.6, 0.35) -- narrower than the seat: no shared side planes
		back.CanCollide = false
		put(back, CFrame.lookAt(pos, pos + face) * CFrame.new(0, 1.5, 1.05), color or C.panelDark, M.Wood)
	end
	return s
end

---------------------------------------------------------------------------
-- walls: wallX = a wall along z at a fixed x; wallZ = along x at a fixed z.
-- openings = { { centre, width, sill?, head? } } - with a sill it's a window, else a doorway
---------------------------------------------------------------------------
local F0 = FY + 0.6 -- the floor surface
local function runWall(name: string, fixed: number, a: number, b: number, alongX: boolean, h: number, openings: { { number } }?, color: Color3?, material: Enum.Material?, thick: number?, y0: number?)
	local base = y0 or F0
	local th = thick or 1.4
	local col, mat = color or C.plaster, material or M.Plaster
	local function seg(s: number, e: number, ya: number, yb: number, nm: string, c: Color3, m: Enum.Material, tr: number?, t: number?)
		if e - s < 0.05 or yb - ya < 0.05 then return end
		local mid = (s + e) / 2
		local size = if alongX then Vector3.new(e - s, yb - ya, t or th) else Vector3.new(t or th, yb - ya, e - s)
		local pos = if alongX then Vector3.new(mid, (ya + yb) / 2, fixed) else Vector3.new(fixed, (ya + yb) / 2, mid)
		local p = block(nm, size, pos, c, m)
		if tr then p.Transparency = tr end
	end
	local cuts = {}
	for _, o in openings or {} do table.insert(cuts, o) end
	table.sort(cuts, function(x, y) return x[1] < y[1] end)
	local at = math.min(a, b)
	local stop = math.max(a, b)
	for _, o in cuts do
		local s, e = o[1] - o[2] / 2, o[1] + o[2] / 2
		seg(at, s, base, base + h, name, col, mat)
		local sill, head = o[3], o[4] or (if o[3] then h - 6 else math.min(12, h))
		if sill then
			seg(s, e, base, base + sill, name, col, mat)
			seg(s, e, base + sill, base + head, name .. "Window", C.glass, M.Glass, 0.5, 0.3)
			seg(s - 0.8, e + 0.8, base + sill - 0.6, base + sill, name .. "Sill", C.marbleGrey, M.Marble, nil, th + 1)
			seg(s - 0.8, e + 0.8, base + head, base + head + 1.2, name .. "Head", C.marbleGrey, M.Marble, nil, th + 1)
		else
			-- a doorway: a marble frame round it
			local jamb = if alongX then function(z: number) return Vector3.new(z, base + head / 2, fixed) end else function(z: number) return Vector3.new(fixed, base + head / 2, z) end
			for _, edge in { s - 0.35, e + 0.35 } do
				deco(name .. "Jamb", if alongX then Vector3.new(0.7, head, th + 0.6) else Vector3.new(th + 0.6, head, 0.7), jamb(edge), C.marbleGrey)
			end
		end
		seg(s, e, base + head, base + h, name, col, mat)
		at = e
	end
	seg(at, stop, base, base + h, name, col, mat)
end
local function wallX(name: string, x: number, z0: number, z1: number, h: number, openings: { { number } }?, color: Color3?, material: Enum.Material?, thick: number?)
	runWall(name, x, z0, z1, false, h, openings, color, material, thick)
end
local function wallZ(name: string, z: number, x0: number, x1: number, h: number, openings: { { number } }?, color: Color3?, material: Enum.Material?, thick: number?)
	runWall(name, z, x0, x1, true, h, openings, color, material, thick)
end
-- a room's ceiling (and a light), plus the Room_ marker
local function room(name: string, x0: number, x1: number, z0: number, z1: number, h: number, ceilingColor: Color3?, floorColor: Color3?, floorMat: Enum.Material?)
	block(name .. "Ceiling", Vector3.new(x1 - x0, 0.8, z1 - z0), Vector3.new((x0 + x1) / 2, F0 + h + 0.4, (z0 + z1) / 2), ceilingColor or C.plaster, M.Plaster)
	if floorColor then
		deco(name .. "Floor", Vector3.new(x1 - x0 - 0.4, 0.1, z1 - z0 - 0.4), Vector3.new((x0 + x1) / 2, F0 + 0.05, (z0 + z1) / 2), floorColor, floorMat or M.WoodPlanks)
	end
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local nx = math.max(1, math.floor((x1 - x0) / 26))
	local nz = math.max(1, math.floor((z1 - z0) / 26))
	for i = 0, nx - 1 do
		for k = 0, nz - 1 do
			lamp(Vector3.new(x0 + (i + 0.5) * (x1 - x0) / nx, F0 + h - 1.5, z0 + (k + 0.5) * (z1 - z0) / nz), 30)
		end
	end
	marker("Room_" .. name, Vector3.new(cx, F0 + 3, cz))
end

---------------------------------------------------------------------------
-- ornaments: column, lamp standard, statue
---------------------------------------------------------------------------
local function column(x: number, y0: number, z: number, h: number, d: number, color: Color3?)
	local col = color or C.marble
	block("Plinth", Vector3.new(d * 1.45, 1.6, d * 1.45), Vector3.new(x, y0 + 0.8, z), col)
	cylinder("BaseTorus", 1.2, d * 1.3, Vector3.new(x, y0 + 2.2, z), col)
	cylinder("BaseTorus", 0.8, d * 1.15, Vector3.new(x, y0 + 3.2, z), col)
	local capH = d * 1.1
	local shaftH = h - 3.6 - capH
	cylinder("Shaft", shaftH, d, Vector3.new(x, y0 + 3.6 + shaftH / 2, z), col)
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2
		deco("Flute", Vector3.new(0.28, shaftH * 0.94, d * 0.12), Vector3.new(x + math.cos(a) * d / 2, y0 + 3.6 + shaftH / 2, z + math.sin(a) * d / 2), col:Lerp(Color3.new(), 0.08), M.Marble, -a)
	end
	local top = y0 + 3.6 + shaftH
	cylinder("Necking", 0.6, d * 1.04, Vector3.new(x, top + 0.3, z), col)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		wedge("Acanthus", Vector3.new(d * 0.32, capH * 0.5, 0.9), CFrame.new(x + math.cos(a) * d * 0.5, top + capH * 0.3, z + math.sin(a) * d * 0.5) * CFrame.Angles(0, -a + math.rad(90), 0), C.marbleWarm).CanCollide = false
		local a2 = a + math.pi / 8
		wedge("Acanthus", Vector3.new(d * 0.3, capH * 0.5, 0.9), CFrame.new(x + math.cos(a2) * d * 0.56, top + capH * 0.62, z + math.sin(a2) * d * 0.56) * CFrame.Angles(0, -a2 + math.rad(90), 0), C.marbleWarm).CanCollide = false
	end
	cylinder("Bell", capH * 0.85, d * 1.02, Vector3.new(x, top + capH * 0.45, z), col)
	for _, dx in { -1, 1 } do
		for _, dz in { -1, 1 } do
			cylinder("Volute", 0.8, d * 0.34, Vector3.new(x + dx * d * 0.62, top + capH * 0.82, z + dz * d * 0.62), C.marbleWarm, M.Marble, "z").CanCollide = false
		end
	end
	block("Abacus", Vector3.new(d * 1.5, 1, d * 1.5), Vector3.new(x, top + capH + 0.5, z), col)
end

local function lampStandard(x: number, y0: number, z: number)
	block("LampPlinth", Vector3.new(4, 5, 4), Vector3.new(x, y0 + 2.5, z), C.granite, M.Granite)
	cylinder("LampPost", 14, 0.9, Vector3.new(x, y0 + 12, z), C.bronze, M.Metal)
	cylinder("LampRing", 0.6, 2, Vector3.new(x, y0 + 7, z), C.bronze, M.Metal)
	for i = 0, 3 do
		local a = i * math.pi / 2
		deco("LampArm", Vector3.new(3, 0.4, 0.4), Vector3.new(x + math.cos(a) * 1.5, y0 + 17.5 + i * 0.06, z + math.sin(a) * 1.5), C.bronze, M.Metal, -a)
		ball("LampGlobe", 1.8, Vector3.new(x + math.cos(a) * 3, y0 + 18.4, z + math.sin(a) * 3), C.light, M.Neon).CanCollide = false
	end
	light(ball("LampGlobe", 2.4, Vector3.new(x, y0 + 20, z), C.light, M.Neon), 34, 1.4)
end

local function statue(name: string, x: number, y0: number, z: number, s: number, justice: boolean?)
	local col = C.marbleWarm
	block(name .. "Pedestal", Vector3.new(4 * s, 1.6 * s, 4 * s), Vector3.new(x, y0 + 0.8 * s, z), C.marble)
	cylinder(name .. "Robe", 6 * s, 2.6 * s, Vector3.new(x, y0 + 4.6 * s, z), col)
	cylinder(name .. "Torso", 2.6 * s, 2 * s, Vector3.new(x, y0 + 8.7 * s, z), col)
	ball(name .. "Head", 1.5 * s, Vector3.new(x, y0 + 10.7 * s, z), col)
	if justice then
		block(name .. "Sword", Vector3.new(0.25 * s, 5 * s, 0.25 * s), Vector3.new(x, y0 + 6 * s, z + 1.3 * s), C.brass, M.Metal)
		block(name .. "ArmUp", Vector3.new(0.5 * s, 3.4 * s, 0.5 * s), Vector3.new(x, y0 + 10.6 * s, z - 1.3 * s), col)
		block(name .. "Beam", Vector3.new(3.2 * s, 0.2 * s, 0.2 * s), Vector3.new(x, y0 + 12.4 * s, z - 1.3 * s), C.brass, M.Metal)
		for _, dx in { -1.5, 1.5 } do
			cylinder(name .. "Pan", 0.2 * s, 1.2 * s, Vector3.new(x + dx * s, y0 + 11.2 * s, z - 1.3 * s), C.brass, M.Metal)
		end
		block(name .. "Blindfold", Vector3.new(1.55 * s, 0.35 * s, 1.55 * s), Vector3.new(x, y0 + 10.9 * s, z), C.marbleGrey)
	end
end

---------------------------------------------------------------------------
-- THE GRAND ENTRY: podium, staircase, portico, pediment
---------------------------------------------------------------------------
group("Entry")
local FRONT = HX
local PORT_X = FRONT + 22 -- the column line
local PORT_W = 212 -- the portico's width (z)
block("Podium", Vector3.new(2 * HX + 2, FY, 2 * HZ + 2), Vector3.new(0, FY / 2, 0), C.granite, M.Granite)
block("PortGround", Vector3.new(PORT_X - FRONT + 8, FY, PORT_W + 8), Vector3.new((FRONT + PORT_X + 8) / 2, FY / 2, 0), C.granite, M.Granite)
block("PortFloor", Vector3.new(PORT_X - FRONT + 8, 0.6, PORT_W + 8), Vector3.new((FRONT + PORT_X + 8) / 2, FY + 0.3, 0), C.marble)
-- the staircase: 18 even steps (0.5 up, 2.4 deep) the whole width of the portico
local STEPS, RUN = 18, 2.4
local STAIR_X0 = PORT_X + 8 -- the top step meets the portico floor here
local STAIR_W = 196
for i = 1, STEPS do
	local h = FY + 0.6 - (FY + 0.6) * (i - 1) / STEPS -- the first step is the portico floor height
	h = (FY + 0.6) * (STEPS - i + 1) / (STEPS + 1)
	local x = STAIR_X0 + (i - 0.5) * RUN
	block("Step", Vector3.new(RUN, h, STAIR_W), Vector3.new(x, h / 2, 0), C.marble)
	deco("StepNose", Vector3.new(0.34, 0.24, STAIR_W + 0.1), Vector3.new(x + RUN / 2 - 0.13, h - 0.08, 0), C.marbleGrey) -- proud of tread and riser
end
local STAIR_END = STAIR_X0 + STEPS * RUN
-- granite cheek walls either side, with the bronze lamp standards
for _, side in { -1, 1 } do
	local z = side * (STAIR_W / 2 + 3)
	wedge("StairCheek", Vector3.new(6, FY + 1.6, STEPS * RUN), CFrame.new(STAIR_X0 + STEPS * RUN / 2, (FY + 1.6) / 2, z) * CFrame.Angles(0, math.rad(-90), 0), C.granite, M.Granite)
	lampStandard(STAIR_END - 3, 0, z)
	lampStandard(STAIR_X0 - 2, FY + 0.6, side * (PORT_W / 2 - 2))
end
marker("CourthouseSteps", Vector3.new(STAIR_X0 - 4, F0 + 3, 0))
marker("VehicleDropoff", Vector3.new(STAIR_END + 14, 3, 0))

-- ten fluted Corinthian columns, pilasters behind, and the portico's end walls (antae)
local COL_H, COL_D = 70, 5.6
for i = 0, 9 do
	column(PORT_X, F0, -90 + i * 20, COL_H, COL_D)
	deco("Pilaster", Vector3.new(1.2, COL_H - 6, 4.5), Vector3.new(FRONT + 2.2, F0 + (COL_H - 6) / 2, -90 + i * 20), C.marbleWarm)
	deco("PilasterCap", Vector3.new(1.8, 3, 5.6), Vector3.new(FRONT + 2.4, F0 + COL_H - 4.5, -90 + i * 20), C.marbleWarm)
end
for _, side in { -1, 1 } do
	block("Anta", Vector3.new(PORT_X - FRONT + 8, COL_H + 14, 6), Vector3.new((FRONT + PORT_X + 8) / 2, F0 + (COL_H + 14) / 2, side * (PORT_W / 2 + 1)), C.marble)
end
local ENT_Y = F0 + COL_H
local ENT_W = PORT_W + 8
block("Architrave", Vector3.new(PORT_X - FRONT + 8, 4, ENT_W), Vector3.new((FRONT + PORT_X) / 2 + 2, ENT_Y + 2, 0), C.marble)
deco("ArchitraveBand", Vector3.new(0.6, 0.8, ENT_W), Vector3.new(PORT_X + 6.3, ENT_Y + 3.2, 0), C.marbleGrey)
block("Frieze", Vector3.new(PORT_X - FRONT + 8, 6, ENT_W), Vector3.new((FRONT + PORT_X) / 2 + 2, ENT_Y + 7, 0), C.marbleWarm)
do
	local plate = deco("FriezeText", Vector3.new(180, 3.6, 0.3), Vector3.new(PORT_X + 6.2, ENT_Y + 7, 0), C.marbleWarm, M.Marble, math.rad(90))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.Parent = plate
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.Garamond
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(96, 88, 76)
	t.Text = "THE TRUE ADMINISTRATION OF JUSTICE IS THE FIRMEST PILLAR OF GOOD GOVERNMENT"
	t.Parent = gui
end
for i = 0, 107 do
	deco("Dentil", Vector3.new(1.2, 1.2, 1), Vector3.new(PORT_X + 6.2, ENT_Y + 10.6, -107 + i * 2), C.marble)
end
block("Cornice", Vector3.new(PORT_X - FRONT + 12, 2.4, ENT_W + 6), Vector3.new((FRONT + PORT_X) / 2 + 3, ENT_Y + 12.2, 0), C.marble)
local PED_Y, PED_RISE, PED_SPAN = ENT_Y + 13.4, 28, ENT_W + 6
for side = -1, 1, 2 do
	wedge("Tympanum", Vector3.new(PORT_X - FRONT + 6, PED_RISE, PED_SPAN / 2),
		CFrame.new((FRONT + PORT_X) / 2 + 2, PED_Y + PED_RISE / 2, side * PED_SPAN / 4) * CFrame.Angles(0, if side > 0 then math.rad(180) else 0, 0), C.marbleWarm)
	local slope = math.atan2(PED_RISE, PED_SPAN / 2)
	local len = math.sqrt(PED_RISE ^ 2 + (PED_SPAN / 2) ^ 2)
	local rc = block("RakingCornice", Vector3.new(PORT_X - FRONT + 11, 2.2, len + 2), Vector3.zero, C.marble)
	rc.CFrame = BASE * CFrame.new((FRONT + PORT_X) / 2 + 3, PED_Y + PED_RISE / 2 + 1, side * PED_SPAN / 4) * CFrame.Angles(side * slope, 0, 0)
end
do
	local x = PORT_X + 5.4
	deco("ReliefBeam", Vector3.new(0.6, 0.8, 20), Vector3.new(x, PED_Y + 14, 0), C.bronze, M.Metal)
	deco("ReliefPost", Vector3.new(0.6, 11, 0.8), Vector3.new(x, PED_Y + 8.5, 0), C.bronze, M.Metal)
	for _, z in { -9, 9 } do
		cylinder("ReliefPan", 0.6, 5.5, Vector3.new(x, PED_Y + 8, z), C.bronze, M.Metal, "x").CanCollide = false
		deco("ReliefChain", Vector3.new(0.4, 5.5, 0.3), Vector3.new(x, PED_Y + 11.2, z), C.bronze, M.Metal)
	end
end
statue("LadyJustice", (FRONT + PORT_X) / 2 + 2, PED_Y + PED_RISE - 1, 0, 1.8, true)
statue("Acroterion", (FRONT + PORT_X) / 2 + 2, PED_Y - 1, -PED_SPAN / 2 + 4, 1.3)
statue("Acroterion", (FRONT + PORT_X) / 2 + 2, PED_Y - 1, PED_SPAN / 2 - 4, 1.3)
block("PorticoCeiling", Vector3.new(PORT_X - FRONT + 8, 1.2, PORT_W), Vector3.new((FRONT + PORT_X + 8) / 2, ENT_Y - 0.6, 0), C.marbleWarm)
for xi = 0, 2 do
	for zi = 0, 16 do
		local cx, cz = FRONT + 5 + xi * 7, -96 + zi * 12
		deco("Coffer", Vector3.new(5.5, 0.8, 9.5), Vector3.new(cx, ENT_Y - 1.6, cz), C.marbleGrey)
		cylinder("Rosette", 0.4, 1.6, Vector3.new(cx, ENT_Y - 2.1, cz), C.brass, M.Metal).CanCollide = false
	end
end
for i = 0, 4 do
	cylinder("LanternChain", 8, 0.25, Vector3.new(FRONT + 12, ENT_Y - 5, -80 + i * 40), C.bronze, M.Metal).CanCollide = false
	local l = ball("PorticoLantern", 2.6, Vector3.new(FRONT + 12, ENT_Y - 10, -80 + i * 40), C.light, M.Neon)
	l.CanCollide = false
	light(l, 40, 1.3)
end

---------------------------------------------------------------------------
-- THE BUILDING BEHIND THE FACADE - two real storeys
--   ground  F0 .. F1 (32)   upper  F1 .. ROOF (48)
--   central band z -40..40: VESTIBULE (x 70..88) | ROTUNDA (circle, centre x 35, r 34) |
--                           STAIR HALL (x -47..1, the imperial staircase) | BACK BLOCK (x -88..-47)
--   corridors z +-(40..52) on both floors, the whole depth; rooms z +-(52..116)
---------------------------------------------------------------------------
local F1 = F0 + 32 -- the upper floor
local ROOF = F0 + 80 -- underside of the roof
local SH = ROOF - F0
local GH = 32 - 1.2 -- ground-floor walls stop at the underside of the upper floor slab (no shared top plane)
local BAND, CORR = 40, 12
local WING = BAND + CORR -- 52: where the rooms start
local RCX, RR = 35, 34 -- rotunda centre (x) and inner radius
local SX0, SX1 = -47, 1 -- the stair hall
local BX1 = SX0 -- the back block: x -88..-47

-- walls with a base height (upper storey)
local function wallXAt(name: string, y0: number, x: number, z0: number, z1: number, h: number, openings: { { number } }?, color: Color3?, material: Enum.Material?, thick: number?)
	runWall(name, x, z0, z1, false, h, openings, color, material, thick, y0)
end
local function wallZAt(name: string, y0: number, z: number, x0: number, x1: number, h: number, openings: { { number } }?, color: Color3?, material: Enum.Material?, thick: number?)
	runWall(name, z, x0, x1, true, h, openings, color, material, thick, y0)
end
-- a room on a storey: floor finish, ceiling lights, its marker (the ceiling is the slab above)
local function roomAt(name: string, y0: number, h: number, x0: number, x1: number, z0: number, z1: number, floorColor: Color3?, floorMat: Enum.Material?, markerPos: Vector3?)
	if floorColor then
		deco(name .. "Floor", Vector3.new(x1 - x0 - 0.6, 0.12, z1 - z0 - 0.6), Vector3.new((x0 + x1) / 2, y0 + 0.06, (z0 + z1) / 2), floorColor, floorMat or M.WoodPlanks)
	end
	local nx = math.max(1, math.floor((x1 - x0) / 24))
	local nz = math.max(1, math.floor((z1 - z0) / 24))
	for i = 0, nx - 1 do
		for k = 0, nz - 1 do
			local p = Vector3.new(x0 + (i + 0.5) * (x1 - x0) / nx, y0 + h - 1.2, z0 + (k + 0.5) * (z1 - z0) / nz)
			deco("CeilingRose", Vector3.new(3, 0.3, 3), p + Vector3.new(0, 0.9, 0), C.marbleWarm)
			lamp(p, 30)
		end
	end
	marker("Room_" .. name, markerPos or Vector3.new((x0 + x1) / 2, y0 + 3, (z0 + z1) / 2))
end

---------------------------------------------------------------------------
-- SHELL: outer walls (two rows of windows), cornices, attic, roof (with the drum's hole)
---------------------------------------------------------------------------
group("Shell")
local function windowRow(a: number, b: number, every: number, sill: number, head: number, skip: { { number } }?): { { number } }
	local g = {}
	local n = math.floor((b - a) / every)
	local start = a + ((b - a) - (n - 1) * every) / 2
	for i = 0, n - 1 do
		local c = start + i * every
		local ok = true
		for _, s in skip or {} do
			if math.abs(c - s[1]) < s[2] then ok = false end
		end
		if ok then table.insert(g, { c, 7, sill, head }) end
	end
	return g
end
-- front wall: the three bronze doorways below, tall windows above (behind the portico)
local DOORS = { { -32, 12, 26 }, { 0, 14, 30 }, { 32, 12, 26 } }
do
	local o = {}
	for _, d in DOORS do table.insert(o, { d[1], d[2], nil, d[3] }) end
	for _, z in { -96, -76, -60, 60, 76, 96 } do table.insert(o, { z, 7, 8, 24 }) end -- ground windows of the wings
	wallXAt("FrontWallLow", F0, FRONT, -HZ, HZ, GH, o, C.marble, M.Marble, 3)
	wallXAt("FrontWallHigh", F1, FRONT, -HZ, HZ, SH - 32, windowRow(-HZ, HZ, 20, 8, 34), C.marble, M.Marble, 3)
	for _, d in DOORS do
		local z, w, top = d[1], d[2], d[3]
		-- the leaves stand open, folded flat against the inside of the front wall (the side doors'
		-- leaves both fold toward the middle - the side walls are too close on the outside)
		local spots = if z == 0 then { -(w * 0.75 + 0.1), w * 0.75 + 0.1 } else { -math.sign(z) * (w * 0.75 + 0.1), -math.sign(z) * (w * 1.25 + 0.2) }
		for _, dz in spots do
			deco("BronzeDoor", Vector3.new(0.5, top - 6, w / 2), Vector3.new(FRONT - 1.85, F0 + (top - 6) / 2, z + dz), C.bronze, M.Metal)
			deco("DoorPanel", Vector3.new(0.2, (top - 6) * 0.4, w / 2 - 1.2), Vector3.new(FRONT - 2.2, F0 + (top - 6) * 0.7, z + dz), C.brass, M.Metal)
			deco("DoorPanel", Vector3.new(0.2, (top - 6) * 0.4, w / 2 - 1.2), Vector3.new(FRONT - 2.2, F0 + (top - 6) * 0.27, z + dz), C.brass, M.Metal)
		end
		local tr = deco("Transom", Vector3.new(0.4, 5, w), Vector3.new(FRONT, F0 + top - 3, z), C.bronze, M.DiamondPlate)
		tr.Transparency = 0.25
		deco("DoorHead", Vector3.new(4, 2.4, w + 4), Vector3.new(FRONT + 1.6, F0 + top + 1.2, z), C.marbleGrey)
		deco("DoorPediment", Vector3.new(4.6, 1.2, w + 6), Vector3.new(FRONT + 2, F0 + top + 3, z), C.marble)
	end
end
-- back wall: the prisoner sally port, the judges' private entrance, windows
do
	local low = windowRow(-HZ, HZ, 20, 8, 24, { { -20, 12 }, { 86, 10 } })
	table.insert(low, { -20, 14, nil, 16 }) -- sally port
	table.insert(low, { 86, 8, nil, 14 }) -- staff door into the north corridor
	wallXAt("BackWallLow", F0, -HX, -HZ, HZ, GH, low, C.marble, M.Marble, 3)
	wallXAt("BackWallHigh", F1, -HX, -HZ, HZ, SH - 32, windowRow(-HZ, HZ, 20, 8, 34), C.marble, M.Marble, 3)
	deco("SallyPortSign", Vector3.new(0.4, 2, 14), Vector3.new(-HX - 1.8, F0 + 17.5, -20), C.black, M.DiamondPlate)
	block("SallyDock", Vector3.new(10, FY, 20), Vector3.new(-HX - 5, FY / 2, -20), C.granite, M.Concrete)
	for i = 1, 18 do
		local h = FY * (18 - i + 1) / 19
		block("SallyStep", Vector3.new(1.4, h, 20), Vector3.new(-HX - 10 - (i - 0.5) * 1.4, h / 2, -20), C.granite, M.Concrete)
	end
	marker("PrisonerDropoff", Vector3.new(-HX - 46, 3, -20))
	block("StaffLanding", Vector3.new(6, FY, 10), Vector3.new(-HX - 3, FY / 2, 86), C.granite, M.Concrete)
	for i = 1, 18 do
		local h = FY * (18 - i + 1) / 19
		block("StaffStep", Vector3.new(1.4, h, 10), Vector3.new(-HX - 6 - (i - 0.5) * 1.4, h / 2, 86), C.granite, M.Concrete)
	end
end
-- the side walls
for _, s in { { "SideWallS", -HZ }, { "SideWallN", HZ } } do
	wallZAt(s[1] .. "Low", F0, s[2], -HX, HX, GH, windowRow(-HX, HX, 18, 8, 24), C.marble, M.Marble, 3)
	wallZAt(s[1] .. "High", F1, s[2], -HX, HX, SH - 32, windowRow(-HX, HX, 18, 8, 36), C.marble, M.Marble, 3)
end
for k = 0, 3 do
	local y = FY + 2 + k * 2.4
	deco("Rustication", Vector3.new(0.4, 0.4, 2 * HZ), Vector3.new(-HX - 1.7, y, 0), C.marbleGrey)
	deco("Rustication", Vector3.new(2 * HX, 0.4, 0.4), Vector3.new(0, y, -HZ - 1.7), C.marbleGrey)
	deco("Rustication", Vector3.new(2 * HX, 0.4, 0.4), Vector3.new(0, y, HZ + 1.7), C.marbleGrey)
end
deco("StringCourseS", Vector3.new(2 * HX + 4, 1.4, 1.4), Vector3.new(0, F1 - 0.5, -HZ - 1.4), C.marbleWarm)
deco("StringCourseN", Vector3.new(2 * HX + 4, 1.4, 1.4), Vector3.new(0, F1 - 0.5, HZ + 1.4), C.marbleWarm)
deco("StringCourseB", Vector3.new(1.4, 1.4, 2 * HZ + 4), Vector3.new(-HX - 1.4, F1 - 0.5, 0), C.marbleWarm)
deco("StringCourseF", Vector3.new(1.4, 1.4, 2 * HZ + 4), Vector3.new(HX + 1.4, F1 - 0.5, 0), C.marbleWarm)
-- cornices run round the edge of the roof only (a slab here would cap the rotunda)
local function edgeFrame(name: string, y: number, h: number, out: number, depth: number, color: Color3)
	block(name, Vector3.new(2 * HX + 2 * out, h, depth), Vector3.new(0, y, -HZ - out + depth / 2), color)
	block(name, Vector3.new(2 * HX + 2 * out, h, depth), Vector3.new(0, y, HZ + out - depth / 2), color)
	block(name, Vector3.new(depth, h, 2 * HZ + 2 * out - 2 * depth), Vector3.new(-HX - out + depth / 2, y, 0), color)
	block(name, Vector3.new(depth, h, 2 * HZ + 2 * out - 2 * depth), Vector3.new(HX + out - depth / 2, y, 0), color)
end
edgeFrame("MainCornice", ROOF + 1.5, 3, 4, 10, C.marble)
-- attic + roof as a frame round the drum's hole (x 1..69, z -40..40)
do
	local function roofRect(x0: number, x1: number, z0: number, z1: number)
		block("Attic", Vector3.new(x1 - x0, 6, z1 - z0), Vector3.new((x0 + x1) / 2, ROOF + 6, (z0 + z1) / 2), C.marbleWarm)
		block("Roof", Vector3.new(x1 - x0, 1.2, z1 - z0), Vector3.new((x0 + x1) / 2, ROOF + 9.6, (z0 + z1) / 2), C.roof, M.Slate)
	end
	roofRect(-HX, RCX - RR, -HZ, HZ)
	roofRect(RCX + RR, HX, -HZ, HZ)
	roofRect(RCX - RR, RCX + RR, -HZ, -BAND)
	roofRect(RCX - RR, RCX + RR, BAND, HZ)
	edgeFrame("AtticCornice", ROOF + 9, 1.4, 2, 6, C.marble)
end
block("GroundFloor", Vector3.new(2 * HX - 3, 0.6, 2 * HZ - 3), Vector3.new(0, FY + 0.3, 0), C.marbleWarm)

---------------------------------------------------------------------------
-- THE UPPER FLOOR SLAB (F1): everywhere except the rotunda and the stair hall's void
---------------------------------------------------------------------------
group("Floors")
local function slab(x0: number, x1: number, z0: number, z1: number)
	block("UpperFloor", Vector3.new(x1 - x0, 1.2, z1 - z0), Vector3.new((x0 + x1) / 2, F1 - 0.6, (z0 + z1) / 2), C.marbleWarm)
end
slab(-HX, HX, BAND, HZ) -- north wing + corridor
slab(-HX, HX, -HZ, -BAND) -- south wing + corridor
slab(-HX, SX0, -BAND, BAND) -- back block
slab(RCX + RR, HX, -BAND, BAND) -- over the vestibule: the upper hall
slab(-4, 1, -BAND, BAND) -- the bridge at the top of the staircase

---------------------------------------------------------------------------
-- THE ROTUNDA: drum, infill, column rings, gallery, the real dome, oculus, lantern
---------------------------------------------------------------------------
group("Rotunda")
local DRUM_TOP = ROOF + 16
local N = 48
local function onCircle(theta: number, r: number, y: number): Vector3
	return Vector3.new(RCX + math.cos(theta) * r, y, math.sin(theta) * r)
end
-- openings in the drum: { centre angle, half-width (studs), y from, y to }
local OPEN = {
	{ 0, 14, F0, F0 + 26 }, { math.pi, 12, F0, F0 + 22 }, -- vestibule (a grand 28 x 26 opening) / stair hall (ground)
	{ math.pi / 2, 5, F0, F0 + 14 }, { -math.pi / 2, 5, F0, F0 + 14 }, -- the corridors (ground)
	{ 0, 6, F1 - 1.2, F1 + 16 }, { math.pi, 8, F1 - 1.2, F1 + 16 }, -- upper hall / the bridge (upper)
	{ math.pi / 2, 5, F1 - 1.2, F1 + 14 }, { -math.pi / 2, 5, F1 - 1.2, F1 + 14 }, -- the upper corridors
}
-- a true ring (not a disc): n flat segments round the rotunda's centre
local function ring(name: string, r: number, width: number, height: number, y: number, color: Color3?, material: Enum.Material?, n: number?)
	local count = n or 48
	for i = 0, count - 1 do
		local th = (i + 0.5) / count * 2 * math.pi
		local p = Instance.new("Part")
		p.Name = name
		p.Size = Vector3.new(width, height + (i % 2) * 0.08, 2 * math.pi * (r + width / 2) / count + 0.3) -- neighbours differ: no shared plane
		p.CanCollide = false
		put(p, CFrame.new(onCircle(th, r, y)) * CFrame.Angles(0, -th, 0), color or C.marble, material)
	end
end
local function angleDiff(a: number, b: number): number
	local d = (a - b) % (2 * math.pi)
	if d > math.pi then d -= 2 * math.pi end
	return math.abs(d)
end
-- the drum wall: segments, cut where a doorway passes, clerestory windows above the roof
local SEG_W = 2 * math.pi * (RR + 1) / N + 0.4
for i = 0, N - 1 do
	local th = (i + 0.5) / N * 2 * math.pi
	local cuts = {}
	for _, o in OPEN do
		if angleDiff(th, o[1]) * (RR + 1) < o[2] then table.insert(cuts, { o[3], o[4] }) end
	end
	table.sort(cuts, function(a, b) return a[1] < b[1] end)
	local function piece(y0: number, y1: number, color: Color3, material: Enum.Material, transparent: number?)
		if y1 - y0 < 0.05 then return end
		local p = Instance.new("Part")
		p.Name = "Drum"
		-- odd columns sit 0.05 higher, so neighbours never share a top / bottom plane
		local shift = (i % 2) * 0.05
		y0, y1 = (if y0 <= F0 + 0.01 then y0 else y0 + shift), y1 + shift
		p.Size = Vector3.new(2, y1 - y0, SEG_W)
		put(p, CFrame.new(onCircle(th, RR + 1, (y0 + y1) / 2)) * CFrame.Angles(0, -th, 0), color, material)
		if transparent then p.Transparency = transparent end
	end
	local y = F0
	local stops = { DRUM_TOP }
	for _, c in cuts do
		piece(y, c[1], C.marbleWarm, M.Marble)
		y = c[2]
	end
	-- above the roof: the clerestory band (every other segment a window)
	if y < ROOF + 3 then
		piece(y, ROOF + 3, C.marbleWarm, M.Marble)
		y = ROOF + 3
	end
	if i % 2 == 0 then
		piece(y, ROOF + 12, C.glass, M.Glass, 0.45)
	else
		piece(y, ROOF + 12, C.marble, M.Marble)
	end
	piece(ROOF + 12, stops[1], C.marble, M.Marble)
end
-- pilasters round the outside of the drum, and its cornice ring
for i = 0, N - 1, 2 do
	local th = (i + 1) / N * 2 * math.pi
	local p = Instance.new("Part")
	p.Name = "DrumPilaster"
	p.Size = Vector3.new(1, DRUM_TOP - ROOF - 10, 2)
	p.CanCollide = false
	put(p, CFrame.new(onCircle(th, RR + 2.4, (ROOF + 10 + DRUM_TOP) / 2)) * CFrame.Angles(0, -th, 0), C.marble)
end
ring("DrumCornice", RR + 3, 4, 2.4, DRUM_TOP + 1.2, C.marble)
ring("DrumInnerCornice", RR - 0.6, 2.2, 1.6, DRUM_TOP - 0.6, C.marbleWarm)
-- solid masonry filling the corners between the circle and the square band (the "poche")
do
	local CELL = 4
	for x = RCX - RR, RCX + RR - CELL, CELL do
		for z = -BAND, BAND - CELL, CELL do
			local cx, cz = x + CELL / 2, z + CELL / 2
			local r = math.sqrt((cx - RCX) ^ 2 + cz ^ 2)
			if r > RR + 2.6 then
				-- leave the side passages open (ground and upper doorways at the corridors)
				local passage = math.abs(cx - RCX) < 6 and math.abs(cz) > 30
				local function fill(y0: number, y1: number)
					if y1 > y0 then block("Poche", Vector3.new(CELL, y1 - y0, CELL), Vector3.new(cx, (y0 + y1) / 2, cz), C.marbleWarm) end
				end
				if passage then
					fill(F0 + 14.1, F1 - 1.2) -- (a hair above the drum opening's head: no shared plane)
					fill(F1 + 14.1, ROOF + 9)
				else
					fill(F0, ROOF + 9)
				end
			end
		end
	end
end
-- the floor: concentric marble rings and a compass star
cylinder("RotundaFloorRing", 0.1, 2 * RR, Vector3.new(RCX, F0 + 0.05, 0), C.marbleGrey).CanCollide = false
cylinder("RotundaFloorRing", 0.14, 2 * RR - 8, Vector3.new(RCX, F0 + 0.07, 0), C.marbleDark).CanCollide = false
cylinder("RotundaFloorRing", 0.18, 2 * RR - 12, Vector3.new(RCX, F0 + 0.09, 0), C.marble).CanCollide = false
cylinder("RotundaFloorRing", 0.22, 24, Vector3.new(RCX, F0 + 0.11, 0), C.marbleGreen).CanCollide = false
cylinder("RotundaFloorRing", 0.26, 16, Vector3.new(RCX, F0 + 0.13, 0), C.marble).CanCollide = false
for i = 0, 3 do
	local a = i * math.pi / 4
	local ray = deco("CompassRay", Vector3.new(if i % 2 == 0 then 22 else 14, 0.3, 1.2), Vector3.new(RCX, F0 + 0.15, 0), C.brass, M.Metal, -a)
	ray.CFrame = BASE * CFrame.new(RCX, F0 + 0.15 + i * 0.03, 0) * CFrame.Angles(0, -a, 0)
end
cylinder("CompassHeart", 0.34, 4, Vector3.new(RCX, F0 + 0.17, 0), C.bronze, M.Metal).CanCollide = false
-- the lower ring of columns (carries the gallery) and the upper ring (carries the drum's entablature)
local GAL_IN = RR - 9 -- the gallery's inner edge
for i = 0, 15 do
	local th = i / 16 * 2 * math.pi + math.pi / 16
	local p = onCircle(th, GAL_IN + 2.5, 0)
	column(p.X, F0, p.Z, F1 - F0 - 1.2, 2.6, C.marbleGreen)
	column(p.X, F1, p.Z, 30, 2.2, C.marble)
end
-- the gallery: a ring floor at F1, with a marble parapet and a brass rail
for i = 0, N - 1 do
	local th = (i + 0.5) / N * 2 * math.pi
	local mid = (GAL_IN + RR + 1) / 2
	local seg = Instance.new("Part")
	seg.Name = "Gallery"
	local alt = (i % 2) * 0.08
	seg.Size = Vector3.new(RR + 1 - GAL_IN, 1.2 + alt, 2 * math.pi * (RR + 1) / N + 0.6)
	put(seg, CFrame.new(onCircle(th, mid, F1 - 0.6)) * CFrame.Angles(0, -th, 0), C.marble)
	local soffit = Instance.new("Part")
	soffit.Name = "GallerySoffit"
	-- the soffit stops at the drum's inner face (it used to run into the wall and share its planes)
	soffit.Size = Vector3.new(RR - GAL_IN - 0.1, 1.6 + alt, 2 * math.pi * RR / N + 0.36)
	soffit.CanCollide = false
	put(soffit, CFrame.new(onCircle(th, (GAL_IN + RR) / 2 - 0.05, F1 - 2)) * CFrame.Angles(0, -th, 0), C.marbleWarm)
	-- marble parapet on the inner edge
	local par = Instance.new("Part")
	par.Name = "GalleryParapet"
	par.Size = Vector3.new(0.8 + alt, 3.4 + alt, 2 * math.pi * GAL_IN / N + 0.4)
	put(par, CFrame.new(onCircle(th, GAL_IN + 0.4, F1 + 1.7)) * CFrame.Angles(0, -th, 0), C.marble)
	local rail = Instance.new("Part")
	rail.Name = "GalleryRail"
	rail.Size = Vector3.new(1.1 + alt, 0.35 + alt, 2 * math.pi * GAL_IN / N + 0.56)
	rail.CanCollide = false
	put(rail, CFrame.new(onCircle(th, GAL_IN + 0.4, F1 + 3.55)) * CFrame.Angles(0, -th, 0), C.brass, M.Metal)
end
ring("UpperEntablature", GAL_IN + 2.5, 5, 3, F1 + 31.5, C.marbleWarm)
-- THE DOME: a real hollow shell. Inside: coffers (checkered) on rings, ribs; outside: copper.
do
	local MER = 32
	local RINGS = 10
	local maxLat = math.rad(82) -- the oculus opens above this
	for ring = 0, RINGS - 1 do
		local a0 = ring / RINGS * maxLat
		local a1 = (ring + 1) / RINGS * maxLat
		local am = (a0 + a1) / 2
		for m = 0, MER - 1 do
			local th = (m + 0.5) / MER * 2 * math.pi
			for _, shell in { { RR + 1, if (ring + m) % 2 == 0 then C.plaster else C.marbleWarm, M.Plaster, 1.2 }, { RR + 3.4, C.roof, M.Slate, 1.6 } } do
				local r = shell[1]
				local pos = Vector3.new(RCX + math.cos(th) * math.cos(am) * r, DRUM_TOP + math.sin(am) * r, math.sin(th) * math.cos(am) * r)
				local outward = (pos - Vector3.new(RCX, DRUM_TOP, 0)).Unit
				local tangent = Vector3.new(-math.sin(th), 0, math.cos(th))
				local up = outward:Cross(tangent).Unit * -1
				local width = 2 * math.pi * r * math.cos(a0) / MER + 0.5
				local height = r * (a1 - a0) + 0.4
				local p = Instance.new("Part")
				p.Name = if shell[1] < RR + 2 then "DomeInner" else "DomeOuter"
				p.Size = Vector3.new(width, height, shell[4])
				put(p, CFrame.fromMatrix(pos, tangent, up), shell[2], shell[3])
				if shell[1] < RR + 2 then
					p.CanCollide = false
					-- a gilded rosette in every other coffer
					if (ring + m) % 2 == 0 and ring < RINGS - 2 then
						local rosette = Instance.new("Part")
						rosette.Name = "DomeRosette"
						rosette.Size = Vector3.new(1.2, 1.2, 0.3)
						rosette.CanCollide = false
						put(rosette, CFrame.fromMatrix(pos - outward * 0.75, tangent, up), C.brass, M.Metal)
					end
				end
			end
		end
	end
	-- ribs on the inside at every fourth meridian
	for m = 0, MER - 1, 4 do
		local th = m / MER * 2 * math.pi
		for ring = 0, RINGS - 1 do
			local am = (ring + 0.5) / RINGS * maxLat
			local r = RR + 0.3
			local pos = Vector3.new(RCX + math.cos(th) * math.cos(am) * r, DRUM_TOP + math.sin(am) * r, math.sin(th) * math.cos(am) * r)
			local outward = (pos - Vector3.new(RCX, DRUM_TOP, 0)).Unit
			local tangent = Vector3.new(-math.sin(th), 0, math.cos(th))
			local up = outward:Cross(tangent).Unit * -1
			local rib = Instance.new("Part")
			rib.Name = "DomeRib"
			rib.Size = Vector3.new(1 + (ring % 2) * 0.1, r * maxLat / RINGS + 0.4, 0.8 + (ring % 2) * 0.08)
			rib.CanCollide = false
			put(rib, CFrame.fromMatrix(pos, tangent, up), C.marbleWarm)
		end
	end
	-- the oculus ring and the lantern on top (open to the sky through its windows)
	local topY = DRUM_TOP + math.sin(maxLat) * (RR + 1)
	local ocR = math.cos(maxLat) * (RR + 1)
	ring("OculusRing", ocR + 0.2, 1.6, 1.2, topY, C.brass, M.Metal, 24)
	for i = 0, 7 do
		local th = i / 8 * 2 * math.pi
		cylinder("LanternColumn", 8, 0.7, Vector3.new(RCX + math.cos(th) * (ocR + 0.5), topY + 4, math.sin(th) * (ocR + 0.5)), C.marble)
	end
	cylinder("LanternGlass", 7, 2 * ocR, Vector3.new(RCX, topY + 4, 0), C.glass, M.Glass).Transparency = 0.7
	cylinder("LanternRoof", 1.2, 2 * ocR + 3, Vector3.new(RCX, topY + 8.6, 0), C.roof, M.Slate)
	ball("LanternCap", 2 * ocR, Vector3.new(RCX, topY + 9, 0), C.roof, M.Slate)
	block("Finial", Vector3.new(0.6, 6, 0.6), Vector3.new(RCX, topY + 9 + ocR + 3, 0), C.brass, M.Metal)
	ball("FinialOrb", 1.4, Vector3.new(RCX, topY + 9 + ocR + 6, 0), C.brass, M.Metal)
	light(ball("OculusGlow", 3, Vector3.new(RCX, topY + 3, 0), C.light, M.Neon), 90, 2.2)
end
-- light in the rotunda: lamps on the gallery parapet and round the drum
for i = 0, 7 do
	local th = i / 8 * 2 * math.pi + math.pi / 8
	local p = onCircle(th, GAL_IN + 0.4, F1 + 4.6)
	light(ball("ParapetLamp", 1.2, p, C.light, M.Neon), 40, 1.2)
	local q = onCircle(th, RR - 0.5, F0 + 14)
	light(ball("DrumSconce", 1.4, q, C.light, M.Neon), 36, 1.2)
end
marker("RotundaSpot", Vector3.new(RCX + 10, F0 + 3, 0))

---------------------------------------------------------------------------
-- THE VESTIBULE (x 70..88, ground) and the UPPER HALL above it
---------------------------------------------------------------------------
group("Vestibule")
local VX0 = RCX + RR + 1 -- 70
-- THE FOYER: a transverse entrance hall (18 deep, 80 wide, 31 high). The main axis runs clear
-- from the bronze doors through a 28 x 26 opening into the rotunda; security is at the side doors.
wallXAt("VestibuleBack", F0, VX0, -BAND, BAND, GH, { { 0, 28, nil, 26 } }, C.marbleWarm, M.Marble, 2)
wallZAt("VestibuleS", F0, -BAND, VX0, HX, GH, { { 79, 8, nil, 14 } }, C.marbleWarm, M.Marble)
wallZAt("VestibuleN", F0, BAND, VX0, HX, GH, { { 79, 8, nil, 14 } }, C.marbleWarm, M.Marble)
-- the opening's surround: green marble columns either side, a marble entablature over it
for _, z in { -16.5, 16.5 } do
	column(VX0 + 2.6, F0, z, 26, 2.8, C.marbleGreen)
end
block("OpeningLintel", Vector3.new(4, 3, 36), Vector3.new(VX0 + 2.6, F0 + 27.5, 0), C.marble)
deco("OpeningLintelBand", Vector3.new(4.4, 0.8, 36.4), Vector3.new(VX0 + 2.6, F0 + 28.4, 0), C.marbleGrey)
-- columns flanking the side bays
for _, z in { -31, 31 } do
	column(VX0 + 2.6, F0, z, GH, 2.8, C.marbleGreen)
end
-- coffered ceiling with rosettes
for xi = 0, 3 do
	for zi = 0, 15 do
		local cx, cz = VX0 + 2.5 + xi * 4.4, -38 + zi * 5
		deco("VestibuleCoffer", Vector3.new(3.4, 0.6, 3.6), Vector3.new(cx, F1 - 1.6, cz), C.marbleGrey)
		cylinder("VestibuleRosette", 0.3, 1.2, Vector3.new(cx, F1 - 2.05, cz), C.brass, M.Metal).CanCollide = false
	end
end
-- the floor: a dark marble band with a lighter inlay running from the doors to the rotunda
deco("FoyerBand", Vector3.new(HX - VX0 - 1, 0.1, 14), Vector3.new((VX0 + HX) / 2, F0 + 0.05, 0), C.marbleDark)
deco("FoyerInlay", Vector3.new(HX - VX0 - 3, 0.16, 10), Vector3.new((VX0 + HX) / 2, F0 + 0.08, 0), C.marbleWarm)
for _, z in { -32, 32 } do
	-- security at each side door: a walk-through detector and a desk beside it
	deco("DetectorL", Vector3.new(1, 8, 1), Vector3.new(FRONT - 9, F0 + 4, z - 3.6), C.black, M.Metal)
	deco("DetectorR", Vector3.new(1, 8, 1), Vector3.new(FRONT - 9, F0 + 4, z + 3.6), C.black, M.Metal)
	deco("DetectorTop", Vector3.new(1.2, 1, 8.2), Vector3.new(FRONT - 9, F0 + 8.5, z), C.black, M.Metal)
	block("SecurityDesk", Vector3.new(8, 3.6, 3), Vector3.new(FRONT - 12, F0 + 1.8, z - math.sign(z) * 7), C.panel, M.Wood)
end
marker("MetalDetector", Vector3.new(FRONT - 9, F0 + 3, -32))
for _, z in { -30, 0, 30 } do
	lamp(Vector3.new(VX0 + 9, F1 - 3, z), 36)
end
-- upper hall (above the vestibule, looking out through the portico)
wallXAt("UpperHallBack", F1, VX0, -BAND, BAND, SH - 32, { { 0, 12, nil, 18 } }, C.marbleWarm, M.Marble, 2)
wallZAt("UpperHallS", F1, -BAND, VX0, HX, SH - 32, { { 79, 8, nil, 14 } }, C.marbleWarm, M.Marble)
wallZAt("UpperHallN", F1, BAND, VX0, HX, SH - 32, { { 79, 8, nil, 14 } }, C.marbleWarm, M.Marble)
roomAt("UpperHall", F1, SH - 32, VX0, HX, -BAND, BAND, C.wood)
for _, z in { -20, 20 } do
	block("HallBench", Vector3.new(2.6, 1.8, 10), Vector3.new(VX0 + 4, F1 + 0.9, z), C.panel, M.Wood)
end

---------------------------------------------------------------------------
-- THE STAIR HALL (x -47..1): an imperial staircase. A broad central flight climbs to a
-- landing with Lady Justice in a niche, then twin flights turn back up to the bridge,
-- which crosses over the foot of the stairs into the rotunda's gallery.
---------------------------------------------------------------------------
group("StairHall")
local LAND = F0 + 16 -- the half landing
local LAND_X0, LAND_X1 = SX0, -32
-- the hall's side walls: solid below (the corridors come in through the rotunda), and a doorway
-- from each end of the bridge out to the upper corridors
wallZAt("StairHallS", F0, -BAND, SX0, SX1, GH, nil, C.marbleWarm, M.Marble)
wallZAt("StairHallN", F0, BAND, SX0, SX1, GH, nil, C.marbleWarm, M.Marble)
wallZAt("StairHallSUp", F1, -BAND, SX0, SX1, SH - 32, { { -1.6, 5, nil, 14 } }, C.marbleWarm, M.Marble)
wallZAt("StairHallNUp", F1, BAND, SX0, SX1, SH - 32, { { -1.6, 5, nil, 14 } }, C.marbleWarm, M.Marble)
wallXAt("StairHallBack", F0, SX0, -BAND, BAND, SH, nil, C.marbleWarm, M.Marble, 2)
-- central flight: 20 steps, 24 wide, from x 0 back to x -32
do
	local n, rise, run = 20, (LAND - F0) / 20, 1.6
	for i = 1, n do
		local h = rise * i
		local x = 0 - (i - 0.5) * run
		block("CentralStep", Vector3.new(run, h, 24), Vector3.new(x, F0 + h / 2, 0), C.marble)
		deco("CentralNose", Vector3.new(0.34, 0.24, 24.1), Vector3.new(x + run / 2 - 0.13, F0 + h - 0.08, 0), C.marbleGrey)
	end
	-- the half landing (the full width of the hall)
	block("Landing", Vector3.new(LAND_X1 - LAND_X0 - 1, LAND - F0, 2 * BAND - 1.4), Vector3.new((LAND_X0 + LAND_X1) / 2 + 0.5, F0 + (LAND - F0) / 2, 0), C.marble) -- inside the walls' faces
	-- the flight's balustrades (sloped marble parapets with a brass rail) and newels with lamps
	local len = math.sqrt((n * run) ^ 2 + (LAND - F0) ^ 2)
	local slope = math.atan2(LAND - F0, n * run)
	for _, side in { -1, 1 } do
		local z = side * 12.4
		local par = block("CentralParapet", Vector3.new(len, 3.4, 0.8), Vector3.zero, C.marble)
		par.CFrame = BASE * CFrame.new(-n * run / 2, F0 + (LAND - F0) / 2 + 1.7, z) * CFrame.Angles(0, 0, -slope)
		local rail = deco("CentralRail", Vector3.new(len, 0.35, 1.1), Vector3.zero, C.brass, M.Metal)
		rail.CFrame = BASE * CFrame.new(-n * run / 2, F0 + (LAND - F0) / 2 + 3.6, z) * CFrame.Angles(0, 0, -slope)
		cylinder("Newel", 4.4, 2, Vector3.new(0.8, F0 + 2.2, z), C.marble)
		cylinder("NewelLampPost", 6, 0.5, Vector3.new(0.8, F0 + 7.4, z), C.bronze, M.Metal)
		light(ball("NewelLamp", 2.2, Vector3.new(0.8, F0 + 11, z), C.light, M.Neon), 36, 1.4)
	end
	-- the landing's open edge between the flights
	for _, side in { -1, 1 } do
		block("LandingParapet", Vector3.new(0.8, 3.4, 13), Vector3.new(LAND_X1 - 0.4, LAND + 1.7, side * 19), C.marble)
		deco("LandingRail", Vector3.new(1.1, 0.35, 13), Vector3.new(LAND_X1 - 0.4, LAND + 3.55, side * 19), C.brass, M.Metal)
	end
end
-- twin return flights: 20 steps each, 14 wide, from the landing (x -32) up to the bridge (x -4)
do
	local n, rise, run = 20, (F1 - LAND) / 20, 1.4
	for _, side in { -1, 1 } do
		local zc = side * (BAND - 0.7 - 6.65) -- z 26..39.3: up to the wall face, not into it
		for i = 1, n do
			local h = (LAND - F0) + rise * i
			local x = LAND_X1 + (i - 0.5) * run
			block("ReturnStep", Vector3.new(run, h, 13.3), Vector3.new(x, F0 + h / 2, zc), C.marble)
			deco("ReturnNose", Vector3.new(0.34, 0.24, 14.1), Vector3.new(x - run / 2 + 0.13, F0 + h - 0.08, zc), C.marbleGrey)
		end
		local len = math.sqrt((n * run) ^ 2 + (F1 - LAND) ^ 2)
		local slope = math.atan2(F1 - LAND, n * run)
		local z = side * (BAND - 14.4)
		local par = block("ReturnParapet", Vector3.new(len, 3.4, 0.8), Vector3.zero, C.marble)
		par.CFrame = BASE * CFrame.new(LAND_X1 + n * run / 2, LAND + (F1 - LAND) / 2 + 1.7, z) * CFrame.Angles(0, 0, slope)
		local rail = deco("ReturnRail", Vector3.new(len, 0.35, 1.1), Vector3.zero, C.brass, M.Metal)
		rail.CFrame = BASE * CFrame.new(LAND_X1 + n * run / 2, LAND + (F1 - LAND) / 2 + 3.6, z) * CFrame.Angles(0, 0, slope)
	end
end
-- the bridge's parapet (facing back down the stairs), between the two flight tops
block("BridgeParapet", Vector3.new(0.8, 3.4, 2 * (BAND - 14)), Vector3.new(-4.4, F1 + 1.7, 0), C.marble)
deco("BridgeRail", Vector3.new(1.1, 0.35, 2 * (BAND - 14)), Vector3.new(-4.4, F1 + 3.55, 0), C.brass, M.Metal)
-- Lady Justice in a niche on the landing, framed by green marble columns; a great window above
block("NicheBack", Vector3.new(1, 30, 16), Vector3.new(SX0 + 1.2, LAND + 15, 0), C.marbleGreen)
for _, z in { -9, 9 } do
	column(SX0 + 3, LAND, z, 26, 2.2, C.marble)
end
statue("StairJustice", SX0 + 5, LAND, 0, 1.3, true)
-- the stair hall's coffered ceiling and lanterns
for xi = 0, 8 do
	for zi = 0, 11 do
		deco("StairCoffer", Vector3.new(4.2, 0.6, 5.4), Vector3.new(SX0 + 3 + xi * 5.3, ROOF - 0.9, -BAND + 3.5 + zi * 6.6), C.marbleGrey)
	end
end
block("StairHallCeiling", Vector3.new(SX1 - SX0, 1, 2 * BAND), Vector3.new((SX0 + SX1) / 2, ROOF - 0.1, 0), C.plaster, M.Plaster)
for _, x in { -36, -14 } do
	for _, z in { -22, 22 } do
		cylinder("LanternRod", 14, 0.25, Vector3.new(x, ROOF - 7, z), C.bronze, M.Metal).CanCollide = false
		light(ball("StairLantern", 3, Vector3.new(x, ROOF - 15, z), C.light, M.Neon), 46, 1.4)
	end
end
marker("Room_StairLanding", Vector3.new(-40, LAND + 3, 20))
marker("Room_Bridge", Vector3.new(-1.5, F1 + 3, 0))

---------------------------------------------------------------------------
-- CORRIDORS (both floors): z +-(40..52), x -88..88
---------------------------------------------------------------------------
group("Corridors")
for _, y0 in { F0, F1 } do
	for _, side in { -1, 1 } do
		local zc = side * (BAND + CORR / 2)
		deco("Runner", Vector3.new(2 * HX - 6, 0.1, 5), Vector3.new(0, y0 + 0.06, zc), Color3.fromRGB(110, 28, 34), M.Fabric)
		for x = -76, 76, 19 do
			lamp(Vector3.new(x, (if y0 == F0 then F1 else ROOF) - 1.5, zc), 28)
		end
	end
end
-- the corridors' inner walls beside the stair hall / back block are the stair hall walls (above);
-- beside the rotunda the poche closes them; beside the back block:
wallZAt("BackBlockS", F0, -BAND, -HX, SX0, GH, { { -70, 8, nil, 14 } })
wallZAt("BackBlockN", F0, BAND, -HX, SX0, GH, { { -60, 8, nil, 14 } })
wallZAt("BackBlockSUp", F1, -BAND, -HX, SX0, SH - 32, nil)
wallZAt("BackBlockNUp", F1, BAND, -HX, SX0, SH - 32, { { -52, 8, nil, 14 } })

---------------------------------------------------------------------------
-- GROUND FLOOR ROOMS
---------------------------------------------------------------------------
group("SouthGround")
local S0, S1 = -HZ, -WING
wallZAt("SouthGroundHall", F0, S1, -HX, HX, GH, { { 59, 10, nil, 14 }, { 10, 8, nil, 14 }, { -20, 6, nil, 12 }, { -59, 10, nil, 14 } })
wallXAt("SG_Div1", F0, 30, S0, S1, GH, { { -100, 6, nil, 12 } })
wallXAt("SG_Div2", F0, -10, S0, S1, GH, nil)
wallXAt("SG_Div3", F0, -30, S0, S1, GH, nil)
-- CLERK OF THE COURT
roomAt("ClerksOffice", F0, 32, 30, HX, S0, S1, C.marbleWarm, M.Marble, Vector3.new(59, F0 + 3, -58))
block("ClerkCounter", Vector3.new(44, 4, 3), Vector3.new(63, F0 + 2, -66), C.panel, M.Wood)
deco("ClerkGrille", Vector3.new(44, 7, 0.3), Vector3.new(63, F0 + 7.5, -66.6), C.brass, M.DiamondPlate).Transparency = 0.45
deco("ClerkGate", Vector3.new(4, 3.4, 0.4), Vector3.new(36, F0 + 1.7, -66), C.panelDark, M.Wood)
marker("ClerkWindow", Vector3.new(63, F0 + 3, -60))
marker("ClerkSpot", Vector3.new(63, F0 + 3, -71))
for i = 0, 3 do
	block("ClerkDesk", Vector3.new(6, 3, 4), Vector3.new(44 + i * 11, F0 + 1.5, -84), C.panelDark, M.Wood)
	chair("ClerkChair" .. i, Vector3.new(44 + i * 11, F0 + 1, -87.5), Vector3.new(0, 0, 1))
	block("FilingCabinet", Vector3.new(4, 6, 2.2), Vector3.new(44 + i * 11, F0 + 3, S0 + 2.6), C.marbleGrey, M.Metal)
end
-- RECORDS
roomAt("Records", F0, 32, -10, 30, S0, S1, C.wood, nil, Vector3.new(10, F0 + 3, -58))
for i = 0, 5 do
	block("RecordShelf", Vector3.new(30, 14, 2), Vector3.new(10, F0 + 7, -66 - i * 8), C.panelDark, M.Wood)
	for k = 0, 3 do
		deco("Files", Vector3.new(29, 2, 2.1), Vector3.new(10, F0 + 2 + k * 3.2, -66 - i * 8), Color3.fromRGB(196 - k * 18, 178, 140), M.Fabric)
	end
end
-- RESTROOMS
roomAt("Restrooms", F0, 32, -30, -10, S0, S1, C.tile, M.SmoothPlastic, Vector3.new(-20, F0 + 3, -58))
for i = 0, 3 do
	block("Stall", Vector3.new(0.4, 8, 8), Vector3.new(-27 + i * 5, F0 + 4, -110), C.marbleGrey)
	block("Sink", Vector3.new(2, 3, 3), Vector3.new(-28, F0 + 3, -70 - i * 6), C.tile, M.SmoothPlastic)
end
-- JURY ASSEMBLY (where the jury pool waits to be called)
roomAt("JuryAssembly", F0, 32, -HX, -30, S0, S1, C.wood, nil, Vector3.new(-59, F0 + 3, -58))
for row = 0, 4 do
	for k = 0, 5 do
		chair("AssemblySeat" .. row .. "_" .. k, Vector3.new(-80 + k * 8, F0 + 1, -70 - row * 8), Vector3.new(0, 0, 1), C.panel)
	end
end

group("NorthGround")
local N0, N1 = WING, HZ
wallZAt("NorthGroundHall", F0, N0, -HX, HX, GH, { { 59, 10, nil, 14 }, { 20, 6, nil, 12 }, { 0, 6, nil, 12 }, { -20, 6, nil, 12 }, { -59, 8, nil, 14 } })
wallXAt("NG_Div1", F0, 30, N0, N1, GH, nil)
wallXAt("NG_Div2", F0, 10, N0, N1, GH, nil)
wallXAt("NG_Div3", F0, -10, N0, N1, GH, nil)
wallXAt("NG_Div4", F0, -30, N0, N1, GH, nil)
-- LAW LIBRARY
roomAt("LawLibrary", F0, 32, 30, HX, N0, N1, C.wood, nil, Vector3.new(59, F0 + 3, 58))
for i = 0, 4 do
	block("Bookcase", Vector3.new(34, 20, 2), Vector3.new(63, F0 + 10, 70 + i * 9), C.panelDark, M.Wood)
	for k = 0, 5 do
		deco("Books", Vector3.new(33, 2.6, 2.1), Vector3.new(63, F0 + 2 + k * 3.3, 70 + i * 9), if k % 2 == 0 then C.books else C.green, M.Fabric)
	end
end
for _, x in { 38, 80 } do
	block("ReadingTable", Vector3.new(4, 3, 14), Vector3.new(x, F0 + 1.5, 108), C.panel, M.Wood)
	ball("BankerLamp", 1.2, Vector3.new(x, F0 + 3.8, 108), C.green, M.Glass).CanCollide = false
end
-- ATTORNEY CONFERENCE A / B
for i, r in { { 10, 30 }, { -10, 10 } } do
	local cx = (r[1] + r[2]) / 2
	roomAt("AttorneyConference" .. i, F0, 32, r[1], r[2], N0, N1, C.wood, nil, Vector3.new(cx, F0 + 3, 58))
	block("ConfTable", Vector3.new(8, 0.6, 24), Vector3.new(cx, F0 + 3.2, 88), C.panelDark, M.Wood)
	block("ConfTableBase", Vector3.new(3, 2.9, 14), Vector3.new(cx, F0 + 1.45, 88), C.panelDark, M.Wood)
	for k = 0, 3 do
		chair("Conf" .. i .. "_" .. k .. "a", Vector3.new(cx - 6, F0 + 1, 79 + k * 6), Vector3.new(1, 0, 0), C.leather)
		chair("Conf" .. i .. "_" .. k .. "b", Vector3.new(cx + 6, F0 + 1, 79 + k * 6), Vector3.new(-1, 0, 0), C.leather)
	end
end
-- WITNESS WAITING
roomAt("WitnessWaiting", F0, 32, -30, -10, N0, N1, C.wood, nil, Vector3.new(-20, F0 + 3, 58))
for k = 0, 4 do
	block("WaitingBench", Vector3.new(14, 1.8, 2.6), Vector3.new(-20, F0 + 0.9, 66 + k * 10), C.panel, M.Wood)
end
-- COURT OFFICERS
roomAt("CourtOfficers", F0, 32, -HX, -30, N0, N1, C.marbleGrey, M.Marble, Vector3.new(-59, F0 + 3, 58))
for i = 0, 9 do
	block("Locker", Vector3.new(2.6, 7, 2), Vector3.new(-84 + i * 3, F0 + 3.5, N1 - 2.2), Color3.fromRGB(70, 80, 96), M.Metal)
end
block("OfficersDesk", Vector3.new(14, 3, 5), Vector3.new(-60, F0 + 1.5, 92), C.panelDark, M.Wood)
deco("Monitors", Vector3.new(12, 3, 0.6), Vector3.new(-60, F0 + 4.6, 94), C.black, M.Glass)

-- THE BACK BLOCK, ground: sally port hall, holding cells, the secure stair up to court holding
group("BackGround")
roomAt("SallyPort", F0, 32, -HX, SX0, -BAND, BAND, C.granite, M.Concrete, Vector3.new(-74, F0 + 3, -24))
for c = 0, 2 do
	local z0 = 0 + c * 12 -- cells along z 0..36, bars facing -x
	wallZAt("CellWall", F0, z0, -HX, -68, 14, nil, C.granite, M.Concrete)
	for i = 0, 6 do
		if i < 2 or i > 4 then
			cylinder("CellBar", 14, 0.4, Vector3.new(-68, F0 + 7, z0 + 1 + i * 1.6), C.black, M.Metal)
		end
	end
	block("CellBench", Vector3.new(2.4, 1.8, 10), Vector3.new(-HX + 2.4, F0 + 0.9, z0 + 6), C.granite, M.Concrete)
end
wallZAt("CellWallEnd", F0, 36, -HX, -68, 14, nil, C.granite, M.Concrete)
-- the secure stair (switchback, 2 x 16 steps) along the stair hall's back wall: x -64..-50
do
	local n, rise, run = 16, (F1 - F0) / 32, 2
	for i = 1, n do
		local h = rise * i
		block("SecureStepA", Vector3.new(6, h, run), Vector3.new(-53, F0 + h / 2, -36 + (i - 0.5) * run), C.granite, M.Concrete)
	end
	block("SecureLanding", Vector3.new(14, rise * n, 6), Vector3.new(-56, F0 + rise * n / 2, -36 + n * run + 3), C.granite, M.Concrete)
	for i = 1, n do
		local h = rise * (n + i)
		block("SecureStepB", Vector3.new(6, h, run), Vector3.new(-60, F0 + h / 2, -36 + n * run - (i - 0.5) * run), C.granite, M.Concrete)
	end
	-- the opening in the upper floor slab above the stair is left by the slab layout below
	block("SecureRail", Vector3.new(0.6, 3.4, n * run), Vector3.new(-56.5, F0 + 3, -36 + n * run / 2), C.black, M.Metal)
end
marker("Room_SecureStair", Vector3.new(-60, F1 + 3, -30))

---------------------------------------------------------------------------
-- UPPER FLOOR ROOMS
---------------------------------------------------------------------------
group("NorthUpper")
local UH = SH - 32
-- the corridor wall: the courtroom's public doors, the jury room, the press room
wallZAt("NorthUpperHall", F1, N0, -HX, HX, UH, { { 50, 12, nil, 18 }, { -26, 6, nil, 14 }, { -64, 6, nil, 14 }, { 74, 6, nil, 14 } })
wallXAt("NU_Div1", F1, 60, N0, N1, UH, nil)
wallXAt("NU_Div2", F1, -40, N0, N1, UH, { { 104, 6, nil, 14 } }) -- the jury's door into the courtroom
-- THE MAIN COURTROOM, Dept. 1 (x -40..60, z 52..116): bench in the west, gallery in the east
local CX0, CX1, CZ0, CZ1 = -40, 60, N0, N1
local CZC = (CZ0 + CZ1) / 2 -- 84
roomAt("Courtroom", F1, UH, CX0, CX1, CZ0, CZ1, C.wood, nil, Vector3.new(56, F1 + 3, CZC))
-- pilasters: between the tall windows on the north wall, and clear of the doors on the south
for _, x in { -27, -9, 9, 27, 45 } do
	deco("Pilaster", Vector3.new(3, UH - 6, 0.9), Vector3.new(x, F1 + (UH - 6) / 2, CZ1 - 2.4), C.marble)
	deco("PilasterCap", Vector3.new(4, 2, 1.4), Vector3.new(x, F1 + UH - 6, CZ1 - 2.4), C.marbleWarm)
end
for _, x in { -36, -12, 8, 28 } do
	deco("Pilaster", Vector3.new(3, UH - 6, 0.9), Vector3.new(x, F1 + (UH - 6) / 2, CZ0 + 1.4), C.marble)
	deco("PilasterCap", Vector3.new(4, 2, 1.4), Vector3.new(x, F1 + UH - 6, CZ0 + 1.4), C.marbleWarm)
end
-- wainscot: below the window sills on the north wall; on the south wall in runs between the doors
deco("CourtWainscotN", Vector3.new(CX1 - CX0, 7, 0.4), Vector3.new((CX0 + CX1) / 2, F1 + 3.5, CZ1 - 2), C.panel, M.Wood)
for _, run in { { CX0, -29.4 }, { -22.6, 43.6 }, { 56.4, CX1 } } do -- the doors are at x -29..-23 and 44..56
	deco("CourtWainscotS", Vector3.new(run[2] - run[1], 10, 0.4), Vector3.new((run[1] + run[2]) / 2, F1 + 5, CZ0 + 1), C.panel, M.Wood)
end
for i = 0, 4 do
	deco("CourtBeam", Vector3.new(2.4, 2.4, CZ1 - CZ0), Vector3.new(CX0 + 10 + i * 20, ROOF - 1.4, CZC), C.panelDark, M.Wood)
end
-- the bench wall (marble with green panels and the seal)
deco("BenchWall", Vector3.new(0.6, 34, 40), Vector3.new(CX0 + 1, F1 + 17, CZC), C.marble)
for _, dz in { -14, 14 } do
	deco("GreenPanel", Vector3.new(0.3, 20, 8), Vector3.new(CX0 + 1.4, F1 + 14, CZC + dz), C.marbleGreen)
end
cylinder("Seal", 0.5, 12, Vector3.new(CX0 + 1.6, F1 + 24, CZC), C.brass, M.Metal, "x").CanCollide = false
cylinder("SealInner", 0.6, 8, Vector3.new(CX0 + 1.7, F1 + 24, CZC), C.bronze, M.Metal, "x").CanCollide = false
deco("InGodWeTrust", Vector3.new(0.3, 2.2, 22), Vector3.new(CX0 + 1.4, F1 + 32, CZC), C.brass, M.Metal)
for _, dz in { -8, 8 } do
	cylinder("FlagPole", 16, 0.4, Vector3.new(CX0 + 3.5, F1 + 8, CZC + dz), C.brass, M.Metal)
	deco("Flag", Vector3.new(0.2, 5, 6), Vector3.new(CX0 + 3.5, F1 + 13, CZC + dz + (if dz > 0 then 3 else -3)), if dz > 0 then Color3.fromRGB(40, 60, 140) else Color3.fromRGB(160, 40, 40), M.Fabric)
end
-- the bench: raised dais with steps on the north side for the judge
block("BenchDais", Vector3.new(12, 4, 28), Vector3.new(CX0 + 8, F1 + 2, CZC), C.panelDark, M.Wood)
for k = 1, 4 do
	block("BenchStep", Vector3.new(10, k, 1.5), Vector3.new(CX0 + 8, F1 + k / 2, CZC + 14 + (4 - k) * 1.5 + 0.75), C.panelDark, M.Wood)
end
block("BenchFront", Vector3.new(2, 7, 28.2), Vector3.new(CX0 + 14, F1 + 3.5, CZC), C.panel, M.Wood)
for k = -3, 3 do
	deco("BenchPanel", Vector3.new(0.3, 4.6, 3.2), Vector3.new(CX0 + 15.1, F1 + 3.5, CZC + k * 3.8), C.panelDark, M.Wood)
end
block("BenchTop", Vector3.new(4, 0.6, 29), Vector3.new(CX0 + 13, F1 + 7.3, CZC), C.panelDark, M.Wood)
chair("JudgeSeat", Vector3.new(CX0 + 8, F1 + 4.6, CZC), Vector3.new(1, 0, 0), C.black)
-- clerk and witness stand either side of the bench
block("CourtClerkDesk", Vector3.new(4, 3.4, 10), Vector3.new(CX0 + 18, F1 + 1.7, CZC + 20), C.panel, M.Wood)
chair("CourtClerkSeat", Vector3.new(CX0 + 15, F1 + 1, CZC + 20), Vector3.new(1, 0, 0))
block("WitnessBox", Vector3.new(7, 2, 7), Vector3.new(CX0 + 16, F1 + 1, CZC - 20), C.panelDark, M.Wood)
deco("WitnessRail", Vector3.new(0.5, 4, 7), Vector3.new(CX0 + 19.6, F1 + 4, CZC - 20), C.panel, M.Wood)
block("WitnessStep", Vector3.new(4, 1, 1.6), Vector3.new(CX0 + 15, F1 + 0.5, CZC - 15.7), C.panelDark, M.Wood)
chair("WitnessSeat", Vector3.new(CX0 + 15.5, F1 + 2.4, CZC - 20), Vector3.new(1, 0, 0.3))
-- the jury box along the north wall (the jury enters from its own door in the west wall)
block("JuryDais", Vector3.new(30, 1.2, 6), Vector3.new(CX0 + 30, F1 + 0.6, CZ1 - 10), C.panelDark, M.Wood)
block("JuryDais2", Vector3.new(30, 2.4, 5), Vector3.new(CX0 + 30, F1 + 1.2, CZ1 - 4.5), C.panelDark, M.Wood)
block("JuryRail", Vector3.new(24, 3.5, 0.6), Vector3.new(CX0 + 33, F1 + 1.75, CZ1 - 13.4), C.panel, M.Wood)
for row = 0, 1 do
	for i = 1, 6 do
		chair("JurorSeat" .. (row * 6 + i), Vector3.new(CX0 + 19 + (i - 1) * 4.6, F1 + 1.6 + row * 1.2, CZ1 - 11 + row * 5.5), Vector3.new(0, 0, -1), C.panel)
	end
end
-- counsel tables, the bar with its gate, the gallery
block("DefenseTable", Vector3.new(5, 3.2, 14), Vector3.new(CX0 + 34, F1 + 1.6, CZC - 10), C.panel, M.Wood)
chair("DefendantSeat", Vector3.new(CX0 + 38, F1 + 1, CZC - 13), Vector3.new(-1, 0, 0))
chair("DefenseSeat", Vector3.new(CX0 + 38, F1 + 1, CZC - 7), Vector3.new(-1, 0, 0))
block("ProsecutionTable", Vector3.new(5, 3.2, 14), Vector3.new(CX0 + 34, F1 + 1.6, CZC + 10), C.panel, M.Wood)
chair("ProsecutorSeat", Vector3.new(CX0 + 38, F1 + 1, CZC + 10), Vector3.new(-1, 0, 0))
marker("BailiffSpot", Vector3.new(CX0 + 22, F1 + 3, CZ0 + 6))
block("BarRailS", Vector3.new(0.8, 3.4, CZC - 4 - CZ0 - 2), Vector3.new(CX0 + 50, F1 + 1.7, (CZ0 + 2 + CZC - 4) / 2), C.panel, M.Wood)
block("BarRailN", Vector3.new(0.8, 3.4, CZ1 - 16 - CZC - 4), Vector3.new(CX0 + 50, F1 + 1.7, (CZC + 4 + CZ1 - 16) / 2), C.panel, M.Wood)
local g = 0
for row = 0, 7 do
	local x = CX0 + 56 + row * 5
	for _, side in { -1, 1 } do
		local zc = CZC + side * 15
		block("Pew", Vector3.new(2.4, 1.6, 22), Vector3.new(x, F1 + 1.3, zc), C.panel, M.Wood)
		block("PewBack", Vector3.new(0.5, 3.6, 21.8), Vector3.new(x + 1.3, F1 + 2.4, zc), C.panel, M.Wood)
		for k = 0, 4 do
			g += 1
			local s = chair("GallerySeat" .. g, Vector3.new(x, F1 + 2.2, zc - 9 + k * 4.5), Vector3.new(-1, 0, 0), C.panel, true)
			s.Transparency = 1
		end
	end
end
-- THE JURY ROOM (x -88..-40): the long table, twelve chairs, tall windows, the clock, the fan
roomAt("JuryRoom", F1, UH, -HX, CX0, N0, N1, C.wood, nil, Vector3.new(-64, F1 + 3, 58))
do
	local jcx, jcz = -64, 86
	block("JuryTable", Vector3.new(34, 0.8, 8), Vector3.new(jcx, F1 + 3.4, jcz), C.wood, M.Wood)
	for _, dx in { -15, 15 } do
		for _, dz in { -3, 3 } do
			block("TableLeg", Vector3.new(0.6, 3, 0.6), Vector3.new(jcx + dx, F1 + 1.5, jcz + dz), C.panelDark, M.Wood)
		end
	end
	local j = 0
	for side = -1, 1, 2 do
		for i = 0, 4 do
			j += 1
			chair("JuryRoomSeat" .. j, Vector3.new(jcx - 13 + i * 6.5, F1 + 1.6, jcz + side * 6.5), Vector3.new(0, 0, -side), C.wood)
		end
	end
	chair("JuryRoomSeat11", Vector3.new(jcx - 20, F1 + 1.6, jcz), Vector3.new(1, 0, 0), C.wood)
	chair("JuryRoomSeat12", Vector3.new(jcx + 20, F1 + 1.6, jcz), Vector3.new(-1, 0, 0), C.wood)
	marker("JuryRoomSpot", Vector3.new(jcx, F1 + 3, N0 + 6))
	cylinder("WallClock", 0.4, 3, Vector3.new(-HX + 1.6, F1 + 18, jcz), Color3.fromRGB(245, 240, 225), M.SmoothPlastic, "x").CanCollide = false
	deco("FanStand", Vector3.new(0.4, 5, 0.4), Vector3.new(-84, F1 + 2.5, N1 - 4), C.black, M.Metal)
	cylinder("FanCage", 1.2, 3.4, Vector3.new(-83.7, F1 + 5.6, N1 - 4), C.black, M.Metal, "x").CanCollide = false
	block("WaterCooler", Vector3.new(1.6, 4.5, 1.6), Vector3.new(-44, F1 + 2.25, N0 + 4), Color3.fromRGB(220, 225, 230), M.SmoothPlastic)
	deco("WashroomDoor", Vector3.new(4.5, 9, 0.4), Vector3.new(-78, F1 + 4.5, N0 + 1), C.panel, M.Wood)
	deco("CoatRack", Vector3.new(0.4, 7, 0.4), Vector3.new(-86, F1 + 3.5, N0 + 4), C.panelDark, M.Wood)
end
-- PRESS ROOM (x 60..88)
roomAt("PressRoom", F1, UH, 60, HX, N0, N1, C.wood, nil, Vector3.new(74, F1 + 3, 58))
for row = 0, 2 do
	block("PressDesk", Vector3.new(4, 3, 20), Vector3.new(68 + row * 7, F1 + 1.5, 90), C.panel, M.Wood)
end

group("SouthUpper")
wallZAt("SouthUpperHall", F1, S1, -HX, HX, UH, { { -68, 6, nil, 14 }, { -39, 6, nil, 14 }, { 30, 10, nil, 16 }, { 64, 6, nil, 14 } })
wallXAt("SU_Div1", F1, -48, S0, S1, UH, { { -100, 6, nil, 14 } }) -- chambers <-> robing room
wallXAt("SU_Div2", F1, -30, S0, S1, UH, nil)
wallXAt("SU_Div3", F1, 40, S0, S1, UH, nil)
-- THE JUDGE'S CHAMBERS (x -88..-48)
roomAt("JudgesChambers", F1, UH, -HX, -48, S0, S1, C.wood, nil, Vector3.new(-68, F1 + 3, -58))
deco("Rug", Vector3.new(20, 0.1, 26), Vector3.new(-70, F1 + 0.18, -88), Color3.fromRGB(110, 28, 34), M.Fabric)
block("ChambersDesk", Vector3.new(5, 3.2, 12), Vector3.new(-80, F1 + 1.6, -88), C.panelDark, M.Wood)
chair("ChambersChair", Vector3.new(-84, F1 + 1, -88), Vector3.new(1, 0, 0), C.leather)
chair("ChambersGuest1", Vector3.new(-72, F1 + 1, -92), Vector3.new(-1, 0, 0), C.leather)
chair("ChambersGuest2", Vector3.new(-72, F1 + 1, -84), Vector3.new(-1, 0, 0), C.leather)
block("ChambersBookcase", Vector3.new(30, 18, 2), Vector3.new(-68, F1 + 9, S0 + 2.2), C.panelDark, M.Wood)
marker("ChambersSpot", Vector3.new(-68, F1 + 3, -60))
-- ROBING ROOM (x -48..-30)
roomAt("RobingRoom", F1, UH, -48, -30, S0, S1, C.wood, nil, Vector3.new(-39, F1 + 3, -58))
for i = 0, 3 do
	deco("Robe", Vector3.new(2.4, 6, 0.6), Vector3.new(-45 + i * 4, F1 + 4.8, S0 + 1.8), C.black, M.Fabric)
end
-- COURTROOM Dept. 2 (x -30..40)
roomAt("CourtroomDept2", F1, UH, -30, 40, S0, S1, C.wood, nil, Vector3.new(30, F1 + 3, -58))
block("Dept2Dais", Vector3.new(10, 3, 22), Vector3.new(-24, F1 + 1.5, -88), C.panelDark, M.Wood)
for k = 1, 3 do
	block("Dept2Step", Vector3.new(8, k, 1.4), Vector3.new(-24, F1 + k / 2, -77 + (3 - k) * 1.4 + 0.7), C.panelDark, M.Wood)
end
block("Dept2BenchFront", Vector3.new(2, 6, 22.2), Vector3.new(-18.5, F1 + 3, -88), C.panel, M.Wood)
chair("Dept2JudgeSeat", Vector3.new(-25, F1 + 3.6, -88), Vector3.new(1, 0, 0), C.black)
cylinder("Dept2Seal", 0.5, 9, Vector3.new(-29, F1 + 18, -88), C.brass, M.Metal, "x").CanCollide = false
block("Dept2Table", Vector3.new(4, 3, 10), Vector3.new(-6, F1 + 1.5, -96), C.panel, M.Wood)
block("Dept2Table", Vector3.new(4, 3, 10), Vector3.new(-6, F1 + 1.5, -80), C.panel, M.Wood)
for row = 0, 4 do
	block("Dept2Pew", Vector3.new(2.4, 1.6, 40), Vector3.new(8 + row * 6, F1 + 1.3, -88), C.panel, M.Wood)
	block("Dept2PewBack", Vector3.new(0.5, 3.6, 39.8), Vector3.new(9.3 + row * 6, F1 + 2.4, -88), C.panel, M.Wood)
end
-- WITNESS ROOM (x 40..88)
roomAt("WitnessRoom", F1, UH, 40, HX, S0, S1, C.wood, nil, Vector3.new(64, F1 + 3, -58))
block("WitnessTable", Vector3.new(8, 0.6, 20), Vector3.new(64, F1 + 3.2, -88), C.panelDark, M.Wood)
block("WitnessTableBase", Vector3.new(3, 2.9, 12), Vector3.new(64, F1 + 1.45, -88), C.panelDark, M.Wood)

-- BACK BLOCK, upper: COURT HOLDING beside the courtroom (the secure stair comes up here)
group("BackUpper")
roomAt("CourtHolding", F1, UH, -HX, SX0, -BAND, BAND, C.granite, M.Concrete, Vector3.new(-74, F1 + 3, 30))
wallXAt("UpperCellFront", F1, -70, 0, 36, 14, { { 18, 5, nil, 10 } }, C.black, M.DiamondPlate, 0.6)
wallZAt("UpperCellSide", F1, 0, -HX, -70, 14, nil, C.granite, M.Concrete)
block("UpperCellBench", Vector3.new(2.4, 1.8, 16), Vector3.new(-HX + 2.4, F1 + 0.9, 18), C.granite, M.Concrete)
marker("HoldingSpot", Vector3.new(-80, F1 + 3, 18))
-- the hole in the slab above the secure stair: rebuild the back block's floor round it
do
	local slabPart = nil
	for _, p in groups.Floors:GetChildren() do
		if p:IsA("BasePart") and math.abs(p.Size.X - (SX0 + HX)) < 0.1 and math.abs(p.Size.Z - 2 * BAND) < 0.1 then slabPart = p end
	end
	if slabPart then slabPart:Destroy() end
	current = groups.Floors
	slab(-HX, -64, -BAND, BAND)
	slab(-50, SX0, -BAND, BAND)
	slab(-64, -50, -4, BAND)
	current = groups.BackUpper
	block("StairWellRail", Vector3.new(14, 3.4, 0.6), Vector3.new(-57, F1 + 1.7, -4), C.black, M.Metal)
	block("StairWellRail", Vector3.new(0.6, 3.4, 36), Vector3.new(-50.3, F1 + 1.7, -22), C.black, M.Metal)
end

model:SetAttribute("Facility", "Courthouse")
model:SetAttribute("Inspiration", "12 Angry Men (1957) - New York County Courthouse, 60 Centre Street")
model.PrimaryPart = groups.Entry:FindFirstChild("Podium") :: BasePart
model.Parent = workspace

---------------------------------------------------------------------------
-- TRIM PASS: no two faces may share a plane. Where a trim piece's face lies in the same plane
-- as an overlapping face of another part, facing the same way, the two flicker (z-fight) as
-- the camera moves - push the trim out along that face until it has its own space.
---------------------------------------------------------------------------
local TRIM_NAMES = { "Nose", "Sill", "Head", "Jamb", "Pilaster", "Rustication", "StringCourse", "Wainscot", "Cornice",
	"Coffer", "Rosette", "Tile", "Runner", "Rug", "Panel", "Band", "Frieze", "Dentil", "Inlay", "Rail", "Soffit",
	"Parapet", "Rib", "Rose", "Board", "Plaque", "Text", "InGodWeTrust", "Transom", "DoorHead", "DoorPediment", "Medallion",
	"Seal", "Flag", "Books", "Files", "Robe", "Monitors", "Grille", "Gate", "Capital", "Abacus", "Cap", "Plinth", "Necking" }
local LOCKED = { "Wall", "Div", "Hall", "Drum", "Poche", "Floor", "Gallery", "Podium", "Attic", "Roof", "Landing",
	"Step", "Anta", "Ceiling", "Slab", "Dock", "Port", "Shaft", "Column" }
local function isTrim(p: BasePart): boolean
	if not p.CanCollide then return true end
	local locked = false
	for _, n in LOCKED do
		if p.Name:find(n, 1, true) then locked = true end
	end
	if not locked then return true end -- furniture and fittings may move a hair
	for _, n in TRIM_NAMES do
		if p.Name:find(n, 1, true) then return true end
	end
	return false
end
local function isBox(p: BasePart): boolean
	return p:IsA("Part") and (p :: Part).Shape == Enum.PartType.Block
end
-- the six faces of a box part: { normal, plane offset (n . point on face), its two in-plane axes + half extents }
local function faces(p: BasePart)
	local cf, half = p.CFrame, p.Size / 2
	local axes = { { cf.RightVector, half.X }, { cf.UpVector, half.Y }, { -cf.LookVector, half.Z } }
	local out = {}
	for i, a in axes do
		local others = {}
		for j, b in axes do
			if j ~= i then table.insert(others, b) end
		end
		for _, sgn in { 1, -1 } do
			local n = a[1] * sgn
			table.insert(out, { n = n, d = n:Dot(cf.Position) + a[2], u = others[1], v = others[2] })
		end
	end
	return out
end
-- half extent of a box part along a world direction
local function extent(p: BasePart, dir: Vector3): number
	local cf, h = p.CFrame, p.Size / 2
	return math.abs(dir:Dot(cf.RightVector)) * h.X + math.abs(dir:Dot(cf.UpVector)) * h.Y + math.abs(dir:Dot(cf.LookVector)) * h.Z
end
local function overlap1(c1: number, e1: number, c2: number, e2: number): number
	return math.min(c1 + e1, c2 + e2) - math.max(c1 - e1, c2 - e2)
end
-- structural pieces never move (moving a slab would leave a lip at the stairs)
local STRUCTURAL = { UpperFloor = true, GroundFloor = true, Landing = true, Podium = true, PortFloor = true, PortGround = true,
	Gallery = true, StairTop = true, SallyDock = true, StaffLanding = true }
local fixedTrim = 0
do
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	local seen: { [string]: boolean } = {}
	local ids: { [Instance]: number } = {}
	local nextId = 0
	local function id(p: Instance): number
		if not ids[p] then nextId += 1; ids[p] = nextId end
		return ids[p]
	end
	local function movable(p: BasePart): boolean
		return isTrim(p) and not STRUCTURAL[p.Name]
	end
	for _, t in model:GetDescendants() do
		if t:IsA("BasePart") and isBox(t) and t.Transparency < 1 and (movable(t) or true) then
			for _, o in workspace:GetPartBoundsInBox(t.CFrame, t.Size + Vector3.new(0.2, 0.2, 0.2), params) do
				if o ~= t and isBox(o) and o.Transparency < 1 then
					local a, b = id(t), id(o)
					local key = if a < b then a .. ":" .. b else b .. ":" .. a
					if not seen[key] then
						seen[key] = true
						-- which one moves: a movable trim piece, the smaller one if both are
						local mover, other = nil, nil
						local tm, om = movable(t), movable(o :: BasePart)
						if tm and om then
							if t.Size.X * t.Size.Y * t.Size.Z <= o.Size.X * o.Size.Y * o.Size.Z then mover, other = t, o else mover, other = o, t end
						elseif tm then mover, other = t, o
						elseif om then mover, other = o, t end
						if mover and other then
							local push = Vector3.zero
							for _, f in faces(mover) do
								for _, g in faces(other) do
									if f.n:Dot(g.n) > 0.999 and math.abs(f.d - g.d) < 0.03 then
										local ou = overlap1(f.u[1]:Dot(mover.Position), f.u[2], f.u[1]:Dot(other.Position), extent(other, f.u[1]))
										local ov = overlap1(f.v[1]:Dot(mover.Position), f.v[2], f.v[1]:Dot(other.Position), extent(other, f.v[1]))
										if ou > 0.05 and ov > 0.05 then
											push += f.n * 0.06
										end
									end
								end
							end
							if push.Magnitude > 0 then
								mover.CFrame = mover.CFrame + push
								fixedTrim += 1
							end
						end
					end
				end
			end
		end
	end
end
print(("[Courthouse] trim pass: %d face clashes fixed"):format(fixedTrim))

---------------------------------------------------------------------------
-- CHECK: walk to every room from the street (the cells from the sally port)
---------------------------------------------------------------------------
local PathfindingService = game:GetService("PathfindingService")
local report, fails = {}, 0
local function reach(label: string, a: Vector3, b: Vector3)
	local path = PathfindingService:CreatePath({ AgentRadius = 1.5, AgentHeight = 5, AgentCanJump = false, WaypointSpacing = 6 })
	local ok = pcall(function() path:ComputeAsync(a, b) end)
	local good = ok and path.Status == Enum.PathStatus.Success
	if not good then fails += 1 end
	table.insert(report, label .. ": " .. (if good then "ok" else "FAIL"))
end
local function at(n: string): Vector3
	return (markers:FindFirstChild(n) :: BasePart).Position + Vector3.new(0, if markers[n]:IsA("Seat") then 2 else 0, 0)
end
local street = at("VehicleDropoff")
for _, m in markers:GetChildren() do
	if m:IsA("BasePart") and (m.Name:sub(1, 5) == "Room_" or m.Name == "RotundaSpot" or m.Name == "ClerkWindow" or m.Name == "ChambersSpot" or m.Name == "JuryRoomSpot") then
		reach("street -> " .. m.Name, street, m.Position)
	end
end
reach("~ sally port -> holding (up the secure stair)", at("PrisonerDropoff"), at("HoldingSpot"))
reach("~ holding -> defendant's chair", at("HoldingSpot"), at("DefendantSeat"))
reach("~ chambers -> judge's chair", at("ChambersSpot"), at("JudgeSeat"))
reach("~ jury room -> jury box", at("JuryRoomSpot"), at("JurorSeat1"))
reach("~ gallery -> witness stand", at("Room_Courtroom"), at("WitnessSeat"))
reach("~ rotunda -> gallery (via the grand staircase)", at("RotundaSpot"), (markers.RotundaSpot.CFrame * CFrame.new(-10, F1 - F0, 30)).Position)
table.sort(report)
print(("[Courthouse] built: %d parts, %d walkability failures"):format(#model:GetDescendants(), fails))
return ("%d parts, %d failures, %d trim clashes fixed\n%s"):format(#model:GetDescendants(), fails, fixedTrim, table.concat(report, "\n"))
