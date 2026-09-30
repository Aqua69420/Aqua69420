-- Package the Facility Mapper Studio plugin as a model file.
-- usage: lune run tools/build_plugin.luau
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local script = roblox.Instance.new("Script")
script.Name = "FacilityMapper"
script.Source = fs.readFile("plugins/FacilityMapper/FacilityMapper.server.lua")
local xml = roblox.serializeModel({ script }, true)
-- Studio reads script source from a ProtectedString property
local a, b = string.find(xml, '<string name="Source">', 1, true)
if a then
	local close = string.find(xml, "]]></string>", b, true)
	xml = string.sub(xml, 1, a - 1) .. '<ProtectedString name="Source">' .. string.sub(xml, b + 1, close - 1) .. "]]></ProtectedString>" .. string.sub(xml, close + #"]]></string>")
end
fs.writeFile("plugins/FacilityMapper.rbxmx", xml)
print("wrote plugins/FacilityMapper.rbxmx")
