-- Builds workspace.Courthouse (run once in Studio's Edit datamodel; v263).
-- Modelled on the courthouse in 12 Angry Men (1957) - the New York County Courthouse at
-- 60 Centre Street: the grand staircase and the giant Corinthian portico of the opening
-- shot, the marble rotunda, the courtroom and the jury room.
--
-- FLOOR PLAN (local: x = depth, back -88 .. front +88; z = width -116 .. 116; front = +X)
--   front     grand staircase (18 x 0.5-stud steps) -> portico -> 3 bronze doors
--   centre    ROTUNDA x 26..88, z -50..50 (stairs along both side walls to a U balcony)
--             MAIN COURTROOM (Dept. 1) x -52..26, z -50..50
--   corridors SOUTH z -62..-50 and NORTH z 50..62 (x -60..88), BACK x -60..-52 (z -62..62)
--   south     Clerk's Office | Records | Restrooms | Courtroom Dept. 2
--   north     Attorney Conference 1 & 2 | Law Library | Witness Waiting | THE JURY ROOM
--   back      Court Holding (+ prisoner sally port) | Court Officers | Robing Room | Judge's Chambers
-- Every room is reached through a doorway; the build checks it with PathfindingService.
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
		back.Size = Vector3.new(2.2, 2.6, 0.35)
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
		deco("LampArm", Vector3.new(3, 0.4, 0.4), Vector3.new(x + math.cos(a) * 1.5, y0 + 17.5, z + math.sin(a) * 1.5), C.bronze, M.Metal, -a)
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
	deco("StepNose", Vector3.new(0.3, 0.2, STAIR_W), Vector3.new(x - RUN / 2 + 0.15, h - 0.1, 0), C.marbleGrey)
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
-- THE SHELL: marble walls, tall windows, rusticated base, cornice, attic, roof, dome
---------------------------------------------------------------------------
group("Shell")
local SH = COL_H + 10
local function windows(a: number, b: number, every: number, skip: { number }?): { { number } }
	local g = {}
	local n = math.floor((b - a) / every)
	local start = a + ((b - a) - (n - 1) * every) / 2
	for i = 0, n - 1 do
		local c = start + i * every
		local ok = true
		for _, s in skip or {} do
			if math.abs(c - s) < 8 then ok = false end
		end
		if ok then table.insert(g, { c, 7, 10, 26 }) end
	end
	return g
end
-- front: the three bronze doorways
local DOORS = { { -32, 12, 26 }, { 0, 14, 30 }, { 32, 12, 26 } }
do
	local o = {}
	for _, d in DOORS do table.insert(o, { d[1], d[2], nil, d[3] }) end
	wallX("FrontWall", FRONT, -HZ, HZ, SH, o, C.marble, M.Marble, 3)
	for _, d in DOORS do
		local z, w, top = d[1], d[2], d[3]
		for _, s in { -1, 1 } do
			deco("BronzeDoor", Vector3.new(w / 2, top - 8, 0.5), Vector3.new(FRONT - w / 4 - 1.6, F0 + (top - 8) / 2, z + s * (w / 2 - 0.25)), C.bronze, M.Metal, math.rad(90))
		end
		local tr = deco("Transom", Vector3.new(0.4, 7, w), Vector3.new(FRONT, F0 + top - 4, z), C.bronze, M.DiamondPlate)
		tr.Transparency = 0.25
		deco("DoorHead", Vector3.new(4, 2.4, w + 4), Vector3.new(FRONT + 1.6, F0 + top + 1.2, z), C.marbleGrey)
		deco("DoorPediment", Vector3.new(4.6, 1.2, w + 6), Vector3.new(FRONT + 2, F0 + top + 3, z), C.marble)
	end
end
-- the back: the prisoner sally port (a roll-up gate) and a staff door
wallX("BackWall", -HX, -HZ, HZ, SH, { { -86, 14, nil, 16 }, { 86, 8 } }, C.marble, M.Marble, 3)
deco("SallyPortGate", Vector3.new(0.4, 2, 14), Vector3.new(-HX - 0.5, F0 + 15, -86), C.black, M.DiamondPlate)
block("SallyDock", Vector3.new(10, FY, 18), Vector3.new(-HX - 5, FY / 2, -86), C.granite, M.Concrete)
for i = 1, 18 do -- the prisoner ramp: shallow steps down to the drive
	local h = FY * (18 - i + 1) / 19
	block("SallyStep", Vector3.new(1.4, h, 18), Vector3.new(-HX - 10 - (i - 0.5) * 1.4, h / 2, -86), C.granite, M.Concrete)
end
marker("PrisonerDropoff", Vector3.new(-HX - 44, 3, -86))
block("StaffLanding", Vector3.new(6, FY, 10), Vector3.new(-HX - 3, FY / 2, 86), C.granite, M.Concrete)
for i = 1, 18 do
	local h = FY * (18 - i + 1) / 19
	block("StaffStep", Vector3.new(1.4, h, 10), Vector3.new(-HX - 6 - (i - 0.5) * 1.4, h / 2, 86), C.granite, M.Concrete)
end
wallZ("SideWallS", -HZ, -HX, HX, SH, windows(-HX, HX, 22), C.marble, M.Marble, 3)
wallZ("SideWallN", HZ, -HX, HX, SH, windows(-HX, HX, 22), C.marble, M.Marble, 3)
for k = 0, 3 do
	local y = FY + 2 + k * 2.4
	deco("Rustication", Vector3.new(0.4, 0.4, 2 * HZ), Vector3.new(-HX - 1.7, y, 0), C.marbleGrey)
	deco("Rustication", Vector3.new(2 * HX, 0.4, 0.4), Vector3.new(0, y, -HZ - 1.7), C.marbleGrey)
	deco("Rustication", Vector3.new(2 * HX, 0.4, 0.4), Vector3.new(0, y, HZ + 1.7), C.marbleGrey)
end
deco("StringCourse", Vector3.new(2 * HX + 4, 1.2, 2 * HZ + 4), Vector3.new(0, F0 + 40, 0), C.marbleWarm)
block("MainCornice", Vector3.new(2 * HX + 8, 3, 2 * HZ + 8), Vector3.new(0, F0 + SH + 1.5, 0), C.marble)
block("Attic", Vector3.new(2 * HX, 6, 2 * HZ), Vector3.new(0, F0 + SH + 6, 0), C.marbleWarm)
block("AtticCornice", Vector3.new(2 * HX + 4, 1.6, 2 * HZ + 4), Vector3.new(0, F0 + SH + 9.8, 0), C.marble)
block("Roof", Vector3.new(2 * HX - 6, 2, 2 * HZ - 6), Vector3.new(0, F0 + SH + 11.4, 0), C.roof, M.Slate)
block("Floor", Vector3.new(2 * HX - 3, 0.6, 2 * HZ - 3), Vector3.new(0, FY + 0.3, 0), C.marbleWarm)

---------------------------------------------------------------------------
-- THE ROTUNDA (x 26..88, z -50..50)
---------------------------------------------------------------------------
group("Rotunda")
local RX0, RX1, RZ = 26, FRONT, 50
local RCX = (RX0 + RX1) / 2
local RH = 64
local MEZ = F0 + 20 -- the balcony floor
do
	local dome = ball("DomeOutside", 62, Vector3.new(RCX, F0 + SH + 25, 0), C.roof, M.Slate)
	dome.CanCollide = false
	cylinder("Drum", 14, 64, Vector3.new(RCX, F0 + SH + 18, 0), C.marble)
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2
		cylinder("DrumColumn", 12, 1.8, Vector3.new(RCX + math.cos(a) * 33, F0 + SH + 18, math.sin(a) * 33), C.marble)
	end
	cylinder("Lantern", 8, 10, Vector3.new(RCX, F0 + SH + 58, 0), C.marble)
	ball("LanternCap", 9, Vector3.new(RCX, F0 + SH + 62, 0), C.roof, M.Slate)
	block("Finial", Vector3.new(0.6, 6, 0.6), Vector3.new(RCX, F0 + SH + 69, 0), C.brass, M.Metal)
end
-- the rotunda's side walls (doors to the corridors at both ends) and the courtroom wall
wallZ("RotundaS", -RZ, RX0, RX1, RH, { { 34, 8 }, { 80, 8 } }, C.marbleWarm, M.Marble)
wallZ("RotundaN", RZ, RX0, RX1, RH, { { 34, 8 }, { 80, 8 } }, C.marbleWarm, M.Marble)
wallX("RotundaBack", RX0, -RZ, RZ, RH, { { 0, 14, nil, 18 } }, C.marbleWarm, M.Marble)
-- checkerboard floor + medallion
for xi = 0, math.floor((RX1 - RX0) / 4) - 1 do
	for zi = 0, math.floor(2 * RZ / 4) - 1 do
		if (xi + zi) % 2 == 0 then
			deco("Tile", Vector3.new(4, 0.08, 4), Vector3.new(RX0 + 2 + xi * 4, F0 + 0.04, -RZ + 2 + zi * 4), C.marbleDark)
		end
	end
end
cylinder("Medallion", 0.12, 26, Vector3.new(RCX, F0 + 0.1, 0), C.marbleGreen).CanCollide = false
cylinder("Medallion", 0.16, 18, Vector3.new(RCX, F0 + 0.12, 0), C.marble).CanCollide = false
cylinder("MedallionStar", 0.2, 8, Vector3.new(RCX, F0 + 0.14, 0), C.brass, M.Metal).CanCollide = false
-- the ring of green marble columns
for i = 0, 11 do
	local a = i / 12 * math.pi * 2 + math.pi / 12
	column(RCX + math.cos(a) * 21, F0, math.sin(a) * 21, 40, 3, C.marbleGreen)
end
cylinder("RingBeam", 3, 48, Vector3.new(RCX, F0 + 41.5, 0), C.marble).CanCollide = false
-- the U balcony: along both side walls (z 38..50) and across the back (x 26..36)
for _, side in { -1, 1 } do
	block("Balcony", Vector3.new(RX1 - RX0 - 2, 1.2, 12), Vector3.new((RX0 + RX1) / 2, MEZ - 0.6, side * (RZ - 6)), C.marble)
	block("BalconyRail", Vector3.new(RX1 - RX0 - 18, 0.4, 0.4), Vector3.new((RX0 + RX1) / 2 + 8, MEZ + 3.4, side * (RZ - 12)), C.brass, M.Metal)
	block("BalconyParapet", Vector3.new(RX1 - RX0 - 18, 3, 0.5), Vector3.new((RX0 + RX1) / 2 + 8, MEZ + 1.5, side * (RZ - 12)), C.marble)
end
block("BalconyBack", Vector3.new(10, 1.2, 2 * RZ - 2), Vector3.new(RX0 + 5, MEZ - 0.6, 0), C.marble)
block("BalconyBackParapet", Vector3.new(0.5, 3, 2 * RZ - 26), Vector3.new(RX0 + 10, MEZ + 1.5, 0), C.marble)
-- twin staircases along the side walls: from the front of the hall up to the balcony
do
	local n = 20
	local rise = (MEZ - F0) / n
	local run = 2
	for _, side in { -1, 1 } do
		local z = side * (RZ - 15) -- the flight is 6 wide, just inside the balcony's edge
		for i = 1, n do
			local h = rise * i
			local x = RX1 - 6 - i * run -- climbing toward the back
			block("GrandStep", Vector3.new(run, h, 6), Vector3.new(x, F0 + h / 2, z), C.marble)
		end
		block("StairTop", Vector3.new(4, MEZ - F0, 6), Vector3.new(RX1 - 6 - n * run - 2, F0 + (MEZ - F0) / 2, z), C.marble)
		-- brass rail on the open side, newel posts at the foot
		local railLen = n * run
		local rail = block("StairRail", Vector3.new(railLen + 2, 0.4, 0.4), Vector3.zero, C.brass, M.Metal)
		rail.CanCollide = false
		rail.CFrame = BASE * CFrame.new(RX1 - 6 - railLen / 2, F0 + (MEZ - F0) / 2 + 3, z - side * 3.2) * CFrame.Angles(0, 0, math.atan2(MEZ - F0, railLen))
		cylinder("Newel", 5, 1.4, Vector3.new(RX1 - 5, F0 + 2.5, z - side * 3.2), C.marble)
		ball("NewelCap", 1.8, Vector3.new(RX1 - 5, F0 + 5.4, z - side * 3.2), C.brass, M.Metal)
	end
end
-- dome inside: coffers, oculus, chandelier
block("RotundaCeiling", Vector3.new(RX1 - RX0, 1, 2 * RZ), Vector3.new(RCX, F0 + RH + 0.5, 0), C.plaster)
cylinder("DomeRing", 2, 50, Vector3.new(RCX, F0 + RH - 0.5, 0), C.marbleWarm).CanCollide = false
for ring = 0, 2 do
	local r, n = 21 - ring * 6, 16 - ring * 4
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		deco("DomeCoffer", Vector3.new(4.5 - ring, 0.6, 4.5 - ring), Vector3.new(RCX + math.cos(a) * r, F0 + RH - 1.2 - ring * 0.6, math.sin(a) * r), C.marbleGrey, M.Marble, -a)
	end
end
light(cylinder("Oculus", 0.4, 10, Vector3.new(RCX, F0 + RH + 1.1, 0), C.light, M.Neon), 60, 1.6)
cylinder("ChandelierChain", 20, 0.3, Vector3.new(RCX, F0 + RH - 10, 0), C.brass, M.Metal).CanCollide = false
for tier = 0, 2 do
	local r, y = 5 - tier * 1.4, F0 + RH - 20 - tier * 2.5
	cylinder("ChandelierRing", 0.4, r * 2, Vector3.new(RCX, y, 0), C.brass, M.Metal).CanCollide = false
	for i = 0, 9 - tier * 2 do
		local a = i / (10 - tier * 2) * math.pi * 2
		ball("ChandelierLight", 0.9, Vector3.new(RCX + math.cos(a) * r, y + 0.6, math.sin(a) * r), C.light, M.Neon).CanCollide = false
	end
end
light(ball("ChandelierHeart", 2.2, Vector3.new(RCX, F0 + RH - 24, 0), C.light, M.Neon), 70, 2)
-- security at the doors, a directory board, benches
deco("DetectorL", Vector3.new(1, 8, 1), Vector3.new(FRONT - 9, F0 + 4, -3.5), C.black, M.Metal)
deco("DetectorR", Vector3.new(1, 8, 1), Vector3.new(FRONT - 9, F0 + 4, 3.5), C.black, M.Metal)
deco("DetectorTop", Vector3.new(1.2, 1, 8), Vector3.new(FRONT - 9, F0 + 8.5, 0), C.black, M.Metal)
block("SecurityDesk", Vector3.new(4, 3.6, 10), Vector3.new(FRONT - 13, F0 + 1.8, -16), C.panel, M.Wood)
marker("MetalDetector", Vector3.new(FRONT - 9, F0 + 3, 0))
marker("RotundaSpot", Vector3.new(RCX, F0 + 3, 0))
do
	local board = block("Directory", Vector3.new(0.5, 8, 10), Vector3.new(RX0 + 1.2, F0 + 6, -20), C.panelDark, M.Wood)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Right
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.Parent = board
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.Garamond
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(230, 214, 170)
	t.Text = "DIRECTORY\nCourtroom Dept. 1 ............ ahead\nClerk of the Court ........ south hall\nCourtroom Dept. 2 ........ south hall\nRecords .......................... south hall\nAttorney Conference ...... north hall\nLaw Library ................... north hall\nWitness Waiting ............ north hall"
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Parent = gui
end
for _, z in { -30, 30 } do
	block("HallBench", Vector3.new(10, 1.8, 2.6), Vector3.new(RX0 + 8, F0 + 0.9, z), C.panel, M.Wood)
end

---------------------------------------------------------------------------
-- CORRIDORS: south z -62..-50, north z 50..62 (x -60..88), back x -60..-52 (z -62..62)
---------------------------------------------------------------------------
group("Corridors")
local CW = 12
for _, side in { -1, 1 } do
	local zc = side * (RZ + CW / 2)
	deco("Runner", Vector3.new(146, 0.1, 4), Vector3.new(15, F0 + 0.06, zc), Color3.fromRGB(110, 28, 34), M.Fabric)
	block("CorridorCeiling", Vector3.new(148, 0.8, CW), Vector3.new(14, F0 + IH + 0.4, zc), C.plaster, M.Plaster)
	for x = -48, 80, 32 do
		lamp(Vector3.new(x, F0 + IH - 1.5, zc), 30)
	end
end
block("BackCorridorCeiling", Vector3.new(8, 0.8, 2 * (RZ + CW)), Vector3.new(-56, F0 + IH + 0.4, 0), C.plaster, M.Plaster)
lamp(Vector3.new(-56, F0 + IH - 1.5, 0), 30)

---------------------------------------------------------------------------
-- MAIN COURTROOM, Dept. 1 (x -52..26, z -50..50)
---------------------------------------------------------------------------
group("Courtroom")
local CX0, CX1, CZ = -52, RX0, RZ
local CH = 44
-- side walls double as corridor walls: a door at the bench end (south: from holding / north: jury)
wallZ("CourtS", -CZ, CX0, CX1, CH, { { -40, 6 }, { -20, 7, 14, 38 }, { -2, 7, 14, 38 }, { 16, 7, 14, 38 } })
wallZ("CourtN", CZ, CX0, CX1, CH, { { -40, 6 }, { -20, 7, 14, 38 }, { -2, 7, 14, 38 }, { 16, 7, 14, 38 } })
wallX("CourtW", CX0, -CZ, CZ, CH, { { 30, 6 } }) -- the judge's door from the back corridor (north end)
block("CourtCeiling", Vector3.new(CX1 - CX0, 1, 2 * CZ), Vector3.new((CX0 + CX1) / 2, F0 + CH + 0.5, 0), C.plaster, M.Plaster)
for i = 0, 3 do
	deco("CeilingBeam", Vector3.new(2.4, 2.4, 2 * CZ), Vector3.new(CX0 + 10 + i * 20, F0 + CH - 1.2, 0), C.panelDark, M.Wood)
end
for k = 0, 4 do
	local x = CX0 + 3 + k * 18
	for _, z in { -CZ + 1.3, CZ - 1.3 } do
		deco("Pilaster", Vector3.new(3, CH - 4, 0.9), Vector3.new(x, F0 + (CH - 4) / 2, z), C.marble)
		deco("PilasterCap", Vector3.new(4, 2, 1.4), Vector3.new(x, F0 + CH - 5, z), C.marbleWarm)
	end
end
for _, z in { -CZ + 1.2, CZ - 1.2 } do
	deco("CourtCornice", Vector3.new(CX1 - CX0, 1.6, 1.6), Vector3.new((CX0 + CX1) / 2, F0 + CH - 2.5, z), C.marbleWarm)
	deco("Wainscot", Vector3.new(CX1 - CX0, 10, 0.4), Vector3.new((CX0 + CX1) / 2, F0 + 5, z - (z / math.abs(z)) * 0.6), C.panel, M.Wood)
end
deco("BenchWall", Vector3.new(0.6, 30, 2 * CZ - 24), Vector3.new(CX0 + 1.2, F0 + 15, -6), C.marble)
for _, z in { -30, 18 } do
	deco("GreenPanel", Vector3.new(0.3, 18, 12), Vector3.new(CX0 + 1.6, F0 + 14, z), C.marbleGreen)
end
deco("Floorboards", Vector3.new(CX1 - CX0, 0.2, 2 * CZ), Vector3.new((CX0 + CX1) / 2, F0 + 0.1, 0), C.wood, M.WoodPlanks)
block("BenchDais", Vector3.new(12, 4, 30), Vector3.new(CX0 + 8, F0 + 2, 0), C.panelDark, M.Wood)
for k = 1, 4 do -- the judge's steps up onto the bench, from the door side
	block("BenchStep", Vector3.new(10, k, 1.5), Vector3.new(CX0 + 8, F0 + k / 2, 15 + (4 - k) * 1.5 + 0.75), C.panelDark, M.Wood)
end
block("BenchFront", Vector3.new(2, 7, 30), Vector3.new(CX0 + 14, F0 + 3.5, 0), C.panel, M.Wood)
for k = -3, 3 do
	deco("BenchPanel", Vector3.new(0.3, 4.6, 3.2), Vector3.new(CX0 + 15.1, F0 + 3.5, k * 4), C.panelDark, M.Wood)
end
block("BenchTop", Vector3.new(4, 0.6, 31), Vector3.new(CX0 + 13, F0 + 7.3, 0), C.panelDark, M.Wood)
chair("JudgeSeat", Vector3.new(CX0 + 8, F0 + 4.6, 0), Vector3.new(1, 0, 0), C.black)
cylinder("Seal", 0.5, 12, Vector3.new(CX0 + 1.8, F0 + 22, -6), C.brass, M.Metal, "x").CanCollide = false
cylinder("SealInner", 0.6, 8, Vector3.new(CX0 + 1.9, F0 + 22, -6), C.bronze, M.Metal, "x").CanCollide = false
for _, z in { -14, 6 } do
	cylinder("FlagPole", 16, 0.4, Vector3.new(CX0 + 4, F0 + 8, z), C.brass, M.Metal)
	deco("Flag", Vector3.new(0.2, 5, 6), Vector3.new(CX0 + 4, F0 + 13, z + (if z > 0 then 3 else -3)), if z > 0 then Color3.fromRGB(40, 60, 140) else Color3.fromRGB(160, 40, 40), M.Fabric)
end
block("ClerkDesk", Vector3.new(4, 3.4, 10), Vector3.new(CX0 + 18, F0 + 1.7, 16), C.panel, M.Wood)
chair("CourtClerkSeat", Vector3.new(CX0 + 15, F0 + 1, 16), Vector3.new(1, 0, 0))
block("WitnessBox", Vector3.new(7, 2, 7), Vector3.new(CX0 + 14, F0 + 1, -22), C.panelDark, M.Wood)
deco("WitnessRail", Vector3.new(0.5, 4, 7), Vector3.new(CX0 + 17.6, F0 + 4, -22), C.panel, M.Wood)
block("WitnessStep", Vector3.new(4, 1, 1.6), Vector3.new(CX0 + 13, F0 + 0.5, -17.7), C.panelDark, M.Wood) -- up into the box
chair("WitnessSeat", Vector3.new(CX0 + 13.5, F0 + 2.4, -22), Vector3.new(1, 0, 0.3))
block("DefenseTable", Vector3.new(5, 3.2, 14), Vector3.new(CX0 + 31, F0 + 1.6, -12), C.panel, M.Wood)
chair("DefendantSeat", Vector3.new(CX0 + 35, F0 + 1, -15), Vector3.new(-1, 0, 0))
chair("DefenseSeat", Vector3.new(CX0 + 35, F0 + 1, -9), Vector3.new(-1, 0, 0))
block("ProsecutionTable", Vector3.new(5, 3.2, 14), Vector3.new(CX0 + 31, F0 + 1.6, 12), C.panel, M.Wood)
chair("ProsecutorSeat", Vector3.new(CX0 + 35, F0 + 1, 12), Vector3.new(-1, 0, 0))
marker("BailiffSpot", Vector3.new(CX0 + 20, F0 + 3, -34))
block("JuryDais", Vector3.new(26, 1.2, 6), Vector3.new(CX0 + 35, F0 + 0.6, 38), C.panelDark, M.Wood)
block("JuryDais2", Vector3.new(26, 2.4, 5), Vector3.new(CX0 + 35, F0 + 1.2, 43.5), C.panelDark, M.Wood)
block("JuryRail", Vector3.new(20, 3.5, 0.6), Vector3.new(CX0 + 38, F0 + 1.75, 34.6), C.panel, M.Wood) -- open at the bench end
for row = 0, 1 do
	for i = 1, 6 do
		chair("JurorSeat" .. (row * 6 + i), Vector3.new(CX0 + 24 + (i - 1) * 4.2, F0 + 1.6 + row * 1.2, 37 + row * 5.5), Vector3.new(0, 0, -1), C.panel)
	end
end
-- the bar with a swing gate in the middle, then the gallery
block("BarRailS", Vector3.new(0.8, 3.4, 40), Vector3.new(CX0 + 47, F0 + 1.7, -24), C.panel, M.Wood)
block("BarRailN", Vector3.new(0.8, 3.4, 26), Vector3.new(CX0 + 47, F0 + 1.7, 17), C.panel, M.Wood)
local g = 0
for row = 0, 5 do
	local x = CX0 + 53 + row * 4.4
	for _, side in { -1, 1 } do
		local zc = side * 27
		block("Pew", Vector3.new(2.4, 1.6, 28), Vector3.new(x, F0 + 1.3, zc), C.panel, M.Wood)
		block("PewBack", Vector3.new(0.5, 3.6, 28), Vector3.new(x + 1.3, F0 + 2.4, zc), C.panel, M.Wood)
		for k = 0, 5 do
			g += 1
			local s = chair("GallerySeat" .. g, Vector3.new(x, F0 + 2.2, zc - 12 + k * 4.8), Vector3.new(-1, 0, 0), C.panel, true)
			s.Transparency = 1
		end
	end
end
for _, x in { CX0 + 14, CX0 + 40, CX0 + 66 } do
	for _, z in { -24, 24 } do
		cylinder("PendantRod", 6, 0.2, Vector3.new(x, F0 + CH - 3, z), C.brass, M.Metal).CanCollide = false
		light(ball("Pendant", 2.4, Vector3.new(x, F0 + CH - 7, z), C.light, M.Neon), 44, 1.2)
	end
end
marker("Room_Courtroom", Vector3.new(CX0 + 60, F0 + 3, 0))

---------------------------------------------------------------------------
-- THE SOUTH WING (z -116..-62): Clerk | Records | Restrooms | Courtroom Dept. 2 | Holding
---------------------------------------------------------------------------
group("SouthWing")
local SZ0, SZ1 = -HZ, -(RZ + CW) -- -116 .. -62
-- the corridor's outer wall, with a door into every room
wallZ("SouthHallWall", SZ1, -60, FRONT, IH, { { 72, 8 }, { 40, 6 }, { 15, 5 }, { -4, 8 }, { -36, 8 } })
-- room dividers
wallX("ClerkDivider", 54, SZ0, SZ1, IH, { { -100, 6 } }) -- clerk staff into records
wallX("RecordsDivider", 26, SZ0, SZ1, IH, nil)
wallX("RestroomDivider", 4, SZ0, SZ1, IH, nil)
wallX("HoldingDivider", -60, SZ0, SZ1, IH, nil)
-- CLERK'S OFFICE (x 54..88): the public counter by the door, desks and filing cabinets behind
room("ClerksOffice", 54, FRONT, SZ0, SZ1, IH, nil, C.marbleWarm, M.Marble)
block("ClerkCounter", Vector3.new(26, 4, 3), Vector3.new(73, F0 + 2, -70), C.panel, M.Wood)
deco("ClerkGrille", Vector3.new(26, 7, 0.3), Vector3.new(73, F0 + 7.5, -70.6), C.brass, M.DiamondPlate).Transparency = 0.45
deco("ClerkCounterGate", Vector3.new(5, 3.4, 0.4), Vector3.new(57, F0 + 1.7, -70), C.panelDark, M.Wood) -- staff walk through
marker("ClerkWindow", Vector3.new(71, F0 + 3, -66))
marker("ClerkSpot", Vector3.new(71, F0 + 3, -75))
for i = 0, 2 do
	block("ClerkDesk", Vector3.new(6, 3, 4), Vector3.new(62 + i * 9, F0 + 1.5, -86), C.panelDark, M.Wood)
	chair("ClerkChair" .. i, Vector3.new(62 + i * 9, F0 + 1, -89), Vector3.new(0, 0, 1))
	block("FilingCabinet", Vector3.new(3, 6, 2), Vector3.new(62 + i * 9, F0 + 3, SZ0 + 2), C.marbleGrey, M.Metal)
end
-- RECORDS (x 26..54): rows of shelving
room("Records", 26, 54, SZ0, SZ1, IH, nil, C.wood)
for i = 0, 4 do
	block("RecordShelf", Vector3.new(20, 12, 2), Vector3.new(40, F0 + 6, -78 - i * 7), C.panelDark, M.Wood)
	for k = 0, 3 do
		deco("Files", Vector3.new(19, 1.8, 1.8), Vector3.new(40, F0 + 1.8 + k * 3, -78 - i * 7), Color3.fromRGB(200 - k * 20, 180, 140), M.Fabric)
	end
end
-- RESTROOMS (x 4..26)
room("Restrooms", 4, 26, SZ0, SZ1, IH, nil, C.tile, M.SmoothPlastic)
for i = 0, 3 do
	block("Stall", Vector3.new(0.4, 8, 7), Vector3.new(6 + i * 5, F0 + 4, -108), C.marbleGrey)
	block("Sink", Vector3.new(2, 3, 3), Vector3.new(5.6, F0 + 3, -72 - i * 5), C.tile, M.SmoothPlastic)
end
-- COURTROOM Dept. 2 (x -60..4): a smaller courtroom
room("CourtroomDept2", -60, 4, SZ0, SZ1, IH, nil, C.wood)
block("Dept2Bench", Vector3.new(6, 5, 18), Vector3.new(-55, F0 + 2.5, -90), C.panelDark, M.Wood)
chair("Dept2JudgeSeat", Vector3.new(-57, F0 + 5.2, -90), Vector3.new(1, 0, 0), C.black)
block("Dept2Table", Vector3.new(4, 3, 10), Vector3.new(-40, F0 + 1.5, -96), C.panel, M.Wood)
block("Dept2Table", Vector3.new(4, 3, 10), Vector3.new(-40, F0 + 1.5, -82), C.panel, M.Wood)
for row = 0, 3 do
	block("Dept2Pew", Vector3.new(2.4, 1.6, 34), Vector3.new(-26 + row * 6, F0 + 1.3, -92), C.panel, M.Wood)
	block("Dept2PewBack", Vector3.new(0.5, 3.6, 34), Vector3.new(-24.7 + row * 6, F0 + 2.4, -92), C.panel, M.Wood)
end
cylinder("Dept2Seal", 0.5, 8, Vector3.new(-59, F0 + 14, -90), C.brass, M.Metal, "x").CanCollide = false

---------------------------------------------------------------------------
-- THE NORTH WING (z 62..116): Conference 1 & 2 | Law Library | Witness Waiting | JURY ROOM
---------------------------------------------------------------------------
group("NorthWing")
local NZ0, NZ1 = RZ + CW, HZ -- 62 .. 116
wallZ("NorthHallWall", NZ0, -60, FRONT, IH, { { 77, 6 }, { 55, 6 }, { 27, 8 }, { 0, 6 }, { -31, 7 } })
wallX("ConfDivider", 66, NZ0, NZ1, IH, nil)
wallX("LibraryDivider", 44, NZ0, NZ1, IH, nil)
wallX("WitnessDivider", 10, NZ0, NZ1, IH, nil)
wallX("JuryDivider", -10, NZ0, NZ1, IH, nil)
wallX("ChambersDivider", -60, NZ0, NZ1, IH, nil)
-- ATTORNEY CONFERENCE ROOMS
for i, r in { { 66, FRONT }, { 44, 66 } } do
	room("AttorneyConference" .. i, r[1], r[2], NZ0, NZ1, IH, nil, C.wood)
	local cx = (r[1] + r[2]) / 2
	block("ConfTable", Vector3.new(8, 0.6, 22), Vector3.new(cx, F0 + 3.2, 89), C.panelDark, M.Wood)
	block("ConfTableBase", Vector3.new(3, 2.9, 12), Vector3.new(cx, F0 + 1.45, 89), C.panelDark, M.Wood)
	for k = 0, 3 do
		chair("ConfChair" .. i .. "_" .. k .. "a", Vector3.new(cx - 6, F0 + 1, 80 + k * 6), Vector3.new(1, 0, 0), C.leather)
		chair("ConfChair" .. i .. "_" .. k .. "b", Vector3.new(cx + 6, F0 + 1, 80 + k * 6), Vector3.new(-1, 0, 0), C.leather)
	end
end
-- LAW LIBRARY: tall bookcases, reading tables with green lamps
room("LawLibrary", 10, 44, NZ0, NZ1, IH, nil, C.wood)
for i = 0, 3 do
	block("Bookcase", Vector3.new(26, 18, 2), Vector3.new(27, F0 + 9, 80 + i * 9), C.panelDark, M.Wood)
	for k = 0, 4 do
		deco("Books", Vector3.new(25, 2.6, 2.1), Vector3.new(27, F0 + 2 + k * 3.5, 80 + i * 9), if k % 2 == 0 then C.books else C.green, M.Fabric)
	end
end
for _, x in { 16, 38 } do
	block("ReadingTable", Vector3.new(4, 3, 10), Vector3.new(x, F0 + 1.5, 108), C.panel, M.Wood)
	ball("BankerLamp", 1.2, Vector3.new(x, F0 + 3.8, 108), C.green, M.Glass).CanCollide = false
end
-- WITNESS WAITING
room("WitnessWaiting", -10, 10, NZ0, NZ1, IH, nil, C.wood)
for k = 0, 3 do
	block("WaitingBench", Vector3.new(14, 1.8, 2.6), Vector3.new(0, F0 + 0.9, 74 + k * 11), C.panel, M.Wood)
end
block("WaterFountain", Vector3.new(2, 4, 1.6), Vector3.new(8, F0 + 2, 112), C.tile, M.SmoothPlastic)
-- THE JURY ROOM (x -60..-10): the long table, twelve chairs, tall windows, the clock, the fan
room("JuryRoom", -60, -10, NZ0, NZ1, IH, C.jury, C.wood)
local jcx, jcz = -35, 89
block("JuryTable", Vector3.new(36, 0.8, 8), Vector3.new(jcx, F0 + 3.4, jcz), C.wood, M.Wood)
for _, dx in { -16, 16 } do
	for _, dz in { -3, 3 } do
		block("TableLeg", Vector3.new(0.6, 3, 0.6), Vector3.new(jcx + dx, F0 + 1.5, jcz + dz), C.panelDark, M.Wood)
	end
end
local j = 0
for side = -1, 1, 2 do
	for i = 0, 4 do
		j += 1
		chair("JuryRoomSeat" .. j, Vector3.new(jcx - 14 + i * 7, F0 + 1.6, jcz + side * 6.5), Vector3.new(0, 0, -side), C.wood)
	end
end
chair("JuryRoomSeat11", Vector3.new(jcx - 21, F0 + 1.6, jcz), Vector3.new(1, 0, 0), C.wood) -- the foreman's end
chair("JuryRoomSeat12", Vector3.new(jcx + 21, F0 + 1.6, jcz), Vector3.new(-1, 0, 0), C.wood)
marker("JuryRoomSpot", Vector3.new(jcx, F0 + 3, NZ0 + 5))
cylinder("WallClock", 0.4, 3, Vector3.new(-10.9, F0 + 18, jcz), Color3.fromRGB(245, 240, 225), M.SmoothPlastic, "x").CanCollide = false
deco("FanStand", Vector3.new(0.4, 5, 0.4), Vector3.new(-56, F0 + 2.5, 110), C.black, M.Metal)
cylinder("FanCage", 1.2, 3.4, Vector3.new(-55.7, F0 + 5.6, 110), C.black, M.Metal, "x").CanCollide = false
block("WaterCooler", Vector3.new(1.6, 4.5, 1.6), Vector3.new(-13, F0 + 2.25, NZ0 + 4), Color3.fromRGB(220, 225, 230), M.SmoothPlastic)
deco("WashroomDoor", Vector3.new(0.4, 9, 4.5), Vector3.new(-10.9, F0 + 4.5, 106), C.panel, M.Wood)
deco("CoatRack", Vector3.new(0.4, 7, 0.4), Vector3.new(-57, F0 + 3.5, NZ0 + 4), C.panelDark, M.Wood)

---------------------------------------------------------------------------
-- THE BACK (x -88..-60): Holding | Court Officers | Robing | Judge's Chambers
---------------------------------------------------------------------------
group("BackRooms")
local BX0, BX1 = -HX, -60
-- the back corridor's outer wall (x -60), a door into each back room
wallX("BackHallWall", BX1, SZ1, NZ0, IH, { { -40, 6 }, { 0, 6 }, { 40, 6 } })
-- back rooms split along z
wallZ("HoldingNorthWall", -20, BX0, BX1, IH, nil)
wallZ("OfficersNorthWall", 20, BX0, BX1, IH, nil)
-- the corners of the side wings (x -88..-60) belong to the back rooms
wallZ("HoldingSouthEnd", SZ1, BX0, BX1, IH, { { -74, 8 } }) -- holding opens into its own sally port hall
wallZ("ChambersNorthEnd", NZ0, BX0, BX1, IH, { { -74, 6 } })
-- COURT HOLDING (z -116..-20): the sally port hall (z -116..-62), then the cells
room("CourtHolding", BX0, BX1, -116, -20, IH, nil, C.granite, M.Concrete)
for c = 0, 1 do
	local z0 = -58 + c * 19
	for i = 0, 8 do
		if i < 3 or i > 5 then -- the open cell door in the middle
			cylinder("CellBar", 12, 0.4, Vector3.new(-66, F0 + 6, z0 + 1 + i * 1.6), C.black, M.Metal)
		end
	end
	wallZ("CellWall", z0 + 17, BX0, -66, 14, nil, C.granite, M.Concrete)
	block("CellBench", Vector3.new(2.4, 1.8, 12), Vector3.new(BX0 + 3, F0 + 0.9, z0 + 8), C.granite, M.Concrete)
end
marker("HoldingSpot", Vector3.new(-76, F0 + 3, -49))
marker("Room_SallyPort", Vector3.new(-76, F0 + 3, -90))
-- COURT OFFICERS (z -20..20): lockers, a desk, the monitors
room("CourtOfficers", BX0, BX1, -20, 20, IH, nil, C.marbleGrey, M.Marble)
for i = 0, 5 do
	block("Locker", Vector3.new(2, 7, 2.6), Vector3.new(BX0 + 2, F0 + 3.5, -16 + i * 3), Color3.fromRGB(70, 80, 96), M.Metal)
end
block("OfficersDesk", Vector3.new(4, 3, 10), Vector3.new(-72, F0 + 1.5, 8), C.panelDark, M.Wood)
deco("Monitors", Vector3.new(0.6, 3, 8), Vector3.new(-73.5, F0 + 4.6, 8), C.black, M.Glass)
-- ROBING ROOM (z 20..62)
room("RobingRoom", BX0, BX1, 20, NZ0, IH, nil, C.wood)
for i = 0, 3 do
	deco("RobeHook", Vector3.new(0.6, 0.6, 0.6), Vector3.new(BX0 + 1.6, F0 + 8, 26 + i * 6), C.brass, M.Metal)
	deco("Robe", Vector3.new(0.6, 6, 2.4), Vector3.new(BX0 + 1.8, F0 + 4.8, 26 + i * 6), C.black, M.Fabric)
end
block("RobingBench", Vector3.new(2.6, 1.8, 14), Vector3.new(-66, F0 + 0.9, 40), C.panel, M.Wood)
-- JUDGE'S CHAMBERS (z 62..116): the desk, bookcases, leather chairs, a rug
room("JudgesChambers", BX0, BX1, NZ0, HZ, IH, nil, C.wood)
deco("Rug", Vector3.new(18, 0.1, 24), Vector3.new(-74, F0 + 0.15, 92), Color3.fromRGB(110, 28, 34), M.Fabric)
block("ChambersDesk", Vector3.new(5, 3.2, 10), Vector3.new(-80, F0 + 1.6, 92), C.panelDark, M.Wood)
chair("ChambersChair", Vector3.new(-84, F0 + 1, 92), Vector3.new(1, 0, 0), C.leather)
chair("ChambersGuest1", Vector3.new(-74, F0 + 1, 88), Vector3.new(-1, 0, 0), C.leather)
chair("ChambersGuest2", Vector3.new(-74, F0 + 1, 96), Vector3.new(-1, 0, 0), C.leather)
block("ChambersBookcase", Vector3.new(2, 16, 26), Vector3.new(BX0 + 1.6, F0 + 8, 92), C.panelDark, M.Wood)
marker("ChambersSpot", Vector3.new(-70, F0 + 3, 80))

-- room markers that would sit inside furniture move to open floor inside the room
for name, pos in {
	Room_AttorneyConference1 = Vector3.new(77, F0 + 3, 68), Room_AttorneyConference2 = Vector3.new(55, F0 + 3, 68),
	Room_CourtroomDept2 = Vector3.new(-36, F0 + 3, -70), Room_JuryRoom = Vector3.new(-35, F0 + 3, 72),
} do
	local m = markers:FindFirstChild(name) :: BasePart?
	if m then m.CFrame = BASE * CFrame.new(pos) end
end

model:SetAttribute("Facility", "Courthouse")
model:SetAttribute("Inspiration", "12 Angry Men (1957) - New York County Courthouse, 60 Centre Street")
model.PrimaryPart = groups.Entry:FindFirstChild("Podium") :: BasePart
model.Parent = workspace

---------------------------------------------------------------------------
-- CHECK: every room must be walkable from the street (and the cells from the sally port)
---------------------------------------------------------------------------
local PathfindingService = game:GetService("PathfindingService")
local function reach(fromName: string, toPart: BasePart): string
	local from = markers:FindFirstChild(fromName) :: BasePart
	local path = PathfindingService:CreatePath({ AgentRadius = 1.5, AgentHeight = 5, AgentCanJump = false, WaypointSpacing = 6 })
	local ok = pcall(function()
		path:ComputeAsync(from.Position, toPart.Position)
	end)
	return if ok and path.Status == Enum.PathStatus.Success then "ok" else ("FAIL (%s)"):format(if ok then path.Status.Name else "error")
end
local report = {}
local fails = 0
for _, m in markers:GetChildren() do
	if m:IsA("BasePart") and (m.Name:sub(1, 5) == "Room_" or m.Name == "RotundaSpot" or m.Name == "ClerkWindow" or m.Name == "JuryRoomSpot" or m.Name == "ChambersSpot" or m.Name == "BailiffSpot") then
		local r = reach("VehicleDropoff", m)
		if r ~= "ok" then fails += 1 end
		table.insert(report, m.Name .. ": " .. r)
	end
end
local h = markers:FindFirstChild("HoldingSpot") :: BasePart
local r = reach("PrisonerDropoff", h)
if r ~= "ok" then fails += 1 end
table.insert(report, "PrisonerDropoff -> HoldingSpot: " .. r)
do
	local function reachP(label: string, a: Vector3, b: Vector3)
		local path = PathfindingService:CreatePath({ AgentRadius = 1.5, AgentHeight = 5, AgentCanJump = false })
		local ok = pcall(function() path:ComputeAsync(a, b) end)
		local good = ok and path.Status == Enum.PathStatus.Success
		if not good then fails += 1 end
		table.insert(report, label .. ": " .. (if good then "ok" else "FAIL"))
	end
	local rs = (markers:FindFirstChild("RotundaSpot") :: BasePart).CFrame
	local function at(n: string): Vector3 return (markers:FindFirstChild(n) :: BasePart).Position + Vector3.new(0, 2, 0) end
	reachP("~ rotunda -> south balcony", rs.Position, (rs * CFrame.new(10, 20.5, -44)).Position)
	reachP("~ rotunda -> north balcony", rs.Position, (rs * CFrame.new(10, 20.5, 44)).Position)
	reachP("~ jury room -> jury box", at("JuryRoomSpot"), at("JurorSeat1"))
	reachP("~ holding -> defendant's chair", at("HoldingSpot"), at("DefendantSeat"))
	reachP("~ chambers -> judge's chair", at("ChambersSpot"), at("JudgeSeat"))
	reachP("~ gallery -> witness stand", at("Room_Courtroom"), at("WitnessSeat"))
end
table.sort(report)
print(("[Courthouse] built: %d parts, %d walkability failures"):format(#model:GetDescendants(), fails))
return ("%d parts, %d failures\n%s"):format(#model:GetDescendants(), fails, table.concat(report, "\n"))
