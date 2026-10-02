-- Builds workspace.Courthouse (run once in Studio's Edit datamodel; v263).
-- Modelled on the courthouse in 12 Angry Men (1957) - the New York County Courthouse at
-- 60 Centre Street. The film opens looking up its giant Corinthian columns, then moves
-- into the marble rotunda. This is that building:
--   * a full-width grand staircase with a landing, granite cheek walls and bronze lamp standards
--   * a deep portico: ten fluted Corinthian columns, coffered ceiling, entablature with
--     dentils, a pediment with a raking cornice, statues on top - Lady Justice at the peak
--   * three tall bronze doorways into a marble rotunda: checkerboard floor, a ring of
--     columns, a mezzanine balcony with a grand staircase, coffered dome, oculus, chandelier
--   * a wood-and-marble courtroom with high windows, holding, chambers, and the jury room
--     (one long table, twelve chairs, tall windows, a wall clock, a fan that doesn't work)
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
local CENTER = Vector3.new(1983.7, 0, -1662)
local GROUND = workspace:Raycast(CENTER + Vector3.new(0, 600, 0), Vector3.new(0, -700, 0))
local GY = if GROUND then GROUND.Position.Y else 1
local BASE = CFrame.new(CENTER.X, GY, CENTER.Z) * CFrame.Angles(0, math.rad(-90), 0)

local FY = 9 -- the podium: the ground floor is this high above the street
local HALF_X, HALF_Z = 88, 116 -- the building: x -88..88 (depth), z -116..116 (width)

local model = Instance.new("Model")
model.Name = "Courthouse"
local markers = Instance.new("Folder")
markers.Name = "CourtMarkers"
markers.Parent = model
local groups: { [string]: Model } = {}
local function group(name: string): Model
	local g = groups[name]
	if not g then
		g = Instance.new("Model")
		g.Name = name
		g.Parent = model
		groups[name] = g
	end
	return g
end
local current: Instance = group("Exterior")

local C = {
	marble = Color3.fromRGB(240, 237, 230), marbleWarm = Color3.fromRGB(232, 226, 212), marbleGrey = Color3.fromRGB(204, 200, 192),
	marbleDark = Color3.fromRGB(58, 56, 54), marbleGreen = Color3.fromRGB(56, 82, 70), granite = Color3.fromRGB(150, 146, 140),
	plaster = Color3.fromRGB(236, 230, 214), panel = Color3.fromRGB(96, 60, 34), panelDark = Color3.fromRGB(62, 38, 22),
	wood = Color3.fromRGB(122, 80, 46), glass = Color3.fromRGB(190, 210, 222), bronze = Color3.fromRGB(150, 110, 60),
	brass = Color3.fromRGB(204, 168, 88), roof = Color3.fromRGB(110, 140, 128), jury = Color3.fromRGB(206, 200, 176),
	black = Color3.fromRGB(26, 26, 28), light = Color3.fromRGB(255, 240, 210),
}
local M = Enum.Material

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

-- a cylinder along local Y (vertical) unless `axis` says "x" / "z"
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

-- a wall a->b (local XZ) from y0, height h. gaps = { { along, width, sill?, top? } }:
-- with a sill it's a WINDOW (glass + a marble surround), without one a doorway (top default 14)
local function wall(name: string, a: Vector2, b: Vector2, y0: number, h: number, gaps: { { number } }?, color: Color3?, material: Enum.Material?, thick: number?)
	local dir = b - a
	local len = dir.Magnitude
	local u = dir.Unit
	local rot = -math.atan2(u.Y, u.X)
	local th = thick or 1.6
	local function seg(from: number, to: number, ya: number, yb: number, nm: string, col: Color3, mat: Enum.Material, transp: number?, t: number?)
		if to - from < 0.05 or yb - ya < 0.05 then return nil end
		local mid = a + u * ((from + to) / 2)
		local p = block(nm, Vector3.new(to - from, yb - ya, t or th), Vector3.new(mid.X, (ya + yb) / 2, mid.Y), col, mat, rot)
		if transp then p.Transparency = transp end
		return p
	end
	local col, mat = color or C.marble, material or M.Marble
	local cuts = {}
	for _, g in gaps or {} do table.insert(cuts, g) end
	table.sort(cuts, function(x, y) return x[1] < y[1] end)
	local at = 0
	for _, g in cuts do
		local s, e = g[1] - g[2] / 2, g[1] + g[2] / 2
		seg(at, s, y0, y0 + h, name, col, mat)
		local sill, top = g[3], g[4] or (if g[3] then h - 6 else 14)
		if sill then
			seg(s, e, y0, y0 + sill, name, col, mat)
			seg(s, e, y0 + sill, y0 + top, name .. "Window", C.glass, M.Glass, 0.5, 0.3)
			-- surround: sill ledge + head
			seg(s - 0.8, e + 0.8, y0 + sill - 0.6, y0 + sill, name .. "Sill", C.marbleGrey, M.Marble, nil, th + 1)
			seg(s - 0.8, e + 0.8, y0 + top, y0 + top + 1.2, name .. "Head", C.marbleGrey, M.Marble, nil, th + 1)
		end
		seg(s, e, y0 + top, y0 + h, name, col, mat)
		at = e
	end
	seg(at, len, y0, y0 + h, name, col, mat)
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

local function light(part: BasePart, range: number, brightness: number?)
	local l = Instance.new("PointLight")
	-- marble is bright: lights stay soft (strong ones blew the white stone out)
	l.Range = range * 0.7
	l.Brightness = (brightness or 1.1) * 0.35
	l.Color = Color3.fromRGB(255, 232, 196)
	l.Shadows = false
	l.Parent = part
end

-- a fluted Corinthian column standing on (x, y0, z), total height h, shaft diameter d
local function column(x: number, y0: number, z: number, h: number, d: number, color: Color3?)
	local col = color or C.marble
	block("Plinth", Vector3.new(d * 1.45, 1.6, d * 1.45), Vector3.new(x, y0 + 0.8, z), col)
	cylinder("BaseTorus", 1.2, d * 1.3, Vector3.new(x, y0 + 2.2, z), col)
	cylinder("BaseTorus", 0.8, d * 1.15, Vector3.new(x, y0 + 3.2, z), col)
	local capH = d * 1.1
	local shaftH = h - 3.6 - capH
	cylinder("Shaft", shaftH, d, Vector3.new(x, y0 + 3.6 + shaftH / 2, z), col)
	-- fluting: shallow vertical strips round the shaft
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2
		local r = d / 2
		local f = block("Flute", Vector3.new(0.28, shaftH * 0.94, d * 0.12), Vector3.new(x + math.cos(a) * r, y0 + 3.6 + shaftH / 2, z + math.sin(a) * r), col:Lerp(Color3.new(0, 0, 0), 0.08), M.Marble, -a)
		f.CanCollide = false
	end
	local top = y0 + 3.6 + shaftH
	cylinder("Necking", 0.6, d * 1.04, Vector3.new(x, top + 0.3, z), col)
	-- Corinthian capital: two rows of acanthus leaves, volutes at the corners, the abacus on top
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local leaf = wedge("Acanthus", Vector3.new(d * 0.32, capH * 0.5, 0.9), CFrame.new(x + math.cos(a) * d * 0.5, top + capH * 0.3, z + math.sin(a) * d * 0.5) * CFrame.Angles(0, -a + math.rad(90), 0), C.marbleWarm)
		leaf.CanCollide = false
		local a2 = a + math.pi / 8
		local leaf2 = wedge("Acanthus", Vector3.new(d * 0.3, capH * 0.5, 0.9), CFrame.new(x + math.cos(a2) * d * 0.56, top + capH * 0.62, z + math.sin(a2) * d * 0.56) * CFrame.Angles(0, -a2 + math.rad(90), 0), C.marbleWarm)
		leaf2.CanCollide = false
	end
	cylinder("Bell", capH * 0.85, d * 1.02, Vector3.new(x, top + capH * 0.45, z), col)
	for _, dx in { -1, 1 } do
		for _, dz in { -1, 1 } do
			local v = cylinder("Volute", 0.8, d * 0.34, Vector3.new(x + dx * d * 0.62, top + capH * 0.82, z + dz * d * 0.62), C.marbleWarm, M.Marble, "z")
			v.CanCollide = false
		end
	end
	block("Abacus", Vector3.new(d * 1.5, 1, d * 1.5), Vector3.new(x, top + capH + 0.5, z), col)
end

-- a bronze lamp standard (the big lanterns either side of the steps)
local function lampStandard(x: number, y0: number, z: number)
	block("LampPlinth", Vector3.new(4, 5, 4), Vector3.new(x, y0 + 2.5, z), C.granite, M.Granite)
	cylinder("LampPost", 14, 0.9, Vector3.new(x, y0 + 12, z), C.bronze, M.Metal)
	cylinder("LampRing", 0.6, 2, Vector3.new(x, y0 + 7, z), C.bronze, M.Metal)
	for i = 0, 3 do
		local a = i * math.pi / 2
		block("LampArm", Vector3.new(3, 0.4, 0.4), Vector3.new(x + math.cos(a) * 1.5, y0 + 17.5, z + math.sin(a) * 1.5), C.bronze, M.Metal, -a)
		local globe = ball("LampGlobe", 1.8, Vector3.new(x + math.cos(a) * 3, y0 + 18.4, z + math.sin(a) * 3), C.light, M.Neon)
		globe.CanCollide = false
	end
	local top = ball("LampGlobe", 2.4, Vector3.new(x, y0 + 20, z), C.light, M.Neon)
	light(top, 34, 1.4)
end

-- a simple standing statue on a pedestal (robes + head), arms optional
local function statue(name: string, x: number, y0: number, z: number, s: number, justice: boolean?)
	local col = C.marbleWarm
	block(name .. "Pedestal", Vector3.new(4 * s, 1.6 * s, 4 * s), Vector3.new(x, y0 + 0.8 * s, z), C.marble)
	cylinder(name .. "Robe", 6 * s, 2.6 * s, Vector3.new(x, y0 + 4.6 * s, z), col)
	cylinder(name .. "Torso", 2.6 * s, 2 * s, Vector3.new(x, y0 + 8.7 * s, z), col)
	ball(name .. "Head", 1.5 * s, Vector3.new(x, y0 + 10.7 * s, z), col)
	if justice then
		-- Lady Justice: the sword down at her side, the scales held high
		block(name .. "Sword", Vector3.new(0.25 * s, 5 * s, 0.25 * s), Vector3.new(x + 1.3 * s, y0 + 6 * s, z), C.brass, M.Metal)
		block(name .. "ArmUp", Vector3.new(0.5 * s, 3.4 * s, 0.5 * s), Vector3.new(x - 1.3 * s, y0 + 10.6 * s, z), col)
		block(name .. "Beam", Vector3.new(0.2 * s, 0.2 * s, 3.2 * s), Vector3.new(x - 1.3 * s, y0 + 12.4 * s, z), C.brass, M.Metal)
		for _, dz in { -1.5, 1.5 } do
			cylinder(name .. "Pan", 0.2 * s, 1.2 * s, Vector3.new(x - 1.3 * s, y0 + 11.2 * s, z + dz * s), C.brass, M.Metal)
		end
		block(name .. "Blindfold", Vector3.new(1.55 * s, 0.35 * s, 1.55 * s), Vector3.new(x, y0 + 10.9 * s, z), C.marbleGrey)
	end
end

---------------------------------------------------------------------------
-- THE GRAND ENTRY
---------------------------------------------------------------------------
current = group("Entry")
local FRONT = HALF_X -- the front wall line
local PORT_X = FRONT + 22 -- the column line (a deep portico)
local STEP_RUN, STEP_N = 2.4, 16
local STAIR_W = 200
-- the podium the whole building stands on (granite base course + marble)
block("Podium", Vector3.new(2 * HALF_X + 2, FY, 2 * HALF_Z + 2), Vector3.new(0, FY / 2, 0), C.granite, M.Granite)
block("PortGround", Vector3.new(PORT_X - FRONT + 6, FY, STAIR_W + 16), Vector3.new((FRONT + PORT_X + 6) / 2, FY / 2, 0), C.granite, M.Granite)
block("PortFloor", Vector3.new(PORT_X - FRONT + 6, 0.4, STAIR_W + 16), Vector3.new((FRONT + PORT_X + 6) / 2, FY + 0.2, 0), C.marble)
for i = 0, 10 do
	block("PortFloorBand", Vector3.new(PORT_X - FRONT + 6, 0.06, 0.6), Vector3.new((FRONT + PORT_X + 6) / 2, FY + 0.43, -100 + i * 20), C.marbleGrey)
end
-- the staircase: two flights with a landing, all the width of the portico
local stairX0 = PORT_X + 6
for i = 1, STEP_N do
	local h = FY * i / STEP_N
	local landing = (i == STEP_N // 2)
	local x = stairX0 + (STEP_N - i) * STEP_RUN + (if i <= STEP_N // 2 then 6 else 0)
	block("Step", Vector3.new(if landing then STEP_RUN + 6 else STEP_RUN, h, STAIR_W), Vector3.new(x + (if landing then 3 else 0), h / 2, 0), C.marble)
	block("StepNose", Vector3.new(0.3, 0.25, STAIR_W), Vector3.new(x + (if landing then 6 else 0) + STEP_RUN / 2 - 0.1, h - 0.12, 0), C.marbleGrey)
end
local stairLen = STEP_N * STEP_RUN + 6
-- granite cheek walls with lamp standards
for _, side in { -1, 1 } do
	local z = side * (STAIR_W / 2 + 4)
	wedge("StairCheek", Vector3.new(8, FY + 2, stairLen), CFrame.new(stairX0 + stairLen / 2, (FY + 2) / 2, z) * CFrame.Angles(0, math.rad(-90), 0), C.granite, M.Granite)
	block("CheekTop", Vector3.new(10, FY + 3, 8), Vector3.new(stairX0 - 1, (FY + 3) / 2, z), C.granite, M.Granite)
	lampStandard(stairX0 + stairLen - 3, 0, z)
	lampStandard(stairX0 - 1, FY + 3, z)
end
marker("CourthouseSteps", Vector3.new(stairX0 + 2, FY + 3, 0))
marker("VehicleDropoff", Vector3.new(stairX0 + stairLen + 14, 3, 0))

-- ten giant fluted Corinthian columns
local COL_H, COL_D = 70, 5.6
for i = 0, 9 do
	column(PORT_X, FY, -90 + i * 20, COL_H, COL_D)
end
-- pilasters on the front wall behind them (the half-columns that answer the colonnade)
for i = 0, 9 do
	local z = -90 + i * 20
	block("Pilaster", Vector3.new(1.2, COL_H - 6, 4.5), Vector3.new(FRONT + 1.6, FY + (COL_H - 6) / 2, z), C.marbleWarm)
	block("PilasterCap", Vector3.new(1.8, 3, 5.6), Vector3.new(FRONT + 1.8, FY + COL_H - 4.5, z), C.marbleWarm)
end
-- the entablature: architrave, frieze (with the inscription), dentils, cornice
local ENT_Y = FY + COL_H
local ENT_W = 196
block("Architrave", Vector3.new(PORT_X - FRONT + 8, 4, ENT_W), Vector3.new((FRONT + PORT_X) / 2 + 1, ENT_Y + 2, 0), C.marble)
block("ArchitraveBand", Vector3.new(0.6, 0.8, ENT_W), Vector3.new(PORT_X + 4.3, ENT_Y + 3.2, 0), C.marbleGrey)
block("Frieze", Vector3.new(PORT_X - FRONT + 8, 6, ENT_W), Vector3.new((FRONT + PORT_X) / 2 + 1, ENT_Y + 7, 0), C.marbleWarm)
do
	local plate = block("FriezeText", Vector3.new(170, 3.6, 0.3), Vector3.new(PORT_X + 5.2, ENT_Y + 7, 0), C.marbleWarm, M.Marble, math.rad(90))
	plate.CanCollide = false
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 1
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
for i = 0, 97 do
	local d = block("Dentil", Vector3.new(1.2, 1.2, 1), Vector3.new(PORT_X + 5.2, ENT_Y + 10.6, -97 + i * 2), C.marble)
	d.CanCollide = false
end
block("Cornice", Vector3.new(PORT_X - FRONT + 12, 2.4, ENT_W + 6), Vector3.new((FRONT + PORT_X) / 2 + 2, ENT_Y + 12.2, 0), C.marble)
-- the pediment: tympanum (recessed, a shade darker) and the raking cornice
local PED_Y, PED_RISE, PED_SPAN = ENT_Y + 13.4, 26, ENT_W + 6
for side = -1, 1, 2 do
	wedge("Tympanum", Vector3.new(PORT_X - FRONT + 4, PED_RISE, PED_SPAN / 2),
		CFrame.new((FRONT + PORT_X) / 2, PED_Y + PED_RISE / 2, side * PED_SPAN / 4) * CFrame.Angles(0, if side > 0 then math.rad(180) else 0, 0), C.marbleWarm)
	-- the raking cornice: a thin slab laid along each slope, standing proud of the tympanum
	local slope = math.atan2(PED_RISE, PED_SPAN / 2)
	local len = math.sqrt(PED_RISE ^ 2 + (PED_SPAN / 2) ^ 2)
	block("RakingCornice", Vector3.new(PORT_X - FRONT + 9, 2.2, len + 2), Vector3.zero, C.marble)
		.CFrame = BASE * CFrame.new((FRONT + PORT_X) / 2 + 2, PED_Y + PED_RISE / 2 + 1, side * PED_SPAN / 4) * CFrame.Angles(side * slope, 0, 0)
end
-- a relief in the tympanum: the scales of justice in bronze
do
	local x = PORT_X + 3.2
	block("ReliefBeam", Vector3.new(0.6, 0.8, 18), Vector3.new(x, PED_Y + 13, 0), C.bronze, M.Metal)
	block("ReliefPost", Vector3.new(0.6, 10, 0.8), Vector3.new(x, PED_Y + 8, 0), C.bronze, M.Metal)
	for _, z in { -8, 8 } do
		cylinder("ReliefPan", 0.6, 5, Vector3.new(x, PED_Y + 7.5, z), C.bronze, M.Metal, "x")
		block("ReliefChain", Vector3.new(0.4, 5, 0.3), Vector3.new(x, PED_Y + 10.5, z), C.bronze, M.Metal)
	end
end
-- statues on the pediment: Lady Justice at the peak, figures at the corners
statue("LadyJustice", (FRONT + PORT_X) / 2, PED_Y + PED_RISE, 0, 1.7, true)
statue("Acroterion", (FRONT + PORT_X) / 2, ENT_Y + 13.4, -PED_SPAN / 2 + 3, 1.2)
statue("Acroterion", (FRONT + PORT_X) / 2, ENT_Y + 13.4, PED_SPAN / 2 - 3, 1.2)
-- the coffered ceiling of the portico
block("PorticoCeiling", Vector3.new(PORT_X - FRONT + 4, 1.2, ENT_W), Vector3.new((FRONT + PORT_X) / 2, ENT_Y - 0.6, 0), C.marbleWarm)
for xi = 0, 2 do
	for zi = 0, 15 do
		local cx = FRONT + 4 + xi * 6.5
		local cz = -90 + zi * 12
		local coffer = block("Coffer", Vector3.new(5, 0.8, 9.5), Vector3.new(cx, ENT_Y - 1.6, cz), C.marbleGrey)
		coffer.CanCollide = false
		local rose = cylinder("Rosette", 0.4, 1.6, Vector3.new(cx, ENT_Y - 2.1, cz), C.brass, M.Metal)
		rose.CanCollide = false
	end
end
for i = 0, 4 do
	local lantern = ball("PorticoLantern", 2.6, Vector3.new(FRONT + 12, ENT_Y - 10, -80 + i * 40), C.light, M.Neon)
	cylinder("LanternChain", 8, 0.25, Vector3.new(FRONT + 12, ENT_Y - 5, -80 + i * 40), C.bronze, M.Metal)
	light(lantern, 40, 1.3)
end

---------------------------------------------------------------------------
-- the shell: marble walls with a rusticated base, tall windows, a cornice, a copper roof
---------------------------------------------------------------------------
current = group("Shell")
local SH = COL_H + 10 -- shell height above the podium
local function winGaps(len: number, every: number, w: number, sill: number, top: number): { { number } }
	local g = {}
	local n = math.floor(len / every)
	local start = (len - (n - 1) * every) / 2
	for i = 0, n - 1 do
		table.insert(g, { start + i * every, w, sill, top })
	end
	return g
end
-- the front wall: three tall bronze doorways (and windows above them)
wall("FrontWall", Vector2.new(FRONT, -HALF_Z), Vector2.new(FRONT, HALF_Z), FY, SH,
	{ { HALF_Z - 32, 12, nil, 26 }, { HALF_Z, 14, nil, 30 }, { HALF_Z + 32, 12, nil, 26 } }, C.marble, M.Marble, 3)
for _, dz in { -32, 0, 32 } do
	local w, top = if dz == 0 then 14 else 12, if dz == 0 then 30 else 26
	-- open bronze door leaves, a bronze transom grille, a marble frame
	for _, s in { -1, 1 } do
		local leaf = block("BronzeDoor", Vector3.new(w / 2, top - 8, 0.5), Vector3.new(FRONT - w / 4 - 0.5, FY + (top - 8) / 2, dz + s * (w / 2 - 0.25)), C.bronze, M.Metal, math.rad(90))
		leaf.CanCollide = false
	end
	local transom = block("Transom", Vector3.new(0.4, 7, w), Vector3.new(FRONT, FY + top - 4, dz), C.bronze, M.DiamondPlate)
	transom.Transparency = 0.25
	block("DoorFrame", Vector3.new(3.6, top + 2, 1.2), Vector3.new(FRONT + 1, FY + (top + 2) / 2, dz - w / 2 - 0.6), C.marbleGrey)
	block("DoorFrame", Vector3.new(3.6, top + 2, 1.2), Vector3.new(FRONT + 1, FY + (top + 2) / 2, dz + w / 2 + 0.6), C.marbleGrey)
	block("DoorHead", Vector3.new(4, 2.4, w + 4), Vector3.new(FRONT + 1.2, FY + top + 1.2, dz), C.marbleGrey)
	block("DoorPediment", Vector3.new(4.6, 1.2, w + 6), Vector3.new(FRONT + 1.6, FY + top + 3, dz), C.marble)
end
wall("BackWall", Vector2.new(-HALF_X, -HALF_Z), Vector2.new(-HALF_X, HALF_Z), FY, SH, { { 40, 10 } }, C.marble, M.Marble, 3)
wall("SideWallS", Vector2.new(-HALF_X, -HALF_Z), Vector2.new(FRONT, -HALF_Z), FY, SH, winGaps(2 * HALF_X, 22, 7, 10, 34), C.marble, M.Marble, 3)
wall("SideWallN", Vector2.new(-HALF_X, HALF_Z), Vector2.new(FRONT, HALF_Z), FY, SH, winGaps(2 * HALF_X, 22, 7, 10, 34), C.marble, M.Marble, 3)
-- rusticated base course: horizontal bands around the bottom of the outside walls
for k = 0, 3 do
	local y = FY + 2 + k * 2.4
	block("Rustication", Vector3.new(0.4, 0.4, 2 * HALF_Z), Vector3.new(-HALF_X - 1.7, y, 0), C.marbleGrey)
	block("Rustication", Vector3.new(2 * HALF_X, 0.4, 0.4), Vector3.new(0, y, -HALF_Z - 1.7), C.marbleGrey)
	block("Rustication", Vector3.new(2 * HALF_X, 0.4, 0.4), Vector3.new(0, y, HALF_Z + 1.7), C.marbleGrey)
end
block("StringCourse", Vector3.new(2 * HALF_X + 4, 1.2, 2 * HALF_Z + 4), Vector3.new(0, FY + 40, 0), C.marbleWarm).CanCollide = false
block("MainCornice", Vector3.new(2 * HALF_X + 8, 3, 2 * HALF_Z + 8), Vector3.new(0, FY + SH + 1.5, 0), C.marble)
block("Attic", Vector3.new(2 * HALF_X, 6, 2 * HALF_Z), Vector3.new(0, FY + SH + 6, 0), C.marbleWarm)
block("AtticCornice", Vector3.new(2 * HALF_X + 4, 1.6, 2 * HALF_Z + 4), Vector3.new(0, FY + SH + 9.8, 0), C.marble)
block("Roof", Vector3.new(2 * HALF_X - 6, 2, 2 * HALF_Z - 6), Vector3.new(0, FY + SH + 11.4, 0), C.roof, M.Slate)
-- the rotunda dome rising above the roof (copper green)
local LOB_X0, LOB_X1 = 26, FRONT -- the rotunda: x 26..88
local RC = Vector3.new((LOB_X0 + LOB_X1) / 2, 0, 0) -- its centre
do
	cylinder("Drum", 14, 64, Vector3.new(RC.X, FY + SH + 18, 0), C.marble)
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2
		cylinder("DrumColumn", 12, 1.8, Vector3.new(RC.X + math.cos(a) * 33, FY + SH + 18, math.sin(a) * 33), C.marble)
	end
	local dome = ball("Dome", 62, Vector3.new(RC.X, FY + SH + 25, 0), C.roof, M.Slate)
	dome.CanCollide = false
	cylinder("Lantern", 8, 10, Vector3.new(RC.X, FY + SH + 58, 0), C.marble)
	ball("LanternCap", 9, Vector3.new(RC.X, FY + SH + 62, 0), C.roof, M.Slate)
	block("Finial", Vector3.new(0.6, 6, 0.6), Vector3.new(RC.X, FY + SH + 69, 0), C.brass, M.Metal)
end
block("Floor", Vector3.new(2 * HALF_X - 3, 0.6, 2 * HALF_Z - 3), Vector3.new(0, FY + 0.3, 0), C.marbleWarm)
local F0 = FY + 0.6 -- the floor surface

---------------------------------------------------------------------------
-- THE ROTUNDA (x 26..88, z -58..58): checkerboard marble, a ring of columns, a balcony,
-- a grand staircase, the coffered dome and a chandelier
---------------------------------------------------------------------------
current = group("Rotunda")
local RZ = 58
local RH = 64 -- inside height up to the dome ring
wall("RotundaBack", Vector2.new(LOB_X0, -HALF_Z), Vector2.new(LOB_X0, HALF_Z), F0, RH, { { HALF_Z, 16, nil, 22 } }, C.marbleWarm)
wall("RotundaS", Vector2.new(LOB_X0, -RZ), Vector2.new(FRONT, -RZ), F0, RH, { { 30, 10, nil, 16 } }, C.marbleWarm)
wall("RotundaN", Vector2.new(LOB_X0, RZ), Vector2.new(FRONT, RZ), F0, RH, { { 30, 10, nil, 16 } }, C.marbleWarm)
-- the checkerboard floor
do
	local tile = 4
	for xi = 0, math.floor((LOB_X1 - LOB_X0) / tile) - 1 do
		for zi = 0, math.floor(2 * RZ / tile) - 1 do
			if (xi + zi) % 2 == 0 then
				local t = block("Tile", Vector3.new(tile, 0.08, tile), Vector3.new(LOB_X0 + tile / 2 + xi * tile, F0 + 0.04, -RZ + tile / 2 + zi * tile), C.marbleDark)
				t.CanCollide = false
			end
		end
	end
	cylinder("Medallion", 0.12, 26, Vector3.new(RC.X, F0 + 0.1, 0), C.marbleGreen)
	cylinder("Medallion", 0.16, 18, Vector3.new(RC.X, F0 + 0.12, 0), C.marble)
	cylinder("MedallionStar", 0.2, 8, Vector3.new(RC.X, F0 + 0.14, 0), C.brass, M.Metal)
end
-- the ring of columns under the dome
for i = 0, 11 do
	local a = i / 12 * math.pi * 2 + math.pi / 12
	column(RC.X + math.cos(a) * 24, F0, math.sin(a) * 24, 40, 3, C.marbleGreen)
end
cylinder("RingBeam", 3, 54, Vector3.new(RC.X, F0 + 41.5, 0), C.marble)
-- the mezzanine balcony round the hall (on three sides) with brass rails
local MEZ = F0 + 22
for _, z in { -RZ + 6, RZ - 6 } do
	block("Balcony", Vector3.new(LOB_X1 - LOB_X0 - 4, 1.2, 12), Vector3.new((LOB_X0 + LOB_X1) / 2, MEZ, z), C.marble)
	block("BalconyRail", Vector3.new(LOB_X1 - LOB_X0 - 4, 0.4, 0.4), Vector3.new((LOB_X0 + LOB_X1) / 2, MEZ + 3.6, z - (z / math.abs(z)) * 6), C.brass, M.Metal)
	for k = 0, 28 do
		local x = LOB_X0 + 3 + k * 2
		local baluster = cylinder("Baluster", 3, 0.5, Vector3.new(x, MEZ + 2, z - (z / math.abs(z)) * 6), C.marble)
		baluster.CanCollide = false
	end
end
block("BalconyBack", Vector3.new(10, 1.2, 2 * RZ), Vector3.new(LOB_X0 + 5, MEZ, 0), C.marble)
-- the grand staircase: from the floor at the back of the hall, splitting left and right up to the balcony
do
	local steps = 18
	local rise = (MEZ - F0) / steps
	for i = 1, steps do
		local h = rise * i
		local x = LOB_X0 + 22 - i * 1.0
		if i <= 9 then
			block("GrandStep", Vector3.new(1.2, h, 20), Vector3.new(x + 11, F0 + h / 2, 0), C.marble)
		else
			for _, side in { -1, 1 } do
				block("GrandStep", Vector3.new(10, h, 1.4), Vector3.new(LOB_X0 + 10, F0 + h / 2, side * (10 + (i - 9) * 1.4)), C.marble)
			end
		end
	end
	block("StairLanding", Vector3.new(10, rise * 9, 20), Vector3.new(LOB_X0 + 10 + 0.4, F0 + rise * 4.5, 0), C.marble)
	for _, side in { -1, 1 } do
		block("StairRail", Vector3.new(14, 0.5, 0.5), Vector3.new(LOB_X0 + 25, F0 + 6, side * 10.4), C.brass, M.Metal)
		cylinder("Newel", 5, 1.4, Vector3.new(LOB_X0 + 32, F0 + 2.5, side * 10.4), C.marble)
		ball("NewelCap", 1.8, Vector3.new(LOB_X0 + 32, F0 + 5.4, side * 10.4), C.brass, M.Metal)
	end
end
-- the coffered inner dome, the oculus and the chandelier
block("RotundaCeiling", Vector3.new(LOB_X1 - LOB_X0, 1, 2 * RZ), Vector3.new(RC.X, F0 + RH + 0.5, 0), C.plaster)
cylinder("DomeRing", 2, 56, Vector3.new(RC.X, F0 + RH - 0.5, 0), C.marbleWarm)
for ring = 0, 2 do
	local r = 24 - ring * 7
	local n = 16 - ring * 4
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		local coffer = block("DomeCoffer", Vector3.new(4.5 - ring, 0.6, 4.5 - ring), Vector3.new(RC.X + math.cos(a) * r, F0 + RH - 1.2 - ring * 0.6, math.sin(a) * r), C.marbleGrey, M.Marble, -a)
		coffer.CanCollide = false
	end
end
local oculus = cylinder("Oculus", 0.4, 10, Vector3.new(RC.X, F0 + RH + 1.1, 0), C.light, M.Neon)
light(oculus, 60, 1.6)
do
	-- the chandelier: tiers of lights hanging from the oculus
	cylinder("ChandelierChain", 20, 0.3, Vector3.new(RC.X, F0 + RH - 10, 0), C.brass, M.Metal)
	for tier = 0, 2 do
		local r = 5 - tier * 1.4
		local y = F0 + RH - 20 - tier * 2.5
		cylinder("ChandelierRing", 0.4, r * 2, Vector3.new(RC.X, y, 0), C.brass, M.Metal)
		for i = 0, 9 - tier * 2 do
			local a = i / (10 - tier * 2) * math.pi * 2
			local g = ball("ChandelierLight", 0.9, Vector3.new(RC.X + math.cos(a) * r, y + 0.6, math.sin(a) * r), C.light, M.Neon)
			g.CanCollide = false
		end
	end
	light(ball("ChandelierHeart", 2.2, Vector3.new(RC.X, F0 + RH - 24, 0), C.light, M.Neon), 70, 2)
end
-- wall sconces round the hall
for _, x in { LOB_X0 + 12, LOB_X1 - 12 } do
	for _, z in { -RZ + 1.5, RZ - 1.5 } do
		local s = ball("Sconce", 1.4, Vector3.new(x, F0 + 12, z), C.light, M.Neon)
		light(s, 22, 1)
	end
end
-- security at the doors, the clerk's office on the south side, benches
block("DetectorL", Vector3.new(1, 8, 1), Vector3.new(FRONT - 8, F0 + 4, -3.5), C.black, M.Metal)
block("DetectorR", Vector3.new(1, 8, 1), Vector3.new(FRONT - 8, F0 + 4, 3.5), C.black, M.Metal)
block("DetectorTop", Vector3.new(1.2, 1, 8), Vector3.new(FRONT - 8, F0 + 8.5, 0), C.black, M.Metal)
block("SecurityDesk", Vector3.new(4, 3.6, 10), Vector3.new(FRONT - 12, F0 + 1.8, -14), C.panel, M.Wood)
marker("MetalDetector", Vector3.new(FRONT - 8, F0 + 3, 0))
block("ClerkCounter", Vector3.new(18, 4, 3), Vector3.new(RC.X + 14, F0 + 2, -RZ + 2), C.panel, M.Wood)
block("ClerkGrille", Vector3.new(18, 7, 0.3), Vector3.new(RC.X + 14, F0 + 7.5, -RZ + 1.5), C.brass, M.DiamondPlate).Transparency = 0.45
marker("ClerkWindow", Vector3.new(RC.X + 14, F0 + 3, -RZ + 6))
marker("ClerkSpot", Vector3.new(RC.X + 14, F0 + 3, -RZ - 4))
for _, z in { -40, 40 } do
	block("HallBench", Vector3.new(12, 1.8, 2.6), Vector3.new(FRONT - 20, F0 + 0.9, z), C.panel, M.Wood)
	block("HallBenchBack", Vector3.new(12, 3, 0.5), Vector3.new(FRONT - 20, F0 + 2.4, z + (z / math.abs(z)) * 1.3), C.panel, M.Wood)
end

---------------------------------------------------------------------------
-- THE COURTROOM (x -52..26, z -50..50): bench in the west, marble pilasters, high windows
---------------------------------------------------------------------------
current = group("Courtroom")
local CX0, CX1, CZ = -52, LOB_X0, 50
local CH = 44
wall("CourtS", Vector2.new(CX0, -CZ), Vector2.new(CX1, -CZ), F0, CH, winGaps(CX1 - CX0, 18, 7, 14, 38), C.plaster, M.Plaster)
wall("CourtN", Vector2.new(CX0, CZ), Vector2.new(CX1, CZ), F0, CH, { { 14, 6 }, { 32, 7, 14, 38 }, { 50, 7, 14, 38 }, { 68, 7, 14, 38 } }, C.plaster, M.Plaster)
wall("CourtW", Vector2.new(CX0, -CZ), Vector2.new(CX0, CZ), F0, CH, { { CZ - 34, 6 }, { CZ + 34, 6 } }, C.plaster, M.Plaster)
block("CourtCeiling", Vector3.new(CX1 - CX0, 1, 2 * CZ), Vector3.new((CX0 + CX1) / 2, F0 + CH + 0.5, 0), C.plaster, M.Plaster)
for i = 0, 3 do
	block("CeilingBeam", Vector3.new(2.4, 2.4, 2 * CZ), Vector3.new(CX0 + 10 + i * 20, F0 + CH - 1.2, 0), C.panelDark, M.Wood)
end
-- marble pilasters between the windows, a marble cornice, wood wainscot
for k = 0, 4 do
	local x = CX0 + 3 + k * 18
	for _, z in { -CZ + 1.3, CZ - 1.3 } do
		block("Pilaster", Vector3.new(3, CH - 4, 0.9), Vector3.new(x, F0 + (CH - 4) / 2, z), C.marble)
		block("PilasterCap", Vector3.new(4, 2, 1.4), Vector3.new(x, F0 + CH - 5, z), C.marbleWarm)
	end
end
block("CourtCorniceS", Vector3.new(CX1 - CX0, 1.6, 1.6), Vector3.new((CX0 + CX1) / 2, F0 + CH - 2.5, -CZ + 1.2), C.marbleWarm)
block("CourtCorniceN", Vector3.new(CX1 - CX0, 1.6, 1.6), Vector3.new((CX0 + CX1) / 2, F0 + CH - 2.5, CZ - 1.2), C.marbleWarm)
local function wainscot(a: Vector2, b: Vector2, h: number, off: Vector2)
	local mid = (a + b) / 2 + off
	local u = (b - a).Unit
	block("Wainscot", Vector3.new((b - a).Magnitude, h, 0.4), Vector3.new(mid.X, F0 + h / 2, mid.Y), C.panel, M.Wood, -math.atan2(u.Y, u.X))
	block("WainscotRail", Vector3.new((b - a).Magnitude, 0.5, 0.7), Vector3.new(mid.X, F0 + h, mid.Y), C.panelDark, M.Wood, -math.atan2(u.Y, u.X))
end
wainscot(Vector2.new(CX0, -CZ), Vector2.new(CX1, -CZ), 10, Vector2.new(0, 1))
wainscot(Vector2.new(CX0, CZ), Vector2.new(CX1, CZ), 10, Vector2.new(0, -1))
-- behind the bench: a marble wall with dark green marble panels
block("BenchWall", Vector3.new(0.6, 30, 2 * CZ - 20), Vector3.new(CX0 + 1.2, F0 + 15, 0), C.marble)
for _, z in { -28, 28 } do
	block("GreenPanel", Vector3.new(0.3, 18, 14), Vector3.new(CX0 + 1.6, F0 + 14, z), C.marbleGreen)
end
block("Floorboards", Vector3.new(CX1 - CX0, 0.2, 2 * CZ), Vector3.new((CX0 + CX1) / 2, F0 + 0.1, 0), C.wood, M.WoodPlanks)
-- the judge's bench
block("BenchDais", Vector3.new(12, 4, 30), Vector3.new(CX0 + 8, F0 + 2, 0), C.panelDark, M.Wood)
block("BenchFront", Vector3.new(2, 7, 30), Vector3.new(CX0 + 14, F0 + 3.5, 0), C.panel, M.Wood)
for k = -3, 3 do
	block("BenchPanel", Vector3.new(0.3, 4.6, 3.2), Vector3.new(CX0 + 15.1, F0 + 3.5, k * 4), C.panelDark, M.Wood)
end
block("BenchTop", Vector3.new(4, 0.6, 31), Vector3.new(CX0 + 13, F0 + 7.3, 0), C.panelDark, M.Wood)
chair("JudgeSeat", Vector3.new(CX0 + 8, F0 + 4.6, 0), Vector3.new(1, 0, 0), C.black)
do
	local seal = cylinder("Seal", 0.5, 12, Vector3.new(CX0 + 1.8, F0 + 22, 0), C.brass, M.Metal, "x")
	seal.CanCollide = false
	cylinder("SealInner", 0.6, 8, Vector3.new(CX0 + 1.9, F0 + 22, 0), C.bronze, M.Metal, "x").CanCollide = false
end
for _, z in { -12, 12 } do
	cylinder("FlagPole", 16, 0.4, Vector3.new(CX0 + 4, F0 + 8, z), C.brass, M.Metal)
	ball("FlagFinial", 0.8, Vector3.new(CX0 + 4, F0 + 16.3, z), C.brass, M.Metal)
	block("Flag", Vector3.new(0.2, 5, 7), Vector3.new(CX0 + 4, F0 + 13, z + 3.5 * (if z > 0 then 1 else -1)), if z > 0 then Color3.fromRGB(40, 60, 140) else Color3.fromRGB(160, 40, 40), M.Fabric)
end
block("ClerkDesk", Vector3.new(4, 3.4, 12), Vector3.new(CX0 + 18, F0 + 1.7, 15), C.panel, M.Wood)
block("WitnessBox", Vector3.new(7, 2, 7), Vector3.new(CX0 + 14, F0 + 1, -22), C.panelDark, M.Wood)
block("WitnessRail", Vector3.new(0.5, 4, 7), Vector3.new(CX0 + 17.6, F0 + 4, -22), C.panel, M.Wood)
chair("WitnessSeat", Vector3.new(CX0 + 13.5, F0 + 2.4, -22), Vector3.new(1, 0, 0.3))
block("DefenseTable", Vector3.new(5, 3.2, 14), Vector3.new(CX0 + 31, F0 + 1.6, -12), C.panel, M.Wood)
chair("DefendantSeat", Vector3.new(CX0 + 35, F0 + 1, -15), Vector3.new(-1, 0, 0))
chair("DefenseSeat", Vector3.new(CX0 + 35, F0 + 1, -9), Vector3.new(-1, 0, 0))
block("ProsecutionTable", Vector3.new(5, 3.2, 14), Vector3.new(CX0 + 31, F0 + 1.6, 12), C.panel, M.Wood)
chair("ProsecutorSeat", Vector3.new(CX0 + 35, F0 + 1, 12), Vector3.new(-1, 0, 0))
marker("BailiffSpot", Vector3.new(CX0 + 19, F0 + 3, -30))
block("JuryDais", Vector3.new(26, 1.2, 6), Vector3.new(CX0 + 35, F0 + 0.6, 38), C.panelDark, M.Wood)
block("JuryDais2", Vector3.new(26, 2.4, 5), Vector3.new(CX0 + 35, F0 + 1.2, 43.5), C.panelDark, M.Wood)
block("JuryRail", Vector3.new(26, 3.5, 0.6), Vector3.new(CX0 + 35, F0 + 1.75, 34.6), C.panel, M.Wood)
for row = 0, 1 do
	for i = 1, 6 do
		chair("JurorSeat" .. (row * 6 + i), Vector3.new(CX0 + 24 + (i - 1) * 4.2, F0 + 1.6 + row * 1.2, 37 + row * 5.5), Vector3.new(0, 0, -1), C.panel)
	end
end
block("BarRail", Vector3.new(0.8, 3.4, 2 * CZ - 24), Vector3.new(CX0 + 47, F0 + 1.7, -4), C.panel, M.Wood)
local g = 0
for row = 0, 5 do
	local x = CX0 + 53 + row * 4.4
	for _, side in { -1, 1 } do
		local zc = side * 25
		block("Pew", Vector3.new(2.4, 1.6, 30), Vector3.new(x, F0 + 1.3, zc), C.panel, M.Wood)
		block("PewBack", Vector3.new(0.5, 3.6, 30), Vector3.new(x + 1.3, F0 + 2.4, zc), C.panel, M.Wood)
		for k = 0, 5 do
			g += 1
			local s = chair("GallerySeat" .. g, Vector3.new(x, F0 + 2.2, zc - 12.5 + k * 5), Vector3.new(-1, 0, 0), C.panel, true)
			s.Transparency = 1
		end
	end
end
for _, x in { CX0 + 14, CX0 + 40, CX0 + 66 } do
	for _, z in { -24, 24 } do
		cylinder("PendantRod", 6, 0.2, Vector3.new(x, F0 + CH - 3, z), C.brass, M.Metal)
		light(ball("Pendant", 2.4, Vector3.new(x, F0 + CH - 7, z), C.light, M.Neon), 44, 1.2)
	end
end

---------------------------------------------------------------------------
-- behind the courtroom (x -88..-52): court holding, chambers; the jury room (north-west)
---------------------------------------------------------------------------
current = group("BackRooms")
local BX0 = -HALF_X
wall("HoldingWall", Vector2.new(BX0, -8), Vector2.new(CX0, -8), F0, 20, { { 22, 6 } }, C.plaster, M.Plaster)
for i = 0, 9 do
	cylinder("Bar", 12, 0.4, Vector3.new(CX0 - 6 - i * 1.2, F0 + 6, -22), C.black, M.Metal)
end
block("HoldingBench", Vector3.new(16, 1.8, 2.4), Vector3.new(BX0 + 12, F0 + 0.9, -44), C.granite, M.Concrete)
marker("HoldingSpot", Vector3.new(BX0 + 14, F0 + 3, -32))
wall("ChambersWall", Vector2.new(BX0, 22), Vector2.new(CX0, 22), F0, 20, { { 26, 6 } }, C.plaster, M.Plaster)
block("ChambersDesk", Vector3.new(4, 3.2, 9), Vector3.new(BX0 + 14, F0 + 1.6, 7), C.panelDark, M.Wood)
block("Bookcase", Vector3.new(2, 14, 22), Vector3.new(BX0 + 3, F0 + 7, 7), C.panelDark, M.Wood)
marker("ChambersSpot", Vector3.new(BX0 + 20, F0 + 3, 7))
-- THE JURY ROOM
local JX0, JX1, JZ0, JZ1 = BX0, 8, CZ + 8, HALF_Z
wall("JuryRoomS", Vector2.new(JX0, JZ0), Vector2.new(JX1, JZ0), F0, 28, { { 86, 6 } }, C.jury, M.Plaster)
wall("JuryRoomE", Vector2.new(JX1, JZ0), Vector2.new(JX1, JZ1), F0, 28, nil, C.jury, M.Plaster)
block("JuryCeiling", Vector3.new(JX1 - JX0, 1, JZ1 - JZ0), Vector3.new((JX0 + JX1) / 2, F0 + 28.5, (JZ0 + JZ1) / 2), C.jury, M.Plaster)
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
chair("JuryRoomSeat" .. j, Vector3.new(jcx - 23, F0 + 1.6, jcz), Vector3.new(1, 0, 0), C.wood)
j += 1
chair("JuryRoomSeat" .. j, Vector3.new(jcx + 23, F0 + 1.6, jcz), Vector3.new(-1, 0, 0), C.wood)
marker("JuryRoomSpot", Vector3.new(jcx, F0 + 3, JZ0 + 4))
cylinder("WallClock", 0.4, 3, Vector3.new(JX1 - 0.9, F0 + 18, jcz), Color3.fromRGB(245, 240, 225), M.SmoothPlastic, "x")
block("FanStand", Vector3.new(0.4, 5, 0.4), Vector3.new(JX0 + 5, F0 + 2.5, JZ1 - 6), C.black, M.Metal)
cylinder("FanCage", 1.2, 3.4, Vector3.new(JX0 + 5.3, F0 + 5.6, JZ1 - 6), C.black, M.Metal, "x")
block("WaterCooler", Vector3.new(1.6, 4.5, 1.6), Vector3.new(JX1 - 3, F0 + 2.25, JZ0 + 4), Color3.fromRGB(220, 225, 230), M.SmoothPlastic)
block("WashroomDoor", Vector3.new(0.4, 9, 4.5), Vector3.new(JX1 - 0.9, F0 + 4.5, JZ1 - 10), C.panel, M.Wood)
block("CoatRack", Vector3.new(0.4, 7, 0.4), Vector3.new(JX0 + 4, F0 + 3.5, JZ0 + 5), C.panelDark, M.Wood)
light(ball("JuryLight", 2, Vector3.new(jcx - 10, F0 + 25, jcz), C.light, M.Neon), 34, 1.1)
light(ball("JuryLight", 2, Vector3.new(jcx + 10, F0 + 25, jcz), C.light, M.Neon), 34, 1.1)
wall("HallN", Vector2.new(JX1, JZ0), Vector2.new(LOB_X0, JZ0), F0, 30, { { 9, 8 } }, C.plaster, M.Plaster)
light(ball("HallLight", 1.6, Vector3.new(17, F0 + 24, 84), C.light, M.Neon), 40)
light(ball("HallLight", 1.6, Vector3.new(-40, F0 + 24, -84), C.light, M.Neon), 40)

model:SetAttribute("Facility", "Courthouse")
model:SetAttribute("Inspiration", "12 Angry Men (1957) - New York County Courthouse, 60 Centre Street")
model.PrimaryPart = model:FindFirstChild("Entry") and (model.Entry :: Model):FindFirstChild("Podium") :: BasePart
model.Parent = workspace
print(("[Courthouse] built: %d parts"):format(#model:GetDescendants()))
return #model:GetDescendants()
