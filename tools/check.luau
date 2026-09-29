-- Compile-check every exported script (syntax only).
-- usage: lune run tools/check.luau [file ...]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local bad = 0
local function check(path)
	local ok, result = pcall(luau.compile, fs.readFile(path))
	-- luau.compile does not always throw: a failed compile returns bytecode whose
	-- first byte is 0 followed by the error (e.g. "Out of local registers").
	if ok and type(result) == "string" and string.byte(result, 1) == 0 then
		ok, result = false, string.sub(result, 2)
	end
	if not ok then bad += 1; print("FAIL " .. path .. "\n  " .. tostring(result)) end
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
