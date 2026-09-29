-- CasinoClient: slot machine, keno, blackjack, baccarat, roulette and hold'em
-- screens for CasinoServer.
-- Walk up to a machine/table and press E. Type a bet (you can write 250k or 10m).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local casino = ReplicatedStorage:WaitForChild("Functions"):WaitForChild("Casino")
local openEvent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("CasinoOpen")

local FELT = Color3.fromRGB(18, 70, 40)
local DARK = Color3.fromRGB(25, 25, 30)
local GOLD = Color3.fromRGB(235, 185, 40)
local WHITE = Color3.new(1, 1, 1)
local RED = Color3.fromRGB(210, 50, 50)
local GREEN = Color3.fromRGB(60, 160, 70)

local ICONS = {
	CHERRY = "🍒", LEMON = "🍋", ORANGE = "🍊", GRAPE = "🍇",
	BELL = "🔔", BAR = "BAR", SEVEN = "7", DIAMOND = "💎",
}
local ICON_LIST = { "CHERRY", "LEMON", "ORANGE", "GRAPE", "BELL", "BAR", "SEVEN", "DIAMOND" }

local CLEO_ICONS = {
	QUEEN = "Q", KING = "K", ACE = "A", ANKH = "☥", EYE = "👁", SCARAB = "🪲",
	SPHINX = "🔺", CLEOPATRA = "👑",
}
local CLEO_ICON_LIST = { "QUEEN", "KING", "ACE", "ANKH", "EYE", "SCARAB", "SPHINX", "CLEOPATRA" }
local CLEO_COLORS = {
	QUEEN = Color3.new(1, 1, 1), KING = Color3.new(1, 1, 1), ACE = Color3.new(1, 1, 1),
	ANKH = Color3.fromRGB(80, 200, 220), EYE = Color3.fromRGB(80, 200, 220),
	SCARAB = Color3.fromRGB(60, 220, 100), SPHINX = Color3.fromRGB(235, 185, 40),
	CLEOPATRA = Color3.fromRGB(235, 185, 40),
}

local screen = Instance.new("ScreenGui")
screen.Name = "CasinoGui"
screen.ResetOnSpawn = false
screen.DisplayOrder = 18
screen.Parent = player:WaitForChild("PlayerGui")

local function make(className, props, parent)
	local obj = Instance.new(className)
	for k, v in pairs(props) do
		obj[k] = v
	end
	obj.Parent = parent
	return obj
end

local function label(parent, text, props)
	local l = make("TextLabel", {
		BackgroundTransparency = 1, Text = text, TextColor3 = WHITE,
		Font = Enum.Font.SourceSansBold, TextScaled = true,
	}, parent)
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

local function button(parent, text, color, props)
	local b = make("TextButton", {
		Text = text, TextColor3 = WHITE, Font = Enum.Font.SourceSansBold, TextScaled = true,
		BackgroundColor3 = color or GREEN, BorderSizePixel = 0, AutoButtonColor = true,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	return b
end

local function fmt(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return "$" .. out:gsub("^,", "")
end

local function parseBet(text)
	text = tostring(text):lower():gsub("[,%$%s]", "")
	local num, suffix = text:match("^([%d%.]+)([km]?)$")
	num = tonumber(num)
	if not num then
		return nil
	end
	if suffix == "k" then
		num *= 1000
	elseif suffix == "m" then
		num *= 1000000
	end
	return math.floor(num)
end

local function balance()
	local cash, bank = player:FindFirstChild("Cash"), player:FindFirstChild("Money")
	return (cash and cash.Value or 0) + (bank and bank.Value or 0)
end

local current = nil
local closeCleanup=nil
local function close()
	if closeCleanup then local cleanup=closeCleanup;closeCleanup=nil;cleanup() end
	if current then
		current:Destroy()
		current = nil
	end
end

player.CharacterRemoving:Connect(close)

-- Shared window: title, balance, bet box with quick buttons, status line.
local function window(title, tierName, minBet, maxBet, height)
	close()
	local frame = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0.56, 0, height, 0), BackgroundColor3 = FELT, BorderSizePixel = 0,
	}, screen)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, frame)
	make("UIStroke", { Color = GOLD, Thickness = 2 }, frame)
	current = frame
	label(frame, title, { Position = UDim2.new(0.02, 0, 0.01, 0), Size = UDim2.new(0.6, 0, 0.08, 0), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GOLD })
	label(frame, ("%s  |  %s - %s"):format(tierName, fmt(minBet), fmt(maxBet)), {
		Position = UDim2.new(0.02, 0, 0.09, 0), Size = UDim2.new(0.6, 0, 0.05, 0),
		TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.SourceSans,
	})
	local bal = label(frame, "", { Position = UDim2.new(0.6, 0, 0.09, 0), Size = UDim2.new(0.33, 0, 0.05, 0), TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.SourceSans })
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not frame.Parent then
			conn:Disconnect()
			return
		end
		bal.Text = "Balance: " .. fmt(balance())
	end)
	local x = button(frame, "X", RED, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.new(0, 30, 0, 30) })
	x.MouseButton1Click:Connect(close)

	-- bet row
	local betBox = make("TextBox", {
		Position = UDim2.new(0.02, 0, 0.84, 0), Size = UDim2.new(0.26, 0, 0.12, 0),
		BackgroundColor3 = DARK, TextColor3 = WHITE, Font = Enum.Font.SourceSansBold, TextScaled = true,
		Text = tostring(minBet), PlaceholderText = "Bet", ClearTextOnFocus = false,
	}, frame)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, betBox)
	local function getBet()
		return math.clamp(parseBet(betBox.Text) or minBet, minBet, maxBet)
	end
	local function setBet(v)
		betBox.Text = tostring(math.clamp(math.floor(v), minBet, maxBet))
	end
	betBox.FocusLost:Connect(function()
		setBet(getBet())
	end)
	local quick = { { "MIN", function() setBet(minBet) end }, { "½", function() setBet(getBet() / 2) end },
		{ "x2", function() setBet(getBet() * 2) end }, { "MAX", function() setBet(maxBet) end } }
	for i, q in ipairs(quick) do
		local b = button(frame, q[1], DARK, { Position = UDim2.new(0.29 + (i - 1) * 0.075, 0, 0.84, 0), Size = UDim2.new(0.068, 0, 0.12, 0) })
		b.MouseButton1Click:Connect(q[2])
	end
	local status = label(frame, "", { Position = UDim2.new(0.02, 0, 0.72, 0), Size = UDim2.new(0.96, 0, 0.09, 0), TextColor3 = GOLD })
	return frame, getBet, status
end

---------------------------------------------------------------------------
-- Slots
---------------------------------------------------------------------------
local function openSlots(id, tierName, minBet, maxBet)
	local frame, getBet, status = window("SLOTS", tierName, minBet, maxBet, 0.5)
	local reels = {}
	for i = 1, 3 do
		local box = make("Frame", { Position = UDim2.new(0.08 + (i - 1) * 0.29, 0, 0.18, 0), Size = UDim2.new(0.26, 0, 0.5, 0), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, frame)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, box)
		reels[i] = label(box, ICONS.SEVEN, { Size = UDim2.new(1, 0, 1, 0), TextColor3 = RED, Font = Enum.Font.GothamBlack })
	end
	local spinning = false
	local spin = button(frame, "SPIN", RED, { Position = UDim2.new(0.62, 0, 0.84, 0), Size = UDim2.new(0.35, 0, 0.12, 0) })
	spin.MouseButton1Click:Connect(function()
		if spinning then
			return
		end
		spinning = true
		status.Text = ""
		local result
		task.spawn(function()
			result = casino:InvokeServer("Spin", id, getBet())
		end)
		local started = os.clock()
		local stopped = { false, false, false }
		while frame.Parent and not (stopped[1] and stopped[2] and stopped[3]) do
			local t = os.clock() - started
			for i = 1, 3 do
				if not stopped[i] then
					if result and t > 0.8 + i * 0.45 then
						stopped[i] = true
						if result.ok then
							reels[i].Text = ICONS[result.reels[i]]
						end
					else
						reels[i].Text = ICONS[ICON_LIST[math.random(1, #ICON_LIST)]]
					end
				end
			end
			if result and not result.ok then
				break
			end
			task.wait(0.06)
		end
		if result then
			if not result.ok then
				status.Text = result.message
			elseif result.win > 0 then
				status.Text = ("WIN %s  (%sx)"):format(fmt(result.win), tostring(result.multiplier))
				casino:InvokeServer("Reveal", id) -- credits the win now, right as it's revealed
			else
				status.Text = "No win - try again"
			end
		end
		spinning = false
	end)
	label(frame, "3 of a kind: 💎200x  7 80x  BAR 30x  🔔15x  🍇10x  🍊8x  🍋5x  🍒4x   |  two 🍒 2x, one 🍒 1x", {
		Position = UDim2.new(0.02, 0, 0.68, 0), Size = UDim2.new(0.96, 0, 0.04, 0), Font = Enum.Font.SourceSans,
	})
end

---------------------------------------------------------------------------
-- Cleopatra - 3 rows x 5 reels, 20 paylines, wilds, scatters, free-spins
-- bonus. Doesn't draw the actual line shapes over the grid (that's a lot of
-- overlay geometry for little gameplay benefit) - it just tells you how
-- many lines paid and the total.
---------------------------------------------------------------------------
local function openCleopatra(id, tierName, minBet, maxBet)
	local frame, getBet, status = window("CLEOPATRA  -  20 paylines, wilds & scatters", tierName, minBet, maxBet, 0.66)
	local cells = {} -- cells[col][row]
	for col = 1, 5 do
		cells[col] = {}
		for row = 1, 3 do
			local box = make("Frame", {
				Position = UDim2.new(0.03 + (col - 1) * 0.188, 0, 0.14 + (row - 1) * 0.15, 0),
				Size = UDim2.new(0.17, 0, 0.14, 0),
				BackgroundColor3 = Color3.fromRGB(15, 15, 20), BorderSizePixel = 0,
			}, frame)
			make("UICorner", { CornerRadius = UDim.new(0, 5) }, box)
			cells[col][row] = label(box, CLEO_ICONS.CLEOPATRA, { Size = UDim2.new(1, 0, 1, 0), TextColor3 = CLEO_COLORS.CLEOPATRA, Font = Enum.Font.GothamBlack })
		end
	end

	local bonusBanner = label(frame, "", {
		Position = UDim2.new(0.03, 0, 0.62, 0), Size = UDim2.new(0.94, 0, 0.05, 0),
		TextColor3 = Color3.fromRGB(235, 185, 40), Visible = false,
	})

	local spinning = false
	local spin = button(frame, "SPIN", RED, { Position = UDim2.new(0.62, 0, 0.84, 0), Size = UDim2.new(0.35, 0, 0.1, 0) })

	-- Server sends the grid flattened as col1row1, col1row2, col1row3, col2row1, ...
	local function settle(flat)
		local i = 1
		for col = 1, 5 do
			for row = 1, 3 do
				local sym = flat[i]
				cells[col][row].Text = CLEO_ICONS[sym]
				cells[col][row].TextColor3 = CLEO_COLORS[sym]
				i += 1
			end
		end
	end

	local function settleColumn(flat, col)
		for row = 1, 3 do
			local sym = flat[(col - 1) * 3 + row]
			cells[col][row].Text = CLEO_ICONS[sym]
			cells[col][row].TextColor3 = CLEO_COLORS[sym]
		end
	end

	spin.MouseButton1Click:Connect(function()
		if spinning then
			return
		end
		spinning = true
		status.Text = ""
		bonusBanner.Visible = false
		local result
		task.spawn(function()
			result = casino:InvokeServer("Spin", id, getBet())
		end)
		local started = os.clock()
		local stopped = { false, false, false, false, false }
		while frame.Parent and not (stopped[1] and stopped[2] and stopped[3] and stopped[4] and stopped[5]) do
			local t = os.clock() - started
			for col = 1, 5 do
				if not stopped[col] then
					if result and t > 0.6 + col * 0.3 then
						stopped[col] = true
						if result.ok then
							settleColumn(result.grid, col)
						end
					else
						for row = 1, 3 do
							local sym = CLEO_ICON_LIST[math.random(1, #CLEO_ICON_LIST)]
							cells[col][row].Text = CLEO_ICONS[sym]
							cells[col][row].TextColor3 = CLEO_COLORS[sym]
						end
					end
				end
			end
			if result and not result.ok then
				break
			end
			task.wait(0.06)
		end

		if not result or not result.ok then
			status.Text = result and result.message or "?"
			spinning = false
			return
		end
		settle(result.grid)
		local lineCount = #result.hitLines

		if result.bonus then
			bonusBanner.Visible = true
			bonusBanner.Text = ("BONUS! %d FREE SPINS at 3x"):format(result.bonus.spins)
			task.wait(1.2)
			local running = 0
			for i, spinResult in ipairs(result.bonus.results) do
				if not frame.Parent then
					break
				end
				settle(spinResult.grid)
				running += spinResult.win
				bonusBanner.Text = ("Free spin %d / %d  -  running total %s"):format(i, result.bonus.spins, fmt(running))
				task.wait(0.3)
			end
		end

		if result.win > 0 then
			status.Text = lineCount > 0 and ("WIN %s  (%d line%s)"):format(fmt(result.win), lineCount, lineCount == 1 and "" or "s")
				or ("WIN %s"):format(fmt(result.win))
			casino:InvokeServer("Reveal", id)
		else
			status.Text = "No win - try again"
		end
		spinning = false
	end)

	label(frame, "3+ matching left-to-right on any of 20 lines wins. 👑 Cleopatra is wild. 🔺 Sphinx x3+ anywhere triggers free spins.", {
		Position = UDim2.new(0.02, 0, 0.68, 0), Size = UDim2.new(0.96, 0, 0.04, 0), Font = Enum.Font.SourceSans,
	})
end

---------------------------------------------------------------------------
-- Keno
------------------------------------------------------------------------------------------------------------------------------------------------------
-- Keno
---------------------------------------------------------------------------
local function openKeno(id, tierName, minBet, maxBet)
	local frame, getBet, status = window("KENO  -  pick up to 10 numbers", tierName, minBet, maxBet, 0.62)
	local grid = make("Frame", { Position = UDim2.new(0.02, 0, 0.15, 0), Size = UDim2.new(0.96, 0, 0.56, 0), BackgroundTransparency = 1 }, frame)
	local picks, cells = {}, {}
	local function pickCount()
		local n = 0
		for _ in pairs(picks) do
			n += 1
		end
		return n
	end
	for n = 1, 80 do
		local r, c = (n - 1) // 10, (n - 1) % 10
		local cell = button(grid, tostring(n), DARK, { Position = UDim2.new(c / 10, 2, r / 8, 2), Size = UDim2.new(0.1, -4, 0.125, -4) })
		cells[n] = cell
		cell.MouseButton1Click:Connect(function()
			if picks[n] then
				picks[n] = nil
			elseif pickCount() < 10 then
				picks[n] = true
			end
			for m, other in ipairs(cells) do
				other.BackgroundColor3 = picks[m] and GOLD or DARK
				other.TextColor3 = picks[m] and Color3.new(0, 0, 0) or WHITE
			end
		end)
	end
	local busy = false
	local play = button(frame, "PLAY", RED, { Position = UDim2.new(0.62, 0, 0.84, 0), Size = UDim2.new(0.35, 0, 0.12, 0) })
	play.MouseButton1Click:Connect(function()
		if busy then
			return
		end
		local list = {}
		for n in pairs(picks) do
			table.insert(list, n)
		end
		if #list == 0 then
			status.Text = "Pick at least one number"
			return
		end
		busy = true
		for m, other in ipairs(cells) do
			other.BackgroundColor3 = picks[m] and GOLD or DARK
		end
		local result = casino:InvokeServer("Play", id, getBet(), list)
		if not result.ok then
			status.Text = result.message
			busy = false
			return
		end
		status.Text = "Drawing..."
		for i, n in ipairs(result.drawn) do
			if not frame.Parent then
				return
			end
			cells[n].BackgroundColor3 = picks[n] and GREEN or RED
			status.Text = ("Drawing... %d/20"):format(i)
			task.wait(0.08)
		end
		status.Text = result.win > 0 and ("%d hits - WIN %s"):format(result.hits, fmt(result.win))
			or ("%d hits - no win"):format(result.hits)
		if result.win > 0 then
			casino:InvokeServer("Reveal", id) -- credits the win now, right as it's revealed
		end
		busy = false
	end)
end

---------------------------------------------------------------------------
-- Blackjack v89 - original casino UI path, shared dealer, every player hand
-- visible at the physical table, and a round lifecycle that cannot deadlock.
---------------------------------------------------------------------------
local function openBlackjack(id, tierName, minBet, maxBet, tableCamera)
	local frame, getBet, status = window("BLACKJACK  -  MULTIPLAYER TABLE", tierName, minBet, maxBet, 0.86)
	frame.Size=UDim2.fromScale(0.90,0.86)
	status.Position = UDim2.new(0.02, 0, 0.73, 0)
	status.Size = UDim2.new(0.96, 0, 0.08, 0)

	local dealerRow = make("Frame", {
		Position = UDim2.new(0.02, 0, 0.15, 0), Size = UDim2.new(0.96, 0, 0.23, 0),
		BackgroundTransparency = 1,
	}, frame)
	local playersPanel = make("ScrollingFrame", {
		Position = UDim2.new(0.02, 0, 0.40, 0), Size = UDim2.new(0.96, 0, 0.30, 0),
		BackgroundColor3 = Color3.fromRGB(13, 50, 29), BorderSizePixel = 0,
		ScrollBarThickness = 6, CanvasSize = UDim2.new(0, 0, 0, 0),
	}, frame)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, playersPanel)

	local camera=workspace.CurrentCamera
    local savedCamera=camera and {kind=camera.CameraType,cf=camera.CFrame,fov=camera.FieldOfView,subject=camera.CameraSubject}
    local tableMode=false
    local originalLayout={}
    local toggle=button(frame,"TABLE VIEW",DARK,{Position=UDim2.fromScale(0.68,0.015),Size=UDim2.fromScale(0.23,0.065)})
    local function restoreCamera()
        if camera and savedCamera then camera.CameraType=savedCamera.kind;camera.CFrame=savedCamera.cf;camera.FieldOfView=savedCamera.fov;camera.CameraSubject=savedCamera.subject end
    end
    -- v150: hide every world ProximityPrompt locally while blackjack is open.
    -- Individual prompt suppression prevents the table's E prompt from sitting over the cards.
    local promptService=game:GetService("ProximityPromptService")
    local promptsWereEnabled=promptService.Enabled
    promptService.Enabled=false
    local hiddenPrompts={}
    local function hideBlackjackPrompt(obj)
        if obj:IsA("ProximityPrompt") then
            if hiddenPrompts[obj] == nil then hiddenPrompts[obj]=obj.Enabled end
            obj.Enabled=false
        end
    end
    for _,obj in workspace:GetDescendants() do hideBlackjackPrompt(obj) end
    local promptAddedConnection=workspace.DescendantAdded:Connect(hideBlackjackPrompt)
    local hiddenSigns={}
    local building=workspace:FindFirstChild("BellagioBuilding")
    if building then
        for _,gui in building:GetDescendants() do
            if gui:IsA("BillboardGui") and gui.Name=="LimitSign" then
                hiddenSigns[gui]=gui.Enabled;gui.Enabled=false
            end
        end
    end
    closeCleanup=function()
        restoreCamera()
        if promptAddedConnection then promptAddedConnection:Disconnect();promptAddedConnection=nil end
        for prompt,enabled in hiddenPrompts do if prompt.Parent then prompt.Enabled=enabled end end
        promptService.Enabled=promptsWereEnabled
        for gui,enabled in hiddenSigns do if gui.Parent then gui.Enabled=enabled end end
    end
    local function setMode(useTable)
        tableMode=useTable and typeof(tableCamera)=="CFrame" and camera~=nil
        -- v150: keep a compact dealer/player card HUD visible in physical table view.
        dealerRow.Visible=true;playersPanel.Visible=true
        frame.AnchorPoint=Vector2.new(0.5,tableMode and 1 or 0.5)
        frame.Position=UDim2.fromScale(0.5,tableMode and 0.98 or 0.5)
        frame.Size=tableMode and UDim2.new(0.90,0,0,200) or UDim2.fromScale(0.90,0.86)
        for _,child in frame:GetChildren() do
            if child:IsA("GuiObject") and child~=dealerRow and child~=playersPanel then
                originalLayout[child]=originalLayout[child] or {pos=child.Position,size=child.Size}
                local layout=originalLayout[child]
                child.Position=layout.pos;child.Size=layout.size
                if tableMode then
                    if layout.pos.Y.Scale>=0.80 then
                        child.Position=UDim2.new(layout.pos.X.Scale,layout.pos.X.Offset,1,-56)
                        child.Size=UDim2.new(layout.size.X.Scale,layout.size.X.Offset,0,44)
                    elseif child==status then child.Position=UDim2.new(0.02,0,1,-100);child.Size=UDim2.new(0.96,0,0,34)
                    elseif layout.size.Y.Scale>0 then
                        child.Size=UDim2.new(layout.size.X.Scale,layout.size.X.Offset,0,24)
                        if layout.pos.Y.Scale>=0.08 then child.Position=UDim2.new(layout.pos.X.Scale,layout.pos.X.Offset,0,34) end
                    end
                end
            end
        end
        toggle.Text=tableMode and "ENLARGE HAND" or "TABLE VIEW"
        if tableMode then camera.CameraType=Enum.CameraType.Scriptable;camera.CFrame=tableCamera;camera.FieldOfView=55 else restoreCamera() end
    end
    toggle.Visible=typeof(tableCamera)=="CFrame"
    toggle.Activated:Connect(function() setMode(not tableMode) end)
    make("UIGradient",{Color=ColorSequence.new(Color3.fromRGB(13,48,35),Color3.fromRGB(27,104,70)),Rotation=90},frame)
    local dealerKey,playersKey
    local suitIcon = { S = "♠", H = "♥", D = "♦", C = "♣" }

	local function cardText(card)
		if card == "??" then return "?" end
		local suit = card:sub(-1)
		return card:sub(1, -2) .. (suitIcon[suit] or suit)
	end

	local function showDealer(cards, totalValue)
		local key=table.concat(cards or {},",")..tostring(totalValue)
		if key==dealerKey then return end;dealerKey=key
		dealerRow:ClearAllChildren()
		label(dealerRow, "DEALER" .. (totalValue and ("  (" .. totalValue .. ")") or ""), {
			Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(0.22, 0, 0.28, 0),
			TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GOLD,
		})
		for i, card in ipairs(cards or {}) do
			local box = make("Frame", {
				Position = UDim2.new(0.25+(i-1)*math.min(0.09,0.62/math.max(1,#cards-1)),0,0.03,0), Size = UDim2.new(0.085,0,0.94,0),
				BackgroundColor3 = card == "??" and Color3.fromRGB(120, 30, 30) or WHITE, BorderSizePixel = 0,
			}, dealerRow)
			make("UICorner", { CornerRadius = UDim.new(0, 5) }, box)
			local suit = card ~= "??" and card:sub(-1) or ""
			label(box, cardText(card), {
				Size = UDim2.new(1, 0, 1, 0),
				TextColor3 = (suit == "H" or suit == "D") and RED or (card == "??" and WHITE or Color3.new(0, 0, 0)),
			})
		end
	end

	local function showPlayers(players)
		local key=game:GetService("HttpService"):JSONEncode(players or {})
        if key==playersKey then return end;playersKey=key
        playersPanel:ClearAllChildren()
        players=table.clone(players or {})
        table.sort(players,function(a,b) if a.isYou~=b.isYou then return a.isYou end;return a.seat<b.seat end)
		local y = 4
		for _, ps in ipairs(players or {}) do
			local rowHeight = tableMode and (ps.isYou and 54 or 44) or (ps.isYou and 174 or 116)
			local row = make("Frame", {
				Position = UDim2.new(0, 4, 0, y), Size = UDim2.new(1, -12, 0, rowHeight),
				BackgroundColor3 = ps.isYou and Color3.fromRGB(34, 92, 55) or DARK,
				BorderSizePixel = 0,
			}, playersPanel)
			make("UICorner", { CornerRadius = UDim.new(0, 5) }, row)
			local who = tostring(ps.name or ps.username or "Player") .. (ps.isYou and "  (YOU)" or "")
			label(row, who, {
				Position = UDim2.new(0.01, 0, 0.05, 0), Size = UDim2.new(0.25, 0, 0.40, 0),
				TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = ps.isYou and GOLD or WHITE,
			})
			label(row, fmt(ps.bet or 0) .. (ps.total and ("  |  " .. ps.total) or ""), {
				Position = UDim2.new(0.01, 0, 0.50, 0), Size = UDim2.new(0.25, 0, 0.36, 0),
				TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.SourceSans,
			})
			for i, card in ipairs(ps.cards or {}) do
				local box = make("Frame", {
					Position = UDim2.new(0.28+(i-1)*math.min(0.10,0.62/math.max(1,#ps.cards-1)),0,0.07,0), Size = UDim2.new(0.085,0,0.72,0),
					BackgroundColor3 = WHITE, BorderSizePixel = 0,
				}, row)
				make("UICorner", { CornerRadius = UDim.new(0, 4) }, box)
				local suit = card:sub(-1)
				label(box, cardText(card), {
					Size = UDim2.new(1, 0, 1, 0),
					TextColor3 = (suit == "H" or suit == "D") and RED or Color3.new(0, 0, 0),
				})
			end
			if ps.result and ps.result ~= "" then
				label(row, ps.result, {
					Position = UDim2.new(0.28, 0, 0.82, 0), Size = UDim2.new(0.70, 0, 0.14, 0),
					TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = ps.win and ps.win > 0 and GOLD or WHITE,
				})
			end
			y += tableMode and (rowHeight + 4) or (ps.isYou and 180 or 122)
		end
		playersPanel.CanvasSize = UDim2.new(0, 0, 0, math.max(y, 1))
	end

	local deal = button(frame, "BET / JOIN", RED, {
		Position = UDim2.new(0.62, 0, 0.84, 0), Size = UDim2.new(0.35, 0, 0.12, 0),
	})
	local actions = {}
	for i, name in ipairs({ "Hit", "Stand", "Double" }) do
		actions[name] = button(frame, name:upper(), DARK, {
			Position = UDim2.new(0.62 + (i - 1) * 0.12, 0, 0.84, 0),
			Size = UDim2.new(0.11, 0, 0.12, 0), Visible = false,
		})
	end

	setMode(toggle.Visible)
	local busy=false
	local function request(action, bet)
		local ok, result = pcall(function()
			return casino:InvokeServer(action, id, bet)
		end)
		if not ok then
			warn("[CasinoClient] blackjack request failed:", result)
			return { ok = false, message = "Blackjack connection error" }
		end
		return result
	end

	local function render(state)
		if not frame.Parent or current ~= frame then return end
		if type(state) ~= "table" or not state.ok then
			status.Text = type(state) == "table" and tostring(state.message) or "Blackjack unavailable"
			return
		end
		showDealer(state.dealer or {}, state.dealerTotal)
		showPlayers(state.players or {})

		local canAct = state.canAct == true
		for _, b in pairs(actions) do b.Visible = canAct end
		actions.Double.Visible = canAct and state.canDouble == true

		-- Finished players were still marked joined in v88, which hid this button.
		-- A finished table must ALWAYS offer the next hand immediately.
		deal.Visible = state.phase == "Finished" or ((state.phase == "Idle" or state.phase == "Betting") and not state.joined)
		deal.Text = state.phase == "Finished" and "BET NEXT HAND" or "BET / JOIN"

		if state.phase == "Idle" then
			status.Text = "Place a bet to open the table. Other players can join the same hand."
		elseif state.phase == "Betting" then
			local n = state.playersCount or 0
			if state.joined then
				status.Text = ("Bet locked - %d player(s), dealing in %ds"):format(n, state.bettingSeconds or 0)
			else
				status.Text = ("BETTING OPEN - %d player(s), %ds to join"):format(n, state.bettingSeconds or 0)
			end
		elseif state.phase == "Playing" then
			if canAct then
				status.Text = ("YOUR HAND - Hit, Stand or Double  |  %ds"):format(state.actionSeconds or 0)
			else
				status.Text = state.result ~= "" and state.result or "Waiting for the other players..."
			end
		elseif state.phase == "Dealer" then
			status.Text = "All players finished - dealer is playing..."
		elseif state.phase == "Finished" then
			local result = state.result ~= "" and state.result or "Round finished"
			status.Text = result .. ((state.win or 0) > 0 and ("  -  " .. fmt(state.win)) or "") .. ("  |  resets in %ds"):format(state.restartSeconds or 0)
		end
	end

	deal.MouseButton1Click:Connect(function()
		if busy then return end;busy=true
		render(request("Deal", getBet()));busy=false
	end)
	for name, b in pairs(actions) do
		b.MouseButton1Click:Connect(function()
			if busy then return end;busy=true
			render(request(name));busy=false
		end)
	end

	render(request("View"))
	task.spawn(function()
		while frame.Parent and current == frame do
			task.wait(0.5)
			if not frame.Parent or current ~= frame then break end
			if busy then continue end
			local character=player.Character;local root=character and character:FindFirstChild("HumanoidRootPart")
			if not root or (typeof(tableCamera)=="CFrame" and (root.Position-tableCamera.Position).Magnitude>25) then close();break end
			busy=true;local state = request("View");busy=false
			if type(state) == "table" and state.ok then render(state) end
		end
	end)
end

local SLOT_GAMES={
 NeonWild={title="NEON WILD",reels=3,color=Color3.fromRGB(125,65,190),
  symbols={{"CHERRY",32},{"LEMON",24},{"BELL",18},{"BAR",12},{"SEVEN",8},{"DIAMOND",4},{"WILD",2}},
  pays={CHERRY=8,LEMON=12,BELL=20,BAR=40,SEVEN=100,DIAMOND=230,WILD=400},
  rules="3 matching symbols pay. WILD substitutes. Three WILDs pay 400x."},
 LuckySevens={title="LUCKY SEVENS",reels=3,color=Color3.fromRGB(180,45,55),
  symbols={{"CHERRY",30},{"LEMON",24},{"BELL",20},{"BAR",14},{"SEVEN",10},{"DIAMOND",2}},
  pays={CHERRY=7,LEMON=9,BELL=16,BAR=33,SEVEN=155,DIAMOND=400},
  rules="3 matching symbols pay. Otherwise one 7 pays 0.5x; two 7s pay 4x."},
 GemRush={title="GEM RUSH",reels=5,color=Color3.fromRGB(25,125,145),
  symbols={{"RUBY",30},{"EMERALD",27},{"SAPPHIRE",22},{"DIAMOND",16},{"WILD",5}},
  pays={RUBY={2,8,35},EMERALD={3,11,45},SAPPHIRE={3,14,60},DIAMOND={5,24,110},WILD={8,35,175}},
  rules="One payline: match 3+ from the LEFT. WILD substitutes. Best match pays."},
}

local function slotMultiplier(kind,reels)
 local config=SLOT_GAMES[kind];local best=0
 for symbol,payout in config.pays do
  local run=0
  for _,value in reels do
   if value==symbol or (kind~="LuckySevens" and value=="WILD") then run+=1 else break end
  end
  if kind=="GemRush" then if run>=3 then best=math.max(best,payout[math.min(run,5)-2]) end
  elseif run==3 then best=math.max(best,payout) end
 end
 if kind=="LuckySevens" and best==0 then
  local sevens=0;for _,value in reels do if value=="SEVEN" then sevens+=1 end end
  best=if sevens==2 then 4 elseif sevens==1 then 0.5 else 0
 end
 return best
end

local function openVariant(kind,id,tierName,minBet,maxBet)
 local config=SLOT_GAMES[kind]
 local frame,getBet,status=window(config.title,tierName,minBet,maxBet,0.68)
 frame.Size=UDim2.fromScale(0.84,0.68)
 local symbols={CHERRY="🍒",LEMON="🍋",BELL="🔔",BAR="BAR",SEVEN="7",DIAMOND="◆",WILD="WILD",RUBY="♦",EMERALD="◆",SAPPHIRE="◆"}
 local colors={RUBY=RED,EMERALD=GREEN,SAPPHIRE=Color3.fromRGB(50,120,225),DIAMOND=Color3.fromRGB(60,195,215),WILD=GOLD}
 local reels={}
 for i=1,config.reels do
  local width=0.92/config.reels
  local box=make("Frame",{Position=UDim2.fromScale(0.04+(i-1)*width,0.20),Size=UDim2.fromScale(width-0.012,0.34),BackgroundColor3=Color3.fromRGB(245,240,225),BorderSizePixel=0},frame)
  make("UICorner",{CornerRadius=UDim.new(0,9)},box)
  reels[i]=label(box,"◆",{Size=UDim2.fromScale(1,1),TextColor3=config.color,Font=Enum.Font.GothamBlack})
 end
 label(frame,config.rules,{Position=UDim2.fromScale(0.04,0.55),Size=UDim2.fromScale(0.92,0.07),TextWrapped=true})
 local payText={}
 for _,entry in config.symbols do
  local pay=config.pays[entry[1]]
  table.insert(payText,entry[1].." "..(type(pay)=="table" and table.concat(pay,"/") or tostring(pay)).."x")
 end
 label(frame,table.concat(payText,"  •  "),{Position=UDim2.fromScale(0.04,0.63),Size=UDim2.fromScale(0.92,0.065),TextColor3=GOLD,TextWrapped=true})
 local spin=button(frame,"SPIN",config.color,{Position=UDim2.fromScale(0.62,0.84),Size=UDim2.fromScale(0.35,0.12)})
 local busy=false
 spin.Activated:Connect(function()
  if busy then return end
  busy=true;spin.Text="SPINNING";status.Text=""
  local result;local bet=getBet()
  task.spawn(function()
   local ok,data=pcall(function() return casino:InvokeServer("Spin",id,bet) end)
   result=ok and data or {ok=false,message="Connection interrupted. Check your balance before trying again."}
  end)
  local started=os.clock()
  while frame.Parent do
   local elapsed=os.clock()-started
   if result and not result.ok then break end
   local finished=true
   for i=1,config.reels do
    local value
    if result and elapsed>0.65+i*0.25 then value=result.reels[i]
    else finished=false;value=config.symbols[math.random(1,#config.symbols)][1] end
    reels[i].Text=symbols[value] or value;reels[i].TextColor3=colors[value] or config.color
   end
   if finished or elapsed>12 then break end
   task.wait(0.06)
  end
  if frame.Parent then
   if not result then status.Text="Still awaiting server. Any win is credited automatically.";spin.Text="CLOSE / REOPEN";return end
   if not result.ok then status.Text=result.message
   else
    status.Text=result.win>0 and ("RETURN "..fmt(result.win).."  •  "..result.multiplier.."x") or "No winning combination"
    pcall(function() casino:InvokeServer("Reveal",id) end)
   end
   busy=false;spin.Text="SPIN"
  end
 end)
end


---------------------------------------------------------------------------
-- v208: Dragon Fortune, Baccarat, Roulette and No-Limit Hold'em screens.
---------------------------------------------------------------------------
local NEW = {}
do
	local SUIT = { S = "♠", H = "♥", D = "♦", C = "♣" }
	local function cardBox(parent, card, props)
		local hidden = card == "??"
		local suit = hidden and "" or card:sub(-1)
		local box = make("Frame", {
			BackgroundColor3 = hidden and Color3.fromRGB(35, 57, 110) or WHITE, BorderSizePixel = 0,
		}, parent)
		for k, v in pairs(props or {}) do
			box[k] = v
		end
		make("UICorner", { CornerRadius = UDim.new(0, 5) }, box)
		label(box, hidden and "◆" or (card:sub(1, -2) .. (SUIT[suit] or "")), {
			Size = UDim2.fromScale(1, 1),
			TextColor3 = hidden and WHITE or ((suit == "H" or suit == "D") and RED or Color3.new(0, 0, 0)),
			Font = Enum.Font.GothamBold,
		})
		return box
	end

	local function cardRow(parent, cards, x, y, w, h, gap)
		for i, card in ipairs(cards) do
			cardBox(parent, card, { Position = UDim2.fromScale(x + (i - 1) * (w + gap), y), Size = UDim2.fromScale(w, h) })
		end
	end

	local function request(action, id, a, b)
		local ok, result = pcall(function()
			return casino:InvokeServer(action, id, a, b)
		end)
		if not ok then
			return { ok = false, message = "Connection error" }
		end
		return result
	end

	-- keeps a table screen fresh and closes it when you walk away
	local function poll(frame, id, tableCamera, render)
		task.spawn(function()
			while frame.Parent and current == frame do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if not root or (typeof(tableCamera) == "CFrame" and (root.Position - tableCamera.Position).Magnitude > 30) then
					close()
					break
				end
				local state = request("View", id)
				if frame.Parent and current == frame and type(state) == "table" and state.ok then
					render(state)
				end
				task.wait(0.5)
			end
		end)
	end

	-------------------------------------------------------------------------
	-- Dragon Fortune: 5x3, 243 ways
	-------------------------------------------------------------------------
	local DRAGON_ICONS = { NINE = "9", TEN = "10", JACK = "J", QUEEN = "Q", KING = "K", ACE = "A", JADE = "🟢", COIN = "🪙", TIGER = "🐯", DRAGON = "🐉", WILD = "WILD", PEARL = "⚪" }
	local DRAGON_COLORS = { JADE = GREEN, COIN = GOLD, TIGER = Color3.fromRGB(240, 140, 40), DRAGON = RED, WILD = GOLD, PEARL = WHITE }
	local DRAGON_LIST = { "NINE", "TEN", "JACK", "QUEEN", "KING", "ACE", "JADE", "COIN", "TIGER", "DRAGON", "WILD", "PEARL" }
	function NEW.DragonFortune(id, tierName, minBet, maxBet)
		local frame, getBet, status = window("DRAGON FORTUNE  -  243 ways", tierName, minBet, maxBet, 0.7)
		frame.BackgroundColor3 = Color3.fromRGB(90, 16, 18)
		local cells = {}
		for col = 1, 5 do
			cells[col] = {}
			for row = 1, 3 do
				local box = make("Frame", {
					Position = UDim2.new(0.03 + (col - 1) * 0.188, 0, 0.15 + (row - 1) * 0.16, 0), Size = UDim2.new(0.17, 0, 0.15, 0),
					BackgroundColor3 = Color3.fromRGB(25, 10, 10), BorderSizePixel = 0,
				}, frame)
				make("UICorner", { CornerRadius = UDim.new(0, 6) }, box)
				make("UIStroke", { Color = GOLD, Transparency = 0.5 }, box)
				cells[col][row] = label(box, "🐉", { Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBlack, TextColor3 = RED })
			end
		end
		local function show(sym, cell)
			cell.Text = DRAGON_ICONS[sym] or sym
			cell.TextColor3 = DRAGON_COLORS[sym] or WHITE
		end
		local banner = label(frame, "", { Position = UDim2.fromScale(0.03, 0.635), Size = UDim2.fromScale(0.94, 0.045), TextColor3 = GOLD })
		label(frame, "Any 3+ matching on adjacent reels from the left, any row. WILD (reels 2-4) substitutes. 3+ ⚪ Pearls anywhere: 8-20 free spins at 2x.", {
			Position = UDim2.fromScale(0.02, 0.68), Size = UDim2.fromScale(0.96, 0.04), Font = Enum.Font.SourceSans, TextWrapped = true,
		})
		local spin = button(frame, "SPIN", RED, { Position = UDim2.fromScale(0.62, 0.84), Size = UDim2.fromScale(0.35, 0.12) })
		local busy = false
		local function settle(flat, col)
			for row = 1, 3 do
				show(flat[(col - 1) * 3 + row], cells[col][row])
			end
		end
		spin.MouseButton1Click:Connect(function()
			if busy then
				return
			end
			busy = true
			status.Text = ""
			banner.Text = ""
			local result
			task.spawn(function()
				result = request("Spin", id, getBet())
			end)
			local started = os.clock()
			local stopped = {}
			while frame.Parent do
				local t = os.clock() - started
				local all = true
				for col = 1, 5 do
					if not stopped[col] then
						if result and result.ok and t > 0.6 + col * 0.3 then
							stopped[col] = true
							settle(result.grid, col)
						else
							all = false
							for row = 1, 3 do
								show(DRAGON_LIST[math.random(1, #DRAGON_LIST)], cells[col][row])
							end
						end
					end
				end
				if all or (result and not result.ok) or t > 12 then
					break
				end
				task.wait(0.06)
			end
			if not result or not result.ok then
				status.Text = result and result.message or "Still waiting for the server - any win is paid automatically"
				busy = false
				return
			end
			if result.bonus then
				banner.Text = ("%d PEARLS!  %d FREE SPINS at 2x"):format(result.pearls, result.bonus.spins)
				task.wait(1.2)
				local running = 0
				for i, fs in ipairs(result.bonus.results) do
					if not frame.Parent then
						break
					end
					for col = 1, 5 do
						settle(fs.grid, col)
					end
					running += fs.win
					banner.Text = ("Free spin %d / %d  -  %s"):format(i, result.bonus.spins, fmt(running))
					task.wait(0.35)
				end
			end
			if result.win > 0 then
				local best = result.hits[1]
				for _, h in ipairs(result.hits) do
					if h.win > best.win then
						best = h
					end
				end
				status.Text = ("WIN %s"):format(fmt(result.win)) .. (best and ("  -  best: %d %s x%d ways"):format(best.count, best.symbol, best.ways) or "")
				request("Reveal", id)
			else
				status.Text = "No win - try again"
			end
			busy = false
		end)
	end

	-------------------------------------------------------------------------
	-- Baccarat
	-------------------------------------------------------------------------
	function NEW.Baccarat(id, tierName, minBet, maxBet, tableCamera)
		local frame, getBet, status = window("BACCARAT  -  Player 1:1  •  Banker 0.95:1  •  Tie 8:1", tierName, minBet, maxBet, 0.74)
		frame.Size = UDim2.fromScale(0.8, 0.74)
		local board = make("Frame", { Position = UDim2.fromScale(0.02, 0.15), Size = UDim2.fromScale(0.96, 0.4), BackgroundTransparency = 1 }, frame)
		local info = label(frame, "", { Position = UDim2.fromScale(0.02, 0.56), Size = UDim2.fromScale(0.96, 0.08), TextWrapped = true, Font = Enum.Font.SourceSans })
		local road = label(frame, "", { Position = UDim2.fromScale(0.02, 0.64), Size = UDim2.fromScale(0.96, 0.06), TextColor3 = GOLD, Font = Enum.Font.Code })
		local sides = {}
		local colors = { Player = Color3.fromRGB(40, 90, 190), Banker = RED, Tie = GREEN }
		for i, side in ipairs({ "Player", "Banker", "Tie" }) do
			local b = button(frame, side:upper(), colors[side], { Position = UDim2.fromScale(0.62 + (i - 1) * 0.12, 0.84), Size = UDim2.fromScale(0.11, 0.12) })
			sides[side] = b
			b.MouseButton1Click:Connect(function()
				local r = request("Bet", id, getBet(), side)
				if not r.ok then
					status.Text = r.message
				end
			end)
		end
		local lastKey
		local function render(st)
			local key = table.concat(st.playerCards, ",") .. "|" .. table.concat(st.bankerCards, ",")
			if key ~= lastKey then
				lastKey = key
				board:ClearAllChildren()
				label(board, "PLAYER" .. (st.playerTotal and ("  " .. st.playerTotal) or ""), { Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(0.48, 0.18), TextColor3 = Color3.fromRGB(120, 170, 255) })
				label(board, "BANKER" .. (st.bankerTotal and ("  " .. st.bankerTotal) or ""), { Position = UDim2.fromScale(0.52, 0), Size = UDim2.fromScale(0.48, 0.18), TextColor3 = Color3.fromRGB(255, 120, 120) })
				cardRow(board, st.playerCards, 0.02, 0.22, 0.13, 0.74, 0.02)
				cardRow(board, st.bankerCards, 0.54, 0.22, 0.13, 0.74, 0.02)
			end
			local lines = {}
			for _, b in ipairs(st.bets) do
				table.insert(lines, ("%s%s %s on %s%s"):format(b.isYou and "▶ " or "", b.name, fmt(b.bet), b.side, (b.win and b.win > 0) and (" → " .. fmt(b.win)) or ""))
			end
			info.Text = #lines > 0 and table.concat(lines, "   •   ") or "No bets yet"
			road.Text = "Last coups: " .. (#st.history > 0 and table.concat(st.history, " ") or "-")
			for _, b in pairs(sides) do
				b.Visible = st.phase == "Idle" or st.phase == "Finished" or (st.phase == "Betting" and not st.mySide)
			end
			if st.phase == "Idle" then
				status.Text = "Choose your bet and press PLAYER, BANKER or TIE to open the coup"
			elseif st.phase == "Betting" then
				status.Text = (st.mySide and ("Your " .. fmt(st.myBet) .. " is on " .. st.mySide .. "  -  ") or "BETS OPEN  -  ") .. ("cards in %ds"):format(st.seconds)
			elseif st.phase == "Dealing" then
				status.Text = "Dealing..."
			elseif st.phase == "Finished" then
				status.Text = st.result .. (st.mySide and ((st.myWin or 0) > 0 and ("  -  you get " .. fmt(st.myWin)) or "  -  you lose") or "")
			end
		end
		poll(frame, id, tableCamera, render)
	end

	-------------------------------------------------------------------------
	-- Roulette
	-------------------------------------------------------------------------
	local REDS = {}
	for _, n in ipairs({ 1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36 }) do
		REDS[n] = true
	end
	function NEW.Roulette(id, tierName, minBet, maxBet, tableCamera)
		local frame, getBet, status = window("ROULETTE  -  single zero", tierName, minBet, maxBet, 0.9)
		frame.Size = UDim2.fromScale(0.92, 0.9)
		local layout = make("Frame", { Position = UDim2.fromScale(0.02, 0.15), Size = UDim2.fromScale(0.96, 0.44), BackgroundTransparency = 1 }, frame)
		local spots = {} -- key -> button
		local function place(kind, value)
			local r = request("Bet", id, getBet(), { kind = kind, value = value })
			if not r.ok then
				status.Text = r.message
			end
		end
		local function spot(key, text, color, pos, size, kind, value)
			local b = button(layout, text, color, { Position = pos, Size = size })
			make("UIStroke", { Color = WHITE, Transparency = 0.6 }, b)
			b.MouseButton1Click:Connect(function()
				place(kind, value)
			end)
			spots[key] = { button = b, text = text }
		end
		local cw, ch = 1 / 14, 0.2
		spot("Straight0", "0", GREEN, UDim2.fromScale(0, 0), UDim2.new(cw, -2, ch * 3, -2), "Straight", 0)
		for n = 1, 36 do
			local col = math.ceil(n / 3)
			local row = 3 - ((n - 1) % 3)
			spot("Straight" .. n, tostring(n), REDS[n] and RED or Color3.fromRGB(20, 20, 24), UDim2.fromScale(col * cw, (row - 1) * ch), UDim2.new(cw, -2, ch, -2), "Straight", n)
		end
		for c = 1, 3 do
			spot("Column" .. c, "2:1", DARK, UDim2.fromScale(13 * cw, (3 - c) * ch), UDim2.new(cw, -2, ch, -2), "Column", c)
		end
		for d = 1, 3 do
			spot("Dozen" .. d, ({ "1st 12", "2nd 12", "3rd 12" })[d], DARK, UDim2.fromScale(cw + (d - 1) * 4 * cw, 3 * ch), UDim2.new(4 * cw, -2, ch, -2), "Dozen", d)
		end
		local outside = { { "Low", "1-18" }, { "Even", "EVEN" }, { "Red", "RED" }, { "Black", "BLACK" }, { "Odd", "ODD" }, { "High", "19-36" } }
		for i, o in ipairs(outside) do
			local color = o[1] == "Red" and RED or (o[1] == "Black" and Color3.fromRGB(20, 20, 24) or DARK)
			spot(o[1] .. "0", o[2], color, UDim2.fromScale(cw + (i - 1) * 2 * cw, 4 * ch), UDim2.new(2 * cw, -2, ch, -2), o[1], 0)
		end
		local result = label(frame, "", { Position = UDim2.fromScale(0.02, 0.6), Size = UDim2.fromScale(0.3, 0.1), TextColor3 = GOLD, Font = Enum.Font.GothamBlack })
		local history = label(frame, "", { Position = UDim2.fromScale(0.33, 0.6), Size = UDim2.fromScale(0.65, 0.05), Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Left })
		local mine = label(frame, "", { Position = UDim2.fromScale(0.33, 0.65), Size = UDim2.fromScale(0.65, 0.06), Font = Enum.Font.SourceSans, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left })
		local clear = button(frame, "TAKE BACK BETS", DARK, { Position = UDim2.fromScale(0.62, 0.84), Size = UDim2.fromScale(0.35, 0.12) })
		clear.MouseButton1Click:Connect(function()
			local r = request("Clear", id)
			if not r.ok then
				status.Text = r.message
			end
		end)
		local function render(st)
			local stacked = {}
			for _, bet in ipairs(st.myBets or {}) do
				local key = bet.kind .. tostring(bet.value)
				stacked[key] = (stacked[key] or 0) + bet.amount
			end
			for key, s in pairs(spots) do
				s.button.Text = stacked[key] and (s.text .. "\n●" .. fmt(stacked[key]):gsub("%$", "")) or s.text
			end
			if st.result then
				result.Text = ("%d %s"):format(st.result, st.resultColor or "")
				result.TextColor3 = st.resultColor == "Red" and RED or (st.resultColor == "Green" and GREEN or WHITE)
			else
				result.Text = "—"
			end
			local hist = {}
			for _, n in ipairs(st.history or {}) do
				table.insert(hist, tostring(n))
			end
			history.Text = "History: " .. (#hist > 0 and table.concat(hist, " ") or "-")
			mine.Text = ("Your bets this spin: %s   •   players betting: %d"):format(fmt(st.myTotal or 0), st.players or 0)
			clear.Visible = st.phase == "Betting" and (st.myTotal or 0) > 0
			if st.phase == "Idle" then
				status.Text = "Pick a chip size, then tap the layout to bet. The wheel spins 18s after the first bet."
			elseif st.phase == "Betting" then
				status.Text = ("PLACE YOUR BETS  -  %ds"):format(st.seconds)
			elseif st.phase == "Spinning" then
				status.Text = "No more bets - the ball is rolling..."
			elseif st.phase == "Finished" then
				status.Text = ("%d %s"):format(st.result or 0, st.resultColor or "") .. ((st.myWin or 0) > 0 and ("  -  YOU WIN " .. fmt(st.myWin)) or ((st.myTotal or 0) > 0 and "  -  no win" or ""))
			end
		end
		poll(frame, id, tableCamera, render)
	end

	-------------------------------------------------------------------------
	-- No-Limit Texas Hold'em
	-------------------------------------------------------------------------
	function NEW.Holdem(id, tierName, minBet, maxBet, tableCamera)
		local frame, getBet, status = window("TEXAS HOLD'EM  -  NO LIMIT", tierName, minBet, maxBet, 0.92)
		frame.Size = UDim2.fromScale(0.94, 0.92)
		status.Size = UDim2.fromScale(0.62, 0.09)
		local header = label(frame, "", { Position = UDim2.fromScale(0.02, 0.09), Size = UDim2.fromScale(0.6, 0.05), TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.SourceSans })
		local boardFrame = make("Frame", { Position = UDim2.fromScale(0.02, 0.15), Size = UDim2.fromScale(0.5, 0.17), BackgroundTransparency = 1 }, frame)
		local potLabel = label(frame, "", { Position = UDim2.fromScale(0.54, 0.15), Size = UDim2.fromScale(0.2, 0.08), TextColor3 = GOLD })
		local handFrame = make("Frame", { Position = UDim2.fromScale(0.76, 0.15), Size = UDim2.fromScale(0.22, 0.17), BackgroundTransparency = 1 }, frame)
		local seatsPanel = make("Frame", { Position = UDim2.fromScale(0.02, 0.34), Size = UDim2.fromScale(0.62, 0.37), BackgroundColor3 = Color3.fromRGB(13, 50, 29), BorderSizePixel = 0 }, frame)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, seatsPanel)
		local logLabel = label(frame, "", { Position = UDim2.fromScale(0.66, 0.34), Size = UDim2.fromScale(0.32, 0.37), Font = Enum.Font.SourceSans, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextXAlignment = Enum.TextXAlignment.Left, TextScaled = false, TextSize = 14 })

		-- setup row (blinds) - reuses the bet box as buy-in / raise amount
		local sbBox = make("TextBox", { Position = UDim2.fromScale(0.08, 0.5), Size = UDim2.fromScale(0.2, 0.07), BackgroundColor3 = DARK, TextColor3 = WHITE, Font = Enum.Font.SourceSansBold, TextScaled = true, Text = "5", PlaceholderText = "Small blind", ClearTextOnFocus = false, Visible = false, ZIndex = 3 }, frame)
		local bbBox = make("TextBox", { Position = UDim2.fromScale(0.34, 0.5), Size = UDim2.fromScale(0.2, 0.07), BackgroundColor3 = DARK, TextColor3 = WHITE, Font = Enum.Font.SourceSansBold, TextScaled = true, Text = "10", PlaceholderText = "Big blind", ClearTextOnFocus = false, Visible = false, ZIndex = 3 }, frame)
		local setupHint = label(frame, "Small blind / big blind (e.g. 5/10 or 50k/100k) - the box below is your buy-in", { Position = UDim2.fromScale(0.04, 0.42), Size = UDim2.fromScale(0.56, 0.06), Font = Enum.Font.SourceSans, TextWrapped = true, Visible = false, ZIndex = 3 })

		local buttons = {}
		local function actionButton(name, text, color, x, y, w)
			local b = button(frame, text, color, { Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w or 0.1, 0.055), Visible = false })
			buttons[name] = b
			return b
		end
		local sit = actionButton("Sit", "SIT DOWN", GREEN, 0.62, 0.84, 0.35)
		sit.Size = UDim2.fromScale(0.35, 0.12)
		actionButton("Fold", "FOLD", RED, 0.66, 0.74)
		actionButton("Call", "CHECK", DARK, 0.77, 0.74)
		actionButton("Raise", "RAISE", Color3.fromRGB(40, 90, 190), 0.88, 0.74)
		actionButton("AllIn", "ALL IN", Color3.fromRGB(150, 40, 150), 0.88, 0.8)
		actionButton("AddBot", "+ BOT", DARK, 0.66, 0.8)
		actionButton("RemoveBot", "- BOT", DARK, 0.77, 0.8)
		actionButton("TopUp", "ADD CHIPS", DARK, 0.66, 0.86, 0.15)
		actionButton("Leave", "CASH OUT", RED, 0.82, 0.86, 0.16)

		local state = nil
		local function send(action, a, b)
			local r = request(action, id, a, b)
			if not r.ok then
				status.Text = r.message or "?"
			end
		end
		buttons.Sit.MouseButton1Click:Connect(function()
			local sb, bb = parseBet(sbBox.Text), parseBet(bbBox.Text)
			send("Sit", getBet(), { sb = sb, bb = bb })
		end)
		buttons.Fold.MouseButton1Click:Connect(function()
			send("Fold")
		end)
		buttons.Call.MouseButton1Click:Connect(function()
			send(state and state.toCall > 0 and "Call" or "Check")
		end)
		buttons.Raise.MouseButton1Click:Connect(function()
			send("Raise", getBet())
		end)
		buttons.AllIn.MouseButton1Click:Connect(function()
			send("AllIn")
		end)
		buttons.AddBot.MouseButton1Click:Connect(function()
			send("AddBot")
		end)
		buttons.RemoveBot.MouseButton1Click:Connect(function()
			send("RemoveBot")
		end)
		buttons.TopUp.MouseButton1Click:Connect(function()
			send("TopUp", getBet())
		end)
		buttons.Leave.MouseButton1Click:Connect(function()
			send("Leave")
		end)

		local lastBoard, lastHand
		local function render(st)
			state = st
			header.Text = st.configured and ("Blinds %s / %s   •   buy-in from %s   •   %d seat(s) free"):format(fmt(st.sb), fmt(st.bb), fmt(st.minBuyIn), st.freeSeats) or "Empty table - you set the stakes"
			local boardKey = table.concat(st.board, ",")
			if boardKey ~= lastBoard then
				lastBoard = boardKey
				boardFrame:ClearAllChildren()
				cardRow(boardFrame, st.board, 0, 0, 0.18, 1, 0.02)
			end
			potLabel.Text = st.pot > 0 and ("POT " .. fmt(st.pot)) or ""
			local me
			seatsPanel:ClearAllChildren()
			for i, seat in ipairs(st.seats) do
				if seat.isYou then
					me = seat
				end
				local row = make("Frame", {
					Position = UDim2.new(0, 4, (i - 1) / 6, 2), Size = UDim2.new(1, -8, 1 / 6, -4),
					BackgroundColor3 = seat.turn and Color3.fromRGB(120, 95, 20) or (seat.isYou and Color3.fromRGB(34, 92, 55) or DARK), BorderSizePixel = 0,
				}, seatsPanel)
				make("UICorner", { CornerRadius = UDim.new(0, 4) }, row)
				local name = (seat.dealer and "Ⓓ " or "") .. seat.name .. (seat.bot and " (bot)" or "") .. (seat.isYou and "  (YOU)" or "")
				label(row, name, { Position = UDim2.fromScale(0.01, 0), Size = UDim2.fromScale(0.34, 1), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = seat.folded and Color3.fromRGB(140, 140, 140) or WHITE })
				label(row, fmt(seat.stack), { Position = UDim2.fromScale(0.35, 0), Size = UDim2.fromScale(0.17, 1), Font = Enum.Font.SourceSans })
				label(row, seat.bet > 0 and ("bet " .. fmt(seat.bet)) or "", { Position = UDim2.fromScale(0.52, 0), Size = UDim2.fromScale(0.15, 1), Font = Enum.Font.SourceSans, TextColor3 = GOLD })
				local act = seat.handName and (seat.handName .. ((seat.won or 0) > 0 and (" +" .. fmt(seat.won)) or "")) or (seat.folded and "Folded" or seat.action)
				label(row, act, { Position = UDim2.fromScale(0.67, 0), Size = UDim2.fromScale(0.2, 1), Font = Enum.Font.SourceSans, TextWrapped = true })
				if not seat.isYou and #seat.cards > 0 and not seat.folded then
					cardRow(row, seat.cards, 0.88, 0.05, 0.055, 0.9, 0.005)
				end
			end
			local handKey = me and table.concat(me.cards, ",") or ""
			if handKey ~= lastHand then
				lastHand = handKey
				handFrame:ClearAllChildren()
				if me and #me.cards > 0 then
					cardRow(handFrame, me.cards, 0, 0, 0.46, 1, 0.04)
				end
			end
			logLabel.Text = table.concat(st.log, "\n")
			local seated = st.seated
			buttons.Sit.Visible = not seated
			buttons.Sit.Text = st.configured and "SIT DOWN (buy-in)" or "OPEN TABLE"
			sbBox.Visible = not seated and not st.configured
			bbBox.Visible = sbBox.Visible
			setupHint.Visible = sbBox.Visible
			buttons.Fold.Visible = st.myTurn
			buttons.Call.Visible = st.myTurn
			buttons.Call.Text = st.toCall > 0 and ("CALL " .. fmt(math.min(st.toCall, st.myStack))) or "CHECK"
			buttons.Raise.Visible = st.myTurn and st.maxRaiseTo > st.currentBet
			buttons.Raise.Text = st.currentBet > 0 and "RAISE TO" or "BET"
			buttons.AllIn.Visible = st.myTurn
			buttons.AddBot.Visible = seated and st.freeSeats > 0
			buttons.RemoveBot.Visible = seated
			buttons.TopUp.Visible = seated and st.phase ~= "Playing"
			buttons.Leave.Visible = seated
			if not seated then
				status.Text = st.configured and ("Enter a buy-in (at least %s) and sit down"):format(fmt(st.minBuyIn)) or "Set the blinds and your buy-in, then OPEN TABLE"
			elseif st.phase == "Waiting" then
				status.Text = "Waiting for another player - press + BOT to play against bots"
			elseif st.myTurn then
				status.Text = ("YOUR ACTION (%ds)  -  to call %s  •  raise to at least %s  (type the amount in the box)"):format(st.seconds, fmt(st.toCall), fmt(st.minRaiseTo))
			elseif st.phase == "Playing" then
				status.Text = "Waiting for the other players..."
			elseif st.phase == "Finished" then
				status.Text = ("Next hand in %ds"):format(st.seconds)
			end
		end
		poll(frame, id, tableCamera, render)
	end
end

openEvent.OnClientEvent:Connect(function(kind, id, tierName, minBet, maxBet, tableCamera)
	if SLOT_GAMES[kind] then
		openVariant(kind,id,tierName,minBet,maxBet)
	elseif kind == "Slots" then
		openSlots(id, tierName, minBet, maxBet)
	elseif kind == "Cleopatra" then
		openCleopatra(id, tierName, minBet, maxBet)
	elseif kind == "Keno" then
		openKeno(id, tierName, minBet, maxBet)
	elseif kind == "BlackJack" then
		openBlackjack(id, tierName, minBet, maxBet, tableCamera)
	elseif NEW[kind] then
		NEW[kind](id, tierName, minBet, maxBet, tableCamera)
	end
end)
