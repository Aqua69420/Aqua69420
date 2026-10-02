-- Builds workspace.Courthouse (run once in Studio's Edit datamodel; v263).
-- Modelled on the courthouse in 12 Angry Men (1957) - the New York County Courthouse:
-- a raised stone podium with a broad staircase, a colonnade of giant columns under a
-- pediment, a marble rotunda lobby, a tall wood-panelled courtroom with high windows,
-- and the jury room: one long table, twelve chairs, tall windows, a wall clock, a fan,
-- a water cooler and the washroom door.
--
-- Markers the Court module looks up (CourtMarkers folder):
--   seats:  JudgeSeat, WitnessSeat, DefendantSeat, DefenseSeat, ProsecutorSeat, JurorSeat1-12,
--           GallerySeat1-n, JuryRoomSeat1-12
--   points: BailiffSpot, ClerkWindow, MetalDetector, CourthouseSteps, VehicleDropoff, HoldingSpot,
--           JuryRoomSpot, ChambersSpot, ClerkSpot
-- Placed on the user's lot (Workspace["Caesars Palace2"].FacilityMap Courtroom zone:
-- x 1700..2267, z -1810..-1501, roads on every side). Local +X = the front = world +Z (the north road).
do
	local prev = workspace:FindFirstChild("Courthouse")
	if prev then prev:Destroy() end -- before the ground ray, or it lands on the old roof
end
local GROUND = workspace:Raycast(Vector3.new(1983.7, 600, -1640), Vector3.new(0, -700, 0))
local GY = if GROUND then GROUND.Position.Y else 1
local BASE = CFrame.new(1983.7, GY, -1640) * CFrame.Angles(0, math.rad(-90), 0)

local FY = 7 -- the podium: the ground floor is this high above the street
local HALF_X, HALF_Z = 90, 112 -- the building: x -90..90 (depth), z -112..112 (width)

local old = workspace:FindFirstChild("Courthouse")
if old then old:Destroy() end
local model = Instance.new("Model")
model.Name = "Courthouse"
local markers = Instance.new("Folder")
markers.Name = "CourtMarkers"
markers.Parent = model

local C = {
	stone = Color3.fromRGB(214, 208, 194), stoneDark = Color3.fromRGB(176, 170, 156), marble = Color3.fromRGB(232, 228, 220),
	marbleDark = Color3.fromRGB(70, 66, 62), plaster = Color3.fromRGB(226, 218, 198), panel = Color3.fromRGB(92, 58, 34),
	panelDark = Color3.fromRGB(64, 40, 24), wood = Color3.fromRGB(118, 76, 44), green = Color3.fromRGB(70, 92, 76),
	glass = Color3.fromRGB(190, 210, 220), brass = Color3.fromRGB(196, 160, 84), roof = Color3.fromRGB(96, 96, 100),
	jury = Color3.fromRGB(200, 196, 170), black = Color3.fromRGB(28, 28, 30),
}
local M = Enum.Material

local function put(p: BasePart, cf: CFrame, color: Color3, material: Enum.Material?, parent: Instance?)
	p.Anchored = true
	p.CFrame = BASE * cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent or model
	return p
end

local function block(name: string, size: Vector3, pos: Vector3, color: Color3, material: Enum.Material?, rotY: number?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	return put(p, CFrame.new(pos) * CFrame.Angles(0, rotY or 0, 0), color, material)
end

local function cylinder(name: string, length: number, diameter: number, pos: Vector3, color: Color3, material: Enum.Material?, vertical: boolean?)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(length, diameter, diameter)
	local cf = CFrame.new(pos) * (if vertical then CFrame.Angles(0, 0, math.rad(90)) else CFrame.identity)
	return put(p, cf, color, material)
end

-- a wall from a to b (local XZ) from floor y0, height h; gaps = { { along, width, sill?, top? } }
-- a gap with a sill is a WINDOW (glass fills it), without one it's a doorway
local function wall(name: string, a: Vector2, b: Vector2, y0: number, h: number, gaps: { { number } }?, color: Color3?, material: Enum.Material?, thick: number?)
	local dir = b - a
	local len = dir.Magnitude
	local u = dir.Unit
	local rot = -math.atan2(u.Y, u.X)
	local function seg(from: number, to: number, ya: number, yb: number, nm: string, col: Color3, mat: Enum.Material, transp: number?)
		if to - from < 0.05 or yb - ya < 0.05 then return end
		local mid = a + u * ((from + to) / 2)
		local p = block(nm, Vector3.new(to - from, yb - ya, thick or 1.5), Vector3.new(mid.X, (ya + yb) / 2, mid.Y), col, mat, rot)
		if transp then p.Transparency = transp end
	end
	local col, mat = color or C.stone, material or M.Concrete
	local cuts = {}
	for _, g in gaps or {} do table.insert(cuts, g) end
	table.sort(cuts, function(x, y) return x[1] < y[1] end)
	local at = 0
	for _, g in cuts do
		local s, e = g[1] - g[2] / 2, g[1] + g[2] / 2
		seg(at, s, y0, y0 + h, name, col, mat)
		local sill, top = g[3], g[4] or (if g[3] then h - 6 else 12)
		if sill then
			seg(s, e, y0, y0 + sill, name, col, mat)
			seg(s, e, y0 + sill, y0 + top, name .. "Window", C.glass, M.Glass, 0.55)
		end
		seg(s, e, y0 + top, y0 + h, name, col, mat)
		at = e
	end
	seg(at, len, y0, y0 + h, name, col, mat)
end

-- dark wood wainscot along a wall line (inside faces)
local function wainscot(a: Vector2, b: Vector2, y0: number, h: number, offset: Vector2)
	local mid = (a + b) / 2 + offset
	local u = (b - a).Unit
	block("Wainscot", Vector3.new((b - a).Magnitude, h, 0.4), Vector3.new(mid.X, y0 + h / 2, mid.Y), C.panel, M.Wood, -math.atan2(u.Y, u.X))
	block("WainscotRail", Vector3.new((b - a).Magnitude, 0.5, 0.7), Vector3.new(mid.X, y0 + h, mid.Y), C.panelDark, M.Wood, -math.atan2(u.Y, u.X))
end

local function marker(name: string, pos: Vector3)
	local p = block(name, Vector3.one, pos, Color3.new(1, 1, 0))
	p.Transparency = 1
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	p.Parent = markers
	return p
end

-- a chair (Seat + back) facing `face` (local XZ)
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

local function lamp(pos: Vector3, range: number, brightness: number?)
	local p = cylinder("Lamp", 0.8, 3, pos, Color3.fromRGB(255, 244, 214), M.Neon, true)
	local l = Instance.new("PointLight")
	l.Range = range
	l.Brightness = brightness or 1.1
	l.Color = Color3.fromRGB(255, 236, 200)
	l.Parent = p
end

---------------------------------------------------------------------------
-- podium, staircase, colonnade, pediment
---------------------------------------------------------------------------
block("Podium", Vector3.new(HALF_X * 2, FY, HALF_Z * 2), Vector3.new(0, FY / 2, 0), C.stoneDark, M.Concrete)
local steps = 10
for i = 1, steps do
	local h = FY * i / steps
	block("Step", Vector3.new(2.6, h, 180), Vector3.new(HALF_X + 30 - (i - 1) * 2.6, h / 2, 0), C.stone, M.Concrete)
end
block("Terrace", Vector3.new(30 - 2.6 * (steps - 1) + 2.6, FY, 186), Vector3.new(HALF_X + (30 - 2.6 * (steps - 1)) / 2, FY / 2, 0), C.stone, M.Concrete)
block("StepCheekL", Vector3.new(34, FY + 2, 6), Vector3.new(HALF_X + 15, (FY + 2) / 2, -93), C.stoneDark, M.Concrete)
block("StepCheekR", Vector3.new(34, FY + 2, 6), Vector3.new(HALF_X + 15, (FY + 2) / 2, 93), C.stoneDark, M.Concrete)

local COL_H = 54
local colX = HALF_X + 7
for i = 0, 9 do
	local z = -81 + i * 18
	block("ColumnBase", Vector3.new(6, 2, 6), Vector3.new(colX, FY + 1, z), C.stone, M.Marble)
	cylinder("Column", COL_H - 6, 4.4, Vector3.new(colX, FY + 2 + (COL_H - 6) / 2, z), C.stone, M.Marble, true)
	-- Corinthian capital: flared blocks
	block("Capital", Vector3.new(5.2, 2, 5.2), Vector3.new(colX, FY + COL_H - 3, z), C.stone, M.Marble)
	block("CapitalTop", Vector3.new(6.4, 1.6, 6.4), Vector3.new(colX, FY + COL_H - 1.2, z), C.stone, M.Marble)
end
local ENT_Y = FY + COL_H
block("Entablature", Vector3.new(12, 6, 190), Vector3.new(colX - 1, ENT_Y + 3, 0), C.stone, M.Marble)
do
	-- the inscription on the frieze
	local frieze = block("Frieze", Vector3.new(0.4, 3.4, 150), Vector3.new(colX + 5.2, ENT_Y + 3, 0), C.stone, M.Marble)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.Parent = frieze
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.Garamond
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(110, 102, 88)
	t.Text = "THE TRUE ADMINISTRATION OF JUSTICE IS THE FIRMEST PILLAR OF GOOD GOVERNMENT"
	t.Parent = gui
	-- SurfaceGui faces the part's -Z; the part is turned so -Z points out of the building
	frieze.CFrame = BASE * CFrame.new(colX + 5.2, ENT_Y + 3, 0) * CFrame.Angles(0, math.rad(-90), 0)
	frieze.Size = Vector3.new(150, 3.4, 0.4)
end
-- pediment: two wedges make the triangle
do
	local span, rise = 190, 22
	for side = -1, 1, 2 do
		local w = Instance.new("WedgePart")
		w.Name = "Pediment"
		w.Size = Vector3.new(10, rise, span / 2)
		put(w, CFrame.new(colX - 1, ENT_Y + 6 + rise / 2, side * span / 4) * CFrame.Angles(0, if side > 0 then math.rad(180) else 0, 0), C.stone, M.Marble)
	end
end
block("CornerTower", Vector3.new(16, ENT_Y + 4, 16), Vector3.new(HALF_X - 2, (ENT_Y + 4) / 2, -HALF_Z + 8), C.stone, M.Concrete)
block("CornerTower", Vector3.new(16, ENT_Y + 4, 16), Vector3.new(HALF_X - 2, (ENT_Y + 4) / 2, HALF_Z - 8), C.stone, M.Concrete)

---------------------------------------------------------------------------
-- outer shell (3 storeys tall) and roof
---------------------------------------------------------------------------
local SH = 64 -- shell height above the podium
local winGaps = function(len: number, every: number, w: number): { { number } }
	local g = {}
	local n = math.floor(len / every)
	local start = (len - (n - 1) * every) / 2
	for i = 0, n - 1 do
		table.insert(g, { start + i * every, w, 8, 26 }) -- ground-floor windows
	end
	return g
end
-- front wall behind the colonnade, with three tall bronze doorways
wall("FrontWall", Vector2.new(HALF_X, -HALF_Z), Vector2.new(HALF_X, HALF_Z), FY, SH,
	{ { HALF_Z - 30, 10 }, { HALF_Z, 12 }, { HALF_Z + 30, 10 }, { 30, 8, 10, 30 }, { 2 * HALF_Z - 30, 8, 10, 30 } }, C.stone, M.Concrete, 3)
wall("BackWall", Vector2.new(-HALF_X, -HALF_Z), Vector2.new(-HALF_X, HALF_Z), FY, SH, { { 30, 10 } }, C.stone, M.Concrete, 3)
wall("SideWallS", Vector2.new(-HALF_X, -HALF_Z), Vector2.new(HALF_X, -HALF_Z), FY, SH, winGaps(2 * HALF_X, 22, 7), C.stone, M.Concrete, 3)
wall("SideWallN", Vector2.new(-HALF_X, HALF_Z), Vector2.new(HALF_X, HALF_Z), FY, SH, winGaps(2 * HALF_X, 22, 7), C.stone, M.Concrete, 3)
block("Cornice", Vector3.new(2 * HALF_X + 6, 3, 2 * HALF_Z + 6), Vector3.new(0, FY + SH + 1.5, 0), C.stone, M.Marble)
block("Roof", Vector3.new(2 * HALF_X, 2, 2 * HALF_Z), Vector3.new(0, FY + SH + 3.5, 0), C.roof, M.Slate)
block("Floor", Vector3.new(2 * HALF_X - 3, 0.6, 2 * HALF_Z - 3), Vector3.new(0, FY + 0.3, 0), C.marble, M.Marble)
local F0 = FY + 0.6 -- the floor surface

---------------------------------------------------------------------------
-- rotunda lobby (x 40..90, z -50..50): marble, a dome, clerk's office, metal detector
---------------------------------------------------------------------------
local LOB = 40
for i = -4, 4 do
	block("FloorInlay", Vector3.new(48, 0.08, 1.2), Vector3.new(65, F0 + 0.04, i * 11), C.marbleDark, M.Marble)
end
cylinder("RotundaRing", 0.2, 46, Vector3.new(65, F0 + 0.1, 0), C.marbleDark, M.Marble, true)
wall("LobbyBack", Vector2.new(LOB, -HALF_Z), Vector2.new(LOB, HALF_Z), F0, 46, { { HALF_Z, 14 } }, C.plaster, M.Plaster)
wall("LobbyS", Vector2.new(LOB, -50), Vector2.new(HALF_X, -50), F0, 46, { { 25, 8 } }, C.plaster, M.Plaster)
wall("LobbyN", Vector2.new(LOB, 50), Vector2.new(HALF_X, 50), F0, 46, { { 25, 8 } }, C.plaster, M.Plaster)
for _, z in { -36, -18, 18, 36 } do
	cylinder("RotundaColumn", 44, 3.2, Vector3.new(if math.abs(z) > 30 then 56 else 50, F0 + 22, z), C.marble, M.Marble, true)
end
block("LobbyCeiling", Vector3.new(50, 1, 100), Vector3.new(65, F0 + 46.5, 0), C.plaster, M.Plaster)
do
	local dome = Instance.new("Part")
	dome.Name = "Dome"
	dome.Shape = Enum.PartType.Ball
	dome.Size = Vector3.new(40, 40, 40)
	put(dome, CFrame.new(65, F0 + 46, 0), C.plaster, M.Plaster)
	local oculus = cylinder("Oculus", 0.4, 10, Vector3.new(65, F0 + 65.9, 0), C.glass, M.Glass, true)
	oculus.Transparency = 0.4
end
lamp(Vector3.new(65, F0 + 40, 0), 60, 1.6)
lamp(Vector3.new(65, F0 + 30, -30), 30)
lamp(Vector3.new(65, F0 + 30, 30), 30)
-- metal detector + security desk at the doors
block("DetectorL", Vector3.new(1, 8, 1), Vector3.new(80, F0 + 4, -3.5), C.black, M.Metal)
block("DetectorR", Vector3.new(1, 8, 1), Vector3.new(80, F0 + 4, 3.5), C.black, M.Metal)
block("DetectorTop", Vector3.new(1.2, 1, 8), Vector3.new(80, F0 + 8.5, 0), C.black, M.Metal)
block("SecurityDesk", Vector3.new(4, 3.6, 10), Vector3.new(76, F0 + 1.8, -14), C.wood, M.Wood)
marker("MetalDetector", Vector3.new(80, F0 + 3, 0))
-- the clerk's office (south side room) with a brass grille window
block("ClerkCounter", Vector3.new(16, 4, 3), Vector3.new(65, F0 + 2, -48), C.panel, M.Wood)
local grille = block("ClerkGrille", Vector3.new(16, 6, 0.3), Vector3.new(65, F0 + 7, -48.3), C.brass, M.Metal)
grille.Transparency = 0.5
marker("ClerkWindow", Vector3.new(65, F0 + 3, -44))
marker("ClerkSpot", Vector3.new(65, F0 + 3, -54))
-- benches along the lobby
for _, z in { -30, 30 } do
	block("LobbyBench", Vector3.new(10, 1.8, 2.4), Vector3.new(46, F0 + 0.9, z), C.panel, M.Wood)
end
marker("CourthouseSteps", Vector3.new(HALF_X + 18, FY + 3, 0))
marker("VehicleDropoff", Vector3.new(HALF_X + 44, 3, 0))

---------------------------------------------------------------------------
-- the courtroom (x -50..40, z -48..48, 40 high): bench in the west
---------------------------------------------------------------------------
local CX0, CX1, CZ = -50, LOB, 48
local CH = 40
wall("CourtS", Vector2.new(CX0, -CZ), Vector2.new(CX1, -CZ), F0, CH,
	{ { 15, 8, 10, 34 }, { 35, 8, 10, 34 }, { 55, 8, 10, 34 }, { 75, 8, 10, 34 } }, C.plaster, M.Plaster)
wall("CourtN", Vector2.new(CX0, CZ), Vector2.new(CX1, CZ), F0, CH,
	{ { 15, 6 }, { 35, 8, 10, 34 }, { 55, 8, 10, 34 }, { 75, 8, 10, 34 } }, C.plaster, M.Plaster) -- door to the jury room corridor
wall("CourtW", Vector2.new(CX0, -CZ), Vector2.new(CX0, CZ), F0, CH, { { CZ - 30, 6 }, { CZ + 30, 6 } }, C.plaster, M.Plaster) -- holding / chambers doors
block("CourtCeiling", Vector3.new(CX1 - CX0, 1, 2 * CZ), Vector3.new((CX0 + CX1) / 2, F0 + CH + 0.5, 0), C.plaster, M.Plaster)
for i = 0, 3 do
	block("CeilingBeam", Vector3.new(2, 2, 2 * CZ), Vector3.new(CX0 + 12 + i * 22, F0 + CH - 1, 0), C.panelDark, M.Wood)
end
-- wood panelling round the room
wainscot(Vector2.new(CX0, -CZ), Vector2.new(CX1, -CZ), F0, 10, Vector2.new(0, 1))
wainscot(Vector2.new(CX0, CZ), Vector2.new(CX1, CZ), F0, 10, Vector2.new(0, -1))
wainscot(Vector2.new(CX0, -CZ), Vector2.new(CX0, CZ), F0, 22, Vector2.new(1, 0))
block("Floorboards", Vector3.new(CX1 - CX0, 0.2, 2 * CZ), Vector3.new((CX0 + CX1) / 2, F0 + 0.1, 0), C.wood, M.WoodPlanks)

-- the judge's bench: raised, panelled, the seal and flags behind
block("BenchDais", Vector3.new(12, 4, 30), Vector3.new(CX0 + 7, F0 + 2, 0), C.panelDark, M.Wood)
block("BenchFront", Vector3.new(2, 7, 30), Vector3.new(CX0 + 13, F0 + 3.5, 0), C.panel, M.Wood)
block("BenchTop", Vector3.new(4, 0.6, 31), Vector3.new(CX0 + 12, F0 + 7.3, 0), C.panelDark, M.Wood)
chair("JudgeSeat", Vector3.new(CX0 + 7, F0 + 4.6, 0), Vector3.new(1, 0, 0), C.black)
do
	local seal = cylinder("Seal", 0.5, 12, Vector3.new(CX0 + 1, F0 + 20, 0), C.brass, M.Metal)
	seal.CFrame = BASE * CFrame.new(CX0 + 1, F0 + 20, 0)
end
for _, z in { -12, 12 } do
	cylinder("FlagPole", 16, 0.4, Vector3.new(CX0 + 3, F0 + 8, z), C.brass, M.Metal, true)
	block("Flag", Vector3.new(0.2, 5, 7), Vector3.new(CX0 + 3, F0 + 13, z + 3.5 * (if z > 0 then 1 else -1)), if z > 0 then Color3.fromRGB(40, 60, 140) else Color3.fromRGB(160, 40, 40), M.Fabric)
end
block("ClerkDesk", Vector3.new(4, 3.4, 12), Vector3.new(CX0 + 17, F0 + 1.7, 14), C.panel, M.Wood)
-- witness stand (to the judge's right)
block("WitnessBox", Vector3.new(7, 2, 7), Vector3.new(CX0 + 13, F0 + 1, -22), C.panelDark, M.Wood)
block("WitnessRail", Vector3.new(0.5, 4, 7), Vector3.new(CX0 + 16.6, F0 + 4, -22), C.panel, M.Wood)
chair("WitnessSeat", Vector3.new(CX0 + 12.5, F0 + 2.4, -22), Vector3.new(1, 0, 0.3))
-- counsel tables
block("DefenseTable", Vector3.new(5, 3.2, 14), Vector3.new(CX0 + 30, F0 + 1.6, -12), C.panel, M.Wood)
chair("DefendantSeat", Vector3.new(CX0 + 34, F0 + 1, -15), Vector3.new(-1, 0, 0))
chair("DefenseSeat", Vector3.new(CX0 + 34, F0 + 1, -9), Vector3.new(-1, 0, 0))
block("ProsecutionTable", Vector3.new(5, 3.2, 14), Vector3.new(CX0 + 30, F0 + 1.6, 12), C.panel, M.Wood)
chair("ProsecutorSeat", Vector3.new(CX0 + 34, F0 + 1, 12), Vector3.new(-1, 0, 0))
marker("BailiffSpot", Vector3.new(CX0 + 18, F0 + 3, -30))
-- jury box (north side): two raised rows of six behind a rail, facing the room
block("JuryDais", Vector3.new(26, 1.2, 6), Vector3.new(CX0 + 34, F0 + 0.6, 36), C.panelDark, M.Wood)
block("JuryDais2", Vector3.new(26, 2.4, 5), Vector3.new(CX0 + 34, F0 + 1.2, 41.5), C.panelDark, M.Wood)
block("JuryRail", Vector3.new(26, 3.5, 0.6), Vector3.new(CX0 + 34, F0 + 1.75, 32.6), C.panel, M.Wood)
for row = 0, 1 do
	for i = 1, 6 do
		chair("JurorSeat" .. (row * 6 + i), Vector3.new(CX0 + 23 + (i - 1) * 4.2, F0 + 1.6 + row * 1.2, 35 + row * 5.5), Vector3.new(0, 0, -1), C.panel)
	end
end
-- the bar, its gate, and the gallery pews
block("BarRail", Vector3.new(0.8, 3.4, 2 * CZ - 20), Vector3.new(CX0 + 48, F0 + 1.7, -4), C.panel, M.Wood)
local g = 0
for row = 0, 6 do
	local x = CX0 + 54 + row * 5
	for _, side in { -1, 1 } do
		local zc = side * 24
		block("Pew", Vector3.new(2.4, 1.6, 30), Vector3.new(x, F0 + 1.3, zc), C.panel, M.Wood)
		block("PewBack", Vector3.new(0.5, 3.6, 30), Vector3.new(x + 1.3, F0 + 2.4, zc), C.panel, M.Wood)
		for k = 0, 5 do
			g += 1
			local s = chair("GallerySeat" .. g, Vector3.new(x, F0 + 2.2, zc - 12.5 + k * 5), Vector3.new(-1, 0, 0), C.panel, true)
			s.Transparency = 1
		end
	end
end
for _, x in { CX0 + 15, CX0 + 45, CX0 + 75 } do
	for _, z in { -25, 25 } do
		lamp(Vector3.new(x, F0 + CH - 6, z), 42, 1.2)
	end
end

---------------------------------------------------------------------------
-- behind the courtroom (x -90..-50): court holding, judge's chambers, the jury room
---------------------------------------------------------------------------
local BX0 = -HALF_X
wall("BackCorridor", Vector2.new(CX0, -HALF_Z), Vector2.new(CX0, -CZ), F0, 30, nil, C.plaster, M.Plaster)
-- court holding (z -48..-6): bars, a bench
wall("HoldingWall", Vector2.new(BX0, -6), Vector2.new(CX0, -6), F0, 18, { { 20, 6 } }, C.plaster, M.Plaster)
for i = 0, 8 do
	cylinder("Bar", 12, 0.4, Vector3.new(CX0 - 8 - i * 1.2, F0 + 6, -20), C.black, M.Metal, true)
end
block("HoldingBench", Vector3.new(16, 1.8, 2.4), Vector3.new(BX0 + 12, F0 + 0.9, -40), C.stoneDark, M.Concrete)
marker("HoldingSpot", Vector3.new(BX0 + 14, F0 + 3, -30))
-- judge's chambers (z -6..20): desk, bookcases
wall("ChambersWall", Vector2.new(BX0, 20), Vector2.new(CX0, 20), F0, 18, { { 25, 6 } }, C.plaster, M.Plaster)
block("ChambersDesk", Vector3.new(4, 3.2, 9), Vector3.new(BX0 + 14, F0 + 1.6, 7), C.panelDark, M.Wood)
block("Bookcase", Vector3.new(2, 14, 20), Vector3.new(BX0 + 3, F0 + 7, 7), C.panelDark, M.Wood)
marker("ChambersSpot", Vector3.new(BX0 + 20, F0 + 3, 7))
-- THE JURY ROOM (z 48..112, x -90..10): long table, twelve chairs, tall windows, clock, fan
local JX0, JX1, JZ0, JZ1 = BX0, 10, CZ + 8, HALF_Z
wall("JuryRoomS", Vector2.new(JX0, JZ0), Vector2.new(JX1, JZ0), F0, 26, { { 85, 6 } }, C.jury, M.Plaster)
wall("JuryRoomE", Vector2.new(JX1, JZ0), Vector2.new(JX1, JZ1), F0, 26, nil, C.jury, M.Plaster)
block("JuryCeiling", Vector3.new(JX1 - JX0, 1, JZ1 - JZ0), Vector3.new((JX0 + JX1) / 2, F0 + 26.5, (JZ0 + JZ1) / 2), C.jury, M.Plaster)
wainscot(Vector2.new(JX0, JZ0), Vector2.new(JX1, JZ0), F0, 4, Vector2.new(0, 1))
local jcx, jcz = (JX0 + JX1) / 2, (JZ0 + JZ1) / 2
block("JuryTable", Vector3.new(40, 0.8, 8), Vector3.new(jcx, F0 + 3.4, jcz), C.wood, M.Wood)
for _, dx in { -18, 18 } do
	for _, dz in { -3, 3 } do
		block("TableLeg", Vector3.new(0.6, 3, 0.6), Vector3.new(jcx + dx, F0 + 1.5, jcz + dz), C.panelDark, M.Wood)
	end
end
local j = 0
for side = -1, 1, 2 do
	for i = 0, 4 do
		j += 1
		chair("JuryRoomSeat" .. j, Vector3.new(jcx - 16 + i * 8, F0 + 1.6, jcz + side * 6.5), Vector3.new(0, 0, -side), C.wood)
	end
end
j += 1
chair("JuryRoomSeat" .. j, Vector3.new(jcx - 23, F0 + 1.6, jcz), Vector3.new(1, 0, 0), C.wood) -- the foreman
j += 1
chair("JuryRoomSeat" .. j, Vector3.new(jcx + 23, F0 + 1.6, jcz), Vector3.new(-1, 0, 0), C.wood)
marker("JuryRoomSpot", Vector3.new(jcx, F0 + 3, JZ0 + 4))
do
	-- the wall clock
	local clock = cylinder("WallClock", 0.4, 3, Vector3.new(JX1 - 0.9, F0 + 18, jcz), Color3.fromRGB(245, 240, 225), M.SmoothPlastic)
	clock.CFrame = BASE * CFrame.new(JX1 - 0.9, F0 + 18, jcz)
	-- the fan (it doesn't work, of course)
	block("FanStand", Vector3.new(0.4, 5, 0.4), Vector3.new(JX0 + 4, F0 + 2.5, JZ1 - 6), C.black, M.Metal)
	cylinder("FanCage", 1.2, 3.4, Vector3.new(JX0 + 4.3, F0 + 5.6, JZ1 - 6), C.black, M.Metal)
	-- water cooler and the washroom door
	block("WaterCooler", Vector3.new(1.6, 4.5, 1.6), Vector3.new(JX1 - 3, F0 + 2.25, JZ0 + 4), Color3.fromRGB(220, 225, 230), M.SmoothPlastic)
	block("WashroomDoor", Vector3.new(0.4, 9, 4.5), Vector3.new(JX1 - 0.9, F0 + 4.5, JZ1 - 10), C.panel, M.Wood)
	block("CoatRack", Vector3.new(0.4, 7, 0.4), Vector3.new(JX0 + 3, F0 + 3.5, JZ0 + 5), C.panelDark, M.Wood)
end
lamp(Vector3.new(jcx - 10, F0 + 24, jcz), 34, 1.2)
lamp(Vector3.new(jcx + 10, F0 + 24, jcz), 34, 1.2)

-- corridors and the hallway from the lobby (z 50..112 east part)
wall("HallN", Vector2.new(JX1, JZ0), Vector2.new(LOB, JZ0), F0, 30, { { 10, 8 } }, C.plaster, M.Plaster)
lamp(Vector3.new(25, F0 + 24, 80), 40)
lamp(Vector3.new(-40, F0 + 24, -80), 40)

model:SetAttribute("Facility", "Courthouse")
model:SetAttribute("Inspiration", "12 Angry Men (1957) - New York County Courthouse")
model.PrimaryPart = model:FindFirstChild("Podium") :: BasePart
model.Parent = workspace
print(("[Courthouse] built: %d parts"):format(#model:GetDescendants()))
return #model:GetDescendants()
