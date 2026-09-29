-- Export every custom script in a place file to place/scripts/<Instance path>.lua
-- usage: lune run tools/export.luau <place.rbxl>
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local input = process.args[1] or error("usage: lune run tools/export.luau <place.rbxl>")
local game = roblox.deserializePlace(fs.readFile(input))

local SKIP = { "PlayerModule", "ChatScript", "BubbleChat", "ChatServiceRunner", "RbxCharacterSounds" }

local function pathOf(inst)
	local parts = {}
	local cur = inst
	while cur and cur ~= game do
		table.insert(parts, 1, (cur.Name:gsub("[/\\:*?\"<>|]", "_")))
		cur = cur.Parent
	end
	return table.concat(parts, "/")
end

local seen, written = {}, 0
local list = {}
for _, d in game:GetDescendants() do
	if d:IsA("LuaSourceContainer") then
		local p = pathOf(d)
		local skip = false
		for _, s in SKIP do if string.find(p, s, 1, true) then skip = true end end
		if not skip then
			seen[p] = (seen[p] or 0) + 1
			table.insert(list, { p = p, d = d })
		end
	end
end
if fs.isDir("place/scripts") then fs.removeDir("place/scripts") end
for _, item in list do
	if seen[item.p] == 1 then
		local file = "place/scripts/" .. item.p .. "." .. item.d.ClassName .. ".lua"
		local dir = string.match(file, "^(.*)/[^/]+$")
		fs.writeDir(dir)
		fs.writeFile(file, item.d.Source)
		written += 1
	end
end
local dup = {}
for p, n in seen do if n > 1 then table.insert(dup, p .. " (x" .. n .. ")") end end
table.sort(dup)
fs.writeFile("place/DUPLICATE_PATHS.txt", "# Scripts sharing a full path are not exported (build cannot target them)\n" .. table.concat(dup, "\n") .. "\n")
print(("exported %d scripts, %d ambiguous paths skipped"):format(written, #dup))
