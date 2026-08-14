--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConstants = require(Shared:WaitForChild("GameConstants"))
local GameLogic = require(Shared:WaitForChild("GameLogic"))

local ClickEvent = ReplicatedStorage:WaitForChild("ClickEvent")
local PurchaseEvent = ReplicatedStorage:WaitForChild("PurchaseEvent")
local SyncState = ReplicatedStorage:WaitForChild("SyncState")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- No character ever spawns (see GameService's CharacterAutoLoads = false), but
-- hide these anyway as a second layer of defense against the health/backpack
-- UI ever flashing on screen.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

-- 1:1 Visual Recreation (UI Construction)
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoclickerGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local mainContainer = Instance.new("Frame")
mainContainer.Name = "MainContainer"
mainContainer.AutomaticSize = Enum.AutomaticSize.Y
mainContainer.Size = UDim2.new(0, 360, 0, 0)
mainContainer.Position = UDim2.new(0.5, 0, 0.5, 0)
mainContainer.AnchorPoint = Vector2.new(0.5, 0.5)
mainContainer.BackgroundColor3 = Color3.fromHex("1e1e2f")
mainContainer.BorderSizePixel = 0
mainContainer.Parent = screenGui

local uiCorner = Instance.new("UICorner")
uiCorner.CornerRadius = UDim.new(0, 12)
uiCorner.Parent = mainContainer

local uiListLayout = Instance.new("UIListLayout")
uiListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
uiListLayout.Padding = UDim.new(0, 15)
uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder
uiListLayout.Parent = mainContainer

local uiPadding = Instance.new("UIPadding")
uiPadding.PaddingTop = UDim.new(0, 20)
uiPadding.PaddingBottom = UDim.new(0, 20)
uiPadding.Parent = mainContainer

-- Header
local header = Instance.new("TextLabel")
header.Text = "Autoclicker"
header.Font = Enum.Font.SourceSansBold
header.TextSize = 32
header.TextColor3 = Color3.fromHex("f4f4f9")
header.BackgroundTransparency = 1
header.Size = UDim2.new(1, 0, 0, 40)
header.LayoutOrder = 1
header.Parent = mainContainer

-- Score
local scoreLabel = Instance.new("TextLabel")
scoreLabel.Name = "ScoreLabel"
scoreLabel.Text = "Score: 0"
scoreLabel.Font = Enum.Font.SourceSans
scoreLabel.TextSize = 24
scoreLabel.TextColor3 = Color3.fromHex("f4f4f9")
scoreLabel.BackgroundTransparency = 1
scoreLabel.Size = UDim2.new(1, 0, 0, 30)
scoreLabel.LayoutOrder = 2
scoreLabel.Parent = mainContainer

-- Rate
local rateLabel = Instance.new("TextLabel")
rateLabel.Name = "RateLabel"
rateLabel.Text = "+0/sec"
rateLabel.Font = Enum.Font.SourceSans
rateLabel.TextSize = 18
rateLabel.TextColor3 = Color3.fromHex("9a9ab5")
rateLabel.BackgroundTransparency = 1
rateLabel.Size = UDim2.new(1, 0, 0, 20)
rateLabel.LayoutOrder = 3
rateLabel.Parent = mainContainer

-- Click Button
local clickButton = Instance.new("TextButton")
clickButton.Name = "ClickButton"
clickButton.Text = "Click me!"
clickButton.Font = Enum.Font.SourceSansBold
clickButton.TextSize = 28
clickButton.TextColor3 = Color3.new(1, 1, 1)
clickButton.BackgroundColor3 = Color3.fromHex("6c5ce7")
clickButton.Size = UDim2.new(0, 250, 0, 80)
clickButton.BorderSizePixel = 0
clickButton.LayoutOrder = 4
clickButton.Parent = mainContainer

local clickCorner = Instance.new("UICorner")
clickCorner.CornerRadius = UDim.new(0, 8)
clickCorner.Parent = clickButton

-- Shop
local shopFrame = Instance.new("Frame")
shopFrame.Name = "ShopFrame"
shopFrame.AutomaticSize = Enum.AutomaticSize.Y
shopFrame.Size = UDim2.new(0, 320, 0, 0)
shopFrame.BackgroundColor3 = Color3.fromHex("2a2a3f")
shopFrame.BorderSizePixel = 0
shopFrame.LayoutOrder = 5
shopFrame.Parent = mainContainer

local shopCorner = Instance.new("UICorner")
shopCorner.CornerRadius = UDim.new(0, 12)
shopCorner.Parent = shopFrame

local shopLayout = Instance.new("UIListLayout")
shopLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
shopLayout.Padding = UDim.new(0, 8)
shopLayout.SortOrder = Enum.SortOrder.LayoutOrder
shopLayout.Parent = shopFrame

local shopPadding = Instance.new("UIPadding")
shopPadding.PaddingTop = UDim.new(0, 12)
shopPadding.PaddingBottom = UDim.new(0, 12)
shopPadding.Parent = shopFrame

-- Shop rows: one buy button + owned-count label per upgrade, all flat-priced.
local UPGRADE_DISPLAY = {
	{ Id = "AutoClicker", Name = "Auto-Clicker", Effect = "+1/sec", OwnedLabel = "Auto-clickers owned" },
	{ Id = "MegaClicker", Name = "Mega Auto-Clicker", Effect = "+10/sec", OwnedLabel = "Mega auto-clickers owned" },
	{ Id = "ClickPower", Name = "Click Power", Effect = "+1/click", OwnedLabel = "Click power levels" },
	{ Id = "Multiplier", Name = "Global Multiplier", Effect = "+10% income", OwnedLabel = "Multiplier levels" },
}

local shopRows = {}

for i, upgrade in ipairs(UPGRADE_DISPLAY) do
	local cost = GameLogic.GetUpgradeCost(upgrade.Id)

	local buyButton = Instance.new("TextButton")
	buyButton.Name = upgrade.Id .. "BuyButton"
	buyButton.Text = ("Buy %s (%s) -- %d pts"):format(upgrade.Name, upgrade.Effect, cost)
	buyButton.Size = UDim2.new(0, 280, 0, 50)
	buyButton.BackgroundColor3 = Color3.fromHex("6c5ce7")
	buyButton.TextColor3 = Color3.new(1, 1, 1)
	buyButton.Font = Enum.Font.SourceSans
	buyButton.TextSize = 16
	buyButton.TextWrapped = true
	buyButton.LayoutOrder = i * 2
	buyButton.Parent = shopFrame

	local buyCorner = Instance.new("UICorner")
	buyCorner.CornerRadius = UDim.new(0, 8)
	buyCorner.Parent = buyButton

	local ownedLabel = Instance.new("TextLabel")
	ownedLabel.Name = upgrade.Id .. "OwnedLabel"
	ownedLabel.Text = upgrade.OwnedLabel .. ": 0"
	ownedLabel.TextColor3 = Color3.fromHex("f4f4f9")
	ownedLabel.BackgroundTransparency = 1
	ownedLabel.Size = UDim2.new(1, 0, 0, 24)
	ownedLabel.Font = Enum.Font.SourceSans
	ownedLabel.TextSize = 14
	ownedLabel.LayoutOrder = i * 2 + 1
	ownedLabel.Parent = shopFrame

	buyButton.MouseButton1Click:Connect(function()
		PurchaseEvent:FireServer(upgrade.Id)
	end)

	table.insert(shopRows, {
		Id = upgrade.Id,
		Field = GameConstants.UPGRADE_FIELDS[upgrade.Id],
		Cost = cost,
		BuyButton = buyButton,
		OwnedLabel = ownedLabel,
		OwnedText = upgrade.OwnedLabel,
	})
end

-- Reset Button
local resetButton = Instance.new("TextButton")
resetButton.Name = "ResetButton"
resetButton.Text = "Reset Progress"
resetButton.Size = UDim2.new(0, 200, 0, 40)
resetButton.BackgroundColor3 = Color3.fromHex("3a3a52")
resetButton.TextColor3 = Color3.new(1, 1, 1)
resetButton.Font = Enum.Font.SourceSans
resetButton.TextSize = 16
resetButton.LayoutOrder = 6
resetButton.Parent = mainContainer

-- Input Logic
local function animateClick(btn: GuiButton)
	local tween = TweenService:Create(btn, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(btn.Size.X.Scale, btn.Size.X.Offset * 0.96, btn.Size.Y.Scale, btn.Size.Y.Offset * 0.96)
	})
	tween:Play()
	tween.Completed:Wait()
	TweenService:Create(btn, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.new(btn.Size.X.Scale, btn.Size.X.Offset / 0.96, btn.Size.Y.Scale, btn.Size.Y.Offset / 0.96)
	}):Play()
end

clickButton.MouseButton1Click:Connect(function()
	ClickEvent:FireServer()
	animateClick(clickButton)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Space then
		ClickEvent:FireServer()
		animateClick(clickButton)
	end
end)

-- Sync State
SyncState.OnClientEvent:Connect(function(state)
	scoreLabel.Text = "Score: " .. math.floor(state.score)

	local rate = GameLogic.CalculateIdleGain(state, 1)
	rateLabel.Text = ("+%.1f/sec"):format(rate)

	local clickGain = GameLogic.CalculateClickGain(state)
	clickButton.Text = ("Click me! (+%.1f)"):format(clickGain)

	for _, row in ipairs(shopRows) do
		local owned = state[row.Field]
		row.OwnedLabel.Text = row.OwnedText .. ": " .. owned

		if state.score < row.Cost then
			row.BuyButton.BackgroundColor3 = Color3.fromHex("444460")
			row.BuyButton.AutoButtonColor = false
		else
			row.BuyButton.BackgroundColor3 = Color3.fromHex("6c5ce7")
			row.BuyButton.AutoButtonColor = true
		end
	end
end)

-- Dark Void Environment Setup (Client Side)
local camera = workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable
camera.CFrame = CFrame.new(Vector3.new(0, 100, 0), Vector3.new(0, 0, 0))

print("Autoclicker Client Initialized")
