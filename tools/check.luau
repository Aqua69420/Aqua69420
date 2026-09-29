-- Compile-check every exported script (syntax only).
-- usage: lune run tools/check.luau [file ...]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local bad = 0
local function check(path)
	local ok, err = pcall(luau.compile, fs.readFile(path))
	if not ok then bad += 1; print("FAIL " .. path .. "\n  " .. tostring(err)) end
end
local function walk(dir)
	for _, name in fs.readDir(dir) do
		local full = dir .. "/" .. name
		if fs.isDir(full) then walk(full) elseif string.sub(name, -4) == ".lua" then check(full) end
	end
end
if #process.args > 0 then for _, f in process.args do check(f) end else walk("place/scripts") end
print(if bad == 0 then "all scripts compile" else bad .. " failed")
process.exit(if bad == 0 then 0 else 1)
