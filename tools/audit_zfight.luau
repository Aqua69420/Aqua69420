-- Audits a model for z-fighting: two visible block parts with faces in the same plane,
-- facing the same way, overlapping by more than a sliver. Run in Studio's Edit datamodel.
-- Returns the total and the worst name pairs. Usage: loadstring(source)()(workspace.Courthouse)
return function(model: Instance, maxLines: number?): string
	local function faces(p: BasePart)
		local cf, half = p.CFrame, p.Size / 2
		local axes = { { cf.RightVector, half.X }, { cf.UpVector, half.Y }, { -cf.LookVector, half.Z } }
		local res = {}
		for i, a in axes do
			local o = {}
			for j, b in axes do
				if j ~= i then table.insert(o, b) end
			end
			for _, s in { 1, -1 } do
				table.insert(res, { n = a[1] * s, d = (a[1] * s):Dot(cf.Position) + a[2], u = o[1], v = o[2] })
			end
		end
		return res
	end
	local function extent(p: BasePart, dir: Vector3): number
		local cf, h = p.CFrame, p.Size / 2
		return math.abs(dir:Dot(cf.RightVector)) * h.X + math.abs(dir:Dot(cf.UpVector)) * h.Y + math.abs(dir:Dot(cf.LookVector)) * h.Z
	end
	local function ov(c1: number, e1: number, c2: number, e2: number): number
		return math.min(c1 + e1, c2 + e2) - math.max(c1 - e1, c2 - e2)
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	local seen, left, names = {}, 0, {}
	for _, t in model:GetDescendants() do
		if t:IsA("Part") and t.Shape == Enum.PartType.Block and t.Transparency < 1 then
			for _, o in workspace:GetPartBoundsInBox(t.CFrame, t.Size + Vector3.new(0.1, 0.1, 0.1), params) do
				if o ~= t and o:IsA("Part") and o.Shape == Enum.PartType.Block and o.Transparency < 1 and not seen[o] then
					for _, f in faces(t) do
						for _, g in faces(o) do
							if f.n:Dot(g.n) > 0.999 and math.abs(f.d - g.d) < 0.03
								and ov(f.u[1]:Dot(t.Position), f.u[2], f.u[1]:Dot(o.Position), extent(o, f.u[1])) > 0.05
								and ov(f.v[1]:Dot(t.Position), f.v[2], f.v[1]:Dot(o.Position), extent(o, f.v[1])) > 0.05 then
								left += 1
								local a, b = t.Name, o.Name
								if a > b then a, b = b, a end
								names[a .. "/" .. b] = (names[a .. "/" .. b] or 0) + 1
							end
						end
					end
				end
			end
			seen[t] = true
		end
	end
	local list = {}
	for k, v in names do
		table.insert(list, v .. "x " .. k)
	end
	table.sort(list, function(a, b)
		return (tonumber(a:match("^%d+")) or 0) > (tonumber(b:match("^%d+")) or 0)
	end)
	local out = { ("coplanar face clashes: %d"):format(left) }
	for i = 1, math.min(maxLines or 30, #list) do
		table.insert(out, list[i])
	end
	return table.concat(out, "\n")
end
