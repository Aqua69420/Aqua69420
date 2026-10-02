--[[
	GTAHandlingData - PASTE YOUR GTA IV handling.dat LINES HERE.

	1. Open GTA IV's common/data/handling.dat in a text editor.
	2. Copy the lines you want (or the whole file - comments and unused lines are fine)
	   and paste them between the [==[ and ]==] below, replacing the example lines.
	3. Point each Roblox car at a handling line in Cars (car name = handling name).
	   A car with no entry here keeps the old driving.
	The Output prints every line it read ("[GTAHandling] INFERNUS: 1400kg ...") so you can
	check the columns came through right. If your file has a different column order,
	set Columns to a list of field names (see GTAVehicle's header).

	The example lines below are rough stand-ins written for this game, NOT the real
	GTA IV values - replace them with the real file for the real feel.
]]

return {
	-- one metre in studs. 2.8 = Roblox character scale (a 5-stud avatar is ~1.8 m).
	MetersToStuds = 2.8,

	-- which handling line each car uses
	Cars = {
		["Sports Car"] = "INFERNUS",
		["Muscle Car"] = "SABREGT",
		["Van"] = "PONY",
		["SUV"] = "CAVALCADE",
		["Sedan"] = "ADMIRAL",
		["Pickup"] = "BOBCAT",
		["Luxury Coupe"] = "COQUETTE",
		["Luxury Sedan"] = "ORACLE",
		["Lowrider"] = "VOODOO",
		["Limo"] = "STRETCH",
		["MG"] = "BANSHEE",
	},

	Columns = nil, -- nil = GTA IV order

	Text = [==[
; name     mass  drag sub  comX comY comZ  bias gears force inert maxvel brake bbias lock  tmax tmin tlat tlong tsprg tbias susF comp reb  up    low   raise sbias coll weap def  eng  seat value  mflags hflags
INFERNUS   1400  1.0  85   0.0  0.0  -0.15 0.0  5     0.34  1.0   210    0.85  0.55  35.0  2.20 1.95 20.0 1.0   0.15  0.48  2.40 1.20 1.60 0.10  -0.13 0.0   0.50  1.0  1.0  1.0  1.0  0.24 95000  0      0
SABREGT    1600  1.0  85   0.0  0.0  -0.05 0.0  4     0.30  1.0   185    0.65  0.65  35.0  1.95 1.70 21.0 1.0   0.15  0.47  1.80 0.90 1.30 0.12  -0.16 0.0   0.50  1.0  1.0  1.0  1.0  0.20 25000  0      0
PONY       2200  1.6  85   0.0  0.0  0.05  0.0  4     0.18  1.0   140    0.50  0.65  35.0  1.80 1.60 21.0 1.0   0.15  0.50  1.60 1.00 1.40 0.12  -0.18 0.0   0.50  1.0  1.0  1.0  1.0  0.30 15000  0      0
CAVALCADE  2400  1.4  85   0.0  0.0  0.05  0.45 5     0.22  1.0   160    0.60  0.65  35.0  1.85 1.65 21.0 1.0   0.15  0.50  1.70 1.00 1.40 0.14  -0.20 0.0   0.50  1.0  1.0  1.0  1.0  0.30 30000  0      0
ADMIRAL    1700  1.2  85   0.0  0.0  0.0   0.0  5     0.22  1.0   165    0.65  0.65  35.0  1.95 1.75 21.0 1.0   0.15  0.49  1.80 1.00 1.40 0.12  -0.16 0.0   0.50  1.0  1.0  1.0  1.0  0.25 18000  0      0
BOBCAT     2000  1.4  85   0.0  0.0  0.05  0.0  4     0.20  1.0   150    0.55  0.65  35.0  1.85 1.65 21.0 1.0   0.15  0.50  1.60 1.00 1.40 0.14  -0.20 0.0   0.50  1.0  1.0  1.0  1.0  0.30 14000  0      0
COQUETTE   1400  1.0  85   0.0  0.0  -0.10 0.0  5     0.30  1.0   200    0.80  0.55  35.0  2.15 1.90 20.0 1.0   0.15  0.48  2.20 1.20 1.60 0.10  -0.14 0.0   0.50  1.0  1.0  1.0  1.0  0.24 65000  0      0
ORACLE     1800  1.1  85   0.0  0.0  0.0   0.0  5     0.24  1.0   175    0.70  0.65  35.0  2.00 1.80 21.0 1.0   0.15  0.49  1.90 1.00 1.40 0.12  -0.16 0.0   0.50  1.0  1.0  1.0  1.0  0.25 40000  0      0
VOODOO     1800  1.3  85   0.0  0.0  0.0   0.0  4     0.24  1.0   155    0.50  0.65  35.0  1.80 1.60 22.0 1.0   0.15  0.48  1.50 0.80 1.20 0.14  -0.20 0.0   0.50  1.0  1.0  1.0  1.0  0.20 12000  0      0
STRETCH    2800  1.4  85   0.0  0.0  0.0   0.0  4     0.20  1.0   150    0.55  0.60  32.0  1.85 1.65 21.0 1.0   0.15  0.50  1.60 1.00 1.40 0.12  -0.16 0.0   0.50  1.0  1.0  1.0  1.0  0.30 50000  0      0
BANSHEE    1300  1.0  85   0.0  0.0  -0.10 0.0  5     0.32  1.0   195    0.80  0.55  35.0  2.10 1.85 20.0 1.0   0.15  0.47  2.20 1.20 1.60 0.10  -0.14 0.0   0.50  1.0  1.0  1.0  1.0  0.24 60000  0      0
]==],
}
