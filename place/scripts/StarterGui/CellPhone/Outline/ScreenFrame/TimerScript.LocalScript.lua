-- Phone status bar: cash, bank balance and payday countdown (rewritten).
-- Payday itself is paid by ServerScriptService.EconomyServer.
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local screen = script.Parent
local payFrame = screen:WaitForChild("PayFrame")
local timerLabel = screen:WaitForChild("PermFrame"):WaitForChild("Timer")

local cash = player:WaitForChild("Cash")
local bank = player:WaitForChild("Money")
local timer = player:WaitForChild("PaydayTimer")

local function update()
	payFrame.MoneyHeld.Text = "$" .. cash.Value .. " on hand"
	payFrame.CashHeld.Text = "$" .. bank.Value .. " in bank"
	local seconds = math.max(timer.Value, 0)
	local amount = player:GetAttribute("PaydayAmount") or 0
	timerLabel.Text = ("%s$%d in %d:%02d"):format(amount >= 0 and "+" or "-", math.abs(amount), seconds // 60, seconds % 60)
end

cash.Changed:Connect(update)
bank.Changed:Connect(update)
timer.Changed:Connect(update)
player:GetAttributeChangedSignal("PaydayAmount"):Connect(update)
update()
