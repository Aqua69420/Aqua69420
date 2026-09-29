-- Write place/scripts/*.lua back into a place file.
-- usage: lune run tools/build.luau <base.rbxl> <output.rbxl>
-- Only scripts whose text differs from the base are touched; everything else in
-- the place (parts, maps, attributes) is carried through unchanged.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local input = process.args[1] or error("usage: lune run tools/build.luau <base.rbxl> <output.rbxl>")
local output = process.args[2] or error("missing output path")
local game = roblox.deserializePlace(fs.readFile(input))

local function pathOf(inst)
	local parts = {}
	local cur = inst
	while cur and cur ~= game do
		table.insert(parts, 1, (cur.Name:gsub("[/\\:*?\"<>|]", "_")))
		cur = cur.Parent
	end
	return table.concat(parts, "/")
end

local byPath, count = {}, {}
for _, d in game:GetDescendants() do
	if d:IsA("LuaSourceContainer") then
		local key = pathOf(d) .. "." .. d.ClassName .. ".lua"
		byPath[key] = d
		count[key] = (count[key] or 0) + 1
	end
end

local changed = 0
local function walk(dir, rel)
	for _, name in fs.readDir(dir) do
		local full = dir .. "/" .. name
		local key = if rel == "" then name else rel .. "/" .. name
		if fs.isDir(full) then
			walk(full, key)
		elseif string.sub(name, -4) == ".lua" then
			local inst = byPath[key]
			if not inst then
				warn("no script in place for " .. key)
			elseif count[key] > 1 then
				warn("ambiguous path, skipped: " .. key)
			else
				local src = fs.readFile(full)
				if inst.Source ~= src then
					inst.Source = src
					changed += 1
					print("updated " .. key)
				end
			end
		end
	end
end
walk("place/scripts", "")
fs.writeFile(output, roblox.serializePlace(game))
print(("wrote %s (%d scripts updated)"):format(output, changed))
